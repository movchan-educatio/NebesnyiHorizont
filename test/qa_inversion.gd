## QA-only: verifies the two roll-inversion checkboxes on the old Controls
## screen update ELRS, touch input and the saved settings.
extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(1.5).timeout
	var screen := get_tree().current_scene
	var elrs := get_node_or_null("/root/ElrsWifiInput")
	var pad := get_node_or_null("/root/TouchControls")
	var settings := get_node_or_null("/root/GameSettings")
	if screen == null or elrs == null or pad == null or settings == null:
		print("[INVQA] FAIL: missing nodes")
		get_tree().quit()
		return
	var real_path: String = settings.get("game_settings_path")
	var old_elrs := bool(elrs.get("invert_roll"))
	var old_touch := bool(pad.get("invert_roll"))
	settings.set("game_settings_path", "user://qa_inversion.cfg")

	elrs.set("invert_roll", false)
	pad.set("invert_roll", false)
	screen.call("_on_virtual_invert_elrs", true)
	screen.call("_on_virtual_invert_touch", true)
	var on_elrs := bool(elrs.get("invert_roll"))
	var on_touch := bool(pad.get("invert_roll"))
	var hud: Dictionary = settings.get("hud_config")
	var saved_elrs := bool(hud.get("elrs_invert_roll", false))
	var saved_touch := bool(hud.get("touch_invert_roll", false))

	screen.call("_on_virtual_invert_elrs", false)
	screen.call("_on_virtual_invert_touch", false)
	var off_elrs := bool(elrs.get("invert_roll"))
	var off_touch := bool(pad.get("invert_roll"))

	print("[INVQA] on elrs=", on_elrs, " touch=", on_touch,
			" saved=", saved_elrs, "/", saved_touch)
	print("[INVQA] off elrs=", off_elrs, " touch=", off_touch)
	print("[INVQA] ", "PASS" if on_elrs and on_touch and saved_elrs and saved_touch \
			and not off_elrs and not off_touch else "FAIL")

	elrs.set("invert_roll", old_elrs)
	pad.set("invert_roll", old_touch)
	settings.set("game_settings_path", real_path)
	var absolute := ProjectSettings.globalize_path("user://qa_inversion.cfg")
	if FileAccess.file_exists("user://qa_inversion.cfg"):
		DirAccess.remove_absolute(absolute)
	get_tree().quit()
