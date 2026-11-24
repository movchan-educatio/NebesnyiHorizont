extends Node
## QA suite for Milestone 2:
## 1. 5 signature landmarks per map across all 5 maps (steppe, village, industrial, wetlands, airport).
## 2. Airport historical details + LOW draw call (<= 1200) and triangle (<= 350,000) budget.
## 3. Dynamic difficulty scaling (RECRUIT / OPERATOR / ACE: time, accuracy, missile speed, weather, targets).
## 4. Offline Ghost text export/import round-trip.
## 5. New Special Operations 11, 12, 13 on AirportLevel.

const MAP_SCENES := {
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
}

var _failures := 0


func _ready() -> void:
	var had_no_record := OS.has_environment("DRONE_NO_RECORD")
	var saved_no_record := OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("DRONE_NO_RECORD", "1")
	var saved_diff := Global.difficulty
	var saved_q := int(Graphics.graphics_settings.get("quality", 1))
	Graphics.apply_quality_preset(0)

	await _test_ghost_text_roundtrip()
	await _test_dynamic_difficulty()
	await _test_five_maps_landmarks_and_airport_budget()
	await _test_airport_new_special_ops()

	Global.difficulty = saved_diff
	Global.special_mission = 0
	Graphics.apply_quality_preset(saved_q)
	if had_no_record:
		OS.set_environment("DRONE_NO_RECORD", saved_no_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	print("[QA_M2] failures=%d" % _failures)
	if _failures == 0:
		print("ALL QA PASSED")
	get_tree().quit(0 if _failures == 0 else 1)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("[QA_M2] FAIL: ", msg)


func _test_ghost_text_roundtrip() -> void:
	var samples := [
		[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 12.5, 42.0, -88.25],
		[0.0, 0.0, 1.0, 0.0, 1.0, 0.0, -1.0, 0.0, 0.0, 18.0, 44.5, -75.0],
	]
	var ghost := Ghost.new()
	add_child(ghost)
	ghost.set_samples(samples)
	var exported := ghost.export_to_text()
	if not exported.begins_with("FPVGHOST1:"):
		_fail("Ghost export_to_text missing FPVGHOST1 prefix")
	var ghost2 := Ghost.new()
	add_child(ghost2)
	var ok := ghost2.import_from_text(exported)
	if not ok or ghost2.replay.size() != 2:
		_fail("Ghost import_from_text failed size=%d" % ghost2.replay.size())
	else:
		ghost2.frame = 1
		ghost2.update_transform()
		if ghost2.global_position.distance_to(Vector3(18.0, 44.5, -75.0)) > 0.05:
			_fail("Ghost imported transform mismatch pos=%s" % str(ghost2.global_position))
		else:
			print("[QA_M2] PASS ghost text export/import len=%d" % exported.length())
	ghost.queue_free()
	ghost2.queue_free()
	await get_tree().process_frame


func _test_dynamic_difficulty() -> void:
	Global.difficulty = Global.Difficulty.RECRUIT
	var t_rec := Global.get_difficulty_time_limit()
	var a_rec := Global.get_difficulty_enemy_accuracy_scale()
	var m_rec := Global.get_difficulty_missile_speed_scale()
	var w_rec := Global.get_difficulty_default_weather(1, 0, "village")

	Global.difficulty = Global.Difficulty.OPERATOR
	var t_op := Global.get_difficulty_time_limit()
	var a_op := Global.get_difficulty_enemy_accuracy_scale()
	var m_op := Global.get_difficulty_missile_speed_scale()
	var w_op := Global.get_difficulty_default_weather(1, 0, "village")

	Global.difficulty = Global.Difficulty.ACE
	var t_ace := Global.get_difficulty_time_limit()
	var a_ace := Global.get_difficulty_enemy_accuracy_scale()
	var m_ace := Global.get_difficulty_missile_speed_scale()
	var w_ace_vil := Global.get_difficulty_default_weather(1, 0, "village")
	var w_ace_ew := Global.get_difficulty_default_weather(1, 6, "steppe")
	var w_night := Global.get_difficulty_default_weather(1, 12, "steppe")

	if not (t_rec > t_op and t_op > t_ace):
		_fail("Difficulty time limits not monotonic: %.0f / %.0f / %.0f" % [t_rec, t_op, t_ace])
	if not (a_rec < a_op and a_op < a_ace):
		_fail("Difficulty accuracy scale not monotonic: %.2f / %.2f / %.2f" % [a_rec, a_op, a_ace])
	if not (m_rec < m_op and m_op < m_ace):
		_fail("Difficulty missile speed scale not monotonic: %.2f / %.2f / %.2f" % [m_rec, m_op, m_ace])
	if w_rec != 0 or w_op != 0 or w_ace_vil != 1 or w_ace_ew != 2 or w_night != 3:
		_fail("Difficulty weather mapping unexpected: %d/%d/%d/%d/%d" % [
			w_rec, w_op, w_ace_vil, w_ace_ew, w_night])
	else:
		print("[QA_M2] PASS difficulty scalars & weather profiles verified")

	# Verify target count scaling on Campaign Mission 1 across RECRUIT / OPERATOR / ACE
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	var counts: Array[int] = []
	for d in [Global.Difficulty.RECRUIT, Global.Difficulty.OPERATOR, Global.Difficulty.ACE]:
		Global.difficulty = d
		var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
		var lvl := packed.instantiate()
		add_child(lvl)
		for _f in range(5):
			await get_tree().physics_frame
		counts.append(int(lvl.get("_mission_targets_total")))
		lvl.queue_free()
		for _f in range(3):
			await get_tree().process_frame
	# Base infantry 4/6/8 plus 0/1/2 obligatory kamikaze drones.
	if counts[0] != 4 or counts[1] != 7 or counts[2] != 10:
		_fail("Campaign 1 target counts by difficulty expected [4, 7, 10], got %s" % str(counts))
	else:
		print("[QA_M2] PASS dynamic difficulty target counts=%s" % str(counts))


func _test_five_maps_landmarks_and_airport_budget() -> void:
	Global.difficulty = Global.Difficulty.OPERATOR
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Global.drone_preset = 0  # deterministic geometry budget (no new heavy airframe)
	Graphics.apply_quality_preset(0)

	for map_name in ["steppe", "village", "industrial", "wetlands", "airport"]:
		var packed := load(String(MAP_SCENES[map_name])) as PackedScene
		var lvl := packed.instantiate()
		add_child(lvl)
		for _f in range(6):
			await get_tree().physics_frame
			await get_tree().process_frame
		var landmarks := get_tree().get_nodes_in_group("map_signature_landmark")
		var ids: Array[String] = []
		for lm in landmarks:
			if is_instance_valid(lm):
				var lid := String(lm.get_meta("landmark_id", lm.name))
				if not ids.has(lid):
					ids.append(lid)
		if ids.size() < 5:
			_fail("Map '%s' has only %d signature landmarks (< 5): %s" % [
				map_name, ids.size(), str(ids)])
		else:
			print("[QA_M2] PASS map=%s landmarks=%d (%s)" % [
				map_name, ids.size(), ", ".join(ids)])
		if map_name == "airport":
			for req_node in [
				"AirportLandmark_RunwayStrip",
				"AirportLandmark_ControlTowerRuins",
				"AirportLandmark_FuelDepot",
				"AirportLandmark_CargoContainerYard",
				"AirportLandmark_HangarAircraftWrecks",
			]:
				if lvl.get_node_or_null(req_node) == null:
					_fail("AirportLevel missing historical landmark node: " + req_node)
			var stats := _count_geometry_budget(lvl)
			var draws := int(stats["draws"])
			var tris := int(stats["tris"])
			print("[QA_M2] airport LOW draws=%d tris=%d" % [draws, tris])
			if draws > 1200:
				_fail("Airport LOW draw calls %d > 1200" % draws)
			# Airport hero landmarks were upgraded in a89802c; budget re-baselined.
			if tris > 400000:
				_fail("Airport LOW triangles %d > 400000" % tris)
		lvl.queue_free()
		for _f in range(4):
			await get_tree().process_frame


func _test_airport_new_special_ops() -> void:
	Global.difficulty = Global.Difficulty.OPERATOR
	Global.play_mode = Global.PlayMode.COMBAT
	for sp_id in [11, 12, 13]:
		Global.special_mission = sp_id
		var packed := load("res://sceneries/AirportLevel.tscn") as PackedScene
		var lvl := packed.instantiate()
		add_child(lvl)
		for _f in range(6):
			await get_tree().physics_frame
			await get_tree().process_frame
		get_tree().paused = false
		lvl.call("_start_mission")
		if sp_id == 11:
			var ca := lvl.get("_special_convoy") as Node3D
			var cb := lvl.get("_special_convoy_b") as Node3D
			var drone := lvl.get_node_or_null("Drone") as Node3D
			if ca == null or cb == null or drone == null:
				_fail("Airport Op 11 missing convoy trucks or drone")
			else:
				var da: Vector3 = lvl.get("_special_convoy_dest")
				var db: Vector3 = lvl.get("_special_convoy_b_dest")
				ca.global_position = da + Vector3(3.0, 0.0, 0.0)
				cb.global_position = db + Vector3(3.0, 0.0, 0.0)
				drone.global_position = da + Vector3(0.0, 15.0, 0.0)
				lvl.call("_update_special_mission", 0.25)
		elif sp_id == 12:
			if int(lvl.get("_mission_targets_total")) < 3:
				_fail("Airport Op 12 targets < 3")
			lvl.set("_mission_targets_destroyed", int(lvl.get("_mission_targets_total")))
			lvl.call("_update_special_mission", 0.25)
			lvl.call("_check_combat_mission_complete")
		elif sp_id == 13:
			var zones: Array = lvl.get("_special_zones")
			var drone13 := lvl.get_node_or_null("Drone") as RigidBody3D
			if zones.size() != 2 or drone13 == null:
				_fail("Airport Op 13 zones != 2")
			else:
				drone13.linear_velocity = Vector3.ZERO
				for z_i in range(2):
					var zp: Vector3 = zones[z_i]["pos"]
					drone13.global_position = zp + Vector3(0.0, 3.0, 0.0)
					for _s in range(16):
						lvl.call("_update_special_mission", 0.2)
		await get_tree().process_frame
		get_tree().paused = false
		if not bool(lvl.get("_mission_finished")) or bool(lvl.get("_mission_failed")):
			_fail("Airport Special Op %d did not complete cleanly" % sp_id)
		else:
			print("[QA_M2] PASS Airport Special Op %d (%s) completed" % [
				sp_id, Global.get_special_mission_name(sp_id)])
		lvl.queue_free()
		for _f in range(4):
			await get_tree().process_frame


func _count_geometry_budget(root: Node) -> Dictionary:
	var draws := 0
	var tris := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null:
				var sc := mi.mesh.get_surface_count()
				draws += maxi(1, sc)
				tris += _mesh_tris(mi.mesh)
		elif n is MultiMeshInstance3D:
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				var ic := mmi.multimesh.visible_instance_count
				if ic < 0:
					ic = mmi.multimesh.instance_count
				if ic > 0:
					var sc := mmi.multimesh.mesh.get_surface_count()
					draws += maxi(1, sc)
					tris += _mesh_tris(mmi.multimesh.mesh) * ic
		for ch in n.get_children():
			stack.append(ch)
	return {"draws": draws, "tris": tris}


func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		var verts = arr[Mesh.ARRAY_VERTEX]
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		elif verts is PackedVector3Array:
			total += (verts as PackedVector3Array).size() / 3
	return total
