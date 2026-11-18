extends Node

## Regression for the end-of-sortie race: when the last airframe is lost in the
## same frame as the final target kill, a delayed "all airframes lost" timer
## used to read stale counters and fail a mission that had already reached 2/2.
## Two orders are covered:
##   A. final target dies while the airframe-loss debounce is still pending;
##   B. the last airframe is consumed after the final target is already down.

const LevelScene := preload("res://sceneries/BigLevel.tscn")
const TEST := "AIRFRAME_RACE"

var _failures := 0
var _had_no_record := false
var _saved_no_record := ""
var _saved_fulltest := ""
var _had_fulltest := false
var _had_autotest := false
var _saved_autotest := ""
var _had_retry := false
var _saved_retry := ""
var _had_no_limit := false
var _saved_no_limit := ""


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_had_no_record = OS.has_environment("DRONE_NO_RECORD")
	_saved_no_record = OS.get_environment("DRONE_NO_RECORD")
	_had_fulltest = OS.has_environment("DRONE_FULLTEST")
	_saved_fulltest = OS.get_environment("DRONE_FULLTEST")
	_had_autotest = OS.has_environment("DRONE_AUTOTEST")
	_saved_autotest = OS.get_environment("DRONE_AUTOTEST")
	_had_retry = OS.has_environment("DRONE_RETRY_TEST")
	_saved_retry = OS.get_environment("DRONE_RETRY_TEST")
	_had_no_limit = OS.has_environment("QA_NO_AIRFRAME_LIMIT")
	_saved_no_limit = OS.get_environment("QA_NO_AIRFRAME_LIMIT")
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.unset_environment("DRONE_FULLTEST")
	OS.unset_environment("DRONE_AUTOTEST")
	OS.unset_environment("DRONE_RETRY_TEST")
	OS.unset_environment("QA_NO_AIRFRAME_LIMIT")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.drone_preset = 0

	# Case A: the airframe-loss timer is armed while one target is still alive,
	# then the final kill lands during the 1.2 s debounce.
	var level_a := await _spawn_level()
	if level_a == null:
		_check(false, "combat level loaded")
		_finish(null)
		return
	_check(bool(level_a.call("_airframes_limited")),
			"combat sortie enforces the airframe reserve")
	level_a.set("_mission_targets_total", 2)
	level_a.set("_mission_targets_destroyed", 1)
	level_a.set("_sortie_airframes_left", 1)
	level_a.set("_airframe_consumed_this_life", false)
	level_a.set("_pending_combat_complete", false)
	level_a.set("_mission_finished", false)
	level_a.set("_mission_failed", false)
	var consumed_a: bool = level_a.call("consume_sortie_airframe", "STRIKE")
	_check(not consumed_a, "last airframe loss starts the failure debounce")
	# The second target is destroyed 0.2 s later, before the 1.2 s debounce.
	await get_tree().create_timer(0.2).timeout
	level_a.set("_mission_targets_destroyed", 2)
	level_a.call("_check_combat_mission_complete")
	await get_tree().create_timer(2.4).timeout
	_check(not bool(level_a.get("_mission_failed")),
			"debounce timeout does not fail a mission completed during it")
	_check(bool(level_a.get("_mission_finished")),
			"mission completes when the final kill lands inside the debounce")
	var results_a: Control = level_a.get("_results")
	_check(results_a != null and results_a.visible,
			"successful debrief replaces the airframes-lost failure screen")
	await _free_level(level_a)

	# Case B: the target counter already reads 2/2 when the last airframe is
	# consumed.  No failure timer may be armed at all.
	var level_b := await _spawn_level()
	if level_b == null:
		_check(false, "second combat level loaded")
		_finish(null)
		return
	level_b.set("_mission_targets_total", 2)
	level_b.set("_mission_targets_destroyed", 2)
	level_b.set("_sortie_airframes_left", 1)
	level_b.set("_airframe_consumed_this_life", false)
	level_b.set("_pending_combat_complete", false)
	level_b.set("_mission_finished", false)
	level_b.set("_mission_failed", false)
	var consumed_b: bool = level_b.call("consume_sortie_airframe", "STRIKE")
	_check(consumed_b, "completed objectives arm no failure timer for the last airframe")
	await get_tree().create_timer(1.6).timeout
	_check(not bool(level_b.get("_mission_failed")),
			"2/2 objectives are not failed by the airframe reserve")
	level_b.call("_check_combat_mission_complete")
	await get_tree().create_timer(1.6).timeout
	_check(bool(level_b.get("_mission_finished")) and not bool(level_b.get("_mission_failed")),
			"mission completes with all targets destroyed instead of showing airframes lost")
	var results_b: Control = level_b.get("_results")
	_check(results_b != null and results_b.visible,
			"successful debrief is shown after the final target")
	await _free_level(level_b)

	_finish(null)


func _spawn_level() -> Node3D:
	var level := LevelScene.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(6.0).timeout
	if not is_instance_valid(level):
		return null
	return level


func _free_level(level: Node) -> void:
	if level != null and is_instance_valid(level):
		if get_tree().current_scene == level:
			get_tree().current_scene = null
		level.queue_free()
		await get_tree().process_frame


func _restore_env(had: bool, key: String, value: String) -> void:
	if had:
		OS.set_environment(key, value)
	else:
		OS.unset_environment(key)


func _finish(_level: Node) -> void:
	_restore_env(_had_no_record, "DRONE_NO_RECORD", _saved_no_record)
	_restore_env(_had_fulltest, "DRONE_FULLTEST", _saved_fulltest)
	_restore_env(_had_autotest, "DRONE_AUTOTEST", _saved_autotest)
	_restore_env(_had_retry, "DRONE_RETRY_TEST", _saved_retry)
	_restore_env(_had_no_limit, "QA_NO_AIRFRAME_LIMIT", _saved_no_limit)
	print("[", TEST, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
