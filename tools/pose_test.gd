## QA: verify that posing a bone deforms the skinned soldier.
extends Node3D

func _ready() -> void:
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.8, 0.85)
	e.ambient_light_energy = 1.2
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 2.2
	add_child(key)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.3, 0.28)
	ground.material_override = gm
	add_child(ground)

	var path := OS.get_environment("MODEL_PATH")
	if path.is_empty():
		path = "res://Assets/combat/soldier_detailed.glb"
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	# Normalise height.
	var box := _bounds(model)
	if box.size.y > 0.001:
		model.scale = Vector3.ONE * (2.0 / box.size.y)
		box = _bounds(model)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var skel := _find_skel(model)
	if skel != null:
		print("[POSE] bones=", skel.get_bone_count())
		for i in range(skel.get_bone_count()):
			var bn := skel.get_bone_name(i)
			if bn.contains("UpperArm") or bn.contains("Forearm") or bn.contains("Thigh"):
				print("  ", i, " ", bn)
		var idx := -1
		for i in range(skel.get_bone_count()):
			if skel.get_bone_name(i).contains("R UpperArm"):
				idx = i
				break
		if idx >= 0:
			var q := Quaternion(Vector3.UP, deg_to_rad(-70.0))
			skel.set_bone_pose_rotation(idx, q)
			print("[POSE] rotated bone ", idx, " ", skel.get_bone_name(idx))
	# Camera.
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40.0
	cam.position = Vector3(0.0, 1.2, 4.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/pose_test.png"
	print("[POSE] saved ", out, " err=", img.save_png(out))
	get_tree().quit(0)

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

func _find_skel(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var f := _find_skel(c)
		if f != null:
			return f
	return null
