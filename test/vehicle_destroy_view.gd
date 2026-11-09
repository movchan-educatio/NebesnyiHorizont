extends Node3D

## Visual check of the integrated DestructionFx on the real Vehicle nodes.

const VehicleScript = preload("res://combat/vehicle.gd")
var _tank
var _heli
var _out := ""


func _ready() -> void:
	_out = ProjectSettings.globalize_path("res://qa_shots/audit")
	_env()
	_ground()
	_tank = _spawn(VehicleScript.Kind.TANK, Vector3(-5.0, 0.0, 0.0), 0.0)
	_heli = _spawn(VehicleScript.Kind.HELI, Vector3(12.0, 16.0, 0.0), 16.0)
	await get_tree().create_timer(0.8).timeout
	await _shot("01_idle")
	_tank.take_damage(99999.0, _tank.global_position + Vector3.UP * 1.2)
	_heli.take_damage(99999.0, _heli.global_position + Vector3.UP * 1.2)
	await get_tree().create_timer(0.20).timeout
	await _shot("02_blast")
	await get_tree().create_timer(1.10).timeout
	await _shot("03_burning")
	await get_tree().create_timer(2.20).timeout
	await _shot("04_wreck")
	await get_tree().create_timer(0.30).timeout
	get_tree().quit(0)


func _spawn(kind: int, pos: Vector3, cruise: float):
	var v = VehicleScript.new()
	v.kind = kind
	v.position = pos
	v.cruise_height = cruise
	v.hostile = false
	v.move_speed = 0.0
	add_child(v)
	v.set_waypoints([Vector3(pos.x, 0.0, -30.0), Vector3(pos.x, 0.0, 30.0)])
	return v


func _ground() -> void:
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
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)


func _env() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.16, 0.32, 0.56)
	sm.sky_horizon_color = Color(0.62, 0.70, 0.78)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.5
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(8.0, 7.0, 24.0)
	cam.fov = 52.0
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(5.0, 3.0, 0.0), Vector3.UP)


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/live_vehicle_destroy_%s.png" % [_out, stage]
	print("[LIVEVEH] ", path, " err=", img.save_png(path))
