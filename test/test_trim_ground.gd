extends Node

## QA: the LEVEL/HORIZON pitch-trim integrator must stay at zero while the
## drone is resting on the ground.  Otherwise a drone spawned on a slope would
## wind up a permanent nose-down offset and lurch forward on take-off.
##
## The drone is armed on an 8-degree tilted platform with the sticks centred
## and zero throttle; after 3 s the trim must still be ~0.

var drone: Drone = null
var elapsed := 0.0


func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 7)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 1.0, 40.0)
	col.shape = shape
	body.add_child(col)
	add_child(body)
	body.rotation_degrees = Vector3(8.0, 0.0, 0.0)
	body.position = Vector3(0.0, -0.5, 0.0)

	drone.global_position = Vector3(0.0, 1.5, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.input = [0.0, 0.0, 0.0, 0.0]
	drone.flight_controller.request_arm(true)
	print("[TRIM-GROUND] armed=", drone.flight_controller.state_armed)


func _physics_process(delta: float) -> void:
	if drone == null:
		return
	drone.flight_controller.input = [0.0, 0.0, 0.0, 0.0]
	elapsed += delta
	if elapsed >= 3.0:
		var fc := drone.flight_controller
		var trim: float = fc._level_pitch_trim
		print("[TRIM-GROUND] on_ground=", fc.on_ground,
				" tilt=", snappedf(rad_to_deg(Vector3.UP.angle_to(
						drone.global_transform.basis.y)), 0.1),
				" trim=", snappedf(trim, 0.00001),
				" -> ", "PASS" if absf(trim) < 0.005 else "FAIL windup")
		get_tree().quit()
