extends Node

## Regression: engine audio must come from exactly one motor (four identical
## loops beat against each other and sound like a pulsing siren) and every
## played sample must have a real loop flag.

func _ready() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	var drone := level.get_node_or_null("Drone")
	if drone == null:
		print("[AUDIOTEST] FAIL no drone")
		get_tree().quit(1)
		return
	var motors: Array = []
	for node in drone.find_children("*", "Node", true, false):
		if String(node.name).begins_with("Motor"):
			motors.append(node)
	if motors.is_empty():
		motors = drone.get("motors") if drone.get("motors") != null else []
	var with_audio := 0
	var total_players := 0
	var non_looped := 0
	var details: Array = []
	for motor in motors:
		var players := 0
		for child in motor.get_children():
			var p := child as AudioStreamPlayer
			if p == null or p.stream == null:
				continue
			players += 1
			total_players += 1
			var wav := p.stream as AudioStreamWAV
			if wav == null or wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
				non_looped += 1
		if players > 0:
			with_audio += 1
		details.append("%s=%d" % [String(motor.name), players])
	var ok := with_audio == 1 and total_players == 8 and non_looped == 0
	print("[AUDIOTEST] motors=", motors.size(), " with_audio=", with_audio,
			" players=", total_players, " non_looped=", non_looped,
			" ", " ".join(details))
	print("[AUDIOTEST] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
