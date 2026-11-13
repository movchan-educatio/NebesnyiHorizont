extends Node

## Smoke test for the standalone special operations: zones, convoy, night
## strike and EW breach all spawn with their own objective state.

func _ready() -> void:
	var ok := true
	Global.play_mode = Global.PlayMode.COMBAT
	Global.chain_briefing_pending = false
	Global.drone_preset = 2
	for mission_id in [1, 2, 3, 4, 5, 6]:
		Global.special_mission = mission_id
		Global.combat_mission = 1
		var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
		var level: Variant = packed.instantiate()
		add_child(level)
		await get_tree().create_timer(3.0).timeout
		get_tree().paused = false
		var label: String = Global.get_special_mission_name(mission_id)
		match mission_id:
			1:
				var zones: Array = level.get("_special_zones")
				var beacons: Array = level.get("_special_beacons")
				if zones.size() != 3 or beacons.size() != 3:
					printerr("[SPECIAL] FAIL recon zones/beacons: ", zones.size(), "/", beacons.size())
					ok = false
				else:
					print("[SPECIAL] PASS recon zones=3 beacons=3")
			2:
				if level.get("_special_convoy") == null:
					printerr("[SPECIAL] FAIL escort convoy missing")
					ok = false
				else:
					print("[SPECIAL] PASS escort convoy spawned")
			3, 4:
				var zones: Array = level.get("_special_zones")
				if zones.size() != 2 or level.get("_special_pickup_prop") == null:
					printerr("[SPECIAL] FAIL zone mission props: ", zones.size())
					ok = false
				else:
					print("[SPECIAL] PASS zone mission zones=2 pickup prop spawned")
			5:
				if int(level.get("_mission_targets_total")) < 2 \
						or int(level.get("_weather")) != 3:
					printerr("[SPECIAL] FAIL night strike targets/weather: ",
							level.get("_mission_targets_total"), "/", level.get("_weather"))
					ok = false
				else:
					print("[SPECIAL] PASS night strike targets=2 weather=3")
				# Strike targets are down: the mission now requires extraction.
				level.call("_start_mission")
				level.call("_enter_special_extraction")
				var strike_drone := level.get_node_or_null("Drone") as Drone
				if strike_drone == null or not bool(level.get("_special_extract_active")):
					printerr("[SPECIAL] FAIL strike extraction did not activate")
					ok = false
				else:
					var extract: Vector3 = level.get("_special_extract_point")
					strike_drone.global_position = extract + Vector3.UP * 3.0
					await get_tree().create_timer(3.5).timeout
					get_tree().paused = false
					if not bool(level.get("_mission_finished")):
						printerr("[SPECIAL] FAIL strike extraction did not complete")
						ok = false
					else:
						print("[SPECIAL] PASS strike extraction -> mission complete")
			6:
				var reb: RebSystem = level.get("_reb")
				if int(level.get("_mission_targets_total")) < 2 \
						or reb == null or reb.ew_domes.size() < 4:
					printerr("[SPECIAL] FAIL EW breach targets/domes: ",
							level.get("_mission_targets_total"), "/",
							reb.ew_domes.size() if reb != null else -1)
					ok = false
				else:
					print("[SPECIAL] PASS EW breach targets=2 domes=", reb.ew_domes.size())
		var title: String = level.call("_mission_title")
		if not title.contains(label):
			printerr("[SPECIAL] FAIL title '", title, "' missing '", label, "'")
			ok = false
		level.queue_free()
		await get_tree().create_timer(0.3).timeout
	Global.special_mission = 0
	print("[SPECIAL] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
