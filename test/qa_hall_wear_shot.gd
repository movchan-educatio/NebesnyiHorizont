extends Node

## Visual check: the hero hall and nearby buildings carry the war-wear dressing
## (charred ground, rust, rubble).  Run windowed: MOBILE_HALL_SHOT_DIR=<dir>.
const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_environment("MOBILE_HALL_SHOT_DIR")
	if output.is_empty():
		output = "user://hall_shots"
	DirAccess.make_dir_recursive_absolute(output)
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.drone_preset = 0
	var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	var drone := level.get_node_or_null("Drone") as RigidBody3D
	if drone == null:
		get_tree().quit(1)
		return
	drone.freeze = true
	var hall := level.find_child("HeroHall_steppe", true, false) as Node3D
	if hall != null:
		var c := hall.global_position + Vector3.UP * 6.0
		drone.global_position = c + Vector3(60.0, 26.0, 60.0)
		drone.look_at(c, Vector3.UP)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(output.path_join("hall_steppe.png"))
		print("[HALL_SHOT] hall=", hall != null, " err=", err)
	else:
		print("[HALL_SHOT] HeroHall not found")
	get_tree().quit(0)
