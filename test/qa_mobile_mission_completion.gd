extends Node

## Regression test: combat missions 1-4 complete end-to-end on the real
## BigLevel with the legacy maps (recon hold -> strike -> all targets down ->
## extraction hold -> results screen).  Campaign records are snapshotted and
## restored so the QA run never unlocks missions on the developer machine.
const TEST_NAME := "MOBILE_MISSION_COMPLETION"
var _failures := 0
var _saved_records: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_saved_records = Global.campaign_records.duplicate(true)
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.drone_preset = 0
	for mission in range(1, 5):
		Global.combat_mission = mission
		await _run_mission(mission)
	Global.campaign_records = _saved_records
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _run_mission(mission: int) -> void:
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	if packed == null:
		_check(false, "BigLevel loads for mission %d" % mission)
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(6.0).timeout
	var drone := level.get_node_or_null("Drone") as Node3D
	_check(drone != null, "mission %d spawns a drone" % mission)
	if drone == null:
		level.queue_free()
		await get_tree().process_frame
		return
	var targets_total := int(level.get("_mission_targets_total"))
	_check(targets_total > 0, "mission %d registered targets (%d)" % [mission, targets_total])
	level.call("_setup_mission_phases")
	_check(int(level.get("_mission_phase")) == 0, "mission %d starts in the recon phase" % mission)
	# Phase 1/3: hold the recon zone for 3 s.
	drone.freeze = true
	var recon: Vector3 = level.get("_recon_point")
	drone.global_position = recon
	level.set("_mission_started", true)
	for i in range(4):
		level.call("_update_mission_phases", 1.0)
	_check(int(level.get("_mission_phase")) == 1,
			"mission %d recon hold advances to the strike phase" % mission)
	# Phase 2/3: every primary target is destroyed.
	level.set("_mission_targets_destroyed", targets_total)
	level.call("_check_combat_mission_complete")
	_check(int(level.get("_mission_phase")) == 2,
			"mission %d enters extraction after all targets fall" % mission)
	# Phase 3/3: hold the extraction zone for 3 s and finish.
	var extract: Vector3 = level.get("_extract_point")
	drone.global_position = extract
	for i in range(4):
		level.call("_update_mission_phases", 1.0)
	_check(bool(level.get("_mission_finished")),
			"mission %d completes after holding the extraction zone" % mission)
	level.queue_free()
	await get_tree().process_frame
