extends Node

## QA: screenshot a map from several aerial viewpoints.
## Usage: godot --path . res://test/qa_map_shot.tscn -- <Level> (e.g. VillageLevel)

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var lvl := "VillageLevel"
	for a in OS.get_cmdline_user_args():
		lvl = a
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var level := (load("res://sceneries/%s.tscn" % lvl) as PackedScene).instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var cam := Camera3D.new()
	cam.fov = 80.0
	cam.far = 3000.0
	level.add_child(cam)
	cam.current = true
	var views := [
		[Vector3(0, 90, 220), Vector3(0, 0, 0)],
		[Vector3(180, 45, 60), Vector3(0, 5, 0)],
		[Vector3(-160, 30, -120), Vector3(0, 5, -40)],
		[Vector3(0, 400, 1), Vector3(0, 0, 0)],
	]
	for i in range(views.size()):
		cam.global_position = views[i][0]
		cam.look_at(views[i][1], Vector3.UP)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			"res://qa_shots/map_%s_%d.png" % [lvl, i])
	print("[MAPSHOT] done ", lvl)
	get_tree().quit()
