## QA: capture the combat mission FPV view with dynamic objective markers.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DRONE_COMBAT_MISSION", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	var preset := 11
	if OS.get_environment("DRONE_PRESET") != "":
		preset = int(OS.get_environment("DRONE_PRESET"))
	Global.drone_preset = preset
	if OS.has_environment("DRONE_CHAIN_BRIEF"):
		Global.chain_briefing_pending = true
	var level := (load("res://sceneries/BigLevel.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(3.0).timeout
	if OS.has_environment("DRONE_PHASE_TEST"):
		level.call("_start_mission")
		await get_tree().create_timer(1.0).timeout
	var markers := level.get_node_or_null("HUD/ObjectiveMarkers")
	print("[COMBATQA] preset=", preset, " markers=", markers,
			" camera=", level.get_viewport().get_camera_3d())
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_environment("MODEL_OUT")
	if path.is_empty():
		path = "C:/Users/USER_UA/AppData/Local/Temp/opencode/combat_markers.png"
	print("[COMBATQA] ", path, " err=", img.save_png(path))
	get_tree().quit(0)
