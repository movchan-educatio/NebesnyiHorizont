extends Node

## Regression: ground vehicles must never remain parked because of a stale
## combat flag or a dead nav segment.  Covers the direct `_retreating` reset and
## the generic displacement watchdog on an empty flat world.

const VehicleScript = preload("res://combat/vehicle.gd")

var _failures := 0
var _vehicle: Vehicle = null


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[VEH_WD] PASS ", label)
	else:
		_failures += 1
		print("[VEH_WD] FAIL ", label)


func _run() -> void:
	_vehicle = VehicleScript.new()
	_vehicle.kind = VehicleScript.Kind.BMP
	_vehicle.hostile = true
	_vehicle.move_speed = 9.0
	add_child(_vehicle)
	_vehicle.global_position = Vector3.ZERO
	_vehicle.set_waypoints([Vector3.ZERO, Vector3(0.0, 0.0, -60.0)])
	_vehicle.set_physics_process(false)

	# A stale retreat flag must be cleared even when the drone is gone/unarmed
	# (this was the permanent freeze path in every mode).
	_vehicle.set("_retreating", true)
	_vehicle.call("_combat_engage", 0.02)
	_check(not bool(_vehicle.get("_retreating")),
			"combat tick clears a stale retreat flag")

	# The watchdog ignores legitimate mobility kills.
	_vehicle.set("_damage_speed_mult", 0.0)
	var recoveries_before := int(_vehicle.get("_watchdog_recoveries"))
	for i in range(200):
		_vehicle.call("_update_movement_watchdog", 0.02, false, false, false)
	_check(int(_vehicle.get("_watchdog_recoveries")) == recoveries_before,
			"mobility-killed unit is left parked without watchdog churn")
	_vehicle.set("_damage_speed_mult", 1.0)

	# Real immobility for >3 s clears the flags and advances the route.
	_vehicle.set("_retreating", true)
	_vehicle.set("_reverse_left", 1.0)
	_vehicle.set("_watchdog_anchor", _vehicle.global_position)
	_vehicle.set("_watchdog_stall", 0.0)
	var wp_before := int(_vehicle.get("_wp_index"))
	for i in range(160):
		_vehicle.call("_update_movement_watchdog", 0.02, false, false, false)
	_check(not bool(_vehicle.get("_retreating")) and float(_vehicle.get("_reverse_left")) == 0.0,
			"watchdog clears stuck retreat/reverse state")
	_check(int(_vehicle.get("_wp_index")) != wp_before or int(_vehicle.get("_watchdog_recoveries")) > 0,
			"watchdog advances the route after a stall")

	# Last-resort placement stays a short crawl.  The old 8/5/3 m placement
	# looked like a teleport on the airport map, so assert the new bound.
	_vehicle.global_position = Vector3.ZERO
	_vehicle.set_waypoints([Vector3.ZERO, Vector3(0.0, 0.0, -60.0)])
	_vehicle.call("_nudge_toward_route")
	var nudge_dist := _vehicle.global_position.distance_to(Vector3.ZERO)
	_check(nudge_dist > 0.5 and nudge_dist <= 2.1,
			"stall placement is a short crawl, never an 8 m teleport (%.2f m)" % nudge_dist)

	# And the normal case still drives: route movement over 1.5 s.
	_vehicle.global_position = Vector3.ZERO
	_vehicle.set_waypoints([Vector3.ZERO, Vector3(0.0, 0.0, -60.0)])
	_vehicle.set_physics_process(true)
	await get_tree().create_timer(1.5).timeout
	_check(_vehicle.global_position.length() > 3.0,
			"vehicle drives normally over a clear route (%.1f m)" % _vehicle.global_position.length())

	# A new route resets watchdog state so a previous stall cannot leak.
	_vehicle.set("_retreating", true)
	_vehicle.set("_watchdog_recoveries", 2)
	_vehicle.set_waypoints([Vector3.ZERO, Vector3(0.0, 0.0, 40.0)])
	_check(not bool(_vehicle.get("_retreating"))
			and int(_vehicle.get("_watchdog_recoveries")) == 0,
			"set_waypoints resets combat and watchdog state")

	print("[VEH_WD] failures=%d" % _failures)
	if is_instance_valid(_vehicle):
		_vehicle.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)
