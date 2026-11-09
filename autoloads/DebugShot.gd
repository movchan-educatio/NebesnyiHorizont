## QA-only helper: captures a screenshot of whatever scene is running and
## quits.  Activated purely through environment variables, so it is invisible
## during normal play.
##
##   SET_SHOT=res://some_scene.tscn  -> optional, set on the command line
##   SHOT_PATH=C:\path\shot.png      -> output file (capture enabled)
##   SHOT_DELAY=2.0                  -> seconds to wait before capturing
extends Node


func _ready() -> void:
	# QA-only physics-rate override: lets the benchmark compare 120 Hz with the
	# interpolated 60 Hz flight model without editing project.godot.
	var physics_hz := OS.get_environment("DRONE_PHYSICS_HZ")
	if not physics_hz.is_empty():
		Engine.physics_ticks_per_second = clampi(int(physics_hz), 30, 240)
	if OS.has_environment("DRONE_CAMPAIGN_TEST"):
		var runner = load("res://test/qa_campaign_runner.gd")
		if runner != null:
			var node = runner.new()
			node.name = "QaCampaignRunner"
			get_tree().root.add_child.call_deferred(node)
		return
	if OS.has_environment("DRONE_REENTRY_TEST"):
		_run_reentry_test()
		return
	if OS.has_environment("DRONE_FPS_BENCH"):
		_run_fps_bench()
		return
	var path := OS.get_environment("SHOT_PATH")
	if path.is_empty():
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var delay := 2.0
	var delay_env := OS.get_environment("SHOT_DELAY")
	if not delay_env.is_empty():
		delay = maxf(0.0, float(delay_env))
	await get_tree().create_timer(1.0).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(maxf(0.5, delay - 1.0)).timeout
	# QA-only free camera: `SHOT_CAM_AT=x,y,z` and `SHOT_CAM_LOOK=x,y,z` place a
	# temporary camera so the outdoor parts of a map can be inspected without
	# flying the drone there.  Never used during normal play.
	var cam_at := OS.get_environment("SHOT_CAM_AT")
	if not cam_at.is_empty():
		var at := _parse_vec3(cam_at)
		# QA convenience: `SHOT_CAM_GROUND=2.0` keeps the camera 2 m above the
		# procedural terrain instead of guessing its absolute Y.
		var ground_env := OS.get_environment("SHOT_CAM_GROUND")
		if not ground_env.is_empty():
			var lvl := get_tree().current_scene
			var raw_map = lvl.get("frontline_map") if lvl != null else null
			var map_name: String = str(raw_map) if raw_map != null else ""
			if not map_name.is_empty():
				var ft = load("res://scripts/util/frontline_terrain.gd")
				if ft != null:
					at.y = ft.height_at(map_name, at.x, at.z) + float(ground_env)
		var look_env := OS.get_environment("SHOT_CAM_LOOK")
		var look := _parse_vec3(look_env) if not look_env.is_empty() else Vector3.ZERO
		var qa_cam := Camera3D.new()
		qa_cam.name = "QAShotCamera"
		qa_cam.fov = 75.0
		qa_cam.near = 0.05
		qa_cam.far = 6000.0
		get_tree().current_scene.add_child(qa_cam)
		qa_cam.global_position = at
		if not at.is_equal_approx(look):
			qa_cam.look_at(look, Vector3.UP)
		qa_cam.current = true
	# The level may finish its deferred camera setup after the first delay and
	# reclaim `current`.  Force the QA camera again right before capturing.
	if not cam_at.is_empty():
		var scene_now := get_tree().current_scene
		var qa_now := scene_now.get_node_or_null("QAShotCamera") as Camera3D
		if qa_now != null:
			for c in scene_now.find_children("*", "Camera3D", true, false):
				(c as Camera3D).current = false
			qa_now.current = true
	if OS.has_environment("DRONE_CLEAN_SHOT"):
		var clean_scene := get_tree().current_scene
		if clean_scene != null:
			for clean_name in ["Help", "FPVOverlay", "CombatHUD"]:
				var clean_node := clean_scene.get_node_or_null(clean_name)
				if clean_node is CanvasLayer:
					(clean_node as CanvasLayer).visible = false
				elif clean_node is CanvasItem:
					(clean_node as CanvasItem).visible = false
			var clean_hud := clean_scene.get_node_or_null("Drone/HUD")
			if clean_hud is CanvasLayer:
				(clean_hud as CanvasLayer).visible = false
			elif clean_hud is CanvasItem:
				(clean_hud as CanvasItem).visible = false
	if OS.has_environment("SHOT_DEBUG"):
		var scene := get_tree().current_scene
		if scene != null and not cam_at.is_empty():
			var at := _parse_vec3(cam_at)
			print("[SHOTDBG] nearby tall meshes:")
			for mi_node in scene.find_children("*", "GeometryInstance3D", true, false):
				var gi2 := mi_node as GeometryInstance3D
				if gi2 == null:
					continue
				var box2: AABB = gi2.global_transform * gi2.get_aabb()
				if box2.size.y < 2.0 and box2.size.x < 4.0:
					continue
				if box2.get_center().distance_to(at) > 80.0:
					continue
				print("[SHOTDBG]   ", gi2.get_class(), " ", gi2.name,
						" center=", box2.get_center(), " size=", box2.size)
		var view_cam := get_viewport().get_camera_3d()
		print("[SHOTDBG] viewport_cam=", view_cam,
				" pos=", view_cam.global_position if view_cam != null else Vector3.ZERO)
		if scene != null:
			for named in scene.find_children("*", "Node3D", true, false):
				var nlow := String(named.name).to_lower()
				if nlow.contains("admin") or nlow.contains("hospital") or nlow.contains("factory"):
					print("[SHOTDBG] landmark ", named.name, " pos=",
							(named as Node3D).global_position)
			var sun_dbg := scene.get_node_or_null("Sun") as DirectionalLight3D
			if sun_dbg != null:
				print("[SHOTDBG] sun rot=", sun_dbg.global_rotation_degrees,
						" energy=", sun_dbg.light_energy,
						" shadow=", sun_dbg.shadow_enabled,
						" dist=", sun_dbg.directional_shadow_max_distance,
						" dir=", -sun_dbg.global_transform.basis.z)
			var d := scene.get_node_or_null("Drone") as Node3D
			var cam := scene.get_node_or_null("Drone/FPVCamera") as Camera3D
			print("[SHOTDBG] scene=", scene.name)
			if d != null:
				print("[SHOTDBG] drone=", d.global_position,
						" yaw=", d.global_rotation.y)
			if cam != null:
				print("[SHOTDBG] cam=", cam.global_position,
						" fwd=", -cam.global_transform.basis.z)
			var hall := scene.find_child("HeroHall_*", true, false) as Node3D
			if hall != null:
				print("[SHOTDBG] hall=", hall.global_position,
						" rot=", hall.global_rotation, " scale=", hall.scale)
				for mi_node in hall.find_children("hall_*", "MeshInstance3D", true, false):
					var mi := mi_node as MeshInstance3D
					if mi.mesh != null:
						print("[SHOTDBG] ", mi.name, " aabb=",
								mi.global_transform * mi.get_aabb())
	# Let one full process+draw cycle run after the final camera switch.  Some
	# follow-camera systems (FollowGrass) rebuild in _process; capturing in the
	# same frame as the switch produced shots without the near-field grass.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("[SHOT] no image")
		get_tree().quit()
		return
	var err := image.save_png(path)
	print("[SHOT] ", path, " size=", image.get_size(), " err=", err)
	get_tree().quit()


func _parse_vec3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## QA-only FPS benchmark (DRONE_FPS_BENCH=<seconds>): uncaps the frame rate,
## waits for shaders/scene to warm up, then reports average FPS, 1% low and
## the worst frame time, and quits.
func _run_fps_bench() -> void:
	var seconds := maxf(2.0, float(OS.get_environment("DRONE_FPS_BENCH")))
	# QA: pin the window to a fixed size so benchmarks on different machines
	# (and different desktop resolutions) are comparable.
	var qa_size := OS.get_environment("QA_WINDOW_SIZE").to_lower()
	if not qa_size.is_empty():
		var parts := qa_size.split("x")
		if parts.size() == 2:
			get_window().mode = Window.MODE_WINDOWED
			get_window().size = Vector2i(int(parts[0]), int(parts[1]))
			get_window().move_to_center()
	# QA: render the WHOLE frame (3D + post + HUD) at a lower resolution and
	# let the engine stretch it to the window.  This is the "console 720p on a
	# 1080p panel" mode, much cheaper than full-res post-processing.
	var qa_cs := OS.get_environment("QA_CONTENT_SCALE").to_lower()
	if not qa_cs.is_empty():
		var cs_parts := qa_cs.split("x")
		if cs_parts.size() == 2:
			var win := get_window()
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			win.content_scale_size = Vector2i(int(cs_parts[0]), int(cs_parts[1]))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(6.0).timeout
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var times: Array[float] = []
	var process_ms := 0.0
	var physics_ms := 0.0
	var prims := 0.0
	var elapsed := 0.0
	# QA: isolate the cost of the 2D HUD/OSD from the 3D frame.
	if OS.has_environment("QA_NO_HUD"):
		var scene_now := get_tree().current_scene
		if scene_now != null:
			for layer in scene_now.find_children("*", "CanvasLayer", true, false):
				(layer as CanvasLayer).visible = false
	var last := Time.get_ticks_usec()
	while elapsed < seconds:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000000.0
		last = now
		times.append(dt)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		elapsed += dt
	times.sort()
	var count := times.size()
	var avg_fps := float(count) / maxf(elapsed, 0.001)
	var low_idx := clampi(int(count * 0.99), 0, count - 1)
	var low_fps := 1.0 / maxf(times[low_idx], 0.0001)
	var vp := get_viewport()
	var scale := vp.scaling_3d_scale if vp != null else -1.0
	print("[FPSBENCH] quality=%s frames=%d avg_fps=%.1f low1_fps=%.1f worst_ms=%.1f draw_calls=%d process_ms=%.2f physics_ms=%.2f prims=%d scale=%.2f hz=%d" % [
		OS.get_environment("DRONE_QUALITY"), count, avg_fps, low_fps,
		times[count - 1] * 1000.0,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		process_ms / maxf(float(count), 1.0), physics_ms / maxf(float(count), 1.0),
		int(prims / maxf(float(count), 1.0)), scale,
		Engine.physics_ticks_per_second])
	get_tree().quit()


## QA-only re-entry probe: level -> main menu -> level, then reports the HUD
## state and saves a screenshot.  Reproduces the "HUD disappears after coming
## back from the menu" report.  DRONE_REENTRY_TEST=1.
func _run_reentry_test() -> void:
	var level := "res://sceneries/VillageLevel.tscn"
	get_tree().change_scene_to_file(level)
	await get_tree().create_timer(3.0).timeout
	_report_hud("first")
	get_tree().change_scene_to_file("res://GUI/MainMenu.tscn")
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file(level)
	await get_tree().create_timer(3.5).timeout
	_report_hud("second")
	var path := OS.get_environment("SHOT_PATH")
	if not path.is_empty():
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png(path)
			print("[REENTRY] shot ", path)
	get_tree().quit()


func _report_hud(tag: String) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		print("[REENTRY] ", tag, " scene=null")
		return
	var hud = scene.get("_hud")
	var label = scene.get("_hud_label")
	var osd := bool(GameSettings.hud_config.get("osd", true))
	var vis := "?"
	var text := "?"
	var lvis := "?"
	var lmod := "?"
	if hud is CanvasLayer:
		vis = str((hud as CanvasLayer).visible)
	if label is Label:
		text = (label as Label).text.substr(0, 40).replace("\n", " | ")
		lvis = str((label as Label).visible)
		lmod = str((label as Label).modulate)
	print("[REENTRY] ", tag, " scene=", scene.name, " hud_visible=", vis,
			" label_visible=", lvis, " osd=", osd, " modulate=", lmod,
			" text='", text, "'")
