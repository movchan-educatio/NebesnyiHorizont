extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inst: Node3D = load("res://Assets/vehicles/btr-90_ussr.glb").instantiate()
	root.add_child(inst)
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		inst.rotation_degrees.y = yaw
		await process_frame
		var b := inst.global_transform.basis
		# The BTR's gun points along local -Z. Where does that go after yaw?
		var gun_dir := b * Vector3(0, 0, -1)
		print("[BASIS] yaw=", yaw, " x_axis=", b.x, " z_axis=", b.z,
				" local_-Z_world=", gun_dir)
	var v = load("res://combat/vehicle.gd").new()
	v.kind = 2
	root.add_child(v)
	await process_frame
	var model := v.get_node_or_null("Model") as Node3D
	if model:
		print("[BASIS] vehicle model rot=", model.rotation_degrees,
				" global_basis=", model.global_transform.basis,
				" local_-Z_world=", model.global_transform.basis * Vector3(0, 0, -1))
	quit()
