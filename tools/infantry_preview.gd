## QA: preview the authored HECU soldier the way EnemyRifleman uses it.
## Run: godot --path <proj> --resolution 900x900 -s res://tools/infantry_preview.gd
extends SceneTree

const SOLDIER := "res://Assets/vehicles_anim/hecu_half-life_anim.glb"


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
	plane.size = Vector2(40, 40)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.31, 0.24)
	ground.material_override = gm
	holder.add_child(ground)

	var packed := load(SOLDIER) as PackedScene
	if packed == null:
		print("[INFANTRY] load failed")
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	holder.add_child(model)
	model.rotation.y = PI
	# Measured from the Blender-evaluated (skinned) Walk pose: the mesh is
	# 8.6255 units tall, centred at x=0.6075 / z=-0.3453 with its feet at y=-0.1.
	# MeshInstance AABBs are useless for skinned models (bone bind matrices
	# scale the mesh), so use these measured numbers instead.
	var factor := 1.9 / 8.6255
	model.scale = Vector3.ONE * factor
	model.position = Vector3(0.6075 * factor, 0.1 * factor, -0.3453 * factor)

	var anim := _find_anim(model)
	if anim != null:
		print("[INFANTRY] animations=", anim.get_animation_list())
		if OS.has_environment("INFANTRY_WALK") and anim.get_animation_list().has("Walk"):
			anim.play("Walk")
	else:
		print("[INFANTRY] no AnimationPlayer")

	# 2 m reference cube at the origin: if the soldier is invisible, this still
	# shows where the camera is pointing.
	var ref := MeshInstance3D.new()
	var ref_mesh := BoxMesh.new()
	ref_mesh.size = Vector3(0.4, 2.0, 0.4)
	ref.mesh = ref_mesh
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.9, 0.15, 0.1)
	ref.material_override = rm
	ref.position = Vector3(1.4, 1.0, 0.0)
	holder.add_child(ref)

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 55.0
	holder.add_child(cam)
	cam.position = Vector3(0.0, 1.4, -12.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	for i in range(8):
		await process_frame
	print("[INFANTRY] model scale=", model.scale, " pos=", model.position,
			" global=", model.global_transform)
	print("[INFANTRY] ref global=", ref.global_transform)

	for i in range(45):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/infantry_preview.png"
	var err := image.save_png(path)
	print("[INFANTRY] ", path, " err=", err)
	quit()


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
