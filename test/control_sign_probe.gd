extends Node3D

## QA probe: determines the actual world-space response of the flight
## controller to positive yaw / roll / pitch inputs.  The HUD draws +yaw to the
## right, +roll to the right and +pitch up; this test tells us whether the
## flight model agrees with those conventions.

var drone: Drone
var fc: FlightController
var _yaw := 0.0
var _roll := 0.0
var _pitch := 0.0


func _ready() -> void:
	var scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = scene.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 0)
	fc = drone.flight_controller
	fc.state_armed = true
	fc.flight_mode = FlightController.FlightMode.RATE
	drone.gravity_scale = 0.0
	drone.linear_damp = 10.0
	drone.angular_damp = 0.0
	drone.global_position = Vector3(0, 60, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await _measure("yaw+1", 1.0, 0.0, 0.0, 0.55)
	await _measure("roll+1", 0.0, 1.0, 0.0, 0.55)
	await _measure("pitch+1", 0.0, 0.0, 1.0, 0.55)
	get_tree().quit()


func _measure(label: String, yaw: float, roll: float, pitch: float, thr: float) -> void:
	# Reset attitude and rates before every run.
	drone.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 60, 0))
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	fc.angles = Vector3.ZERO
	_yaw = yaw
	_roll = roll
	_pitch = pitch
	fc.input = [thr, yaw, roll, pitch]
	await get_tree().create_timer(0.45).timeout
	var b := drone.global_transform.basis
	var local_ang := b.inverse() * drone.angular_velocity
	print("[SIGN] %s -> local_rate=(%.2f,%.2f,%.2f) world=(%.2f,%.2f,%.2f)" % [
		label, local_ang.x, local_ang.y, local_ang.z,
		drone.angular_velocity.x, drone.angular_velocity.y, drone.angular_velocity.z])


func _physics_process(_delta: float) -> void:
	# Keep the test input alive: nothing else drives the controller here.
	if fc != null:
		fc.input = [0.55, _yaw, _roll, _pitch]
