extends Node3D

## Visual gallery for the 16 Blender-authored frontline props.
##
## Run (windowed, not headless):
##   Godot_v4.6.1-stable_win64_console.exe --path . tools/frontline_gallery.tscn
##
## Saves one overview shot plus a framed close-up of every asset into
## qa_shots/frontline/, then quits.

const ASSETS := [
	"hospital", "admin_building", "factory_hall", "arch",
	"concrete_bridge", "wooden_bridge", "destroyed_bridge", "bunker",
	"observation_post", "checkpoint", "hedgehog", "pylon",
	"sandbag_wall", "oak", "pine", "rocks",
]
const YAW := {
	"hospital": PI,
	"admin_building": PI,
	"factory_hall": PI,
	"checkpoint": PI,
	"bunker": PI,
	"hedgehog": 0.35,
	"rocks": 0.6,
	"oak": 0.4,
	"pine": 0.2,
}
const CELL := Vector2(78.0, 78.0)
const COLS := 4
const OUT_DIR := "C:/Users/USER_UA/Desktop/Новий симулятор/qa_shots"

var _page_root: Node3D
var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR + "/frontline")
	get_window().size = Vector2i(1600, 900)
	_build_environment()
	_build_ground()
	_camera = Camera3D.new()
	_camera.name = "GalleryCamera"
	_camera.near = 0.05
	_camera.far = 1500.0
	_camera.current = true
	add_child(_camera)

	await get_tree().create_timer(1.0).timeout
	await _render_overview()
	await _render_closeups()
	print("[Gallery] done")
	get_tree().quit()


func _new_page() -> void:
	await _clear_page()
	_page_root = Node3D.new()
	_page_root.name = "Page"
	add_child(_page_root)


func _clear_page() -> void:
	if _page_root != null and is_instance_valid(_page_root):
		_page_root.queue_free()
		_page_root = null
	await get_tree().process_frame
	await get_tree().process_frame


func _spawn_asset(asset_name: String, pos: Vector3, yaw: float) -> Node3D:
	var path := "res://Assets/frontline/%s.glb" % asset_name
	if not ResourceLoader.exists(path):
		push_warning("[Gallery] missing " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	_page_root.add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	return inst


func _render_overview() -> void:
	await _new_page()
	for i in range(ASSETS.size()):
		var asset_name: String = ASSETS[i]
		var col := i % COLS
		var row := i / COLS
		var pos := Vector3((float(col) - 1.5) * CELL.x, 0.0,
				(float(row) - 1.5) * CELL.y)
		var inst := _spawn_asset(asset_name, pos, float(YAW.get(asset_name, 0.0)))
		if inst == null:
			continue
		var label := Label3D.new()
		label.text = asset_name
		label.font_size = 96
		label.pixel_size = 0.030
		label.outline_size = 24
		label.modulate = Color(1.0, 0.96, 0.82)
		label.outline_modulate = Color(0.03, 0.03, 0.02, 0.9)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = pos + Vector3(0.0, _top_of(inst) + 3.5, 0.0)
		_page_root.add_child(label)
	_camera.fov = 50.0
	_camera.position = Vector3(0.0, 96.0, 232.0)
	_camera.look_at(Vector3(0.0, 6.0, 0.0), Vector3.UP)
	await _save("frontline_assets_overview.png")


func _render_closeups() -> void:
	for asset_name in ASSETS:
		await _new_page()
		var inst := _spawn_asset(asset_name, Vector3.ZERO,
				float(YAW.get(asset_name, 0.0)))
		if inst == null:
			continue
		await get_tree().process_frame
		var box := _bounds(inst)
		var center := box.get_center()
		var radius := maxf(box.size.length() * 0.5, 1.0)
		var dir := Vector3(0.68, 0.46, -0.86).normalized()
		_camera.fov = 45.0
		var dist := radius / sin(deg_to_rad(_camera.fov * 0.5)) * 1.18
		_camera.position = center + dir * dist
		_camera.look_at(center, Vector3.UP)
		await _save("frontline/%s.png" % asset_name)


func _save(relative_path: String) -> void:
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("[Gallery] viewport image is null for " + relative_path)
		return
	var path := OUT_DIR + "/" + relative_path
	var err := image.save_png(path)
	print("[Gallery] ", path, " err=", err)


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	if first:
		box = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	return box


func _top_of(node: Node3D) -> float:
	var box := _bounds(node)
	return box.position.y + box.size.y


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.42, 0.74)
	sky_mat.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_mat.ground_bottom_color = Color(0.22, 0.21, 0.18)
	sky_mat.ground_horizon_color = Color(0.55, 0.58, 0.55)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 2.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.88)
	env.fog_density = 0.00025
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-46.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 450.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -128.0, 0.0)
	fill.light_color = Color(0.62, 0.72, 0.90)
	fill.light_energy = 0.40
	add_child(fill)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(420.0, 1.0, 390.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(col)
	add_child(body)

	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(420.0, 390.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.31, 0.27)
	mat.roughness = 0.98
	mesh.material_override = mat
	add_child(mesh)
