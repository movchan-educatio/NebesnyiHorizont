extends Node3D

## Visual QA: renders each drone at rest and while propellers spin,
## from a consistent three-quarter view, saving screenshots to qa_shots/props/.
## Run: Godot_v4.6.1-stable_win64_console.exe --path . tools/qa_props.tscn

const OUT_DIR := "C:/Users/USER_UA/Desktop/Новий симулятор/qa_shots/props"
const SPIN_RPMS := [3000.0, 3000.0, 3000.0, 3000.0]

var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.68, 0.72)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 38, 0)
	key.light_energy = 2.2
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(28, -145, 0)
	fill.light_energy = 0.9
	fill.light_color = Color(0.75, 0.85, 1.0)
	add_child(fill)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)

	_holder = Node3D.new()
	add_child(_holder)

	await _run()
	get_tree().quit(0)

func _run() -> void:
	var only := OS.get_environment("QA_PRESET").strip_edges()
	for idx in range(DroneCatalog.count()):
		if only.is_valid_int() and int(only) != idx:
			continue
		var p: Dictionary = DroneCatalog.preset(idx)
		print("=== QA preset %d: %s ===" % [idx, p.get("name", "?")])
		var model: Node3D = DroneCatalog.attach_model(_holder, idx)
		if model == null:
			print("  no model")
			continue
		for i in 3:
			await get_tree().process_frame

		var box: AABB = DroneCatalog.model_bounds_full(model)
		var center := box.get_center()
		var size := maxf(box.size.x, maxf(box.size.y, box.size.z))
		if size < 0.0001:
			size = 0.25
		var dist := size * 1.65
		var cam_pos := center + Vector3(dist * 0.95, dist * 0.75, dist * 1.05)
		_cam.position = cam_pos
		_cam.look_at(center, Vector3.UP)
		_cam.near = 0.005
		_cam.far = 20.0

		await _save("preset_%d_rest.png" % idx)
		# spin a little, then capture two frames
		for i in 5:
			DroneCatalog.animate_propellers(model, 1.0 / 60.0, SPIN_RPMS)
			await get_tree().process_frame
		await _save("preset_%d_spin_a.png" % idx)
		for i in 5:
			DroneCatalog.animate_propellers(model, 1.0 / 60.0, SPIN_RPMS)
			await get_tree().process_frame
		await _save("preset_%d_spin_b.png" % idx)

		_dump_props(model, idx)
		_holder.remove_child(model)
		model.queue_free()
		for i in 2:
			await get_tree().process_frame
	print("QA DONE")

func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(OUT_DIR.path_join(file))
	print("  saved ", file, " err=", err)

func _dump_props(model: Node3D, idx: int) -> void:
	for corner in ["FL", "FR", "BR", "BL"]:
		var motor := model.find_child("motor_" + corner, true, false) as Node3D
		var prop := model.find_child("propeller_" + corner, true, false) as Node3D
		if prop == null:
			print("  [%s] missing prop" % corner)
			continue
		var pbox: AABB = DroneCatalog.model_bounds_full(prop)
		var axis := prop.global_position
		print("  [%s] pivot=%s prop_aabb_center=%s size=%s" % [corner, axis, pbox.get_center(), pbox.size])
