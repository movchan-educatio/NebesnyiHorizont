extends Node

## Regression: the CCIP predictor and the physical store must leave the drone
## from the same point with the same velocity.  The old sight used a guessed
## point 1.15 m below the airframe, so every pipper landed short of the real
## impact (most visibly on the Baba Yaga, whose bay is only 0.3 m below).

const Ballistics = preload("res://combat/ballistics.gd")

var _failures := 0


class FakeLevel:
	extends Node
	var ground_y := 0.0

	func _find_ground_y(_x: float, _z: float) -> float:
		return ground_y


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[BOMB_CCIP] PASS ", label)
	else:
		_failures += 1
		print("[BOMB_CCIP] FAIL ", label)


func _run() -> void:
	var drone := RigidBody3D.new()
	drone.gravity_scale = 0.0
	add_child(drone)
	drone.global_position = Vector3(12.0, 90.0, -7.0)
	drone.global_rotation = Vector3(0.08, 0.7, -0.05)
	drone.linear_velocity = Vector3(4.0, 1.5, -8.0)
	var forward := -drone.global_transform.basis.z

	var state := Ballistics.release_state(drone)
	var origin: Vector3 = state.get("origin", Vector3.ZERO)
	var vel: Vector3 = state.get("velocity", Vector3.ZERO)
	var expected_origin := drone.global_position \
			+ Vector3.DOWN * Ballistics.RELEASE_DOWN_OFFSET \
			+ forward * Ballistics.RELEASE_FORWARD_OFFSET
	var expected_vel := drone.linear_velocity \
			+ forward * Ballistics.RELEASE_FORWARD_IMPULSE \
			+ Vector3.DOWN * Ballistics.RELEASE_DOWN_IMPULSE
	_check(origin.is_equal_approx(expected_origin), "shared hardpoint origin")
	_check(vel.is_equal_approx(expected_vel), "shared release velocity")

	# A modelled bomb bay overrides the origin but keeps the same velocity.
	var bay := Vector3(12.0, 89.55, -7.0)
	var bay_state := Ballistics.release_state(drone, bay)
	_check((bay_state.get("origin", Vector3.ZERO) as Vector3).is_equal_approx(bay),
			"bomb-bay override keeps the exact rack origin")
	_check((bay_state.get("velocity", Vector3.ZERO) as Vector3).is_equal_approx(vel),
			"bomb-bay override keeps the shared release velocity")
	var inf_state := Ballistics.release_state(drone, Vector3.INF)
	_check((inf_state.get("origin", Vector3.ZERO) as Vector3).is_equal_approx(origin),
			"Vector3.INF falls back to the shared hardpoint")

	# The sight's 50 ms predictor must match a 120 Hz integration closely
	# enough that the marker is honest at normal drop altitudes.
	var level := FakeLevel.new()
	add_child(level)
	var wind := Vector3(2.5, 0.0, 1.2)
	var sight := Ballistics.simulate(level, "", origin, vel, wind, "82mm", 0.02)
	var fine := _integrate(origin, vel, wind, "82mm", 1.0 / 120.0)
	var err := (sight.get("impact", Vector3.ZERO) as Vector3).distance_to(fine)
	_check(err < 0.35, "sight impact matches 120 Hz flight within 0.35 m (%.3f m)" % err)

	# The sight must consume the shared release state, not a hardcoded offset.
	var sight_src := FileAccess.get_file_as_string("res://combat/bomb_sight.gd")
	_check(sight_src.contains("release_state"), "bomb sight uses the shared release state")
	_check(not sight_src.contains("Vector3.DOWN * 1.15"),
			"old guessed 1.15 m sight origin is gone")
	var level_src := FileAccess.get_file_as_string("res://sceneries/BigLevel.gd")
	_check(level_src.contains("func _bomb_release_state"),
			"level exposes a common bomb release state")
	_check(level_src.contains("_bomb_release_state(drone, _bomb_kind)"),
			"heavy bomber spawns from the common release state")

	print("[BOMB_CCIP] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _integrate(origin: Vector3, initial_velocity: Vector3, wind: Vector3,
		kind: String, dt: float) -> Vector3:
	var pos := origin
	var vel := initial_velocity
	var k := Ballistics.drag_k(kind)
	var age := 0.0
	while pos.y > 0.0 and age < 60.0:
		var rel := vel - wind
		var speed := rel.length()
		vel += (Vector3.DOWN * Ballistics.G - rel * (speed * k)) * dt
		pos += vel * dt
		age += dt
	return Vector3(pos.x, 0.0, pos.z)
