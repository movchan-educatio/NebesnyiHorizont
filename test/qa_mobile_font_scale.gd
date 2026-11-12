extends Node

## Mobile accessibility regression: the interface font scale setting changes
## _fs() and a live _rebuild_screens() re-lays the whole menu at the new size.
## Also verifies GameSettings clamps an out-of-range saved value on load.
const TEST_NAME := "MOBILE_FONT_SCALE"
var _failures := 0
var _saved_scale := 1.0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_saved_scale = float(GameSettings.hud_config.get("mobile_font_scale", 1.0))
	GameSettings.hud_config["mobile_font_scale"] = 1.0
	var menu = (load("res://GUI/mobile/MobileMenu.tscn") as PackedScene).instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var base := int(menu.call("_fs", 20.0))
	_check(base >= 16, "menu builds with the default font scale (%d px)" % base)
	GameSettings.hud_config["mobile_font_scale"] = 1.4
	var big := int(menu.call("_fs", 20.0))
	_check(big > base, "font scale setting enlarges _fs (%d > %d px)" % [big, base])
	menu.call("_rebuild_screens")
	await get_tree().process_frame
	menu.call("_show", "settings")
	await get_tree().process_frame
	var screens: Dictionary = menu.get("_screens")
	_check(not screens.is_empty(), "menu screens rebuild after a scale change")
	var title_resized := false
	if screens.has("settings"):
		var settings_screen: Control = screens["settings"]
		for l in settings_screen.find_children("*", "Label", true, false):
			var label := l as Label
			if label.text.begins_with("НАЛАШТУВАННЯ ТА СИМУЛЯЦІЯ"):
				title_resized = label.get_theme_font_size("font_size") \
						== int(menu.call("_fs", 32.0))
	_check(title_resized, "settings title uses the enlarged font after rebuild")
	menu.queue_free()

	# Clamp behaviour on load: an out-of-range saved value must come back as
	# 1.45 without touching the real settings file.
	var gs := get_node_or_null("/root/GameSettings")
	var real_path: String = gs.game_settings_path
	var tmp_path := "user://qa_font_scale_tmp.cfg"
	var cf := ConfigFile.new()
	cf.set_value("hud_config", "mobile_font_scale", 9.9)
	cf.save(tmp_path)
	gs.game_settings_path = tmp_path
	gs.load_hud_config()
	_check(absf(float(gs.hud_config["mobile_font_scale"]) - 1.45) < 0.001,
			"out-of-range saved scale clamps to 1.45")
	gs.game_settings_path = real_path
	gs.load_hud_config()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	GameSettings.hud_config["mobile_font_scale"] = _saved_scale
	GameSettings.save_hud_config()
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
