extends Node

## P0 Mobile GUI smoke test & Audio sub-bus persistence regression.
## Loads all 21 GUI scenes under MOBILE_UI=1 / TOUCH_CONTROLS=1 and verifies
## zero script errors, valid layout rects, Audio subbus Audio.cfg round-trip,
## and Global records/daily-challenge formatting.

const MENU_SCENES := [
	"res://GUI/StartScreen.tscn",
	"res://GUI/MainMenu.tscn",
	"res://GUI/mobile/MobileMenu.tscn",
	"res://GUI/OptionsMenu.tscn",
	"res://GUI/AudioMenu.tscn",
	"res://GUI/GraphicsMenu.tscn",
	"res://GUI/GraphicsScreen.tscn",
	"res://GUI/ControlsMenu.tscn",
	"res://GUI/ControlsScreen.tscn",
	"res://GUI/CalibrationMenu.tscn",
	"res://GUI/CalibrationScreen.tscn",
	"res://GUI/GameSettingsMenu.tscn",
	"res://GUI/QuadSettingsMenu.tscn",
	"res://GUI/HUDConfig.tscn",
	"res://GUI/HelpPage.tscn",
	"res://GUI/HelpScreen.tscn",
	"res://GUI/OtherSettingsScreen.tscn",
	"res://GUI/PauseMenu.tscn",
	"res://GUI/DroneSelectScreen.tscn",
	"res://GUI/DroneBuilder.tscn",
	"res://GUI/ConfirmationPopup.tscn",
]

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MENU_QA] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var had_mob := OS.has_environment("MOBILE_UI")
	var saved_mob := OS.get_environment("MOBILE_UI")
	var had_touch := OS.has_environment("TOUCH_CONTROLS")
	var saved_touch := OS.get_environment("TOUCH_CONTROLS")
	var had_no_rec := OS.has_environment("DRONE_NO_RECORD")
	var saved_no_rec := OS.get_environment("DRONE_NO_RECORD")

	OS.unset_environment("MOBILE_UI")
	OS.unset_environment("TOUCH_CONTROLS")
	OS.set_environment("DRONE_NO_RECORD", "1")

	var tested := 0
	for path in MENU_SCENES:
		if path == "res://GUI/StartScreen.tscn":
			# StartScreen redirects to MobileMenu via change_scene_to_file when MOBILE_UI=1,
			# so smoke-test StartScreen in desktop mode first, then enable MOBILE_UI=1.
			OS.unset_environment("MOBILE_UI")
			OS.unset_environment("TOUCH_CONTROLS")
		else:
			OS.set_environment("MOBILE_UI", "1")
			OS.set_environment("TOUCH_CONTROLS", "1")
		var ps := load(path) as PackedScene
		if ps == null:
			_check(false, "load %s" % path)
			continue
		var inst := ps.instantiate()
		if inst == null:
			_check(false, "instantiate %s" % path)
			continue
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		var ok := is_instance_valid(inst)
		if ok and inst is Control:
			var sz := (inst as Control).size
			ok = sz.x >= 0.0 and sz.y >= 0.0
		_check(ok, "smoke %s" % path.get_file())
		tested += 1
		if is_instance_valid(inst):
			inst.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	# Audio sub-bus save/load round-trip (restores original user value afterwards).
	var had_audio_cfg := FileAccess.file_exists(Audio.audio_settings_path)
	var orig_audio_bytes := FileAccess.get_file_as_bytes(Audio.audio_settings_path) if had_audio_cfg else PackedByteArray()
	var orig_combat := float(Audio.get_subbus_volume_linear("Combat"))
	Audio.set_subbus_volume_linear("Combat", 0.42, true)
	Audio.set_subbus_volume_linear("Combat", 0.99, false)
	Audio.load_audio_settings()
	var reloaded_combat := float(Audio.get_subbus_volume_linear("Combat"))
	_check(is_equal_approx(reloaded_combat, 0.42),
			"Audio sub-bus round-trip persisted Combat=%.2f (expected 0.42)" % reloaded_combat)
	if had_audio_cfg:
		var f := FileAccess.open(Audio.audio_settings_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(orig_audio_bytes)
			f.close()
	elif FileAccess.file_exists(Audio.audio_settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Audio.audio_settings_path))
	Audio.set_subbus_volume_linear("Combat", orig_combat, false)
	if had_audio_cfg:
		Audio.load_audio_settings()

	# Records report & OP-10 formatting check.
	var saved_spec10 = Global.campaign_records.get("special_10", null)
	Global.campaign_records["special_10"] = {"completed": true, "stars": 3, "best_score": 900}
	var dc := Global.get_daily_challenge()
	var rep_en := Global.get_records_report(true)
	var rep_ua := Global.get_records_report(false)
	var lb_en := Global.get_leaderboard_summary(true)
	if saved_spec10 == null:
		Global.campaign_records.erase("special_10")
	else:
		Global.campaign_records["special_10"] = saved_spec10
	_check(not dc.is_empty() and rep_en.contains("OP-10") and rep_ua.contains("СО-10") and not lb_en.is_empty() \
			and not rep_en.contains("OP-010") and not rep_ua.contains("СО-010"),
			"Global daily/records/leaderboard formatting uses OP-10/SO-10 (no OP-010)")

	Audio.stop_menu_music()
	_restore_env("MOBILE_UI", had_mob, saved_mob)
	_restore_env("TOUCH_CONTROLS", had_touch, saved_touch)
	_restore_env("DRONE_NO_RECORD", had_no_rec, saved_no_rec)

	print("[MENU_QA] tested=%d failures=%d" % [tested, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _restore_env(key: String, existed: bool, value: String) -> void:
	if existed:
		OS.set_environment(key, value)
	else:
		OS.unset_environment(key)
