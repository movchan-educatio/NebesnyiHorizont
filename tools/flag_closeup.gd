## QA: render close-up stills of the runtime Ukrainian flag decal on every
## airframe that carries it.  Two views per preset: oblique top and grazing
## side, so floating / sunk / mirrored placement is visible.
extends Node3D

const OUT_DIR := "C:/Users/USER_UA/AppData/Local/Temp/opencode/flag_qa"
const PRESETS := [0, 1, 3, 4, 5, 6, 7, 8, 9]

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	viewport = SubViewport.new()
	viewport.size = Vector2i(560, 420)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.12, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.80)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.9
	key.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.9
	fill.light_color = Color(0.72, 0.86, 1.0)
	fill.rotation_degrees = Vector3(-15.0, 160.0, 0.0)
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.fov = 36.0
	camera.near = 0.005
	camera.far = 20.0
	viewport.add_child(camera)
	stage = Node3D.new()
	viewport.add_child(stage)

	for idx in PRESETS:
		await _capture_preset(idx)
	get_tree().quit()


func _capture_preset(idx: int) -> void:
	for c in stage.get_children():
		c.queue_free()
	await get_tree().process_frame
	var parent := Node3D.new()
	stage.add_child(parent)
	var model := DroneCatalog.attach_model(parent, idx)
	await get_tree().process_frame
	if model == null:
		print("[FLAGQA] preset=", idx, " MODEL MISSING")
		return
	var mark := model.get_node_or_null("UkraineMark") as MeshInstance3D
	if mark == null:
		print("[FLAGQA] preset=", idx, " NO MARK")
		return
	var quad := mark.mesh as QuadMesh
	var flag_w: float = quad.size.x if quad != null else 0.0
	var flag_h: float = quad.size.y if quad != null else 0.0
	var point := mark.global_position
	var normal := mark.global_transform.basis.z.normalized()
	var right := mark.global_transform.basis.x.normalized()
	var up := mark.global_transform.basis.y.normalized()
	var dist: float = maxf(flag_w * 4.5, 0.12)
	var name := "%02d_p%02d" % [PRESETS.find(idx) + 1, idx]
	await _shoot(point, normal, right, up, dist, true, OUT_DIR + "/" + name + "_top.png")
	await _shoot(point, normal, right, up, dist, false, OUT_DIR + "/" + name + "_side.png")
	print("[FLAGQA] preset=", idx, " name=", DroneCatalog.preset(idx).get("name", ""),
			" flag=", flag_w, "x", flag_h, " pos=", point, " normal=", normal)


func _shoot(point: Vector3, normal: Vector3, right: Vector3, up: Vector3,
		dist: float, top: bool, path: String) -> void:
	var pos: Vector3
	if top:
		pos = point + normal * dist + right * (dist * 0.30) + up * (dist * 0.22)
	else:
		pos = point + right * dist + normal * (dist * 0.34) + up * (dist * 0.14)
	camera.look_at_from_position(pos, point, normal)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var err := img.save_png(path)
	print("[FLAGQA] saved=", path, " err=", err)
