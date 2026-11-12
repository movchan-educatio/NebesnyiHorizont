extends Node

## Visual check for the new Blender prop pack: loads Steppe, frames three prop
## clusters with the real FPV camera and saves screenshots.
## Run: MOBILE_PROP_SHOT_DIR=<dir> ... qa_mobile_props_shot.tscn
const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")
const VIEWS := [
	{"name": "checkpoint", "at": Vector2(325, 300), "look": Vector2(350, 320), "h": 7.0},
	{"name": "farm", "at": Vector2(-100, 275), "look": Vector2(-150, 300), "h": 9.0},
	{"name": "powerline", "at": Vector2(-235, 150), "look": Vector2(-300, 220), "h": 10.0},
]


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_environment("MOBILE_PROP_SHOT_DIR")
	if output.is_empty():
		output = "user://prop_shots"
	DirAccess.make_dir_recursive_absolute(output)
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.drone_preset = 0
	var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	if packed == null:
		print("[PROP_SHOT] level load failed")
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(4.0).timeout
	var pack := level.find_child("MobilePropPack", true, false)
	print("[PROP_SHOT] placed=", int(pack.get_meta("placed", 0)) if pack != null else -1)
	var drone := level.get_node_or_null("Drone") as RigidBody3D
	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if drone == null or fpv == null:
		print("[PROP_SHOT] drone missing")
		get_tree().quit(1)
		return
	drone.freeze = true
	for view in VIEWS:
		var at: Vector2 = view["at"]
		var look: Vector2 = view["look"]
		var y: float = TERRAIN.height_at("steppe", at.x, at.y) + float(view["h"])
		drone.global_position = Vector3(at.x, y, at.y)
		var target := Vector3(look.x, TERRAIN.height_at("steppe", look.x, look.y) + 3.0, look.y)
		if not drone.global_position.is_equal_approx(target):
			drone.look_at(target, Vector3.UP)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := output.path_join(String(view["name"]) + ".png")
		var err := img.save_png(path)
		print("[PROP_SHOT] ", path, " err=", err)
	get_tree().quit(0)
