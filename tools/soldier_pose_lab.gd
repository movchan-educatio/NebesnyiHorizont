## QA lab: pose the detailed soldier's bones and render a screenshot.
## POSE_SPEC="R UpperArm:z:-60;R Forearm:x:70"
extends Node3D

var _skel: Skeleton3D
var _model: Node3D

func _ready() -> void:
	await get_tree().process_frame
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.17, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.82, 0.88)
	e.ambient_light_energy = 1.1
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 35, 0)
	key.light_energy = 2.1
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, -140, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.72, 0.84, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.29, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)

	var path := OS.get_environment("MODEL_PATH")
	if path.is_empty():
		path = "res://Assets/combat/soldier_detailed.glb"
	_model = (load(path) as PackedScene).instantiate() as Node3D
	add_child(_model)
	_model.rotation_degrees.x = 90.0
	if not OS.get_environment("MODEL_YAW").is_empty():
		_model.rotation_degrees.y = float(OS.get_environment("MODEL_YAW"))
	var box := _bounds(_model)
	if box.size.length() > 0.001:
		var s := 1.88 / maxf(box.size.y, 0.001)
		_model.scale = Vector3.ONE * s
		box = _bounds(_model)
		_model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_skel = _find_skel(_model)
	print("[POSE] box=", _bounds(_model).size, " center=", _bounds(_model).get_center())
	if _skel == null:
		print("[POSE] no skeleton")
		get_tree().quit(1)
		return

	var spec := OS.get_environment("POSE_SPEC")
	for entry in spec.split(";", false):
		var parts := entry.split(":")
		if parts.size() != 3:
			continue
		var idx := _bone_by_substring(parts[0])
		if idx < 0:
			print("[POSE] missing bone ", parts[0])
			continue
		var axis := Vector3.UP
		match parts[1].to_lower():
			"x": axis = Vector3.RIGHT
			"y": axis = Vector3.UP
			"z": axis = Vector3.BACK
		var q := Quaternion(axis, deg_to_rad(float(parts[2])))
		_skel.set_bone_pose_rotation(idx, q)
		print("[POSE] ", parts[0], " -> bone ", idx, " axis ", parts[1], " deg ", parts[2])
	for i in [2, 3, 4, 5, 8, 9, 10, 22, 23, 37, 38]:
		if i < _skel.get_bone_count():
			print("[POSE] bone ", _skel.get_bone_name(i), " global=", _skel.get_bone_global_pose(i).origin)

	# Optional: detach the authored rifle into a static prop so it can be aimed
	# independently of the bind-pose hand orientation.
	if OS.get_environment("RIFLE_PROP") == "1":
		var rifle_mi := _find_rifle_mesh(_model)
		if rifle_mi != null:
			var rbox: AABB = rifle_mi.get_aabb()
			var rcenter_world: Vector3 = rifle_mi.global_transform * rbox.get_center()
			var copy := MeshInstance3D.new()
			copy.mesh = rifle_mi.mesh
			copy.position = -rbox.get_center()
			var pivot := Node3D.new()
			pivot.name = "RiflePivot"
			pivot.position = to_local(rcenter_world)
			pivot.position += Vector3(
					float(OS.get_environment("RIFLE_OFFSET_X")),
					float(OS.get_environment("RIFLE_OFFSET_Y")),
					float(OS.get_environment("RIFLE_OFFSET_Z")))
			pivot.rotation_degrees = Vector3(
					float(OS.get_environment("RIFLE_PITCH")),
					float(OS.get_environment("RIFLE_YAW")),
					float(OS.get_environment("RIFLE_ROLL")))
			add_child(pivot)
			pivot.add_child(copy)
			rifle_mi.visible = false
			print("[POSE] rifle prop center=", pivot.position, " yaw=", pivot.rotation_degrees.y,
					" size=", rbox.size)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 38.0
	var cam_yaw := deg_to_rad(float(OS.get_environment("CAM_YAW")))
	cam.position = Vector3(sin(cam_yaw) * 3.9, 1.25, cos(cam_yaw) * 3.9)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for i in range(12):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/pose_lab.png"
	print("[POSE] saved ", out, " err=", img.save_png(out))
	get_tree().quit(0)

func _find_rifle_mesh(node: Node) -> MeshInstance3D:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name).contains("w_val"):
				return mi
	return null


func _bone_by_substring(text: String) -> int:
	for i in range(_skel.get_bone_count()):
		if _skel.get_bone_name(i).contains(text):
			return i
	return -1

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
