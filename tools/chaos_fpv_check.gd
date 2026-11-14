## QA: capture the player's initial FPV frame in Chaos mode.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DRONE_PLAY_MODE", "combat")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.drone_preset = 12
	var level := (load("res://sceneries/BigLevel.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.5).timeout
	var cam := level.get_viewport().get_camera_3d()
	var drone := level.get_node_or_null("Drone")
	print("[FPVCHECK] camera=", cam, " drone=", drone.global_position if drone else "none")
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "C:/Users/USER_UA/AppData/Local/Temp/opencode/chaos_fpv2.png"
	print("[FPVCHECK] ", path, " err=", img.save_png(path))
	get_tree().quit(0)
