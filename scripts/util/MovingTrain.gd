## MovingTrain: Autonomous freight train controller navigating a closed scenic loop.
## Includes realistic diesel locomotive, open gondolas, closed boxcars,
## headlights, diesel exhaust, solid car collision, and timed station stops.
class_name MovingTrain
extends Node3D

enum State { CRUISE, DECELERATING, STOPPED, ACCELERATING }

const TRACK_LENGTH: float = 972.63
const CRUISE_SPEED: float = 12.0 # ~43 km/h
const STATION_T: float = 0.750 # Station stop position
const BRAKE_DIST_T: float = 0.055 # ~53 meters of smooth braking
const ACCEL_DIST_T: float = 0.045 # ~44 meters of smooth acceleration
const DWELL_TIME: float = 60.0 # Stop for 1 minute at the station

var state: State = State.STOPPED
var t_loco: float = 0.750 # Station stop position
var current_speed: float = 0.0
var dwell_timer: float = 45.0 # Train starts halted at the station platform, then departs
var base_y: float = 0.0

var loco: Node3D = null
var cars: Array[Node3D] = []
var car_t_offsets: Array[float] = [0.0165, 0.0328, 0.0492, 0.0655]


static func track_point(t: float, y_elev: float = 0.0) -> Vector3:
	var u := fmod(fmod(t, 1.0) + 1.0, 1.0)
	var theta := u * TAU
	var x := 165.0 * cos(theta) - 15.0 * sin(2.0 * theta)
	var z := -70.0 + 140.0 * sin(theta) + 18.0 * cos(2.0 * theta)
	return Vector3(x, y_elev, z)


func _ready() -> void:
	set_meta("no_batch", true)
	# Initial placement of train
	_update_train_poses()


func _physics_process(delta: float) -> void:
	match state:
		State.CRUISE:
			current_speed = CRUISE_SPEED
			# Check distance to station
			var dist_to_station := fmod(STATION_T - t_loco + 1.0, 1.0)
			if dist_to_station < BRAKE_DIST_T and dist_to_station > 0.001:
				state = State.DECELERATING
		
		State.DECELERATING:
			var rem := fmod(STATION_T - t_loco + 1.0, 1.0)
			if rem <= 0.002 or rem > BRAKE_DIST_T:
				# Reached station halt
				t_loco = STATION_T
				current_speed = 0.0
				state = State.STOPPED
				dwell_timer = DWELL_TIME
			else:
				var factor := clampf(rem / BRAKE_DIST_T, 0.05, 1.0)
				current_speed = CRUISE_SPEED * smoothstep(0.0, 1.0, factor)
		
		State.STOPPED:
			current_speed = 0.0
			dwell_timer -= delta
			if dwell_timer <= 0.0:
				state = State.ACCELERATING
		
		State.ACCELERATING:
			var traveled := fmod(t_loco - STATION_T + 1.0, 1.0)
			if traveled >= ACCEL_DIST_T and traveled < 0.5:
				current_speed = CRUISE_SPEED
				state = State.CRUISE
			else:
				var factor := clampf(traveled / ACCEL_DIST_T, 0.05, 1.0)
				current_speed = CRUISE_SPEED * smoothstep(0.0, 1.0, factor)

	# Advance along loop
	if current_speed > 0.0001:
		var dt_step := (current_speed * delta) / TRACK_LENGTH
		t_loco = fmod(t_loco + dt_step, 1.0)

	_update_train_poses()


func _update_train_poses() -> void:
	if loco != null and is_instance_valid(loco):
		pose_car(loco, t_loco)
	
	for i in range(cars.size()):
		var car: Node3D = cars[i]
		if car != null and is_instance_valid(car):
			var off: float = car_t_offsets[i] if i < car_t_offsets.size() else 0.0165 * float(i + 1)
			var car_t := fmod(t_loco - off + 1.0, 1.0)
			pose_car(car, car_t)


func pose_car(node: Node3D, t: float) -> void:
	var t_fwd := fmod(fmod(t + 0.004, 1.0) + 1.0, 1.0)
	var t_bwd := fmod(fmod(t - 0.004, 1.0) + 1.0, 1.0)
	var p0 := track_point(t_bwd, base_y)
	var p1 := track_point(t_fwd, base_y)
	var pos := track_point(t, base_y)
	var dir := (p1 - p0).normalized()
	node.global_position = pos + Vector3(0.0, 0.46, 0.0)
	if dir.length_squared() > 0.001:
		node.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
