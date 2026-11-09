## QA: boot the Chaos battle and capture wide + close views.
extends Node

const TERRAIN = preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DRONE_PLAY_MODE", "chaos")
	Global.play_mode = Global.PlayMode.CHAOS
	Global.drone_preset = 12
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(1.5).timeout
	print("[CHAOSQA] initial camera=", level.get_viewport().get_camera_3d())
	await _shot("chaos_fpv.png")
	Engine.time_scale = 3.0
	await get_tree().create_timer(6.0).timeout
	Engine.time_scale = 1.0
	await get_tree().create_timer(0.6).timeout
	var battle := level.find_child("ChaosBattle", true, false)
	if battle == null:
		print("[CHAOSQA] no battle node")
		get_tree().quit(1)
		return
	var soldiers := battle.find_children("*", "ChaosSoldier", true, false)
	var vehicles := battle.find_children("*", "Vehicle", true, false)
	print("[CHAOSQA] soldiers=", soldiers.size(), " vehicles=", vehicles.size())
	var cam := Camera3D.new()
	cam.name = "QACamera"
	cam.fov = 62.0
	cam.far = 800.0
	level.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(30.0, 55.0, 115.0)
	cam.look_at(Vector3(30.0, 1.0, -28.0), Vector3.UP)
	await _shot("chaos_wide.png")
	# Bring a small fire team close to the camera so the QA shot shows the
	# detailed soldier model, muzzle flashes and tracers in the actual map.
	var blue: Array = []
	var red: Array = []
	for s in soldiers:
		if int(s.get("team")) == 0:
			blue.append(s)
		else:
			red.append(s)
	for i in range(4):
		var x := 22.0 + i * 3.2
		if i < blue.size():
			blue[i].global_position = Vector3(x, TERRAIN.height_at("industrial", x, 12.0), 12.0)
			blue[i].rotation.y = 0.0
		if i < red.size():
			red[i].global_position = Vector3(x, TERRAIN.height_at("industrial", x, 18.0), 18.0)
			red[i].rotation.y = PI
	var cam2 := Camera3D.new()
	cam2.fov = 50.0
	cam2.far = 800.0
	level.add_child(cam2)
	cam2.current = true
	cam2.global_position = Vector3(27.0, 4.2, 30.0)
	cam2.look_at(Vector3(27.0, 1.2, 14.0), Vector3.UP)
	await get_tree().create_timer(1.2).timeout
	await _shot("chaos_close.png")
	Engine.time_scale = 1.0
	get_tree().quit(0)

func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/" + file
	print("[CHAOSQA] ", path, " err=", img.save_png(path))
