extends Node

## Full English-localization sweep.
##
## The older qa_english_localization scene checks the mobile menu, briefings and
## a handful of screens.  This one instantiates EVERY GUI screen that can be
## built headlessly, runs MenuUI.localize_tree() over it, walks every text
## surface and fails on any Cyrillic glyph left while Language.EN is active.
## It additionally walks the two hand-maintained dictionaries and the runtime
## data sources (drone catalog, missions, flight school, reports).
##
## Run: Godot --headless --path . res://test/qa_english_localization_full.tscn

const MenuUI := preload("res://GUI/ui/MenuUI.gd")
const LocScript := preload("res://scripts/util/localization_manager.gd")

const GUI_SCENES := [
	"res://GUI/MainMenu.tscn",
	"res://GUI/mobile/MobileMenu.tscn",
	"res://GUI/AudioMenu.tscn",
	"res://GUI/CalibrationMenu.tscn",
	"res://GUI/CalibrationScreen.tscn",
	"res://GUI/ControlsMenu.tscn",
	"res://GUI/ControlsMenuDrone.tscn",
	"res://GUI/ControlsMenuRadioTransmitter.tscn",
	"res://GUI/ControlsScreen.tscn",
	"res://GUI/DroneBuilder.tscn",
	"res://GUI/DroneSelectScreen.tscn",
	"res://GUI/GameSettingsMenu.tscn",
	"res://GUI/GraphicsMenu.tscn",
	"res://GUI/GraphicsScreen.tscn",
	"res://GUI/HelpPage.tscn",
	"res://GUI/HelpScreen.tscn",
	"res://GUI/HUDConfig.tscn",
	"res://GUI/OptionsMenu.tscn",
	"res://GUI/OtherSettingsScreen.tscn",
	"res://GUI/PauseMenu.tscn",
	"res://GUI/QuadSettingsMenu.tscn",
	"res://GUI/RadioTransmitter.tscn",
]

var _failures: Array[String] = []
var _checked_texts := 0
var _checked_screens := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved_language := LocScript.get_language()
	var had_mobile := OS.has_environment("MOBILE_UI")
	var saved_mobile := OS.get_environment("MOBILE_UI")
	var had_record := OS.has_environment("DRONE_NO_RECORD")
	var saved_record := OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_NO_RECORD", "1")
	LocScript.set_language(LocScript.Language.EN, false)
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0

	for scene_path in GUI_SCENES:
		_audit_scene(scene_path)

	_audit_dictionaries()
	_audit_runtime_data()
	_audit_reports()

	for failure in _failures:
		push_error("[EN_FULL] " + failure)
	print("[EN_FULL] screens=", _checked_screens, " texts=", _checked_texts,
			" failures=", _failures.size())

	LocScript.set_language(saved_language, false)
	if had_mobile:
		OS.set_environment("MOBILE_UI", saved_mobile)
	else:
		OS.unset_environment("MOBILE_UI")
	if had_record:
		OS.set_environment("DRONE_NO_RECORD", saved_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _audit_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_failures.append("cannot load " + scene_path)
		return
	var screen := packed.instantiate() as Node
	if screen == null:
		_failures.append("cannot instantiate " + scene_path)
		return
	add_child(screen)
	# add_child() runs the screen's _ready() synchronously, so its widgets
	# exist by the time we localize and scan.  Deliberately avoid awaits here:
	# some of these screens change the active scene tree on their own, which
	# used to cancel the coroutine and skip every screen in the list.
	MenuUI.localize_tree(screen)
	_checked_screens += 1
	_scan_node(screen, scene_path.get_file())

	# A few screens keep their strings in helper methods instead of the scene
	# tree.  Trigger the harmless refresh entry points we know about.
	for method in ["_refresh", "_populate", "_rebuild", "refresh",
			"populate", "rebuild"]:
		if screen.has_method(method):
			screen.call(method)
			MenuUI.localize_tree(screen)
			_scan_node(screen, scene_path.get_file() + ":" + method)

	screen.queue_free()


func _audit_dictionaries() -> void:
	for key in LocScript.DICT.keys():
		_scan_text(LocScript.t(str(key)), "Loc.DICT/" + str(key))
	for key in MenuUI.EN_TEXT.keys():
		_scan_text(MenuUI.translate_text(str(key)), "MenuUI.EN_TEXT/" + str(key))


func _audit_runtime_data() -> void:
	# Drone catalog: the getters already pick the active language.
	if DroneCatalog != null:
		var count := DroneCatalog.count()
		for i in range(count):
			_scan_text(DroneCatalog.get_drone_name(i), "DroneCatalog[%d].name" % i)
			_scan_text(DroneCatalog.get_drone_tag(i), "DroneCatalog[%d].tag" % i)
			_scan_text(DroneCatalog.get_drone_desc(i), "DroneCatalog[%d].desc" % i)
			_scan_text(DroneCatalog.get_drone_info(i), "DroneCatalog[%d].info" % i)
			_scan_text(DroneCatalog.get_drone_drop_name(i),
					"DroneCatalog[%d].drop_name" % i)
			# Raw preset dictionaries intentionally keep Ukrainian source text:
			# the getters above translate it at read time.  Scanning the raw
			# fields here would report false positives.

	for special_id in range(1, 11):
		_scan_text(Global.get_special_mission_name(special_id),
				"Global.get_special_mission_name(%d)" % special_id)
	var challenge: Dictionary = Global.get_daily_challenge()
	for key in ["title", "title_en", "desc", "desc_en"]:
		if challenge.has(key):
			_scan_text(str(challenge[key]), "Global.get_daily_challenge.%s" % key)


func _audit_reports() -> void:
	_scan_text(Global.get_records_report(true), "Global.get_records_report(EN)")
	_scan_text(Global.get_leaderboard_summary(true),
			"Global.get_leaderboard_summary(EN)")


func _scan_node(node: Node, path: String) -> void:
	if node is Label:
		_scan_text((node as Label).text, path + "/" + node.name)
	elif node is Button:
		_scan_text((node as Button).text, path + "/" + node.name)
	elif node is RichTextLabel:
		_scan_text((node as RichTextLabel).text, path + "/" + node.name)
	elif node is LineEdit:
		_scan_text((node as LineEdit).placeholder_text, path + "/" + node.name)
	elif node is Window:
		_scan_text((node as Window).title, path + "/" + node.name)
	if node is OptionButton:
		var option := node as OptionButton
		for i in range(option.item_count):
			_scan_text(option.get_item_text(i), path + "/" + node.name + " item %d" % i)
	for child in node.get_children():
		_scan_node(child, path + "/" + child.name)


func _scan_text(text: String, path: String) -> void:
	_checked_texts += 1
	for character in text:
		var codepoint := character.unicode_at(0)
		if codepoint >= 0x0400 and codepoint <= 0x04FF:
			_failures.append("%s contains Cyrillic: %s" % [path, text])
			return
