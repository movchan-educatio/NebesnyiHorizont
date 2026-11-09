@tool
extends Area3D
class_name Checkpoint


signal entered
signal exited
signal passed


var bodies := []
var areas_per_body := []

@export var backward := false: set = set_backward
var active := false
var selected := false: set = set_selected
var area_visible := false: set = set_area_visible
var mat := StandardMaterial3D.new()

var drone_raycasts := []


func _ready() -> void:
	mat.albedo_color = Color(0.2, 1.0, 0.3, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0

	var _discard = connect("body_entered", Callable(self, "_on_entered"))
	_discard = connect("body_exited", Callable(self, "_on_exited"))
	
	call_deferred("setup_checkpoint_mesh")


func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	if not drone_raycasts.is_empty():
		var entry_direction := global_transform.basis.z
		if backward:
			entry_direction = -entry_direction
		for drone in drone_raycasts:
			var pos_dot: float = (drone.global_transform.origin -
					global_transform.origin).dot(entry_direction)
			var vel_dot: float = drone.linear_velocity.dot(entry_direction)
			if vel_dot < 0:
				if pos_dot < 0 or backward and pos_dot > 0:
					drone_raycasts.erase(drone)
					if active:
						emit_signal("passed", self)
					else:
						emit_signal("exited")
			else:
				drone_raycasts.erase(drone)


func setup_checkpoint_mesh() -> void:
	for col in get_children():
		if col is CollisionShape3D:
			var m := MeshInstance3D.new()
			m.transform = col.transform
			if col.shape is BoxShape3D:
					m.mesh = BoxMesh.new()
					m.mesh.size = (col.shape as BoxShape3D).extents * 2
			elif col.shape is CylinderShape3D:
					m.mesh = CylinderMesh.new()
					var s := col.shape as CylinderShape3D
					m.mesh.top_radius = s.radius
					m.mesh.bottom_radius = s.radius
					m.mesh.height = s.height
			m.mesh.surface_set_material(0, mat)
			m.visible = false
			add_child(m)
			m.set_owner(self)
	set_area_visible(true)


func set_backward(back: bool) -> void:
	backward = back
	if backward:
		mat.emission = Color(1.0, 0.25, 0.2)
	else:
		mat.emission = Color(0.2, 1.0, 0.3)


func set_active(act: bool) -> void:
	active = act
	set_area_visible(active)


func set_selected(select: bool) -> void:
	selected = select
	if selected:
		mat.emission_energy_multiplier = 4.0
	else:
		mat.emission_energy_multiplier = 2.0


func set_area_visible(vis: bool) -> void:
	for c in get_children():
		if c is MeshInstance3D:
			c.visible = vis


func get_velocity_check(body: Node) -> float:
	var dot_product: float = body.linear_velocity.dot(global_transform.basis * (Vector3.FORWARD))
	return dot_product


func _on_entered(body: Node) -> void:
	if body is Drone:
		var dot_product := get_velocity_check(body)
		if !backward and dot_product > 0.0 or backward and dot_product < 0.0:
			if body in bodies:
				var i := bodies.bsearch(body)
				areas_per_body[i] = areas_per_body[i] + 1
			else:
				bodies.append(body)
				areas_per_body.append(1)
			emit_signal("entered")


func _on_exited(body: Node) -> void:
	if body is Drone and bodies.size() > 0:
		var i := bodies.bsearch(body)
		areas_per_body[i] = areas_per_body[i] - 1
		if areas_per_body[i] == 0:
			areas_per_body.remove_at(i)
			bodies.remove_at(i)
			
			var dot_product := get_velocity_check(body)
			if active and (!backward and dot_product > 0.0 or backward and dot_product < 0.0):
				emit_signal("passed", self)
			else:
				emit_signal("exited")


func _on_drone_raycast_hit(drone: Drone) -> void:
	var dot_product := (drone.global_transform.origin - global_transform.origin).dot(global_transform.basis.z)
	if dot_product > 0 or backward and dot_product < 0:
		if not drone_raycasts.has(drone):
			drone_raycasts.append(drone)
