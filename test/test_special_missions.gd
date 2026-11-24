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
	var had_no_record := OS.has_environment("DRONE_NO_RECORD")
	var saved_no_record := OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("DRONE_NO_RECORD", "1")
	var saved_diff := Global.difficulty
	Global.difficulty = Global.Difficulty.OPERATOR
	var ok := true
	Global.play_mode = Global.PlayMode.COMBAT
	Global.chain_briefing_pending = false
	Global.drone_preset = 2
	for mission_id in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		Global.special_mission = mission_id
		Global.combat_mission = 1
		var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
		var level: Variant = packed.instantiate()
		add_child(level)
		await get_tree().create_timer(3.0).timeout
		get_tree().paused = false
		var label: String = Global.get_special_mission_name(mission_id)
		var kamikaze_extra := get_tree().get_nodes_in_group("enemy_kamikaze").size()
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
				if int(level.get("_mission_targets_total")) != 5 + kamikaze_extra \
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
				if int(level.get("_mission_targets_total")) != 3 + kamikaze_extra \
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
				if int(level.get("_mission_targets_total")) != 6 + kamikaze_extra \
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
			10:
				# Six announced waves of one cruise missile each; none have
				# launched yet while the briefing banner is up.
				if int(level.get("_mission_targets_total")) != 6 + kamikaze_extra \
						or int(level.get("_intercept_wave")) != 0:
					printerr("[SPECIAL] FAIL missile intercept setup: ",
							level.get("_mission_targets_total"), "/",
							level.get("_intercept_wave"))
					ok = false
				else:
					print("[SPECIAL] PASS missile intercept 6 targets / 6 waves")
				level.call("_start_mission")
				level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
				level.call("_check_combat_mission_complete")
				await get_tree().process_frame
				get_tree().paused = false
				var beacon10 := level.get("_special_extract_beacon") as Node3D
				if bool(level.get("_special_extract_active")) \
						or (beacon10 != null and beacon10.visible) \
						or not bool(level.get("_mission_finished")):
					printerr("[SPECIAL] FAIL missile intercept direct completion failed")
					ok = false
				else:
					print("[SPECIAL] PASS missile intercept completes with no exit marker")
			11:
				var c_a := level.get("_special_convoy") as Node3D
				var c_b := level.get("_special_convoy_b") as Node3D
				if c_a == null or c_b == null or c_a == c_b:
					printerr("[SPECIAL] FAIL dual convoy missing second truck")
					ok = false
				else:
					print("[SPECIAL] PASS dual convoy spawns 2 independent trucks")
				var drone11 := level.get_node_or_null("Drone") as Node3D
				var dest_a: Vector3 = level.get("_special_convoy_dest")
				var dest_b: Vector3 = level.get("_special_convoy_b_dest")
				level.call("_start_mission")
				if c_a != null and c_b != null and drone11 != null:
					c_a.global_position = dest_a + Vector3(4.0, 0.0, 0.0)
					c_b.global_position = dest_b + Vector3(4.0, 0.0, 0.0)
					drone11.global_position = dest_a + Vector3(0.0, 12.0, 0.0)
					level.call("_update_special_mission", 0.2)
				await get_tree().process_frame
				get_tree().paused = false
				if not bool(level.get("_mission_finished")) or bool(level.get("_mission_failed")):
					printerr("[SPECIAL] FAIL dual convoy completion check failed")
					ok = false
				else:
					print("[SPECIAL] PASS dual convoy completes when both trucks arrive")
			12:
				if int(level.get("_mission_targets_total")) != 4 + kamikaze_extra \
						or int(level.get("_weather")) != 3 \
						or level.get("_dawn_defense_beacon") == null:
					printerr("[SPECIAL] FAIL hold until dawn setup: ",
							level.get("_mission_targets_total"), "/", level.get("_weather"))
					ok = false
				else:
					print("[SPECIAL] PASS hold until dawn targets=4 weather=3 outpost beacon active")
				level.call("_start_mission")
				level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
				level.call("_update_special_mission", 0.2)
				level.call("_check_combat_mission_complete")
				await get_tree().process_frame
				get_tree().paused = false
				if not bool(level.get("_mission_finished")) or int(level.get("_weather")) != 0:
					printerr("[SPECIAL] FAIL hold until dawn sunrise/completion failed")
					ok = false
				else:
					print("[SPECIAL] PASS hold until dawn transitions to sunrise and completes")
			13:
				var zones13: Array = level.get("_special_zones")
				if zones13.size() != 2 or level.get("_special_pickup_prop") == null:
					printerr("[SPECIAL] FAIL SAR landing setup: ", zones13.size())
					ok = false
				else:
					print("[SPECIAL] PASS SAR landing zones=2 crew prop spawned")
				var drone13 := level.get_node_or_null("Drone") as RigidBody3D
				level.call("_start_mission")
				if drone13 != null and zones13.size() == 2:
					drone13.linear_velocity = Vector3.ZERO
					for z_idx in range(2):
						var zp: Vector3 = zones13[z_idx]["pos"]
						drone13.global_position = zp + Vector3(0.0, 2.5, 0.0)
						for _step in range(16):
							level.call("_update_special_mission", 0.2)
				await get_tree().process_frame
				get_tree().paused = false
				if not bool(level.get("_mission_finished")) or bool(level.get("_mission_failed")):
					printerr("[SPECIAL] FAIL SAR landing completion check failed")
					ok = false
				else:
					print("[SPECIAL] PASS SAR landing completes after low-altitude hover/landing in both zones")
		var title: String = level.call("_mission_title")
		if not title.contains(label):
			printerr("[SPECIAL] FAIL title '", title, "' missing '", label, "'")
			ok = false
		level.queue_free()
		await get_tree().create_timer(0.3).timeout
	Global.special_mission = 0
	Global.difficulty = saved_diff
	if had_no_record:
		OS.set_environment("DRONE_NO_RECORD", saved_no_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	print("[SPECIAL] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
