## QA: render the cleaned HECU GLB at raw scale to see its real rendered size.
extends SceneTree

const SOLDIER := "res://Assets/vehicles_anim/hecu_clean.glb"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.1
	env.environment = e
	holder.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-1.0, 0.5, 0.0)
	sun.light_energy = 1.3
	holder.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.31, 0.24)
	ground.material_override = gm
	holder.add_child(ground)

	var packed := load(SOLDIER) as PackedScene
	var model := packed.instantiate() as Node3D
	holder.add_child(model)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	print("[HECU] meshes=", meshes.size())
	for mi in meshes:
		mi.extra_cull_margin = 20000.0
	var anim := _find_anim(model)
	if anim != null:
		print("[HECU] animations=", anim.get_animation_list())
		if anim.get_animation_list().has("Walk"):
			anim.play("Walk")
			if OS.has_environment("HECU_WALK_SPEED"):
				anim.speed_scale = float(OS.get_environment("HECU_WALK_SPEED"))

	var ref := MeshInstance3D.new()
	var ref_mesh := BoxMesh.new()
	ref_mesh.size = Vector3(2, 85, 2)
	ref.mesh = ref_mesh
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.9, 0.15, 0.1)
	ref.material_override = rm
	ref.position = Vector3(30, 42.5, 0)
	holder.add_child(ref)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 50.0
	holder.add_child(cam)
	cam.position = Vector3(0.0, 55.0, -210.0)
	cam.look_at(Vector3(0.0, 42.0, 0.0), Vector3.UP)

	for i in range(10):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/hecu_raw.png"
	var err := image.save_png(path)
	print("[HECU] ", path, " err=", err, " anim=", anim.get_animation_list() if anim else [])
	quit()


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
