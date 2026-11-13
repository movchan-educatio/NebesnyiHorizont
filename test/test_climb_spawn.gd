extends Node

## Takeoff from a launch barrel (same dimensions as TacticalLaunchBarrel):
## checks whether the first metres of the climb oscillate or jitter.
func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.36
	cyl.height = 0.92
	cs.shape = cyl
	cs.position = Vector3(0, 0.46, 0)
	body.add_child(cs)
	add_child(body)
	var packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := packed.instantiate() as Drone
	add_child(drone)
	DroneCatalog.apply_to_drone(drone, 3)
	drone.global_position = Vector3(0, 0.95, 0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze = false
	await get_tree().physics_frame
	drone.flight_controller.set_armed(true)
	drone.freeze = false
	var vy: Array[float] = []
	var wx: Array[float] = []
	var wz: Array[float] = []
	var t := 0.0
	for f in range(300):
		t += 1.0 / 120.0
		drone.flight_controller.input = [clampf(t / 1.5, 0.0, 1.0) * 0.70,
				0.0, 0.0, 0.0]
		await get_tree().physics_frame
		vy.append(drone.linear_velocity.y)
		wx.append(drone.angular_velocity.x)
		wz.append(drone.angular_velocity.z)
	var changes := 0
	for i in range(1, vy.size()):
		if i > 1:
			var dv: float = vy[i] - vy[i - 1]
			var prev: float = vy[i - 1] - vy[i - 2]
			if dv * prev < 0.0 and absf(dv) > 0.01:
				changes += 1
	var max_wx := 0.0
	var max_wz := 0.0
	for i in range(wx.size()):
		max_wx = maxf(max_wx, absf(wx[i]))
		max_wz = maxf(max_wz, absf(wz[i]))
	print("[BARRELCLIMB] y=", drone.global_position.y, " vy_end=", vy[-1],
			" vy_min=", vy.min(), " vy_max=", vy.max(),
			" sign_changes=", changes, " max_wx=", max_wx, " max_wz=", max_wz)
	get_tree().quit(0)
