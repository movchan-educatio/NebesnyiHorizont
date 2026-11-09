extends Node

## QA diagnostic: throttle-only climb.  Arm in LEVEL mode, raise only the left
## stick (input[0]) and check whether the drone acquires horizontal velocity or
## pitch/roll.  This isolates CG/mixer drift from radio channel mapping.

var drone: Drone = null
var elapsed := 0.0
var preset := 7


func _ready() -> void:
	if OS.has_environment("DRONE_TEST_PRESET"):
		preset = int(OS.get_environment("DRONE_TEST_PRESET"))
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, preset)
	drone.global_position = Vector3(0.0, 100.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.request_arm(true)
	print("[THROTTLE-TEST] preset=", preset, " name=",
			DroneCatalog.preset(preset)["name"], " mass=", drone.mass,
			" com=", drone.center_of_mass, " mode=", drone.flight_controller.flight_mode)


func _physics_process(delta: float) -> void:
	if drone == null or not drone.flight_controller.state_armed:
		return
	drone.flight_controller.input = [0.55, 0.0, 0.0, 0.0]
	elapsed += delta
	if int(elapsed * 4.0) != int((elapsed - delta) * 4.0):
		var fc := drone.flight_controller
		var tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
		print("[THROTTLE-TEST] t=", snappedf(elapsed, 0.01),
				" pos=", drone.global_position,
				" vel=", drone.linear_velocity,
				" tilt=", snappedf(tilt, 0.1),
				" angles=", fc.angles,
				" input=", fc.input)
	if elapsed >= 4.0:
		var horiz := Vector2(drone.linear_velocity.x, drone.linear_velocity.z).length()
		print("[THROTTLE-TEST] final horizontal_speed=", horiz,
				" vertical=", drone.linear_velocity.y,
				" -> ", "PASS" if horiz < 0.6 else "FAIL forward drift")
		get_tree().quit()
