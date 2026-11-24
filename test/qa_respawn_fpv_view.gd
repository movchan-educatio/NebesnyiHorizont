extends Node

## Regression test: FPV camera framing, warhead visibility, and propeller hiding
## must survive respawn (_on_respawned), kamikaze respawn, QuadSettings updates,
## and direct DroneCatalog.apply_to_drone() calls across all drone presets.

var _failures := 0
var _shot_dir := ""


func _ready() -> void:
	_shot_dir = OS.get_environment("QA_SHOT_DIR").strip_edges()
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[RESPAWN_FPV] PASS ", label)
	else:
		_failures += 1
		printerr("[RESPAWN_FPV] FAIL ", label)


func _visible_prop_count(drone: Node) -> int:
	var count := 0
	if drone == null:
		return 0
	var dm := drone.get_node_or_null("DroneModel")
	if dm != null:
		for n in dm.find_children("*", "Node3D", true, false):
			if n.is_in_group("drone_prop_pivot") and (n as Node3D).is_visible_in_tree():
				count += 1
		for mi in dm.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var low := String(m.name).to_lower()
			if m.is_visible_in_tree() and (low.contains("newpropmesh") or low.contains("newmotorbell") \
					or low.contains("propeller") or low.contains("motor_fl") or low.contains("motor_fr")):
				count += 1
	for prop in drone.find_children("*", "Propeller", true, false):
		if prop is VisualInstance3D and (prop as VisualInstance3D).is_visible_in_tree():
			count += 1
	return count


func _visible_mesh_count(dm: Node) -> int:
	if dm == null:
		return 0
	var c := 0
	for mi in dm.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.is_visible_in_tree() and m.mesh != null:
			c += 1
	return c


func _save_shot(filename: String) -> void:
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var path := _shot_dir.path_join(filename)
		var err := img.save_png(path)
		print("[RESPAWN_FPV] shot ", path, " err=", err)


func _verify_state(level: Node, tag: String, expected_cam_pos: Vector3,
		expected_cam_rot: Vector3, expected_model_vis: bool, expected_mesh_cnt: int,
		expected_prop_vis: int = 0) -> void:
	var d := level.get_node_or_null("Drone") as Node3D
	var cam := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	var dm := d.get_node_or_null("DroneModel") as Node3D if d != null else null
	var mr = level.get("_model_root")
	_check(d != null and d.visible, "%s: Drone is visible" % tag)
	_check(dm != null and is_instance_valid(dm), "%s: DroneModel exists" % tag)
	_check(mr != null and is_instance_valid(mr) and mr == dm, "%s: _model_root matches live DroneModel" % tag)
	_check(cam != null and cam.position.distance_to(expected_cam_pos) < 0.003,
			"%s: FPVCamera pos=%s matches expected=%s" % [tag, str(cam.position if cam else Vector3.ZERO), str(expected_cam_pos)])
	_check(cam != null and cam.rotation_degrees.distance_to(expected_cam_rot) < 0.5,
			"%s: FPVCamera rot=%s matches expected=%s" % [tag, str(cam.rotation_degrees if cam else Vector3.ZERO), str(expected_cam_rot)])
	_check(dm != null and dm.visible == expected_model_vis,
			"%s: DroneModel.visible=%s expected=%s" % [tag, str(dm.visible if dm else false), str(expected_model_vis)])
	var prop_vis := _visible_prop_count(d)
	_check(prop_vis == expected_prop_vis,
			"%s: %d visible propeller pivots/meshes in FPV (got %d)" % [
					tag, expected_prop_vis, prop_vis])
	var mesh_cnt := _visible_mesh_count(dm)
	_check(mesh_cnt == expected_mesh_cnt,
			"%s: visible mesh count=%d matches initial=%d" % [tag, mesh_cnt, expected_mesh_cnt])


func _run() -> void:
	var saved_mode := Global.play_mode
	var saved_special := Global.special_mission
	var saved_preset := Global.drone_preset
	var saved_rig: bool = bool(GameSettings.hud_config.get("fpv_rig", true))
	GameSettings.hud_config["fpv_rig"] = true

	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 10
	Global.drone_preset = 5 # Start with military_fpv (tactical_uav.glb)

	var packed := load("res://sceneries/AirportLevel.tscn") as PackedScene
	var level := packed.instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	for _i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame

	var d := level.get_node_or_null("Drone") as Node3D
	var cam := level.get_node_or_null("Drone/FPVCamera") as Camera3D

	# Test every preset in DroneCatalog on AirportLevel!
	var shot_presets := {5: "military_fpv", 2: "strila8", 0: "grim7", 1: "grim7m"}
	for idx in range(DroneCatalog.count()):
		var p := DroneCatalog.preset(idx)
		var pid := str(p.get("id", str(idx)))
		Global.drone_preset = idx
		DroneCatalog.apply_to_drone(d, idx)
		await get_tree().process_frame

		var init_pos := cam.position
		var init_rot := cam.rotation_degrees
		var dm := d.get_node_or_null("DroneModel") as Node3D
		var hide_expected := bool(p.get("fpv_hide_model", false)) or bool(p.get("heavy_bomber", false))
		var init_vis := (not hide_expected) and bool(p.get("combat", false))
		if idx >= 10:
			init_vis = true  # freestyle + new airframes intentionally show the model
		var init_meshes := _visible_mesh_count(dm)
		# Visible props are intentional on these airframes (see commits af2a7c8/274efd0).
		var prop_expectations := {3: 16, 7: 2, 8: 2, 10: 12, 11: 16, 12: 16,
				13: 4, 14: 4, 15: 4}
		var expected_props := int(prop_expectations.get(idx, 0))

		_verify_state(level, "Airport[%d:%s] after apply" % [idx, pid],
				init_pos, init_rot, init_vis, init_meshes, expected_props)

		# 1. Trigger respawn (_on_respawned)
		level.call("_on_respawned")
		await get_tree().process_frame
		_verify_state(level, "Airport[%d:%s] after _on_respawned" % [idx, pid],
				init_pos, init_rot, init_vis, init_meshes, expected_props)

		if shot_presets.has(idx):
			await _save_shot("fixed_%s_after_respawn.png" % shot_presets[idx])

		# 2. Trigger QuadSettings.settings_updated (mid-flight Pause -> Rates change)
		QuadSettings.settings_updated.emit()
		await get_tree().process_frame
		_verify_state(level, "Airport[%d:%s] after QuadSettings.settings_updated" % [idx, pid],
				init_pos, init_rot, init_vis, init_meshes, expected_props)

		# 3. Trigger full Drone._on_reset() path
		await d.call("_on_reset")
		await get_tree().process_frame
		_verify_state(level, "Airport[%d:%s] after Drone._on_reset" % [idx, pid],
				init_pos, init_rot, init_vis, init_meshes, expected_props)

	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# Also verify on SteppeLevel (BigLevel base) with preset 5 (military_fpv) and preset 2 (strila8)
	var steppe_packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	Global.drone_preset = 5
	var steppe := steppe_packed.instantiate()
	get_tree().root.add_child(steppe)
	get_tree().current_scene = steppe
	for _i in range(20):
		await get_tree().physics_frame
		await get_tree().process_frame
	var sd := steppe.get_node_or_null("Drone") as Node3D
	var scam := steppe.get_node_or_null("Drone/FPVCamera") as Camera3D
	for idx in [5, 2, 0]:
		Global.drone_preset = idx
		DroneCatalog.apply_to_drone(sd, idx)
		await get_tree().process_frame
		var init_pos := scam.position
		var init_rot := scam.rotation_degrees
		var sdm := sd.get_node_or_null("DroneModel") as Node3D
		var init_meshes := _visible_mesh_count(sdm)
		steppe.call("_on_respawned")
		await get_tree().process_frame
		_verify_state(steppe, "Steppe[%d] after _on_respawned" % idx,
				init_pos, init_rot, true, init_meshes)
		QuadSettings.settings_updated.emit()
		await get_tree().process_frame
		_verify_state(steppe, "Steppe[%d] after QuadSettings.settings_updated" % idx,
				init_pos, init_rot, true, init_meshes)
	steppe.queue_free()
	await get_tree().process_frame

	Global.play_mode = saved_mode
	Global.special_mission = saved_special
	Global.drone_preset = saved_preset
	GameSettings.hud_config["fpv_rig"] = saved_rig

	print("[RESPAWN_FPV] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
