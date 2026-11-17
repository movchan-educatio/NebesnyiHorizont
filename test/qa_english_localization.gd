extends Node

## Audit the mobile menu and every campaign/special-operation briefing for
## Ukrainian text while English is selected.
const MENU := preload("res://GUI/mobile/MobileMenu.tscn")
const DESKTOP_MENU := preload("res://GUI/MainMenu.tscn")
const MenuUI := preload("res://GUI/ui/MenuUI.gd")
const LocScript := preload("res://scripts/util/localization_manager.gd")
const FlightSchoolScript := preload("res://scripts/util/flight_school.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved_language := LocScript.get_language()
	var had_mobile := OS.has_environment("MOBILE_UI")
	var saved_mobile := OS.get_environment("MOBILE_UI")
	var had_no_record := OS.has_environment("DRONE_NO_RECORD")
	var saved_no_record := OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_NO_RECORD", "1")
	LocScript.set_language(LocScript.Language.EN, false)
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0

	var menu := MENU.instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	menu.call("_show", "play")
	MenuUI.localize_tree(menu)
	_scan_node(menu, "MobileMenu")

	var briefing_body := menu.get("_briefing_body") as Label
	var briefing_title := menu.get("_briefing_title") as Label
	if briefing_body == null or briefing_title == null:
		_failures.append("Mobile briefing modal was not built")
	else:
		for mission_id in range(1, 5):
			menu.set("_selected_special", 0)
			menu.set("_selected_mission", mission_id)
			menu.call("_open_mobile_briefing")
			_scan_text(briefing_title.text, "Campaign briefing %d title" % mission_id)
			_scan_text(briefing_body.text, "Campaign briefing %d body" % mission_id)
		for special_id in range(1, 10):
			menu.set("_selected_special", special_id)
			menu.call("_open_mobile_briefing")
			_scan_text(briefing_title.text, "Special briefing %d title" % special_id)
			_scan_text(briefing_body.text, "Special briefing %d body" % special_id)
	menu.queue_free()
	await get_tree().process_frame
	OS.unset_environment("MOBILE_UI")
	var desktop_menu := DESKTOP_MENU.instantiate() as Control
	add_child(desktop_menu)
	await get_tree().process_frame
	MenuUI.localize_tree(desktop_menu)
	_scan_node(desktop_menu, "MainMenu")

	var school := FlightSchoolScript.new()
	add_child(school)
	for step in range(11):
		var lesson: Dictionary = school.call("_step_data", step)
		for key in ["title", "inst", "tip"]:
			_scan_text(str(lesson.get(key, "")), "Flight School module %d %s" % [step, key])

	for extra_scn in [
		"res://GUI/DroneSelectScreen.tscn",
		"res://GUI/ControlsScreen.tscn",
		"res://GUI/QuadSettingsMenu.tscn",
		"res://GUI/HelpScreen.tscn",
		"res://GUI/PauseMenu.tscn",
	]:
		var extra := (load(extra_scn) as PackedScene).instantiate() as Control
		add_child(extra)
		await get_tree().process_frame
		MenuUI.localize_tree(extra)
		_scan_node(extra, extra_scn.get_file())
		extra.queue_free()
		await get_tree().process_frame

	_scan_text(Global.get_records_report(true), "Global.get_records_report(true)")
	_scan_text(Global.get_leaderboard_summary(true), "Global.get_leaderboard_summary(true)")

	for rkey in ["01", "02", "03", "04"]:
		var rstream: AudioStream = Audio.call("_get_radio_stream", rkey) if Audio != null else null
		if rstream == null or rstream.get_length() < 5.0:
			_failures.append("English radio stream %s missing or too short" % rkey)

	desktop_menu.queue_free()
	school.queue_free()
	await get_tree().process_frame
	for missing in _failures:
		push_error("[ENGLISH_LOCALIZATION] " + missing)
	print("[ENGLISH_LOCALIZATION] failures=", _failures.size())
	LocScript.set_language(saved_language, false)
	if had_mobile:
		OS.set_environment("MOBILE_UI", saved_mobile)
	else:
		OS.unset_environment("MOBILE_UI")
	if had_no_record:
		OS.set_environment("DRONE_NO_RECORD", saved_no_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _scan_node(node: Node, path: String) -> void:
	if node is Label:
		_scan_text((node as Label).text, path + "/" + node.name)
	elif node is Button:
		_scan_text((node as Button).text, path + "/" + node.name)
	elif node is RichTextLabel:
		_scan_text((node as RichTextLabel).text, path + "/" + node.name)
	elif node is LineEdit:
		_scan_text((node as LineEdit).placeholder_text, path + "/" + node.name)
	if node is OptionButton:
		var option := node as OptionButton
		for i in range(option.item_count):
			_scan_text(option.get_item_text(i), path + "/" + node.name + " item %d" % i)
	for child in node.get_children():
		_scan_node(child, path + "/" + child.name)


func _scan_text(text: String, path: String) -> void:
	for character in text:
		var codepoint := character.unicode_at(0)
		if codepoint >= 0x0400 and codepoint <= 0x04FF:
			_failures.append("%s contains Cyrillic: %s" % [path, text])
			return
