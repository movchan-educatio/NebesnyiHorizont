extends Node3D

## QA: destroyed ground vehicles must char and settle, destroyed helicopters and
## Shaheds must fall out of the sky, and the damage flash overlay must never be
## left glowing on a wreck.

const VehicleScript = preload("res://combat/vehicle.gd")

var _tank
var _heli
var _fail := 0


func _ready() -> void:
	_make_ground()
	_tank = _spawn(VehicleScript.Kind.TANK, Vector3(0.0, 0.0, 0.0), 0)
	_heli = _spawn(VehicleScript.Kind.HELI, Vector3(24.0, 24.0, 0.0), 24.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tank_y0: float = _tank.global_position.y
	var heli_y0: float = _heli.global_position.y
	print("[VEHDESTR] start tank=", _tank.global_position, " heli=", _heli.global_position)
	_tank.take_damage(99999.0, _tank.global_position + Vector3.UP * 1.2)
	_heli.take_damage(99999.0, _heli.global_position + Vector3.UP * 1.2)
	await get_tree().create_timer(0.05).timeout
	_check("tank destroyed", bool(_tank.is_destroyed), true)
	_check("heli destroyed", bool(_heli.is_destroyed), true)
	_check("tank overlay cleared", _overlay_count(_tank), 0)
	_check("heli overlay cleared", _overlay_count(_heli), 0)
	await get_tree().create_timer(3.6).timeout
	print("[VEHDESTR] after tank=", _tank.global_position, " heli=", _heli.global_position)
	_check("tank settled", _tank.global_position.y <= tank_y0 + 0.2, true)
	_check("heli fell", _heli.global_position.y < heli_y0 - 8.0, true)
	_check("heli on ground", _heli.global_position.y < 2.5, true)
	_check("heli overlay cleared after impact", _overlay_count(_heli), 0)
	if _fail == 0:
		print("[VEHDESTR] PASS")
	else:
		print("[VEHDESTR] FAIL count=", _fail)
	get_tree().quit(0 if _fail == 0 else 1)


func _spawn(kind: int, pos: Vector3, cruise: float):
	var v = VehicleScript.new()
	v.kind = kind
	v.position = pos
	v.cruise_height = cruise
	v.hostile = false
	v.move_speed = 6.0
	add_child(v)
	v.set_waypoints([Vector3(pos.x, 0.0, -40.0), Vector3(pos.x, 0.0, 40.0)])
	return v


func _make_ground() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	cs.shape = box
	body.add_child(cs)
	body.position = Vector3(0.0, -0.5, 0.0)
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.28, 0.20)
	mi.material_override = mat
	add_child(mi)


func _overlay_count(root: Node) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null and mi.material_overlay != null:
			n += 1
	return n


func _check(label: String, got: bool, want: bool) -> void:
	if got == want:
		print("[VEHDESTR] PASS ", label)
	else:
		_fail += 1
		print("[VEHDESTR] FAIL ", label, " got=", got, " want=", want)
