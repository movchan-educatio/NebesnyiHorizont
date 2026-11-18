extends Node

## Real-GPU visual proof for the Grim-7 propeller fix.
## Run windowed (headless viewports cannot read back pixels):
##   Godot --windowed --path . res://test/qa_prop_shots.tscn
## Output: res://qa_shots/bugs/fixed/08..12_grim7_*.png

const LevelScene := preload("res://sceneries/BigLevel.tscn")
const OUT_DIR := "res://qa_shots/bugs/fixed"

var _saved_mode := 0
var _saved_special := 0
var _saved_preset := 0


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("[PROP_SHOTS] FAIL no image for ", name)
		return
	var err := img.save_png(OUT_DIR.path_join(name))
	print("[PROP_SHOTS] ", name, " size=", img.get_size(), " err=", err)


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_saved_mode = Global.play_mode
	_saved_special = Global.special_mission
	_saved_preset = Global.drone_preset

	# --- studio stage: the same model, materials and blade meshes as the hangar
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.26, 0.30, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.81, 0.86)
	env.ambient_light_energy = 0.95
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	sun.light_energy = 1.5
	add_child(sun)

	var holder := Node3D.new()
	add_child(holder)
	var model := DroneCatalog.attach_model(holder, 0)
	if model == null:
		print("[PROP_SHOTS] FAIL Grim-7 model did not attach")
		get_tree().quit(1)
		return
	# Freeze the pivots at a readable angle for the still shots.
	for pivot in model.get_meta("prop_pivots", []):
		(pivot as Node3D).rotation.y = deg_to_rad(18.0)
	model.position.y = 0.02

	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.far = 60.0
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(0.4).timeout

	var views := [
		{"name": "08_grim7_props_top.png",
			"pos": Vector3(0.34, 0.30, 0.40), "look": Vector3(0.0, 0.01, 0.0)},
		{"name": "09_grim7_props_bottom.png",
			"pos": Vector3(0.34, -0.24, 0.40), "look": Vector3(0.0, 0.03, 0.0)},
		{"name": "10_grim7_props_front.png",
			"pos": Vector3(-0.10, 0.16, 0.52), "look": Vector3(0.0, 0.01, -0.04)},
		{"name": "11_grim7_props_back.png",
			"pos": Vector3(0.12, 0.16, -0.52), "look": Vector3(0.0, 0.01, 0.04)},
	]
	for view in views:
		cam.global_position = view["pos"]
		cam.look_at(view["look"], Vector3.UP)
		await get_tree().create_timer(0.15).timeout
		await _shot(String(view["name"]))

	world.queue_free()
	holder.queue_free()
	sun.queue_free()
	cam.queue_free()
	await get_tree().create_timer(0.2).timeout

	# --- in-game FPV: the lens must be clean, no clipped blade arcs
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.drone_preset = 0
	var level := LevelScene.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	level.set("_osd_visible", false)
	for n in level.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var drone := level.get_node_or_null("Drone") as Drone
	if drone != null:
		drone.freeze = true
		drone.global_position = Vector3(0.0, 26.0, 80.0)
		drone.look_at(Vector3(0.0, 20.0, 0.0), Vector3.UP)
		var fc = drone.get("flight_controller")
		if fc != null:
			fc.call("request_arm")
		await get_tree().create_timer(1.2).timeout
		await _shot("12_grim7_fpv_clean.png")

	Global.play_mode = _saved_mode
	Global.special_mission = _saved_special
	Global.drone_preset = _saved_preset
	print("[PROP_SHOTS] done -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)
