extends Node

## QA audio audit: loads one frontline map (AUDIO_MAP env) and reports every
## audio source the map and its combat units created.  Run without --headless
## so the 3D players are actually instantiated.

func _ready() -> void:
	var map_name := OS.get_environment("AUDIO_MAP")
	if map_name.is_empty():
		map_name = "steppe"
	var path := "res://sceneries/%sLevel.tscn" % map_name.capitalize()
	if not ResourceLoader.exists(path):
		path = "res://sceneries/%s.tscn" % map_name
	var scene := load(path) as PackedScene
	if scene == null:
		print("[AUDIOMAP] ", map_name, " LOAD FAIL ", path)
		get_tree().quit(1)
		return
	Global.play_mode = Global.PlayMode.COMBAT
	var mission := int(OS.get_environment("AUDIO_MISSION"))
	if mission <= 0:
		mission = 2
	Global.combat_mission = mission
	Global.drone_preset = 7
	var level := scene.instantiate()
	add_child(level)
	await get_tree().create_timer(4.5).timeout

	var players3d := level.find_children("*", "AudioStreamPlayer3D", true, false)
	var players2d := level.find_children("*", "AudioStreamPlayer", true, false)
	var vehicles: Array = []
	var infantry := 0
	var engines := 0
	for node in level.find_children("*", "Node3D", true, false):
		if node is Vehicle:
			vehicles.append(node)
			if node.get("_engine_player") != null:
				engines += 1
		elif node is EnemyRifleman:
			infantry += 1
	var drone := level.get_node_or_null("Drone")
	var motor_stream_ok := false
	if drone != null:
		var motor_audio = drone.get("_motor_audio")
		motor_stream_ok = motor_audio != null and motor_audio.stream != null
	var ambient := level.get_node_or_null("AmbientBattle")
	print("[AUDIOMAP] map=%s players3d=%d players2d=%d vehicles=%d engines=%d infantry=%d ambient=%s drone_motor=%s" % [
		map_name, players3d.size(), players2d.size(), vehicles.size(), engines,
		infantry, str(ambient != null), str(motor_stream_ok)])
	level.queue_free()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
