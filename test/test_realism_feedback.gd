extends Node

## Verifies the in-flight feedback hooks: wind cue, JAMMING OSD line and the
## low-voltage tag driven by the combat-realism profile.

var _saved := {}


func _ready() -> void:
	for key in ["wind_sim", "reb_zones", "link_limit", "infinite_battery",
			"realism_profile"]:
		_saved[key] = GameSettings.hud_config[key]

	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	var level: Variant = packed.instantiate()
	add_child(level)
	await get_tree().create_timer(3.0).timeout
	# The combat mission may open its chain briefing and pause the tree; the
	# feedback test needs live physics.
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Apply the preset after the level/drone has loaded its persisted settings.
	GameSettings.apply_realism_profile(GameSettings.REALISM_COMBAT, false)
	await get_tree().create_timer(0.4).timeout
	print("[FEEDBACK] profile=", GameSettings.hud_config.get("realism_profile"),
			" wind=", GameSettings.hud_config.get("wind_sim"),
			" reb=", GameSettings.hud_config.get("reb_zones"),
			" link=", GameSettings.hud_config.get("link_limit"))

	var ok := true
	var indicator: Label = level.get("_wind_indicator")
	if indicator == null or not indicator.visible or not indicator.text.contains("ВІТЕР"):
		printerr("[FEEDBACK] FAIL wind indicator: ", indicator.text if indicator != null else "null")
		ok = false
	else:
		print("[FEEDBACK] PASS wind cue '", indicator.text, "'")

	# Put the drone directly into the first EW dome so the OSD shows JAMMING.
	var drone := level.get_node_or_null("Drone") as Drone
	var reb: RebSystem = level.get("_reb")
	if drone != null and reb != null and not reb.ew_domes.is_empty():
		# The test level is a child of this harness, not the tree's current
		# scene, so wire the REB system to the drone explicitly.
		drone.add_to_group("player_drone")
		reb._drone = drone
		var dome_pos: Vector3 = reb.ew_domes[0].get("position", Vector3.ZERO)
		drone.global_position = dome_pos + Vector3(0.0, 25.0, 0.0)
		await get_tree().create_timer(0.6).timeout
		var telemetry: Label = level.get("_telem_right")
		print("[FEEDBACK] dbg limits=", reb.limits_enabled, " zones=", reb.reb_zones_enabled,
				" drone=", drone.global_position, " dome=", dome_pos,
				" distance=", reb.distance_m, " in_ew=", reb.in_ew,
				" paused=", get_tree().paused)
		if reb.in_ew <= 0.0:
			printerr("[FEEDBACK] FAIL drone is not inside an EW dome")
			ok = false
		elif not bool(level.get("_jamming_announced")):
			printerr("[FEEDBACK] FAIL JAMMING state did not trigger")
			ok = false
		elif telemetry == null or not telemetry.text.contains("LQ"):
			printerr("[FEEDBACK] FAIL LQ telemetry missing")
			ok = false
		else:
			print("[FEEDBACK] PASS jamming in_ew=%.2f LQ line present" % reb.in_ew)
	else:
		printerr("[FEEDBACK] FAIL missing drone or EW domes")
		ok = false

	# A nearby hostile SAM must light the direction-of-threat indicator.
	var vehicle_script = load("res://combat/vehicle.gd")
	if vehicle_script != null and drone != null:
		var sam: Vehicle = vehicle_script.new()
		sam.kind = Vehicle.Kind.SAM
		sam.hostile = true
		sam.track_drone = true
		level.add_child(sam)
		sam.global_position = drone.global_position + Vector3(120.0, 0.0, 0.0)
		await get_tree().create_timer(0.6).timeout
		var threat: Label = level.get("_threat_indicator")
		if threat == null or not threat.visible or not threat.text.contains("ЗРК"):
			printerr("[FEEDBACK] FAIL threat indicator: ",
					threat.text if threat != null else "null")
			ok = false
		else:
			print("[FEEDBACK] PASS threat indicator '", threat.text, "'")
		sam.queue_free()
	else:
		printerr("[FEEDBACK] FAIL could not load Vehicle for threat test")
		ok = false

	# Radio callouts must also produce a readable subtitle for the pilot.
	level.call("_play_radio_callout", "ТЕСТ РАДІО", true)
	await get_tree().create_timer(0.15).timeout
	var subtitle: Label = level.get("_radio_subtitle")
	if subtitle == null or not subtitle.visible or not subtitle.text.contains("ТЕСТ РАДІО"):
		printerr("[FEEDBACK] FAIL radio subtitle: ",
				subtitle.text if subtitle != null else "null")
		ok = false
	else:
		print("[FEEDBACK] PASS radio subtitle")

	# Simulate a drained pack (3.3 V/cell).  Unarmed telemetry reads _battery.
	level.set("_battery", 19.8)
	await get_tree().create_timer(0.4).timeout
	var telemetry2: Label = level.get("_telem_right")
	if telemetry2 == null or not (telemetry2.text.contains("LOW VOLTAGE!")
			or telemetry2.text.contains("НИЗЬКА НАПРУГА")):
		printerr("[FEEDBACK] FAIL low-voltage tag missing: ",
				telemetry2.text if telemetry2 != null else "null")
		ok = false
	elif not bool(level.get("_low_battery_announced")):
		printerr("[FEEDBACK] FAIL low-battery announcement did not trigger")
		ok = false
	else:
		print("[FEEDBACK] PASS low-voltage warning")

	for key in _saved.keys():
		GameSettings.hud_config[key] = _saved[key]
	print("[FEEDBACK] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
