extends Node

## Smoke test for the standalone special operations: zones, convoy, night
## strike and EW breach all spawn with their own objective state.

func _has_vehicle_variant(level: Node, wanted: String) -> bool:
	var vehs: Array = level.get("_vehicles")
	for uv in vehs:
		if is_instance_valid(uv) and String(uv.get("variant")) == wanted:
			return true
	return false


func _has_infantry_variant(level: Node, wanted: String) -> bool:
	var infs: Array = level.get("_infantry_units")
	for ui in infs:
		if is_instance_valid(ui) and String(ui.get("variant")) == wanted:
			return true
	return false


func _ready() -> void:
	var ok := true
	Global.play_mode = Global.PlayMode.COMBAT
	Global.chain_briefing_pending = false
	Global.drone_preset = 2
	for mission_id in [1, 2, 3, 4, 5, 6, 7, 8, 9]:
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
				# Strike targets are down: mission completes directly with no lingering exit marker.
				level.call("_start_mission")
				level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
				level.call("_check_combat_mission_complete")
				await get_tree().process_frame
				get_tree().paused = false
				var beacon := level.get("_special_extract_beacon") as Node3D
				if bool(level.get("_special_extract_active")) \
						or (beacon != null and beacon.visible) \
						or not bool(level.get("_mission_finished")):
					printerr("[SPECIAL] FAIL strike direct completion failed or left extract marker")
					ok = false
				else:
					print("[SPECIAL] PASS night strike completes directly with no exit marker")
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
			7:
				if int(level.get("_mission_targets_total")) != 5 \
						or not _has_vehicle_variant(level, "btr8") \
						or not _has_vehicle_variant(level, "mtsm") \
						or not _has_vehicle_variant(level, "ural") \
						or not _has_infantry_variant(level, "spetsnaz"):
					printerr("[SPECIAL] FAIL rear convoy missing models/targets: ",
							level.get("_mission_targets_total"))
					ok = false
				else:
					print("[SPECIAL] PASS rear convoy spawns btr8+mtsm+ural+spetsnaz targets=5")
			8:
				if int(level.get("_mission_targets_total")) != 3 \
						or not _has_vehicle_variant(level, "oreshnik") \
						or not _has_vehicle_variant(level, "btr8") \
						or not _has_vehicle_variant(level, "ural"):
					printerr("[SPECIAL] FAIL oreshnik strike missing models/targets: ",
							level.get("_mission_targets_total"))
					ok = false
				else:
					print("[SPECIAL] PASS oreshnik strike spawns oreshnik+btr8+ural targets=3")
			9:
				var reb9: RebSystem = level.get("_reb")
				if int(level.get("_mission_targets_total")) != 6 \
						or reb9 == null or reb9.ew_domes.size() < 4 \
						or not _has_vehicle_variant(level, "oreshnik") \
						or not _has_vehicle_variant(level, "mtsm") \
						or not _has_vehicle_variant(level, "btr8") \
						or not _has_infantry_variant(level, "spetsnaz"):
					printerr("[SPECIAL] FAIL deep strike missing models/ew/targets: ",
							level.get("_mission_targets_total"), "/",
							reb9.ew_domes.size() if reb9 != null else -1)
					ok = false
				else:
					print("[SPECIAL] PASS deep strike spawns oreshnik+sam+mtsm+btr8+spetsnaz domes=",
							reb9.ew_domes.size())
				level.call("_start_mission")
				level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
				level.call("_check_combat_mission_complete")
				await get_tree().process_frame
				get_tree().paused = false
				var beacon9 := level.get("_special_extract_beacon") as Node3D
				if bool(level.get("_special_extract_active")) \
						or (beacon9 != null and beacon9.visible) \
						or not bool(level.get("_mission_finished")):
					printerr("[SPECIAL] FAIL deep strike direct completion failed or left extract marker")
					ok = false
				else:
					print("[SPECIAL] PASS deep strike completes directly with no exit marker")
		var title: String = level.call("_mission_title")
		if not title.contains(label):
			printerr("[SPECIAL] FAIL title '", title, "' missing '", label, "'")
			ok = false
		level.queue_free()
		await get_tree().create_timer(0.3).timeout
	Global.special_mission = 0
	print("[SPECIAL] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
