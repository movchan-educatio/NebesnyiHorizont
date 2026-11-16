extends Node

## Regression test: combat missions 1-4 complete end-to-end on the real
## BigLevel with the legacy maps (recon hold -> strike -> all targets down ->
## extraction hold -> results screen).  Campaign records are snapshotted and
## restored so the QA run never unlocks missions on the developer machine.
const TEST_NAME := "MOBILE_MISSION_COMPLETION"
const LocScript := preload("res://scripts/util/localization_manager.gd")
var _failures := 0
var _saved_records: Dictionary = {}
var _saved_language: int = LocScript.Language.UA
var _had_mobile_env := false
var _saved_mobile_env := ""
var _had_touch_env := false
var _saved_touch_env := ""
var _had_no_record_env := false
var _saved_no_record_env := ""


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_had_mobile_env = OS.has_environment("MOBILE_UI")
	_saved_mobile_env = OS.get_environment("MOBILE_UI")
	_had_touch_env = OS.has_environment("TOUCH_CONTROLS")
	_saved_touch_env = OS.get_environment("TOUCH_CONTROLS")
	_had_no_record_env = OS.has_environment("DRONE_NO_RECORD")
	_saved_no_record_env = OS.get_environment("DRONE_NO_RECORD")
	_saved_language = LocScript.get_language()
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("TOUCH_CONTROLS", "1")
	OS.set_environment("DRONE_NO_RECORD", "1")
	LocScript.set_language(LocScript.Language.EN, false)
	_check(Global.get_special_mission_name(1) == "RECONNAISSANCE",
			"special operation names use the selected English locale")
	_saved_records = Global.campaign_records.duplicate(true)
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.drone_preset = 0
	for mission in range(1, 5):
		Global.combat_mission = mission
		await _run_mission(mission)
	Global.campaign_records = _saved_records
	LocScript.set_language(_saved_language, false)
	if _had_mobile_env:
		OS.set_environment("MOBILE_UI", _saved_mobile_env)
	else:
		OS.unset_environment("MOBILE_UI")
	if _had_touch_env:
		OS.set_environment("TOUCH_CONTROLS", _saved_touch_env)
	else:
		OS.unset_environment("TOUCH_CONTROLS")
	if _had_no_record_env:
		OS.set_environment("DRONE_NO_RECORD", _saved_no_record_env)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
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
	var touch_on_entry := get_node_or_null("/root/TouchControls")
	_check(touch_on_entry != null and bool(touch_on_entry.get("enabled"))
			and touch_on_entry.visible,
			"mission %d reload restores mobile touch controls" % mission)
	var drone := level.get_node_or_null("Drone") as Node3D
	_check(drone != null, "mission %d spawns a drone" % mission)
	if drone == null:
		level.queue_free()
		await get_tree().process_frame
		return
	var targets_total := int(level.get("_mission_targets_total"))
	_check(targets_total > 0, "mission %d registered targets (%d)" % [mission, targets_total])
	if mission == 1:
		_check(str(level.call("_mission_chain_tasks", 1)).begins_with("MISSION:"),
				"campaign briefing tasks are translated to English")
		_check(str(level.call("_mission_phase_plan_text", 1)).begins_with("PHASES:"),
				"campaign briefing phases are translated to English")
	if mission == 1:
		var infantry: Array = level.get("_infantry_units")
		if not infantry.is_empty():
			var soldier := infantry[0] as Node3D
			var soldier_collider: CollisionShape3D = null
			for child in soldier.get_children():
				if child is CollisionShape3D:
					soldier_collider = child as CollisionShape3D
					break
			_check(soldier != null and is_equal_approx(soldier.scale.x, 1.20),
					"mobile infantry model uses +20% scale")
			_check(soldier_collider != null and is_equal_approx(
					soldier_collider.global_transform.basis.get_scale().x, 1.20),
					"mobile infantry hitbox scales with its model")
		else:
			_check(false, "mobile infantry targets are present for scale QA")
	if mission == 2:
		var vehicles: Array = level.get("_vehicles")
		if not vehicles.is_empty():
			var vehicle := vehicles[0] as Node3D
			var vehicle_collider: CollisionShape3D = null
			for child in vehicle.get_children():
				if child is CollisionShape3D:
					vehicle_collider = child as CollisionShape3D
					break
			_check(vehicle != null and is_equal_approx(vehicle.scale.x, 1.20),
					"mobile vehicle model uses +20% scale")
			_check(vehicle_collider != null and is_equal_approx(
					vehicle_collider.global_transform.basis.get_scale().x, 1.20),
					"mobile vehicle hitbox scales with its model")
		else:
			_check(false, "mobile vehicles are present for scale QA")
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
	# Phase 2/2: every primary target is destroyed -> direct mission completion
	# with no lingering extraction marker.
	level.set("_mission_targets_destroyed", targets_total)
	level.call("_check_combat_mission_complete")
	_check(not bool(level.get("_mission_phase_active")),
			"mission %d deactivates phase extraction immediately after all targets fall" % mission)
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	var phase_info: Dictionary = level.call("get_mission_phase_info")
	_check(bool(level.get("_mission_finished")),
			"mission %d completes directly after all targets are destroyed" % mission)
	_check(phase_info.is_empty(),
			"mission %d leaves no blue exit marker after completion" % mission)
	var results: Control = level.get("_results")
	var results_canvas: CanvasLayer = level.get("_results_canvas_layer")
	var level_hud: CanvasLayer = level.get("_hud")
	var touch := get_node_or_null("/root/TouchControls")
	_check(results != null and results.visible and results_canvas != null
			and results_canvas.layer == 120,
			"mission %d results modal is visible on the top mobile canvas" % mission)
	_check(level_hud != null and not level_hud.visible and touch != null
			and not bool(touch.get("enabled")) and not touch.visible,
			"mission %d hides the gameplay HUD and touch controls" % mission)
	var stats: Label = level.get("_results_stats")
	_check(stats != null and stats.text.contains("TARGETS DESTROYED")
			and not stats.text.contains("ЗНИЩЕНО ЦІЛЕЙ"),
			"mission %d results statistics use English localization" % mission)
	level.queue_free()
	await get_tree().process_frame
