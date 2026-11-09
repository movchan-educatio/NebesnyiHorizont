class_name BombBallistics
extends RefCounted

## Shared free-fall model for the Baba Yaga bomb sight and the physical
## Payload.  A bomb inherits the drone velocity, is retarded by quadratic drag
## relative to the air mass and drifts with the wind while gravity pulls it
## down.  Keeping the predictor and the rigid body on the same equations means
## the CCIP pipper lands where the bomb actually goes.

const G := 9.81
const FRONTLINE_TERRAIN := preload("res://scripts/util/frontline_terrain.gd")


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
	if not map_name.is_empty():
		return FRONTLINE_TERRAIN.height_at(map_name, x, z)
	if level.has_method("_find_ground_y"):
		return float(level.call("_find_ground_y", x, z))
	return float(level.get("_ground_y")) if level.get("_ground_y") != null else -100.0


## Integrate a bomb released at `origin` with `initial_velocity`.
## Returns impact, time of flight and wind drift.  `dt` is deliberately coarse:
## the sight refreshes at ~8 Hz and this loop is 500 steps maximum.
static func simulate(level: Node, map_name: String, origin: Vector3,
		initial_velocity: Vector3, wind: Vector3, kind: String = "82mm",
		dt: float = 0.05) -> Dictionary:
	var pos := origin
	var vel := initial_velocity
	var k := drag_k(kind)
	var age := 0.0
	for i in range(700):
		var rel := vel - wind
		var speed := rel.length()
		var accel := Vector3.DOWN * G - rel * (speed * k)
		vel += accel * dt
		pos += vel * dt
		age += dt
		var ground := ground_at(level, map_name, pos.x, pos.z)
		if pos.y <= ground and age > 0.05:
			return {
				"impact": Vector3(pos.x, ground, pos.z),
				"tof": age,
				"drift": Vector2(pos.x - origin.x, pos.z - origin.z),
				"wind": wind,
				"kind": kind,
			}
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
