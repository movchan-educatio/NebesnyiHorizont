extends Node

## Regression test for the TAC-05 naval mission (Magura-X): the extraction
## marker must be open water, and the mission must actually complete when the
## USV holds the extraction zone after the strike phase.
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[NAVAL_QA] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 5
	Global.drone_preset = 10
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	if packed == null:
		_check(false, "BigLevel loads")
		get_tree().quit(1)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(6.0).timeout
	level.call("_setup_mission_phases")
	var extract: Vector3 = level.get("_extract_point")
	var sea: float = level.get("_sea_y")
	_check(extract.y > sea, "naval extraction marker sits on the water")
	_check(extract.distance_to(Vector3(380.0, sea, -50.0)) > 100.0,
			"naval extraction is clear of the hydro plant")
	_check(extract.distance_to(Vector3(450.0, sea, 110.0)) > 100.0,
			"naval extraction is clear of the enemy warship")
	_check(extract.x > 205.0, "naval extraction stays east of the coast strip")
	var drone := level.get_node_or_null("Drone") as Node3D
	_check(drone != null, "naval mission spawns the USV")
	if drone == null:
		get_tree().quit(1)
		return
	level.set("_mission_started", true)
	level.set("_mission_phase", 2)
	drone.global_position = extract
	for i in range(4):
		level.call("_update_mission_phases", 1.0)
	_check(bool(level.get("_mission_finished")),
			"naval mission completes after holding the extraction zone")
	print("[NAVAL_QA] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
