extends Node3D

## QA suite for the three-step combat training.  It builds the real guide in an
## empty world and drives every transition without a human pilot.

const CombatTrainingScript = preload("res://scripts/util/combat_training.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")

var guide = null
var drone: Drone = null
var _saved_records: Dictionary = {}
var _saved_language: int = LocScript.Language.UA
var _respawn_calls := 0


func _ready() -> void:
	_saved_records = Global.campaign_records.duplicate(true)
	_saved_language = LocScript.get_language()
	LocScript.set_language(LocScript.Language.UA, false)
	print("=== COMBAT TRAINING 3-STEP QA ===")
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = true
	Global.set_combat_training_completed(false)

	var scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(scene != null)
	drone = scene.instantiate() as Drone
	add_child(drone)
	drone.freeze = true
	drone.global_position = Vector3(0.0, 1.0, 0.0)

	var hud_root := Control.new()
	hud_root.custom_minimum_size = Vector2(1280, 720)
	add_child(hud_root)

	guide = CombatTrainingScript.new()
	add_child(guide)
	guide.pause_on_completion = false
	guide.initialize(self, drone, 0.0)
	guide.setup_hud(hud_root)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	assert(guide.step == CombatTrainingScript.Step.ARM_TAKEOFF)
	assert(guide.target != null, "training tank must spawn")
	assert(guide._dots.size() == CombatTrainingScript.TOTAL_STEPS)
	assert(CombatTrainingScript.TOTAL_STEPS == 3)
	var spawn_dist := Vector2(guide.target.global_position.x,
			guide.target.global_position.z).length()
	assert(absf(spawn_dist - CombatTrainingScript.TARGET_DISTANCE) < 2.0,
			"tank must sit ~68 m from spawn, got %.1f" % spawn_dist)
	assert(guide._marker != null and guide._beacon != null and guide._zone != null)
	print("[OK] one tank + beacon + blast zone at %.1f m" % spawn_dist)

	# --- Step 1: ARM + 8 m ------------------------------------------------
	drone.flight_controller.set_armed(true)
	drone.global_position = Vector3(0.0, 9.0, 0.0)
	guide.update_training(0.05)
	assert(guide.step == CombatTrainingScript.Step.APPROACH,
			"arming and 8 m must advance to the approach step")
	print("[OK] step 1: ARM + climb to 8 m")

	# --- Step 2: close within 50 m ----------------------------------------
	var tpos: Vector3 = guide.target.global_position
	drone.global_position = tpos + Vector3(0.0, 20.0, 24.0)
	guide.update_training(0.05)
	assert(guide.step == CombatTrainingScript.Step.DESTROY,
			"closing to <50 m must advance to the destroy step")
	print("[OK] step 2: approach within 50 m")

	# --- Step 3: destroy the tank -----------------------------------------
	guide.target.take_damage(9999.0)
	await get_tree().process_frame
	assert(guide.step == CombatTrainingScript.Step.COMPLETED,
			"target destruction must complete the training")
	assert(Global.is_combat_training_completed())
	assert(guide._completion != null and guide._completion.visible)
	assert(guide._marker != null and not guide._marker.visible)
	print("[OK] step 3: payload kill, completion panel + progress badge")

	# --- Repeat -----------------------------------------------------------
	guide.restart_session()
	assert(guide.step == CombatTrainingScript.Step.ARM_TAKEOFF)
	assert(_respawn_calls == 1, "repeat must respawn the drone")
	assert(guide.target != null and not guide.target.is_destroyed)
	assert(guide.target.health == CombatTrainingScript.TARGET_HEALTH)
	var new_dist := Vector2(guide.target.global_position.x,
			guide.target.global_position.z).length()
	assert(absf(new_dist - CombatTrainingScript.TARGET_DISTANCE) < 2.0,
			"repeated tank must return to the same strip")
	print("[OK] repeat respawns drone and a fresh tank")

	# --- Backspace respawn heals the target and restarts the steps --------
	guide.step = CombatTrainingScript.Step.DESTROY
	guide.target.health = 40.0
	guide.on_player_respawn()
	assert(guide.step == CombatTrainingScript.Step.ARM_TAKEOFF)
	assert(guide.target.health == CombatTrainingScript.TARGET_HEALTH)
	print("[OK] respawn heals target and restarts the 3 steps")

	assert(not guide.get_status_line().is_empty())
	assert(not guide._inst_lbl.text.is_empty())
	print("  HUD:", guide._title_lbl.text)
	print("  metric:", guide._metric_lbl.text)

	print("=== RESULT: COMBAT TRAINING 3-STEP QA PASS ===")
	Global.campaign_records = _saved_records
	Global.save_campaign_records()
	LocScript.set_language(_saved_language, false)
	get_tree().quit(0)


# --- Minimal level API used by the guide in this empty test world ---------
func _find_ground_y(_x: float, _z: float) -> float:
	return 0.0


func _find_dry_spot(x: float, z: float) -> Vector2:
	return Vector2(x, z)


func _respawn_and_rearm() -> void:
	_respawn_calls += 1
	if drone != null and is_instance_valid(drone):
		drone.global_position = Vector3(0.0, 1.0, 0.0)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
