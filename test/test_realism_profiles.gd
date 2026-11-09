extends Node

## Verifies the Arcade / Combat realism presets and the independent REB gate.

var _saved := {}


func _ready() -> void:
	for key in ["wind_sim", "reb_zones", "link_limit", "infinite_battery",
			"realism_profile"]:
		_saved[key] = GameSettings.hud_config[key]

	var ok := true

	# Arcade: calm air, no EW, unlimited link, pack assist.
	GameSettings.apply_realism_profile(GameSettings.REALISM_ARCADE, false)
	ok = _expect_profile(GameSettings.REALISM_ARCADE, false, false, false, true) and ok

	# Combat realism: every field effect on.
	GameSettings.apply_realism_profile(GameSettings.REALISM_COMBAT, false)
	ok = _expect_profile(GameSettings.REALISM_COMBAT, true, true, true, false) and ok

	# A manual override leaves the preset and is reported as "custom".
	GameSettings.hud_config["wind_sim"] = false
	var derived := GameSettings.refresh_realism_profile()
	if derived != GameSettings.REALISM_CUSTOM:
		printerr("[REALISM] FAIL manual override profile: ", derived)
		ok = false
	else:
		print("[REALISM] PASS manual override -> custom")

	# Migration from an older file where REB was bundled into link_limit.
	var old_path := GameSettings.game_settings_path
	var temp_path := "user://test_realism_migration.cfg"
	var old_cfg := ConfigFile.new()
	old_cfg.set_value("hud_config", "link_limit", true)
	old_cfg.set_value("hud_config", "wind_sim", true)
	old_cfg.set_value("hud_config", "infinite_battery", false)
	if old_cfg.save(temp_path) == OK:
		GameSettings.game_settings_path = temp_path
		GameSettings.load_hud_config()
		if not bool(GameSettings.hud_config.get("reb_zones", false)) \
				or String(GameSettings.hud_config.get("realism_profile", "")) \
						!= GameSettings.REALISM_COMBAT:
			printerr("[REALISM] FAIL old config migration")
			ok = false
		else:
			print("[REALISM] PASS old config migration -> combat")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		GameSettings.game_settings_path = old_path
	else:
		printerr("[REALISM] FAIL could not write migration fixture")
		ok = false

	# REB zones can be disabled while distance/terrain link loss stays active.
	GameSettings.hud_config["link_limit"] = true
	GameSettings.hud_config["reb_zones"] = false
	var target := Node3D.new()
	target.name = "Drone"
	target.add_to_group("player_drone")
	add_child(target)
	target.global_position = Vector3(50.0, 20.0, 0.0)
	var reb := RebSystem.new()
	reb.name = "RebSystem"
	reb.use_own_position_as_home = false
	reb.home_position = Vector3.ZERO
	add_child(reb)
	reb.add_ew_dome(Vector3(50.0, 0.0, 0.0), 220.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not reb.limits_enabled:
		printerr("[REALISM] FAIL link limits should stay enabled for this check")
		ok = false
	if reb.in_ew > 0.0 or reb._masts[0].visible:
		printerr("[REALISM] FAIL reb_zones=false must hide EW effect and mast")
		ok = false
	else:
		print("[REALISM] PASS REB zones off -> range link active, no jamming")

	GameSettings.hud_config["reb_zones"] = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if reb.in_ew <= 0.0:
		printerr("[REALISM] FAIL reb_zones=true did not engage EW")
		ok = false
	elif not reb._masts[0].visible:
		printerr("[REALISM] FAIL EW mast did not reappear")
		ok = false
	else:
		print("[REALISM] PASS REB zones on -> in_ew=%.2f" % reb.in_ew)

	for key in _saved.keys():
		GameSettings.hud_config[key] = _saved[key]
	print("[REALISM] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _expect_profile(profile: String, wind: bool, reb: bool, link: bool,
		infinite: bool) -> bool:
	var hc := GameSettings.hud_config
	var actual := String(hc.get("realism_profile", ""))
	var good := actual == profile \
			and bool(hc.get("wind_sim", not wind)) == wind \
			and bool(hc.get("reb_zones", not reb)) == reb \
			and bool(hc.get("link_limit", not link)) == link \
			and bool(hc.get("infinite_battery", not infinite)) == infinite
	if good:
		print("[REALISM] PASS profile ", profile)
	else:
		printerr("[REALISM] FAIL profile ", profile, ": ", actual,
				" wind=", hc.get("wind_sim"), " reb=", hc.get("reb_zones"),
				" link=", hc.get("link_limit"), " inf=", hc.get("infinite_battery"))
	return good
