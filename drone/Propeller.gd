@tool
extends Node3D
class_name Propeller


@onready var cw := $CW
@onready var ccw := $CCW
@onready var prop_disk := $PropBlurDisk

@onready var ray: RayCast3D = null
var max_ray_length := 0.0

@export var diameter := 5.0: set = set_diameter # (float, 0.5, 15)
@export var pitch := 5.0: set = set_pitch # (float, 0.5, 15)
@export var num_blades := 2 # (int, 2, 6)
@export var c_tip := 0.01 # (float, 0.0, 0.1)
@export var cl0 := 0.1 # (float, 0.0, 10.0)
@export var cla := 0.1 # (float, 0.0, 10.0)
@export var cd0 := 0.1 # (float, 0.0, 10.0)
@export var cda := 0.1 # (float, 0.0, 10.0)
@export var cm0 := 0.1 # (float, 0.0, 10.0)
@export var cma := 0.1 # (float, 0.0, 10.0)
@export var disk_delta := 0.2 # (float, 0.0, 10.0)

var clockwise := false: set = set_clockwise
var rpm := 0.0
var use_blur := false
var suppressed := false:
	set(val):
		suppressed = val
		if suppressed:
			if cw != null: cw.visible = false
			if ccw != null: ccw.visible = false
			if prop_disk != null: prop_disk.visible = false
@export var color := Color(1.0, 1.0, 1.0, 1.0): set = set_color
@export var prop_disk_alpha := 1.0: set = set_prop_disk_alpha
@export var prop_disk_emission := 0.0: set = set_prop_disk_emission
@export var prop_disk_falloff := 10: set = set_prop_disk_falloff

var velocity := Vector3.ZERO: set = set_velocity
var forces := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

var radius := 0.0635
var theta_tip := 0.0
var w := 0.0


func update_geometry() -> void:
	radius = diameter * 0.0254 / 2.0
	var raw_deg := 1.25 * pitch / (PI * maxf(diameter, 0.1))
	theta_tip = deg_to_rad(raw_deg)


func set_diameter(d: float) -> void:
	diameter = maxf(d, 0.5)
	update_geometry()


func set_pitch(p: float) -> void:
	pitch = maxf(p, 0.5)
	update_geometry()

# Ground effect parameters
var gnd_radius := 0.0
var gnd_d := 0.0
var gnd_b := 0.0
var gnd_kb := 0.0
@export var ground_effect_max := 1.35

var debug := 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	set_visibility(true)
	prop_disk.visible = false
	
	max_ray_length = diameter * 0.0254 * 2
	ray = get_node_or_null("RayCast3D") as RayCast3D
	if ray == null:
		ray = RayCast3D.new()
		ray.name = "RayCast3D"
		ray.target_position = Vector3(0, -max_ray_length, 0)
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		add_child(ray)
	
	var parent: Node = get_parent()
	while parent != null and not parent is Drone:
		if parent is CollisionObject3D:
			ray.add_exception(parent)
		parent = parent.get_parent()
	if parent is Drone:
		ray.add_exception(parent)
	max_ray_length = minf(diameter * 0.0254 * 2, ray.target_position.length())
	ray.target_position = ray.target_position.normalized() * max_ray_length
	ray.enabled = true
	
	update_geometry()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or suppressed:
		if suppressed:
			if cw != null: cw.visible = false
			if ccw != null: ccw.visible = false
			if prop_disk != null: prop_disk.visible = false
		return
	
	if abs(rpm) > 500:
		if !use_blur:
			use_blur = true
			prop_disk.visible = true
			set_visibility(false)
	else:
		if use_blur:
			use_blur = false
			prop_disk.visible = false
			set_visibility(true)


func set_clockwise(is_cw: bool) -> void:
	clockwise = is_cw
	set_visibility(true)


func set_visibility(show_prop: bool) -> void:
	if suppressed:
		if cw != null: cw.visible = false
		if ccw != null: ccw.visible = false
		if prop_disk != null: prop_disk.visible = false
		return
	if show_prop:
		if cw != null:
			cw.visible = clockwise
		if ccw != null:
			ccw.visible = !clockwise
	else:
		if cw != null:
			cw.visible = false
		if ccw != null:
			ccw.visible = false


func set_color(col: Color) -> void:
	if !is_inside_tree():
		await self.ready
	color = col
	_set_material_parameter(cw.mesh.surface_get_material(0), "propeller_color", color)
	_set_material_parameter(ccw.mesh.surface_get_material(0), "propeller_color", color)
	_set_material_parameter(prop_disk.mesh.surface_get_material(0), "propeller_color", color)


func set_prop_disk_alpha(alpha: float) -> void:
	if !is_inside_tree():
		await self.ready
	prop_disk_alpha = alpha
	_set_material_parameter(prop_disk.mesh.surface_get_material(0), "alpha_boost", prop_disk_alpha)


func set_prop_disk_emission(emission: float) -> void:
	if !is_inside_tree():
		await self.ready
	prop_disk_emission = emission
	_set_material_parameter(prop_disk.mesh.surface_get_material(0), "emission_power", prop_disk_emission)


func set_prop_disk_falloff(falloff: int) -> void:
	if !is_inside_tree():
		await self.ready
	prop_disk_falloff = falloff
	_set_material_parameter(prop_disk.mesh.surface_get_material(0), "emission_falloff", prop_disk_falloff)


func _set_material_parameter(material: Material, parameter: String, value: Variant) -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(parameter, value)
	elif material is StandardMaterial3D:
		var standard := material as StandardMaterial3D
		match parameter:
			"propeller_color":
				standard.albedo_color = value
			"alpha_boost":
				var col := standard.albedo_color
				col.a = value
				standard.albedo_color = col
			"emission_power":
				standard.emission_enabled = true
				standard.emission_energy_multiplier = value
			"emission_falloff":
				pass


func set_velocity(vel: Vector3) -> void:
	velocity = vel


## Static (zero airspeed) thrust of this propeller at the given RPM, computed
## with the same blade-element model as update_forces().  Unlike that method it
## has no side effects and ignores ground effect, which makes it safe to call
## while calibrating the throttle curve.
func static_thrust(at_rpm: float) -> float:
	if at_rpm <= 0.0 or radius <= 0.0 or disk_delta <= 0.0:
		return 0.0
	var w := at_rpm * PI / 30.0
	var sigma := num_blades * c_tip / (PI * radius)
	# v = 0, therefore lambda_c = mu = 0 and most inflow terms disappear.
	var a1 := cla * sigma * (disk_delta - 1.0)
	var a3 := (disk_delta - 1.0) / disk_delta * sigma
	var a4 := -8.0 * cl0 * disk_delta * (1.0 + disk_delta)
	var a5 := cla * (disk_delta - 1.0) * disk_delta * sigma
	var a6 := 8.0 * (2.0 * disk_delta)
	var lambda := (a1 + sqrt(maxf(a3 * (a4 + cla * (a5 - a6)), 0.0))) / 8.0
	var b2 := cl0 * disk_delta * (1.0 + disk_delta)
	var b3 := 2.0 * cla * disk_delta * (lambda - theta_tip)
	var cft := sigma / (2.0 * disk_delta) * (1.0 - disk_delta) * (b2 - b3)
	return 0.5 * 1.225 * PI * radius * radius * w * w * radius * radius * cft


func update_forces() -> void:
	# Forces computed according to paper from ETH Zurich: Rajan Gill and Raffaello D'Andrea
	# Computationally Efficient Force and Moment Models for Propellers in UAV Forward Flight Applications
	var rho := 1.225
	w = rpm * PI / 30.0
	var v := -velocity
	var v_len := v.length()
	var beta := acos(-v.normalized().dot(Vector3.UP))
	var lambda_c := 0.0
	var mu := 0.0
	if w != 0.0:
		lambda_c = v_len * cos(beta) / (w * radius)
		mu = v_len * sin(beta) / (w * radius)
	var sigma := num_blades * c_tip / (PI * radius)
	
	# Induced inflow
	var a1 := -4 * lambda_c + cla * sigma * (disk_delta - 1)
	var a2 := 16 * lambda_c * lambda_c + 8 * cla * (disk_delta - 1) * lambda_c * sigma
	var a3 := (disk_delta - 1) / disk_delta * sigma
	var a4 := -8 * cl0 * disk_delta * (1 + disk_delta)
	var a5 := cla * (disk_delta - 1) * disk_delta * sigma
	var a6 := 8 * (2 * disk_delta + mu * mu * theta_tip)
	var a7 := 8 * cl0 * mu * mu * sigma * log(disk_delta)
	var lambda_i := (a1 + sqrt(a2 + a3 * (a4 + cla * (a5 - a6)) - a7)) / 8.0
	
	var lambda := lambda_c + lambda_i
	
	# Thrust
	a1 = sigma / (2 * disk_delta)
	a2 = cl0 * disk_delta * (1 + disk_delta)
	a3 = 2 * cla * disk_delta * (lambda - theta_tip)
	a4 = cla * mu * mu * theta_tip
	a5 = cl0 * disk_delta * mu * mu * log(disk_delta)
	var cft := a1 * ((1 - disk_delta) * (a2 - a3 + a4) - a5)
	var thrust := 0.5 * rho * PI * radius * radius * w * w * radius * radius * cft
	
	# Drag
	a1 = mu * sigma / (2 * disk_delta)
	a2 = 2 * cd0 * disk_delta
	a3 = (cla - 2 * cda) * lambda
	a4 = 2 * cda * theta_tip
	a5 = cl0 * disk_delta * lambda * log(disk_delta)
	var cfh := a1 * ((1 - disk_delta) * (a2 + theta_tip * (a3 + a4)) - a5)
	var drag := 0.5 * rho * PI * radius * radius * w * w * radius * radius * cfh
	
	# Torque
	a1 = (1 - disk_delta) * sigma / 6.0
	a2 = 2 * cd0 * (1 + disk_delta + disk_delta * disk_delta)
	a3 = 3 * cl0 * (disk_delta + 1) * lambda
	a4 = 6 * (cda * (lambda - theta_tip) - cla * lambda) * (lambda - theta_tip)
	a5 = (3 * mu * mu * (cd0 * disk_delta + cda * theta_tip * theta_tip)) / disk_delta
	var cmq := a1 * (a2 + a3 + a4 + a5)
	var torque := 0.5 * rho * PI * radius * radius * w * w * radius * radius * radius * cmq
	
	# Rolling moment
	a1 = (1 - disk_delta) * sigma * mu / 2.0
	a2 = cl0 * (disk_delta + 1)
	a3 = cla * (lambda - 2 * theta_tip)
	var cmr := a1 * (a2 - a3)
	var roll_moment := 0.5 * rho * PI * radius * radius * w * w * radius * radius * radius * cmr
	
	# Pitching moment
	a1 = c_tip / (2 * disk_delta * radius) * sigma * mu
	a2 = cma * (disk_delta - 1) * (lambda - 2 * theta_tip)
	a3 = 2 * cm0 * disk_delta * log(disk_delta)
	var cmp := a1 * (a2 - a3)
	var pitch_moment := 0.5 * rho * PI * radius * radius * w * w * radius * radius * radius * cmp
	
	# Vector form
	var direction := 1
	if clockwise:
		direction = -1
	var drag_direction := Vector3(v.x, 0.0, v.z).normalized()
	if debug > 0:
		debug += 1
		if debug >= 10:
			debug = 1
			if name == "Propeller1":
				print("beta: %5.3f, lamb_c: %5.3f, mu: %5.3f, lamb_i: %5.3f"
						% [beta, lambda_c, mu, lambda_i])
				print("T: %5.3f, D: %5.3f, Q: %5.3f, R: %5.3f, P: %5.3f"
						% [thrust, drag, torque, roll_moment, pitch_moment])
	var thrust_vec := thrust * Vector3.UP
	var drag_vec := drag * drag_direction
	var torque_vec := torque * Vector3.UP * direction
	var roll_moment_vec := roll_moment * drag_direction * direction
	var pitch_moment_vec := pitch_moment * Vector3.UP.cross(drag_direction)
	
	thrust_vec = thrust_vec * get_ground_effect()
	
	forces = [thrust_vec, drag_vec, torque_vec, roll_moment_vec, pitch_moment_vec]


func set_ground_effect_parameters(rad: float, d: float, b: float, kb: float) ->  void:
	gnd_radius = rad
	gnd_d = d
	gnd_b = b
	gnd_kb = kb


## Ground-effect thrust multiplier for a given rotor height above the surface.
## The old code forced a full ×2 boost whenever the ray hit within two rotor
## radii, which made quads hop off the grass and destroyed hover feel.  Real
## multirotors see roughly +10..35% near the ground; the analytical curve is
## capped at ground_effect_max instead of doubling thrust.
func ground_effect_for_height(height: float) -> float:
	if gnd_radius <= 0.0 or height <= 0.0:
		return 1.0
	var z := maxf(height, 0.005)
	var b_square := gnd_b * gnd_b
	var d_square := gnd_d * gnd_d
	var r_square := gnd_radius * gnd_radius
	var z_square := z * z
	var b1 := gnd_radius / (4.0 * z)
	var a1 := b1 * b1
	var b2 := d_square + 4.0 * z_square
	var a2 := r_square * z / sqrt(b2 * b2 * b2)
	var b3 := 2.0 * d_square + 4.0 * z_square
	var a3 := 0.5 * r_square * z / sqrt(b3 * b3 * b3)
	var b4 := b_square + 4.0 * z_square
	var a4 := 2.0 * r_square * z / sqrt(b4 * b4 * b4) * gnd_kb
	var denominator := 1.0 - a1 - a2 - a3 - a4
	if denominator <= 0.05:
		return ground_effect_max
	return clampf(1.0 / denominator, 1.0, ground_effect_max)


func get_ground_effect() -> float:
	if ray == null or not ray.is_colliding():
		return 1.0
	var height := absf(ray.get_collision_point().y - global_position.y)
	return ground_effect_for_height(height)
