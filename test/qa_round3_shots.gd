extends Node

## Real-GPU captures for the campaign air-intercept fix and the CCIP sight.
## Run windowed (headless viewports cannot read back pixels):
##   Godot --windowed --path . res://test/qa_round3_shots.tscn
## Output: res://qa_shots/bugs/fixed/13..15_*.png

const LevelScene := preload("res://sceneries/BigLevel.tscn")
const VehicleScript := preload("res://combat/vehicle.gd")
const OUT_DIR := "res://qa_shots/bugs/fixed"

var _saved_mode := 0
var _saved_mission := 1
var _saved_special := 0
var _saved_preset := 0


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("[R3_SHOTS] FAIL no image for ", name)
		return
	var err := img.save_png(OUT_DIR.path_join(name))
	print("[R3_SHOTS] ", name, " size=", img.get_size(), " err=", err)


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	_saved_mode = Global.play_mode
	_saved_mission = Global.combat_mission
	_saved_special = Global.special_mission
	_saved_preset = Global.drone_preset
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	await _air_shot(3, VehicleScript.Kind.HELI, "13_mission3_heli_low.png",
			Vector3(15.0, 4.0, 21.0), true)
	await _air_shot(4, VehicleScript.Kind.SHAHED, "14_mission4_shahed_low.png",
			Vector3(14.0, 1.5, 26.0), false)
	await _sight_shot()

	Global.play_mode = _saved_mode
	Global.combat_mission = _saved_mission
	Global.special_mission = _saved_special
	Global.drone_preset = _saved_preset
	print("[R3_SHOTS] done -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


func _air_shot(mission: int, kind: int, file: String, offset: Vector3,
		clean_camera: bool) -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = mission
	Global.special_mission = 0
	Global.drone_preset = 0
	Global.chain_briefing_pending = false
	var level := await _load_level()
	if level == null:
		return
	var target := _first_vehicle(level, kind)
	var drone := level.get_node_or_null("Drone") as Drone
	if target == null or drone == null:
		print("[R3_SHOTS] FAIL mission ", mission, " target or drone missing")
		_free_level(level)
		return
	# Freeze the target so the still frame is not a motion blur of the patrol.
	target.set_physics_process(false)
	if clean_camera:
		# Clean QA camera for the helicopter: the FPV lens is nose-down and the
		# target often sits behind terrain clutter at this range.
		for canvas in level.find_children("*", "CanvasLayer", true, false):
			(canvas as CanvasLayer).visible = false
		var cam := Camera3D.new()
		level.add_child(cam)
		cam.fov = 50.0
		cam.far = 600.0
		cam.global_position = target.global_position + offset
		cam.look_at(target.global_position + Vector3.UP * 1.0, Vector3.UP)
		cam.current = true
		await get_tree().create_timer(0.6).timeout
		await _shot(file)
		cam.queue_free()
		_free_level(level)
		await get_tree().process_frame
		return
	drone.freeze = true
	var at := target.global_position + offset
	drone.global_position = at
	drone.look_at(target.global_position + Vector3.UP * 1.0, Vector3.UP)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	await _shot(file)
	_free_level(level)
	await get_tree().process_frame


func _sight_shot() -> void:
	# Grim-7M carries the shared hardpoint and the CCIP sight.
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.special_mission = 0
	Global.drone_preset = 1
	Global.chain_briefing_pending = false
	var level := await _load_level()
	if level == null:
		return
	var drone := level.get_node_or_null("Drone") as Drone
	var target := _first_primary_target(level)
	if drone == null:
		print("[R3_SHOTS] FAIL bomb-sight drone missing")
		_free_level(level)
		return
	var sight = level.get("_bomb_sight")
	if sight == null:
		print("[R3_SHOTS] FAIL bomb sight was not created")
		_free_level(level)
		return
	sight.call("set_bomb_view", true)
	var focus := target.global_position if target != null else Vector3.ZERO
	var ground_y := focus.y
	drone.freeze = true
	drone.global_position = Vector3(focus.x - 26.0, ground_y + 34.0, focus.z + 26.0)
	drone.look_at(Vector3(focus.x, ground_y, focus.z), Vector3.UP)
	await get_tree().create_timer(1.0).timeout
	await _shot("15_ccip_sight.png")
	_free_level(level)
	await get_tree().process_frame


func _load_level() -> Node:
	var level := LevelScene.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(3.2).timeout
	return level if is_instance_valid(level) else null


func _free_level(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	level.queue_free()


func _first_vehicle(level: Node, kind: int) -> Vehicle:
	for node in get_tree().get_nodes_in_group("vehicle"):
		if node is Vehicle and (node as Vehicle).kind == kind \
				and level.is_ancestor_of(node):
			return node as Vehicle
	return null


func _first_primary_target(level: Node) -> Node3D:
	for node in get_tree().get_nodes_in_group("primary_combat_target"):
		if node is Node3D and level.is_ancestor_of(node) \
				and not bool(node.get("is_destroyed")):
			return node as Node3D
	return null
