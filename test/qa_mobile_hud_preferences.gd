extends Node

## Verify a mobile player's HUD choices survive config loading and level setup.
## The test uses a unique user:// file and restores all in-memory settings.
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOBILE_HUD_PREFS] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var had_mobile := OS.has_environment("MOBILE_UI")
	var mobile_value := OS.get_environment("MOBILE_UI")
	OS.set_environment("MOBILE_UI", "1")
	var settings := get_node("/root/GameSettings")
	var old_path: String = settings.game_settings_path
	var old_config: Dictionary = settings.hud_config.duplicate(true)
	var path := "user://qa_mobile_hud_%d.cfg" % Time.get_ticks_usec()
	settings.game_settings_path = path
	var config := ConfigFile.new()
	var expected := {
		"crosshair": true, "status": true,
		"speed": true, "altitude": true, "heading": true,
		"sticks": false, "osd": false,
	}
	for key in expected:
		config.set_value("hud_config", key, expected[key])
	var err := config.save(path)
	_check(err == OK, "isolated HUD preferences saved")
	if err == OK:
		settings.load_hud_config()
		var loaded := true
		for key in expected:
			loaded = loaded and settings.hud_config.get(key) == expected[key]
		_check(loaded, "saved HUD preferences survive mobile config reload")
		var level := load("res://sceneries/BigLevel.gd").new() as Node
		level.call("_apply_flight_hud_defaults")
		var preserved := true
		for key in expected:
			preserved = preserved and settings.hud_config.get(key) == expected[key]
		_check(preserved, "mobile level setup preserves the player's HUD choices")
		var prior_mode: int = Global.play_mode
		Global.play_mode = Global.PlayMode.TRAINING
		var start_hint := String(level.call("_idle_start_hint"))
		_check(start_hint.contains("АРМ") and not start_hint.contains("SPACE"),
				"mobile launch prompt refers to the ARM control")
		Global.play_mode = prior_mode
		level.free()
	var sight := BombSight.new()
	var prior_preset := int(Global.drone_preset)
	Global.drone_preset = 6
	var expected_preset: Dictionary = DroneCatalog.preset(6)
	var name_key := "name_en" if MenuUI.is_english() else "name"
	_check(sight._airframe_label() == String(expected_preset.get(name_key,
			expected_preset.get("name", "ДРОН"))),
			"bomb sight identifies the selected mobile airframe")
	Global.drone_preset = prior_preset
	var hint := sight._control_hint(false)
	var drop_hint := sight._control_hint(true)
	_check((hint.contains("ВІДЕО") or hint.contains("VIDEO"))
			and not hint.contains("T —"), "mobile bomb sight uses a mobile video hint")
	_check((drop_hint.contains("СКИД") or drop_hint.contains("DROP"))
			and not drop_hint.contains("G —"), "mobile bomb sight uses a mobile drop hint")
	sight.free()
	settings.game_settings_path = old_path
	settings.hud_config = old_config
	if had_mobile:
		OS.set_environment("MOBILE_UI", mobile_value)
	else:
		OS.unset_environment("MOBILE_UI")
	print("[MOBILE_HUD_PREFS] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
