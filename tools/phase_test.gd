## QA: recon -> strike -> extract mission state machine.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DRONE_COMBAT_MISSION", "1")
	OS.set_environment("DRONE_NO_RECORD", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.chain_briefing_pending = false
	var level := (load("res://sceneries/BigLevel.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.5).timeout
	level.call("_start_mission")
	await get_tree().process_frame
	assert(int(level.get("_mission_phase")) == 0, "must start in recon")
	var recon: Vector3 = level.get("_recon_point")
	var drone := level.get_node_or_null("Drone") as Node3D
	drone.global_position = recon
	level.call("_update_mission_phases", 3.1)
	assert(int(level.get("_mission_phase")) == 1, "recon hold must enter strike")
	level.set("_mission_targets_destroyed", int(level.get("_mission_targets_total")))
	level.call("_check_combat_mission_complete")
	assert(int(level.get("_mission_phase")) == 2, "all targets must enter extract")
	var extract: Vector3 = level.get("_extract_point")
	drone.global_position = extract
	level.call("_update_mission_phases", 3.1)
	assert(bool(level.get("_mission_finished")), "extract hold must finish the mission")
	print("[PHASEQA] PASS · recon -> strike -> extract -> debrief")
	get_tree().quit(0)
