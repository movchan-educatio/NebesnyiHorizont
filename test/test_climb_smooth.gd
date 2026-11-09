extends Node

## Reproduces the complaint: does a smooth throttle ramp produce a smooth
## vertical climb, or does the airframe oscillate?
func _ready() -> void:
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 0)
	drone.global_position = Vector3(0, 50, 0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.flight_controller.set_armed(true)
	var samples: Array[float] = []
	var t := 0.0
	for f in range(300):
		t += 1.0 / 120.0
		var thr := clampf(t / 1.2, 0.0, 1.0) * 0.70
		drone.flight_controller.input = [thr, 0.0, 0.0, 0.0]
		await get_tree().physics_frame
		samples.append(drone.linear_velocity.y)
	var changes := 0
	var max_step := 0.0
	for i in range(1, samples.size()):
		var dv: float = samples[i] - samples[i - 1]
		max_step = maxf(max_step, absf(dv))
		if i > 1:
			var prev: float = samples[i - 1] - samples[i - 2]
			if dv * prev < 0.0 and absf(dv) > 0.01:
				changes += 1
	print("[CLIMB] v_end=", samples[-1], " min=", samples.min(),
			" max=", samples.max(), " sign_changes=", changes,
			" max_frame_dv=", max_step)
	get_tree().quit(0)
