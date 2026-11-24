class_name BombBallistics
extends RefCounted

## Shared free-fall model for the Baba Yaga bomb sight and the physical
## Payload.  A bomb inherits the drone velocity, is retarded by quadratic drag
## relative to the air mass and drifts with the wind while gravity pulls it
## down.  Keeping the predictor and the rigid body on the same equations means
## the CCIP pipper lands where the bomb actually goes.

const G := 9.81
const FRONTLINE_TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

## Canonical release state shared by the CCIP sight and every physical dropper.
## The store leaves the hardpoint slightly below and ahead of the airframe
## origin so it clears the propellers, with the same small forward/down impulse
## in both the predictor and the spawned rigid body.  Keeping one definition is
## what makes the pipper land on the real impact point.
const RELEASE_DOWN_OFFSET := 0.35
const RELEASE_FORWARD_OFFSET := 0.2
const RELEASE_FORWARD_IMPULSE := 2.0
const RELEASE_DOWN_IMPULSE := 1.0


## Return the exact origin/velocity used when a store leaves `drone`.
## `origin_override` lets an airframe with a modelled rack release from the bay;
## pass `Vector3.INF` (the default) to use the shared hardpoint.
static func release_state(drone: Node3D, origin_override: Variant = null) -> Dictionary:
	if drone == null or not is_instance_valid(drone):
		return {"origin": Vector3.ZERO, "velocity": Vector3.ZERO, "forward": Vector3.FORWARD}
	var forward := -drone.global_transform.basis.z
	var origin := drone.global_position + Vector3.DOWN * RELEASE_DOWN_OFFSET \
			+ forward * RELEASE_FORWARD_OFFSET
	if origin_override is Vector3 and (origin_override as Vector3).is_finite():
		origin = origin_override
	return {
		"origin": origin,
		"velocity": drone.linear_velocity + forward * RELEASE_FORWARD_IMPULSE \
				+ Vector3.DOWN * RELEASE_DOWN_IMPULSE,
		"forward": forward,
	}


static func drag_k(kind: String) -> float:
	match kind:
		"120mm":
			return 0.00055
		"tm62":
			return 0.0018
		"vog":
			return 0.0018
		_:
			return 0.0011


static func mass_for(kind: String) -> float:
	match kind:
		"120mm":
			return 16.0
		"tm62":
			return 10.0
		"vog":
			return 0.8
		_:
			return 3.2


static func damage_for(kind: String) -> float:
	match kind:
		"120mm":
			return 1200.0
		"tm62":
			return 1600.0
		_:
			return 420.0


static func blast_for(kind: String) -> float:
	match kind:
		"120mm":
			return 13.0
		"tm62":
			return 11.0
		_:
			return 8.0


## Pick the closest munition profile for a per-unit payload mass.  Keeps every
## airframe on its own drag/mass curve instead of one global "vog" default.
static func kind_for_mass(mass_kg: float) -> String:
	if mass_kg >= 10.0:
		return "120mm"
	if mass_kg >= 1.4:
		return "82mm"
	return "vog"


static func ground_at(level: Node, map_name: String, x: float, z: float) -> float:
	if level == null:
		return -100.0
	if map_name == "airport" or map_name == "lis_forest_freestyle" or map_name == "oilrig":
		if level.has_method("_find_ground_y"):
			return float(level.call("_find_ground_y", x, z))
		return 0.12 if map_name == "airport" else 0.0
	if not map_name.is_empty():
		return FRONTLINE_TERRAIN.height_at(map_name, x, z)
	if level.has_method("_find_ground_y"):
		return float(level.call("_find_ground_y", x, z))
	return float(level.get("_ground_y")) if level.get("_ground_y") != null else -100.0


## Integrate a bomb released at `origin` with `initial_velocity`.
## Returns impact, time of flight and wind drift.  `dt` is coarse on purpose:
## the sight solves at 20 Hz and extrapolates between solves, so a 0.035 s step
## keeps the predictor affordable on iOS without moving the pipper noticeably.
static func simulate(level: Node, map_name: String, origin: Vector3,
		initial_velocity: Vector3, wind: Vector3, kind: String = "82mm",
		dt: float = 0.05) -> Dictionary:
	var pos := origin
	var vel := initial_velocity
	var k := drag_k(kind)
	var age := 0.0
	var prev_ground := ground_at(level, map_name, origin.x, origin.z)
	var safe_pos := pos
	var safe_vel := vel
	var safe_age := age
	var safe_ground := prev_ground
	var steps_since_sample := 0
	var coarse_allowed := true
	for i in range(700):
		var prev_pos := pos
		var rel := vel - wind
		var speed := rel.length()
		var accel := Vector3.DOWN * G - rel * (speed * k)
		vel += accel * dt
		pos += vel * dt
		age += dt
		steps_since_sample += 1
		if coarse_allowed and pos.y > prev_ground + 8.0 and steps_since_sample < 12:
			if age > 40.0 or pos.y < -60.0:
				break
			continue
		var ground := ground_at(level, map_name, pos.x, pos.z)
		if pos.y <= ground and age > 0.05:
			if steps_since_sample > 1:
				pos = safe_pos
				vel = safe_vel
				age = safe_age
				prev_ground = safe_ground
				steps_since_sample = 0
				coarse_allowed = false
				continue
			var prev_clear := prev_pos.y - prev_ground
			var cur_pen := pos.y - ground
			var frac := clampf(prev_clear / maxf(prev_clear - cur_pen, 0.0001), 0.0, 1.0)
			var hit_x := lerpf(prev_pos.x, pos.x, frac)
			var hit_z := lerpf(prev_pos.z, pos.z, frac)
			var hit_y := ground_at(level, map_name, hit_x, hit_z)
			var hit_tof := age - dt * (1.0 - frac)
			return {
				"impact": Vector3(hit_x, hit_y, hit_z),
				"tof": hit_tof,
				"drift": Vector2(hit_x - origin.x, hit_z - origin.z),
				"wind": wind,
				"kind": kind,
			}
		prev_ground = ground
		safe_pos = pos
		safe_vel = vel
		safe_age = age
		safe_ground = ground
		steps_since_sample = 0
		if age > 40.0 or pos.y < -60.0:
			break
	return {
		"impact": Vector3(pos.x, maxf(pos.y, -60.0), pos.z),
		"tof": age,
		"drift": Vector2(pos.x - origin.x, pos.z - origin.z),
		"wind": wind,
		"kind": kind,
	}


## Apply the same quadratic drag to a live RigidBody3D payload.
static func apply_drag(body: RigidBody3D, wind: Vector3, kind: String) -> void:
	if body == null:
		return
	var rel := body.linear_velocity - wind
	var k := drag_k(kind)
	body.apply_central_force(-rel * (rel.length() * k) * body.mass)
