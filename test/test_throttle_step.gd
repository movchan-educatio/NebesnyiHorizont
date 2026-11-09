extends Node


var drone: Drone = null
var elapsed := 0.0
var throttle := 0.45


func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 0)
	drone.global_position = Vector3(0.0, 100.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.request_arm(true)
	drone.flight_controller.input = [0.45, 0.0, 0.0, 0.0]


func _physics_process(delta: float) -> void:
	if drone == null or not drone.flight_controller.state_armed:
		return
	elapsed += delta
	if elapsed >= 2.0 and elapsed < 3.0:
		throttle = 1.0
	elif elapsed >= 3.0:
		throttle = 0.45
	drone.flight_controller.input = [throttle, 0.0, 0.0, 0.0]
	if int(elapsed * 10.0) != int((elapsed - delta) * 10.0):
		var fc := drone.flight_controller
		print("[STEP-TEST] t=", snappedf(elapsed, 0.01), " thr=", throttle,
			" pos=", drone.global_position,
			" vel=", drone.linear_velocity,
			" ang_vel=", drone.angular_velocity,
			" angles=", fc.angles)
	if elapsed >= 5.0:
		var tilt: float = rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y))
		print("[STEP-TEST] final tilt_deg=", tilt)
		get_tree().quit(0)
