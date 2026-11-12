extends Node3D

## Mobile-only regression test for infantry model/procedural-animation LOD.
const TEST_NAME := "MOBILE_INFANTRY_LOD"
var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var soldier := EnemyRifleman.new()
	soldier.name = "MobileSoldier"
	add_child(soldier)
	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	if soldier.get("_detailed_rig") == null:
		_check(false, "detailed skinned rig loaded")
		get_tree().quit(1)
		return
	_check(soldier.get("_lod_proxy") != null, "mobile LOD proxy created")

	camera.global_position = Vector3(0, 1.5, 50)
	soldier.call("_update_lod", 0.3)
	var rig := soldier.get("_detailed_rig") as DetailedSoldierRig
	_check(float(rig.get("_mobile_animation_hz")) == 30.0,
			"near LOD updates procedural animation at 30 Hz")
	# Imported GLB bones carry numeric suffixes; use the rig's resolved index.
	var thigh := int(rig.get("_b_thigh_l"))
	_check(thigh >= 0, "left thigh bone available for pose rate test")
	if thigh >= 0:
		var original_pose := rig.skeleton.get_bone_pose_rotation(thigh)
		rig.set_walk(PI * 0.5, 1.0)
		_check(rig.skeleton.get_bone_pose_rotation(thigh).is_equal_approx(original_pose),
				"set_walk does not bypass the mobile pose rate limit")
		rig.call("_process", 1.0 / 30.0)
		_check(not rig.skeleton.get_bone_pose_rotation(thigh).is_equal_approx(original_pose),
				"walk pose updates on the next scheduled mobile tick")
	rig.set_walk(0.0, 0.45)
	_check(float(rig.get("_run_blend")) == 0.0, "procedural walk cycle uses its walk stride")
	rig.set_walk(0.0, 1.35)
	_check(float(rig.get("_run_blend")) == 1.0, "procedural run cycle blends to full run")
	_check(bool(soldier.get("_model").visible) and not bool(soldier.get("_lod_proxy").visible),
			"near LOD shows detailed soldier")

	camera.global_position = Vector3(0, 1.5, 150)
	soldier.call("_update_lod", 0.3)
	_check(float(rig.get("_mobile_animation_hz")) == 15.0,
			"mid LOD updates procedural animation at 15 Hz")
	_check(not bool(soldier.get("_model").visible) and bool(soldier.get("_lod_proxy").visible),
			"mid LOD swaps to the impostor proxy")
	var impostor := soldier.get("_lod_impostor") as Sprite3D
	_check(impostor != null and impostor.hframes == 2 and impostor.vframes == 2,
			"mid LOD uses the four-view baked billboard atlas")
	if impostor != null:
		_check(impostor.frame >= 0 and impostor.frame < 4,
				"billboard selects a valid directional frame")

	camera.global_position = Vector3(0, 1.5, 300)
	soldier.call("_update_lod", 0.3)
	_check(float(rig.get("_mobile_animation_hz")) == 0.0,
			"hidden far LOD suspends procedural pose updates")
	_check(not bool(soldier.get("_model").visible) and not bool(soldier.get("_lod_proxy").visible),
			"far LOD hides model and proxy")

	camera.global_position = Vector3(0, 1.5, 50)
	soldier.call("_update_lod", 0.3)
	_check(float(rig.get("_mobile_animation_hz")) == 30.0
			and bool(soldier.get("_model").visible)
			and not bool(soldier.get("_lod_proxy").visible),
			"near LOD restores rig and animation after far culling")
	# No Drone is present in this test scene; visual LOD must still follow the
	# camera instead of freezing behind the AI's no-drone early return.
	camera.global_position = Vector3(0, 1.5, 300)
	soldier.call("_physics_process", 0.3)
	_check(float(rig.get("_mobile_animation_hz")) == 0.0
			and not bool(soldier.get("_model").visible),
			"camera-based far LOD updates even without a Drone")
	camera.global_position = Vector3(0, 1.5, 50)
	soldier.call("_physics_process", 0.3)
	_check(float(rig.get("_mobile_animation_hz")) == 30.0
			and bool(soldier.get("_model").visible),
			"camera-based near LOD recovers without a Drone")
	var breath_before := float(rig.get("_breath_phase"))
	rig.call("_process", 1.0 / 30.0)
	_check(not is_equal_approx(float(rig.get("_breath_phase")), breath_before),
			"idle breathing procedural animation advances")
	rig.set_crouch(true)
	_check(float(rig.get("_crouch_target")) == 1.0, "crouch pose can be activated")
	rig.set_aim_pitch(0.35)
	rig.set_look_yaw(-0.2)
	_check(is_equal_approx(float(rig.get("_aim_pitch")), 0.35)
			and is_equal_approx(float(rig.get("_look_yaw")), -0.2),
			"aim and scan poses accept target angles")
	rig.kick()
	_check(float(rig.get("_kick")) == 1.0, "fire recoil animation can be triggered")
	rig.start_reload(1.75)
	_check(rig.is_reloading(), "reload animation can be triggered")
	rig.hit_react(true)
	_check(float(rig.get("_hit_flinch")) == 1.0, "hit reaction animation can be triggered")
	rig.play_death(0)
	_check(bool(rig.get("_dead")), "death pose can be triggered")
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
