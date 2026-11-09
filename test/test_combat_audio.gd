extends Node

## Generates every combat-audio stream once and verifies the buffers/loops.
## Runs headless (synthesis does not need an output device).

const SFX := preload("res://combat/sfx.gd")


func _ready() -> void:
	_check("boom", SFX.boom_stream())
	_check("shot", SFX.shot_stream())
	_check("rifle", SFX.rifle_stream())
	_check("cannon", SFX.cannon_stream())
	_check("autocannon", SFX.autocannon_stream())
	_check("track", SFX.track_clatter_stream())
	_check("fire", SFX.fire_stream())
	_check("artillery", SFX.artillery_stream())
	_check("servo", SFX.servo_stream())
	_check("tank_engine", SFX.tank_engine_stream())
	_check("bmp_engine", SFX.bmp_engine_stream())
	_check("apc_engine", SFX.apc_engine_stream())
	_check("truck_engine", SFX.truck_engine_stream())
	_check("heli_rotor", SFX.heli_rotor_stream())
	_check("shahed", SFX.shahed_engine_stream())
	_check("footstep", SFX.footstep_stream())
	_check("soldier_death", SFX.soldier_death_stream())
	_check("drone_impact", SFX.drone_impact_stream())
	for kind in range(7):
		_check("motor_%d" % kind, SFX.drone_motor_stream(kind))
	get_tree().quit()


func _check(name: String, stream: AudioStreamWAV) -> void:
	if stream == null:
		print("[AUDIO] ", name, " FAIL null")
		return
	print("[AUDIO] ", name, " bytes=", stream.data.size(), " rate=",
			stream.mix_rate, " loop=", stream.loop_mode)
