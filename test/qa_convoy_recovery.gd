extends Node

## Regression for the escort mission soft-lock: a blocked convoy used to sit at
## the same spot until the operation timer expired.  The mission director must
## detect the real displacement stall, force a checkpoint run, and still finish
## the operation when the convoy reaches the final approach.

const LevelScene := preload("res://sceneries/VillageLevel.tscn")
const TEST := "CONVOY_QA"

var _failures := 0
var _had_no_record := false
var _saved_no_record := ""


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_had_no_record = OS.has_environment("DRONE_NO_RECORD")
	_saved_no_record = OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("DRONE_NO_RECORD", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 2
	Global.combat_mission = 1
	Global.chain_briefing_pending = false
	Global.drone_preset = 2
	var level := LevelScene.instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.5).timeout

	var convoy: Node3D = level.get("_special_convoy") as Node3D
	var drone := level.get_node_or_null("Drone") as Node3D
	var dest: Vector3 = level.get("_special_convoy_dest")
	_check(convoy != null and drone != null, "escort convoy and drone spawned")
	if convoy == null or drone == null:
		_finish(level)
		return

	# Keep the escort in range and freeze the truck in place, simulating a
	# collision/nav dead end rather than a genuine route.
	convoy.set("move_speed", 0.0)
	var here := convoy.global_position
	convoy.call("set_waypoints", [here, dest])
	convoy.global_position = here
	drone.global_position = here + Vector3(0.0, 30.0, 0.0)
	level.set("_special_convoy_stall", 0.0)
	level.set("_special_convoy_stall_anchor", here)
	level.set("_special_convoy_recoveries", 0)

	convoy.call("escort_emergency_advance")
	var wps: PackedVector3Array = convoy.get("_waypoints")
	_check(bool(convoy.get("_escort_goal_seek"))
			and int(convoy.get("_wp_index")) == wps.size() - 1,
			"emergency advance forces the convoy onto the final checkpoint")
	# Restore the stall detector's anchor after the emergency call.
	level.set("_special_convoy_stall_anchor", convoy.global_position)
	level.set("_special_convoy_stall", 0.0)

	var recoveries := 0
	for i in range(6):
		level.call("_update_escort_mission", 4.5, drone)
		recoveries = maxi(recoveries, int(level.get("_special_convoy_recoveries")))
		if bool(level.get("_mission_finished")):
			break
	print("[", TEST, "] recoveries=", recoveries, " convoy=", convoy.global_position,
			" dest=", dest, " dist=%.1f" % convoy.global_position.distance_to(dest),
			" finished=", level.get("_mission_finished"),
			" failed=", level.get("_mission_failed"))
	_check(recoveries >= 1, "stall watchdog fires at least one recovery")
	_check(convoy.global_position.distance_to(dest) < 55.0,
			"convoy reaches the final approach after repeated stalls")
	_check(bool(level.get("_mission_finished")) and not bool(level.get("_mission_failed")),
			"escort operation completes instead of soft-locking the player")

	_finish(level)


func _finish(level: Node) -> void:
	if level != null and is_instance_valid(level):
		if get_tree().current_scene == level:
			get_tree().current_scene = null
		level.queue_free()
		await get_tree().process_frame
	if _had_no_record:
		OS.set_environment("DRONE_NO_RECORD", _saved_no_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	print("[", TEST, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
