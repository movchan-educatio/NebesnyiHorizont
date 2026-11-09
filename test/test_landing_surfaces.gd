extends Node

## QA: land on a flat platform and on a 20-degree slope.  The airframe must
## settle on top of the surface, disarm, and not emit the crash signal.

var _level: Node
var _drone: Drone
var _crashed := false


func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	_level = packed.instantiate()
	add_child(_level)
	await get_tree().create_timer(5.0).timeout
	_drone = _level.get_node_or_null("Drone") as Drone
	if _drone == null:
		print("[LANDTEST] FAIL no drone")
		get_tree().quit(1)
		return
	_drone.crashed.connect(func(_r): _crashed = true)
	var flat := _platform(Vector3(0.0, 10.0, 0.0), 0.0)
	var slope := _platform(Vector3(24.0, 10.0, 0.0), deg_to_rad(20.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var flat_ok := await _land_on(flat, 11.0, "flat")
	var slope_ok := await _land_on(slope, 11.0, "slope20")
	print("[LANDTEST] flat=", flat_ok, " slope=", slope_ok,
			" crashed=", _crashed, " -> ",
			"PASS" if (flat_ok and slope_ok and not _crashed) else "FAIL")
	get_tree().quit(0 if (flat_ok and slope_ok and not _crashed) else 1)


func _platform(center: Vector3, tilt: float) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = center
	body.rotation.z = tilt
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 2.0, 8.0)
	cs.shape = box
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8.0, 2.0, 8.0)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.55, 0.3)
	mi.material_override = mat
	body.add_child(mi)
	_level.add_child(body)
	return body


func _land_on(platform: Node3D, top_y: float, label: String) -> bool:
	var center := (platform as Node3D).global_position
	_drone.freeze = false
	_drone.global_position = center + Vector3(0.0, 8.0, 0.0)
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.flight_controller.request_arm(true)
	var settled := false
	for i in range(300):
		await get_tree().physics_frame
		if _drone.freeze and _drone.global_position.y > top_y - 1.0:
			settled = true
			break
	var pos := _drone.global_position
	var ok := settled and not _crashed and absf(pos.y - top_y) < 1.2
	print("[LANDTEST] ", label, " pos=", pos, " vel=", _drone.linear_velocity,
			" frozen=", _drone.freeze, " settled=", settled, " ok=", ok)
	return ok
