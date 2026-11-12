extends Node3D

## Mobile-only regression test for infantry model/procedural-animation LOD.
const TEST_NAME := "MOBILE_INFANTRY_LOD"


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)


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
	get_tree().quit(0)
