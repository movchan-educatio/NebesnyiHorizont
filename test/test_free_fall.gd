extends Node

## QA: cut the throttle from a climb and fall freely.  The airframe must stay
## level and quiet: no PID/motor buzz at idle, no tumble.  This is the regression
## test for the "drone shakes during free fall" report.

var drone: Drone = null
var elapsed := 0.0
var steady_t := 0.0
var steady_ang := 0.0
var steady_tilt := 0.0
var steady_rpm := 0.0


func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	drone = packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 7)
	drone.global_position = Vector3(0.0, 700.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.reset_motion_history()
	drone.freeze = true
	await get_tree().physics_frame
	drone.freeze = false
	drone.flight_controller.reset()
	drone.flight_controller.request_arm(true)


func _physics_process(delta: float) -> void:
	if drone == null or not drone.flight_controller.state_armed:
		return
	elapsed += delta
	if elapsed < 1.6:
		drone.flight_controller.input = [0.70, 0.0, 0.0, 0.0]
	elif elapsed < 8.0:
		drone.flight_controller.input = [0.0, 0.0, 0.0, 0.0]
		if elapsed > 3.5:
			steady_t += delta
			steady_ang = maxf(steady_ang, drone.angular_velocity.length())
			steady_tilt = maxf(steady_tilt,
					rad_to_deg(Vector3.UP.angle_to(drone.global_transform.basis.y)))
			steady_rpm = maxf(steady_rpm, drone.flight_controller.motors[0].rpm)
	else:
		var ok := steady_ang < 0.5 and steady_tilt < 8.0 and steady_rpm < 2000.0
		print("[FREEFALL] ang=%.2f tilt=%.1f rpm=%.0f -> %s" % [
				steady_ang, steady_tilt, steady_rpm, "PASS" if ok else "FAIL"])
		get_tree().quit(0 if ok else 1)
