## QA: preview any GLB with neutral studio lighting.
## Run: MODEL_PATH=res://... MODEL_OUT=C:/.../x.png godot --path . --script res://tools/model_preview.gd
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := OS.get_environment("MODEL_PATH")
	if path.is_empty():
		path = "res://Assets/combat/rifleman.glb"
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/model_preview.png"
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.82)
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	holder.add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 2.0
	key.shadow_enabled = true
	holder.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, -140, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.72, 0.84, 1.0)
	holder.add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.28, 0.27, 0.24)
	gm.roughness = 0.95
	ground.material_override = gm
	holder.add_child(ground)

	var packed := load(path) as PackedScene
	if packed == null:
		print("[MODEL] load failed ", path)
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	holder.add_child(model)
	var rot := float(OS.get_environment("MODEL_ROT"))
	model.rotation_degrees = Vector3(
			float(OS.get_environment("MODEL_PITCH")),
			rot,
			float(OS.get_environment("MODEL_ROLL")))
	# Skinned Sketchfab rips are often authored in a bind pose far from the
	# origin; playing the Walk clip restores the sampled root transform.
	var anim_name := OS.get_environment("MODEL_ANIM")
	if not anim_name.is_empty():
		var ap := _find_anim(model)
		if ap != null and ap.get_animation_list().has(anim_name):
			ap.play(anim_name)
			ap.seek(0.35, true)
			for i in range(4):
				await process_frame
	var force_scale := float(OS.get_environment("MODEL_FORCE_SCALE"))
	if force_scale > 0.0:
		model.scale = Vector3.ONE * force_scale
		model.position = Vector3(
				float(OS.get_environment("MODEL_OFFSET_X")),
				float(OS.get_environment("MODEL_OFFSET_Y")),
				float(OS.get_environment("MODEL_OFFSET_Z")))
		for i in range(2):
			await process_frame
	if OS.get_environment("MODEL_NO_GROUND") == "1":
		ground.visible = false
	var target_h := float(OS.get_environment("MODEL_HEIGHT"))
	var box := _bounds(model)
	if OS.get_environment("MODEL_CULL_FIX") == "1":
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi != null:
				mi.custom_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
				mi.extra_cull_margin = 100.0
	if box.size.length() > 0.0001:
		if target_h > 0.01:
			var s := target_h / maxf(box.size.y, 0.0001)
			model.scale = Vector3.ONE * s
			box = _bounds(model)
		var center := box.get_center()
		model.position -= Vector3(center.x, box.position.y, center.z)
		box = _bounds(model)
	print("[MODEL] path=", path, " box=", box.size, " center=", box.get_center())

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 42.0
	cam.near = 0.02
	cam.far = 500.0
	holder.add_child(cam)
	var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var dist := maxf(size, 0.2) * 1.65
	var cam_override := OS.get_environment("MODEL_CAM_POS")
	if not cam_override.is_empty():
		cam.position = _vec3(cam_override)
		cam.look_at(_vec3(OS.get_environment("MODEL_CAM_LOOK")), Vector3.UP)
	else:
		cam.position = box.get_center() + Vector3(dist * 0.92, dist * 0.55, dist * 1.05)
		cam.look_at(box.get_center(), Vector3.UP)

	for i in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(out)
	print("[MODEL] ", out, " err=", err)
	quit(0)

func _vec3(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		return Vector3.ZERO
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
