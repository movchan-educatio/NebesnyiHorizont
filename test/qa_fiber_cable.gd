extends Node

## Regression test for the fiber-optic tether.  Fiber mode must build a visible
## world-space cable from the launch spool to the airframe, keep it attached
## while the drone climbs, hide it outside fiber mode, and reset it on respawn.

const TEST_NAME := "FIBER_QA"

var _failures := 0
var _had_fiber := false
var _saved_fiber := false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	_had_fiber = Global.menu_settings.has("fiber_optic_mode")
	_saved_fiber = bool(Global.menu_settings.get("fiber_optic_mode", false))
	Global.menu_settings["fiber_optic_mode"] = true
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.special_mission = 0
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(3.0).timeout

	var drone := level.get_node_or_null("Drone") as Node3D
	_check(drone != null, "fiber test level spawns a drone")
	if drone == null:
		_finish(level)
		return
	var cable: MeshInstance3D = level.get("_fiber_cable")
	var anchor_ready := bool(level.get("_fiber_anchor_ready"))
	var anchor: Vector3 = level.get("_fiber_anchor")
	_check(cable != null and is_instance_valid(cable), "fiber mode creates the cable node")
	_check(cable != null and cable.visible, "fiber cable is visible at launch")
	_check(anchor_ready, "fiber mode establishes a ground anchor")
	_check(anchor.distance_to(drone.global_position) > 1.0,
			"anchor sits behind the launch pad, not under the airframe (%.2f m)" % \
			anchor.distance_to(drone.global_position))

	var mesh := cable.mesh as ImmediateMesh if cable != null else null
	_check(mesh != null and mesh.get_surface_count() == 2,
			"cable has a glow sheath and a bright core surface")

	var tip: Vector3 = drone.global_position + drone.global_transform.basis.z * 0.34
	var pts: PackedVector3Array = level.call("_fiber_cable_path", anchor, tip)
	_check(pts.size() >= 20, "cable path is subdivided for a smooth curve")
	_check(pts.size() >= 2 and pts[0].distance_to(anchor) < 0.01,
			"cable path starts at the spool")
	_check(pts.size() >= 2 and pts[pts.size() - 1].distance_to(tip) < 0.01,
			"cable path ends at the airframe tail")

	# Lift the airframe and verify the ground spool stays put while the cable
	# follows the tail.
	drone.freeze = true
	var anchor_before := anchor
	drone.global_position += Vector3(24.0, 46.0, -18.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var anchor_after: Vector3 = level.get("_fiber_anchor")
	_check(anchor_after.distance_to(anchor_before) < 0.05,
			"flight does not drag the ground spool with the drone")
	mesh = cable.mesh as ImmediateMesh if cable != null else null
	_check(cable != null and cable.visible, "cable stays visible in flight")
	_check(mesh != null and mesh.get_surface_count() == 2,
			"airborne cable rebuild keeps both ribbon surfaces")
	var airborne_pts: PackedVector3Array = level.call("_fiber_cable_path",
			anchor_after, drone.global_position)
	var max_y := -10000.0
	for p in airborne_pts:
		max_y = maxf(max_y, p.y)
	_check(max_y > anchor_after.y + 20.0,
			"cable geometry spans the full altitude of the airframe")

	Global.menu_settings["fiber_optic_mode"] = false
	await get_tree().process_frame
	await get_tree().process_frame
	_check(cable != null and not cable.visible, "radio mode hides the fiber cable")
	Global.menu_settings["fiber_optic_mode"] = true
	await get_tree().process_frame
	level.call("_reset_fiber_cable")
	_check(cable != null and not cable.visible, "respawn/reset hides the cable")
	_check(not bool(level.get("_fiber_anchor_ready")), "respawn clears the old anchor")

	_finish(level)


func _finish(level: Node) -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
	if _had_fiber:
		Global.menu_settings["fiber_optic_mode"] = _saved_fiber
	else:
		Global.menu_settings.erase("fiber_optic_mode")
	OS.unset_environment("DRONE_NO_RECORD")
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[", TEST_NAME, "] PASS ", label)
	else:
		_failures += 1
		push_error("[%s] FAIL %s" % [TEST_NAME, label])
