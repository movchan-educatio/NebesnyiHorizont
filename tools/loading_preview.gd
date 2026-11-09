## QA: render the mission loading card with the authored background.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	var overlay: Dictionary = LoadingScreen.build(Global.PlayMode.COMBAT, 2,
			"industrial", "OPERATOR", true)
	get_tree().root.add_child(overlay["layer"])
	var bar := overlay["bar"] as ProgressBar
	if bar != null:
		bar.value = 64.0
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/loading_mission.png"
	print("[LOADINGQA] ", out, " err=", img.save_png(out))
	get_tree().quit(0)
