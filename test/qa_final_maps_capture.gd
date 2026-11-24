extends Node
## Reusable visual + performance capture harness for Lis Forest and Oil Rig.
## Saves reference-angle PNGs and mobile-LOW performance telemetry to QA_SHOT_OUT.
## Usage (windowed):
##   Godot --path . res://test/qa_final_maps_capture.tscn

var _cam: Camera3D = null
var _out_dir := "qa_shots/final_maps_baseline"
var _metrics: Dictionary = {"views": {}, "summary": {}}


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_QUALITY", "low")
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	var env_out := OS.get_environment("QA_SHOT_OUT").strip_edges()
	if not env_out.is_empty():
		_out_dir = env_out.trim_suffix("/")
	var capture_mode := OS.get_environment("QA_CAPTURE_MODE").strip_edges().to_lower()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out_dir))
	if capture_mode == "hero":
		get_window().size = Vector2i(1920, 1080)
		await _capture_hero_cards()
		get_tree().quit(0)
		return

	get_window().size = Vector2i(1280, 720)
	await _capture_forest()
	await _capture_oilrig()

	var summary_path := ProjectSettings.globalize_path("res://" + _out_dir + "/metrics.json")
	var f := FileAccess.open(summary_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_metrics, "  "))
		f.close()
	print("[FINAL-CAP] saved metrics to ", _out_dir, "/metrics.json")
	print("[FINAL-CAP] SUMMARY=", JSON.stringify(_metrics["summary"]))
	get_tree().quit(0)


func _hide_all_ui(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is Control and node != self and not (node is SubViewportContainer):
		var p := node.get_parent()
		if p is CanvasLayer or p == get_tree().root:
			(node as Control).visible = false
	for ch in node.get_children():
		_hide_all_ui(ch)


func _set_cam(parent: Node, at: Vector3, look: Vector3, fov: float = 70.0) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.near = 0.25
		_cam.far = 6000.0
		parent.add_child(_cam)
	_cam.fov = fov
	_cam.global_position = at
	if at.distance_squared_to(look) > 0.01:
		var up := Vector3.UP
		if absf((look - at).normalized().dot(Vector3.UP)) > 0.99:
			up = Vector3.FORWARD
		_cam.look_at(look, up)
	_cam.current = true


func _clear_cam() -> void:
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


func _sample_perf_and_save(tag: String, filename: String, wait_frames: int = 12) -> void:
	_hide_all_ui(get_tree().root)
	# Warm up camera frustum/shaders before timing
	for _i in range(4):
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for _i in range(wait_frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dt_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(wait_frames)
	var measured_fps := 1000.0 / maxf(dt_ms, 0.01)
	var dc := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var eng_fps := float(Performance.get_monitor(Performance.TIME_FPS))
	var cpu_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var vram_mb := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	_metrics["views"][tag] = {
		"draw_calls": dc,
		"primitives": prims,
		"objects": objs,
		"measured_fps": snappedf(measured_fps, 0.1),
		"engine_fps": snappedf(eng_fps, 0.1),
		"frame_ms": snappedf(dt_ms, 0.01),
		"cpu_ms": snappedf(cpu_ms, 0.01),
		"vram_mb": snappedf(vram_mb, 0.1),
	}
	print("[FINAL-CAP] %-26s dc=%4d tris=%7d fps=%5.1f (%.2fms) vram=%.1fMB" % [
		tag, dc, prims, measured_fps, dt_ms, vram_mb
	])
	var img := get_viewport().get_texture().get_image()
	if img != null:
		var out_p := ProjectSettings.globalize_path("res://" + _out_dir + "/" + filename)
		img.save_png(out_p)


func _ground_y_of(level: Node, x: float, z: float) -> float:
	if level != null and level.has_method("_find_ground_y"):
		return float(level.call("_find_ground_y", x, z))
	return 8.0


func _capture_forest() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Global.difficulty = Global.Difficulty.OPERATOR
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(2.0).timeout
	_hide_all_ui(get_tree().root)
	if level.has_method("_hide_mobile_gameplay_hud"):
		level.call("_hide_mobile_gameplay_hud")
	var drone := level.get_node_or_null("Drone") as Node3D
	if drone != null:
		drone.visible = false

	var lis := level.find_child("LisFreestyleMap", true, false)
	var scatter_inst := 0
	var scatter_chunks := 0
	var bank_rocks := 0
	var kit_visible := 0
	var fpv_gates := 0
	if lis != null:
		var sc := lis.find_child("ScatterMultiMesh", true, false)
		if sc != null:
			for mmi in sc.find_children("*", "MultiMeshInstance3D", true, false):
				var mm := (mmi as MultiMeshInstance3D).multimesh
				if mm != null:
					scatter_chunks += 1
					scatter_inst += mm.instance_count
		for ch in lis.find_children("bank_rock_*", "MeshInstance3D", true, false):
			if (ch as MeshInstance3D).visible:
				bank_rocks += 1
		for ch in lis.find_children("kit_*", "Node3D", true, false):
			if (ch as Node3D).visible:
				kit_visible += 1
		var fg := lis.get_node_or_null("FPVGates")
		if fg != null:
			fpv_gates = fg.get_child_count()

	_metrics["summary"]["forest"] = {
		"scatter_chunks": scatter_chunks,
		"scatter_instances": scatter_inst,
		"visible_bank_rock_nodes": bank_rocks,
		"visible_kit_nodes": kit_visible,
		"fpv_gates_nodes": fpv_gates,
		"rings_total": int(level.get("_rings_total")),
	}

	_set_cam(level, Vector3(0.0, 460.0, 1.0), Vector3(0.0, 0.0, 0.0), 62.0)
	await _sample_perf_and_save("lis_01_topdown", "lis_01_topdown.png")

	_set_cam(level, Vector3(-430.0, 300.0, 520.0), Vector3(0.0, 12.0, -10.0), 60.0)
	await _sample_perf_and_save("lis_02_aerial", "lis_02_aerial.png")

	var gy3 := _ground_y_of(level, -98.0, 192.0)
	_set_cam(level, Vector3(-98.0, gy3 + 12.0, 192.0), Vector3(-70.0, 10.0, 120.0), 78.0)
	await _sample_perf_and_save("lis_03_sawmill", "lis_03_sawmill.png")

	var gy4 := _ground_y_of(level, 8.0, 22.0)
	_set_cam(level, Vector3(8.0, maxf(gy4 + 12.0, 8.0), 22.0), Vector3(18.0, -4.0, -80.0), 78.0)
	await _sample_perf_and_save("lis_04_river_bridges", "lis_04_river_bridges.png")

	var gy5 := _ground_y_of(level, 198.0, -98.0)
	_set_cam(level, Vector3(198.0, gy5 + 14.0, -98.0), Vector3(195.0, 42.0, -165.0), 78.0)
	await _sample_perf_and_save("lis_05_watchtower", "lis_05_watchtower.png")

	var gy6 := _ground_y_of(level, -218.0, -38.0)
	_set_cam(level, Vector3(-218.0, gy6 + 12.0, -38.0), Vector3(-190.0, 18.0, -110.0), 78.0)
	await _sample_perf_and_save("lis_06_ruins", "lis_06_ruins.png")

	var gy7 := _ground_y_of(level, 152.0, 172.0)
	_set_cam(level, Vector3(152.0, gy7 + 14.0, 172.0), Vector3(150.0, 22.0, 60.0), 78.0)
	await _sample_perf_and_save("lis_07_treehouse", "lis_07_treehouse.png")

	var gy8 := _ground_y_of(level, 95.0, 305.0)
	_set_cam(level, Vector3(95.0, gy8 + 14.0, 305.0), Vector3(95.0, 14.0, 180.0), 78.0)
	await _sample_perf_and_save("lis_08_trestle", "lis_08_trestle.png")

	_set_cam(level, Vector3(0.0, 38.0, 85.0), Vector3(0.0, 0.0, 0.0), 72.0)
	await _sample_perf_and_save("lis_center_origin", "lis_center_origin.png")

	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _capture_oilrig() -> void:
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/OilRigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(2.0).timeout
	_hide_all_ui(get_tree().root)
	if level.has_method("_hide_mobile_gameplay_hud"):
		level.call("_hide_mobile_gameplay_hud")
	var drone := level.get_node_or_null("Drone") as Node3D
	if drone != null:
		drone.visible = false

	var rig := level.find_child("OilRigMap", true, false)
	var cols := 0
	var spawns := 0
	var gates := 0
	var posts := 0
	var visible_rings := 0
	if rig != null:
		var mc := rig.get_node_or_null("MapColliders")
		if mc != null:
			cols = mc.get_child_count()
		var sp := rig.get_node_or_null("SpawnPoints")
		if sp != null:
			spawns = sp.get_child_count()
		var fg := rig.get_node_or_null("FPVGates")
		if fg != null:
			gates = fg.get_child_count()
		var rp := rig.find_child("RailPosts", true, false) as MultiMeshInstance3D
		if rp != null and rp.multimesh != null:
			posts = rp.multimesh.instance_count
		var vr := rig.find_child("VisibleGateRings", true, false) as MultiMeshInstance3D
		if vr != null and vr.multimesh != null:
			visible_rings = vr.multimesh.instance_count

	_metrics["summary"]["oilrig"] = {
		"colliders": cols,
		"spawns": spawns,
		"fpv_gates": gates,
		"rail_posts": posts,
		"visible_rings": visible_rings,
		"biglevel_rings_total": int(level.get("_rings_total")),
	}

	_set_cam(level, Vector3(1150.0, 740.0, 1280.0), Vector3(0.0, 260.0, 0.0), 52.0)
	await _sample_perf_and_save("oilrig_01_overview", "oilrig_01_overview.png")

	_set_cam(level, Vector3(-60.0, 510.0, 1120.0), Vector3(-450.0, 240.0, 450.0), 48.0)
	await _sample_perf_and_save("oilrig_03_closeup", "oilrig_03_closeup.png")

	_set_cam(level, Vector3(-450.0, 620.0, 452.0), Vector3(-450.0, 0.0, 450.0), 68.0)
	await _sample_perf_and_save("oilrig_05_moonpool", "oilrig_05_moonpool.png")

	_set_cam(level, Vector3(-450.0, 42.0, 920.0), Vector3(-450.0, 85.0, 450.0), 68.0)
	await _sample_perf_and_save("oilrig_06_under_deck", "oilrig_06_under_deck.png")

	_set_cam(level, Vector3(-260.0, 395.0, 450.0), Vector3(260.0, 385.0, 450.0), 65.0)
	await _sample_perf_and_save("oilrig_07_skybridge", "oilrig_07_skybridge.png")

	_set_cam(level, Vector3(-20.0, 560.0, 920.0), Vector3(-320.0, 380.0, 480.0), 55.0)
	await _sample_perf_and_save("oilrig_09_helipad_cranes", "oilrig_09_helipad_cranes.png")

	_set_cam(level, Vector3(40.0, 280.0, 760.0), Vector3(0.0, 100.0, 0.0), 58.0)
	await _sample_perf_and_save("oilrig_10_lagoon_tanker", "oilrig_10_lagoon_tanker.png")

	_set_cam(level, Vector3(160.0, 820.0, 460.0), Vector3(380.0, 720.0, 260.0), 50.0)
	await _sample_perf_and_save("oilrig_flare_closeup", "oilrig_flare_closeup.png")

	_clear_cam()
	level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame


func _capture_hero_cards() -> void:
	# 1. Lis Forest hero frame (1920x1080) -> Assets/Branding/mobile_map_lis_forest_freestyle.png
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	DroneCatalog.apply(0)
	var lis_level := (load("res://sceneries/LisLevel.tscn") as PackedScene).instantiate()
	add_child(lis_level)
	await get_tree().create_timer(2.0).timeout
	_hide_all_ui(get_tree().root)
	var ld := lis_level.get_node_or_null("Drone") as Node3D
	if ld != null:
		ld.visible = false
	_set_cam(lis_level, Vector3(-135.0, 72.0, 178.0), Vector3(45.0, 18.0, -45.0), 62.0)
	for _i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var limg := get_viewport().get_texture().get_image()
	if limg != null:
		limg.save_png(ProjectSettings.globalize_path("res://Assets/Branding/mobile_map_lis_forest_freestyle.png"))
		print("[FINAL-CAP] hero saved: Assets/Branding/mobile_map_lis_forest_freestyle.png ", limg.get_size())
	_clear_cam()
	lis_level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame

	# 2. Oil Rig hero frame (1920x1080) -> Assets/Branding/mobile_map_oilrig.png
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	DroneCatalog.apply(0)
	var rig_level := (load("res://sceneries/OilRigLevel.tscn") as PackedScene).instantiate()
	add_child(rig_level)
	await get_tree().create_timer(2.0).timeout
	_hide_all_ui(get_tree().root)
	var rd := rig_level.get_node_or_null("Drone") as Node3D
	if rd != null:
		rd.visible = false
	_set_cam(rig_level, Vector3(1060.0, 680.0, 1180.0), Vector3(0.0, 290.0, 0.0), 50.0)
	for _i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rimg := get_viewport().get_texture().get_image()
	if rimg != null:
		rimg.save_png(ProjectSettings.globalize_path("res://Assets/Branding/mobile_map_oilrig.png"))
		print("[FINAL-CAP] hero saved: Assets/Branding/mobile_map_oilrig.png ", rimg.get_size())
	_clear_cam()
	rig_level.queue_free()
	for _i in range(4):
		await get_tree().physics_frame
