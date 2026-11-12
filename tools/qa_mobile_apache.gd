extends Node3D

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.17, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.82, 0.85)
	env.ambient_light_energy = 1.2
	env_node.environment = env
	add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 30, 0)
	sun.light_energy = 2.0
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.20, 0.24, 0.19)
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	add_child(ground)
	var had_mobile_env := OS.has_environment("MOBILE_UI")
	OS.unset_environment("MOBILE_UI")
	var desktop_heli := Vehicle.new()
	desktop_heli.kind = Vehicle.Kind.HELI
	add_child(desktop_heli)
	var desktop_model := desktop_heli.get_node_or_null("Model") as Node3D
	var desktop_source := str(desktop_model.get_meta("source_glb", "")) \
			if desktop_model != null else ""
	var desktop_path_ok := desktop_source.ends_with("apache_hecu_half-life.glb") \
			and desktop_heli.get("_lod_proxy") == null
	print("[MOBILEAPACHE] desktop_source=", desktop_source,
			" original_kept=", desktop_path_ok)
	desktop_heli.queue_free()
	if had_mobile_env:
		OS.set_environment("MOBILE_UI", "1")
	var heli := Vehicle.new()
	heli.kind = Vehicle.Kind.HELI
	heli.move_speed = 0.0
	heli.fire_range = 0.0
	heli.hostile = false
	add_child(heli)
	heli.position = Vector3.ZERO
	var cam := Camera3D.new()
	cam.current = true
	cam.position = Vector3(0, 32, 28)
	cam.fov = 42.0
	add_child(cam)
	cam.look_at(Vector3(0, 22.0, 0), Vector3.UP)
	for i in range(24):
		await get_tree().process_frame
	var model := heli.get_node_or_null("Model")
	var mesh_count := model.find_children("*", "MeshInstance3D", true, false).size() if model != null else 0
	print("[MOBILEAPACHE] path=", model.scene_file_path if model != null else "<missing>",
			" mesh_nodes=", mesh_count, " expected_mobile=",
			OS.has_environment("MOBILE_UI"))
	var detailed_meshes := model.find_children("*", "MeshInstance3D", true, false).size() if model != null else 0
	var source_glb := str(model.get_meta("source_glb", "")) if model != null else ""
	var full_model_ok := model != null and detailed_meshes <= 26 \
			and source_glb.ends_with("apache_hecu_half-life_mobile.glb")
	if model != null:
		var model_box := DroneCatalog.model_bounds(model)
		print("[MOBILEAPACHE] model_visible=", model.visible,
				" world_bounds=", model_box, " vehicle_pos=", heli.global_position,
				" camera=", cam.global_position, " LOD=", heli.get("_visual_lod"))
	var out := OS.get_environment("SHOT_PATH")
	if not out.is_empty():
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		print("[MOBILEAPACHE] shot=", out, " err=", image.save_png(out))
	cam.global_position = Vector3(0, 10, 300)
	heli.call("_update_mobile_lod", 0.3)
	var proxy_lod_ok: bool = model != null and not model.visible \
			and bool(heli.get("_lod_proxy").visible)
	cam.global_position = Vector3(0, 10, 700)
	heli.call("_update_mobile_lod", 0.3)
	var hidden_lod_ok: bool = model != null and not model.visible \
			and not bool(heli.get("_lod_proxy").visible)
	print("[MOBILEAPACHE] source=", source_glb, " static_nodes=", detailed_meshes,
			" full_model=", full_model_ok, " proxy_lod=", proxy_lod_ok,
			" far_hidden=", hidden_lod_ok)
	get_tree().quit(0 if desktop_path_ok and full_model_ok \
			and proxy_lod_ok and hidden_lod_ok else 1)
