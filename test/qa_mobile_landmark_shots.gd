extends Node

## Visual check for the five large landmarks: frames each structure from the
## air and captures the warehouse door bay so the enterable opening is visible.
## Run: MOBILE_LANDMARK_SHOT_DIR=<dir> ... qa_mobile_landmark_shots.tscn
const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _run() -> void:
	var output := OS.get_environment("MOBILE_LANDMARK_SHOT_DIR")
	if output.is_empty():
		output = "user://landmark_shots"
	DirAccess.make_dir_recursive_absolute(output)
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	Global.drone_preset = 0
	var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	if packed == null:
		print("[LANDMARK_SHOT] level load failed")
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	var pack := level.find_child("MobilePropPack", true, false) as Node3D
	var drone := level.get_node_or_null("Drone") as RigidBody3D
	if pack == null or drone == null:
		print("[LANDMARK_SHOT] pack/drone missing")
		get_tree().quit(1)
		return
	drone.freeze = true
	var idx := 0
	for prop in pack.get_children():
		var node := prop as Node3D
		if not bool(node.get_meta("pack_large", false)):
			continue
		var center := node.global_position + Vector3.UP * 6.0
		var at := center + Vector3(48.0, 22.0, 48.0)
		drone.global_position = at
		drone.look_at(center, Vector3.UP)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := output.path_join("landmark_%02d_%s.png" % [idx, String(node.name)])
		print("[LANDMARK_SHOT] ", path, " err=", img.save_png(path))
		idx += 1
		# The warehouse door faces local +Z after the glTF axis conversion.
		if String(node.name).begins_with("Prop_warehouse"):
			var door_view := node.to_global(Vector3(0, 6.0, 34.0))
			var door_target := node.to_global(Vector3(0, 4.0, 0.0))
			drone.global_position = door_view
			drone.look_at(door_target, Vector3.UP)
			drone.linear_velocity = Vector3.ZERO
			drone.angular_velocity = Vector3.ZERO
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var dimg := get_viewport().get_texture().get_image()
			var dpath := output.path_join("warehouse_door.png")
			print("[LANDMARK_SHOT] ", dpath, " err=", dimg.save_png(dpath))
	print("[LANDMARK_SHOT] landmarks=", idx)
	get_tree().quit(0)
