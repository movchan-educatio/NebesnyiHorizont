## DronePropellerSystem: Animates rotating native propellers for every drone preset.
## Every drone uses its authentic, built-in propeller geometry separated at motor hubs.
class_name DronePropellerSystem
extends RefCounted

## Per-airframe propeller profiles.  `tools/blender_drone_parts.py` exports
## twelve unique meshes (`prop_p0..prop_p11`): 2/3/4 blades with different
## chord, pitch, sweep, thickness and hub.  Each preset uses its own mesh,
## scaled to the real `prop_d` and tinted per airframe.  The old stock props
## were one oversized white mesh shared by every drone.
const PROP_TINTS := [
	Color(0.07, 0.09, 0.09), # 0 Golka - black racing props
	Color(0.84, 0.86, 0.83), # 1 PinaPipe - white props
	Color(0.16, 0.18, 0.20), # 2 DJI Avata 2 - graphite
	Color(0.18, 0.25, 0.16), # 3 Pisun VTOL - olive
	Color(0.08, 0.09, 0.08), # 4 Peleng - black
	Color(0.17, 0.18, 0.20), # 5 Grim-7 - gunmetal
	Color(0.17, 0.18, 0.20), # 6 Grim-7M - gunmetal
	Color(0.68, 0.19, 0.02), # 7 Strila-8 - deep orange
	Color(0.08, 0.10, 0.15), # 8 Falcon-X - dark blue
	Color(0.10, 0.48, 0.24), # 9 Quad-5 - green
	Color(0.25, 0.30, 0.32), # 10 Magura - no props
	Color(0.22, 0.24, 0.16), # 11 military - olive
	Color(0.10, 0.12, 0.09), # 12 Baba Yaga - dark olive composite
	Color(0.72, 0.74, 0.72), # 13 Leleka - white composite
	Color(0.42, 0.45, 0.46), # 14 Furia - gray composite
	Color(0.10, 0.11, 0.12), # 15 Chaklun - graphite
]
const MOTOR_TINTS := [
	Color(0.12, 0.14, 0.16),
	Color(0.20, 0.22, 0.24),
	Color(0.20, 0.22, 0.24),
	Color(0.18, 0.22, 0.16),
	Color(0.12, 0.14, 0.14),
	Color(0.14, 0.15, 0.17),
	Color(0.14, 0.15, 0.17),
	Color(0.20, 0.16, 0.12),
	Color(0.12, 0.14, 0.18),
	Color(0.10, 0.18, 0.12),
	Color(0.20, 0.22, 0.24),
	Color(0.16, 0.18, 0.14),
	Color(0.12, 0.14, 0.11),
	Color(0.22, 0.23, 0.24),
	Color(0.20, 0.21, 0.22),
	Color(0.10, 0.11, 0.12),
]
const PARTS_PATH := "res://Assets/Drones/drone_parts.glb"
## Must stay in sync with PROFILES in tools/blender_drone_parts.py.
const PROP_BLADES := [3, 3, 3, 2, 2, 3, 3, 3, 4, 4, 4, 3, 3, 2, 2, 3]

static var _parts_ready := false
static var _props := {}          # preset index -> ArrayMesh
static var _fallback := {}       # blade count -> ArrayMesh
static var _motor_bell: ArrayMesh = null


## Sets up propeller pivots on the given drone model.
## Returns an Array of 4 Node3D pivots [FL, FR, BR, BL].
static func setup_propellers(model: Node3D, preset_index: int, prop_d: float = 5.0,
		blades: int = 3) -> Array[Node3D]:
	if model == null or not is_instance_valid(model):
		return []
	
	# Check if already set up and valid
	if model.has_meta("prop_pivots"):
		var existing = model.get_meta("prop_pivots")
		if existing is Array and existing.size() >= 4:
			var valid := true
			for p in existing:
				if p == null or not is_instance_valid(p):
					valid = false
					break
			if valid:
				var res: Array[Node3D] = []
				for p in existing:
					res.append(p as Node3D)
				return res

	var pivots: Array[Node3D] = []

	# Fixed-wing pusher drones: one native rear propeller authored in Blender.
	# The shaft points along the glTF -Z / Godot Z axis.
	if preset_index == 13 or preset_index == 14:
		var pusher := model.find_child("propeller_rear", true, false) as Node3D
		if pusher != null:
			pusher.set_meta("spin_dir", 1.0)
			pusher.set_meta("spin_axis", Vector3(0.0, 0.0, 1.0))
			pusher.add_to_group("drone_prop_pivot")
			if _parts_available():
				_replace_prop(pusher, preset_index, prop_d, blades, _flat_rotation(pusher))
			pivots.append(pusher)
			if OS.has_environment("PROP_DEBUG"):
				print("[PROP-PUSHER] preset=", preset_index, " node=", pusher.name)
			model.set_meta("prop_pivots", pivots)
			model.set_meta("preset_index", preset_index)
			return pivots
		if OS.has_environment("PROP_DEBUG"):
			print("[PROP-PUSHER] MISSING preset=", preset_index,
					" props=", model.find_children("*prop*", "", true, false))
	# The jet has no propeller; its turbine is static visual geometry.
	if preset_index == 15:
		model.set_meta("prop_pivots", [])
		return []

	# Baba Yaga: six native propellers authored as empties in the GLB.  Keep
	# the detailed carbon blades instead of replacing them with the generic
	# 2/3/4-blade library mesh; the animation only rotates the pivots.
	if preset_index == 12:
		for i in range(6):
			var hex_prop := model.find_child("propeller_%d" % i, true, false) as Node3D
			if hex_prop == null:
				continue
			hex_prop.set_meta("spin_dir", 1.0 if i % 2 == 0 else -1.0)
			hex_prop.set_meta("spin_axis", Vector3.UP)
			hex_prop.add_to_group("drone_prop_pivot")
			if _parts_available():
				_replace_prop(hex_prop, preset_index, prop_d, blades, _flat_rotation(hex_prop))
			pivots.append(hex_prop)
		if pivots.size() == 6:
			model.set_meta("prop_pivots", pivots)
			model.set_meta("preset_index", preset_index)
			if OS.has_environment("PROP_DEBUG"):
				print("[PROP-HEX] Baba Yaga pivots=", pivots.size())
			return pivots
		pivots.clear()

	if preset_index == 10:
		# Preset 10 is USV "MAGURA-X" (Maritime surface drone / boat).
		# It uses waterjet propulsion and has no quadcopter propellers.
		model.set_meta("prop_pivots", [])
		return []
	
	if preset_index != 10:
		# Every aerial preset (including 11, the 8-10" military airframe) has
		# parented motors and propellers:
		# motor_FL -> propeller_FL, motor_FR -> propeller_FR, motor_BR -> propeller_BR, motor_BL -> propeller_BL
		var corners := ["FL", "FR", "BR", "BL"]
		for i in range(corners.size()):
			var c: String = corners[i]
			var motor_node: Node3D = model.find_child("motor_" + c, true, false)
			var prop_node: Node3D = model.find_child("propeller_" + c, true, false)
			if OS.has_environment("PROP_DEBUG"):
				print("[PROP-NODE] ", c, " motor=", motor_node, " prop=", prop_node)
			
			# Pivot target is the motor (parent), which spins both motor bell and propeller child.
			# If motor node is absent, falls back to rotating propeller directly.
			var target_node: Node3D = motor_node if motor_node != null else prop_node
			if target_node != null:
				var dir: float = 1.0 if (i % 2 == 0) else -1.0
				target_node.set_meta("spin_dir", dir)
				# Spin around the pivot's local up axis. For Falcon-X, the pivot
				# itself is tilted to match each nacelle, so this local axis follows
				# the angled motor shaft; other presets stay vertically aligned.
				var axis: Vector3 = Vector3.UP
				target_node.set_meta("spin_axis", axis)
				target_node.add_to_group("drone_prop_pivot")
				pivots.append(target_node)
				
			var spin_rot := Vector3.ZERO
			if prop_node != null:
				spin_rot = _flat_rotation(prop_node)
				if _parts_available():
					_replace_prop(prop_node, preset_index, prop_d, blades, spin_rot)
				else:
					_normalise_prop_size(prop_node, prop_d)
					_apply_prop_tint(prop_node, preset_index)
			if motor_node != null:
				if _parts_available():
					_replace_motor(motor_node, prop_node, preset_index, spin_rot)
				else:
					_apply_motor_tint(motor_node, prop_node, preset_index)

	model.set_meta("prop_pivots", pivots)
	model.set_meta("preset_index", preset_index)
	if OS.has_environment("PROP_DEBUG"):
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var n := String(mi.name).to_lower()
			if n.contains("prop") or n.contains("motor"):
				print("[PROP] ", mi.get_path(), " aabb=", mi.get_aabb().size,
						" scale=", mi.global_transform.basis.get_scale(),
						" mat=", mi.material_override)
	return pivots


## Spins all 4 propellers by delta according to motor RPM.
## If rpms is empty, an idle spin is applied (useful for menus & preview).
static func animate_propellers(model: Node3D, delta: float, rpms: Array = []) -> void:
	if model == null or not is_instance_valid(model):
		return
	var pivots = model.get_meta("prop_pivots", null)
	if pivots == null or not (pivots is Array) or pivots.is_empty():
		var preset_idx: int = int(model.get_meta("preset_index", 0))
		pivots = setup_propellers(model, preset_idx)
	if pivots == null or pivots.is_empty():
		return

	var has_rpms := not rpms.is_empty()
	for i in range(pivots.size()):
		var pivot: Node3D = pivots[i]
		if pivot == null or not is_instance_valid(pivot):
			continue
		var rpm: float = 240.0 # Menu idle spin (4 rev/s - smooth, visible rotation without wagon-wheel aliasing)
		if has_rpms and not rpms.is_empty():
			# The flight model has four physical motors; the six-rotor visual
			# maps them onto its six pivots.
			rpm = float(rpms[i % rpms.size()])
			
		var dir: float = float(pivot.get_meta("spin_dir", 1.0))
		var visual_rpm: float = clampf(rpm, -18000.0, 18000.0)
		var rad_step: float = visual_rpm * (TAU / 60.0) * delta * dir
		var axis: Vector3 = pivot.get_meta("spin_axis", Vector3.UP)
		pivot.rotate_object_local(axis, rad_step)


## Normalises the native propeller diameter to the preset's real prop_d
## (inches -> metres).  The Blender mesh is kept, so the mount and blade shape
## stay authentic; only the scale is corrected.
static func _parts_available() -> bool:
	_ensure_parts()
	return not _props.is_empty()


static func _ensure_parts() -> void:
	if _parts_ready:
		return
	_parts_ready = true
	if not ResourceLoader.exists(PARTS_PATH):
		return
	var packed := load(PARTS_PATH) as PackedScene
	if packed == null:
		return
	var scene := packed.instantiate()
	for index in range(PROP_BLADES.size()):
		var mi := scene.find_child("prop_p%d" % index, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var mesh := _copy_mesh(mi.mesh)
		_props[index] = mesh
		var blade_key: int = PROP_BLADES[index]
		if not _fallback.has(blade_key):
			_fallback[blade_key] = mesh
	var bell := scene.find_child("motor_bell", true, false) as MeshInstance3D
	if bell != null and bell.mesh != null:
		_motor_bell = _copy_mesh(bell.mesh)
	scene.free()


static func _copy_mesh(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	if src == null:
		return out
	for s in range(src.get_surface_count()):
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
	return out


## New prop meshes are authored in Blender at exactly 1.0 m diameter, with the
## blades in the XZ plane and the spin axis on +Y.  The native mount rotation is
## preserved by aligning +Y with the stock prop's flat axis.
static func _flat_rotation(prop_node: Node3D) -> Vector3:
	if prop_node == null or not prop_node.is_inside_tree():
		# Tests and the menu may inspect a model before it is parented; asking
		# for a global transform there spams errors and returns identity anyway.
		return Vector3.ZERO
	var box := AABB()
	var first := true
	for mi in _prop_meshes(prop_node):
		var xf := prop_node.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return Vector3.ZERO
	var dims := [box.size.x, box.size.y, box.size.z]
	var smallest := 0
	for i in range(1, 3):
		if dims[i] < dims[smallest]:
			smallest = i
	match smallest:
		0:
			return Vector3(0.0, 0.0, -PI * 0.5)
		2:
			return Vector3(PI * 0.5, 0.0, 0.0)
		_:
			return Vector3.ZERO


static func _replace_prop(prop_node: Node3D, preset_index: int, prop_d: float,
		blades: int, spin_rot: Vector3) -> void:
	if prop_node.has_meta("new_prop"):
		return
	prop_node.set_meta("new_prop", true)
	var idx := clampi(preset_index, 0, PROP_BLADES.size() - 1)
	var wanted := clampi(blades, 2, 4)
	var mesh: ArrayMesh = null
	# A preset profile is authoritative only when its blade count matches the
	# flight model.  Custom builder airframes fall back to a generic profile.
	if _props.has(idx) and int(PROP_BLADES[idx]) == wanted:
		mesh = _props[idx]
	if mesh == null:
		mesh = _fallback.get(wanted)
	if mesh == null:
		mesh = _props.get(0)
	if mesh == null:
		return
	_strip_meshes(prop_node)
	var mi := MeshInstance3D.new()
	mi.name = "NewPropMesh"
	mi.mesh = mesh
	mi.rotation = spin_rot
	# The models are stylised and read visually larger than a scale drawing;
	# 0.72 keeps the real prop_d class while stopping the blades from swallowing
	# the airframe in the hangar / chase view.
	mi.scale = Vector3.ONE * maxf(prop_d * 0.0254 * 0.72, 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tint: Color = PROP_TINTS[preset_index % PROP_TINTS.size()]
	mi.material_override = _paint(tint, 0.30, 0.18)
	prop_node.add_child(mi)


static func _replace_motor(motor_node: Node3D, prop_node: Node3D,
		preset_index: int, spin_rot: Vector3) -> void:
	if motor_node.has_meta("new_motor") or _motor_bell == null:
		return
	motor_node.set_meta("new_motor", true)
	_strip_meshes_except(motor_node, prop_node)
	var p := DroneCatalog.preset(preset_index)
	var stator_mm := float(int(p.get("motor_size", 2207)) / 100)
	if stator_mm < 5.0:
		stator_mm = 22.0
	var bell_d := stator_mm * 0.001 * 1.30
	var mi := MeshInstance3D.new()
	mi.name = "NewMotorBell"
	mi.mesh = _motor_bell
	mi.rotation = spin_rot
	mi.scale = Vector3.ONE * bell_d
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tint: Color = MOTOR_TINTS[preset_index % MOTOR_TINTS.size()]
	mi.material_override = _paint(tint, 0.42, 0.62)
	motor_node.add_child(mi)


static func _strip_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).mesh = null
	for child in node.get_children():
		_strip_meshes(child)


static func _strip_meshes_except(node: Node, skip: Node) -> void:
	if node == skip:
		return
	if node is MeshInstance3D:
		(node as MeshInstance3D).mesh = null
	for child in node.get_children():
		_strip_meshes_except(child, skip)


static func _paint(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


static func _normalise_prop_size(prop_node: Node3D, prop_d: float) -> void:
	if prop_node == null or prop_node.has_meta("prop_size_normalised"):
		return
	prop_node.set_meta("prop_size_normalised", true)
	var box := AABB()
	var first := true
	for mi in _prop_meshes(prop_node):
		var xf := prop_node.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var dims := [box.size.x, box.size.y, box.size.z]
	dims.sort()
	var diameter: float = dims[2]
	var target: float = prop_d * 0.0254 * 0.72
	if diameter > 0.0001 and target > 0.0001:
		var factor := clampf(target / diameter, 0.10, 3.0)
		prop_node.scale *= factor


static func _prop_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_prop_meshes(child))
	return out


static func _apply_prop_tint(node: Node, preset_index: int) -> void:
	var mat := StandardMaterial3D.new()
	var tint: Color = PROP_TINTS[preset_index % PROP_TINTS.size()]
	mat.albedo_color = tint
	mat.roughness = 0.38
	mat.metallic = 0.05
	_apply_material_recursive(node, mat)
	if OS.has_environment("PROP_DEBUG"):
		for mi in _prop_meshes(node):
			print("[PROP-TINT] ", mi.name, " override=", mi.material_override,
					" surfaces=", mi.mesh.get_surface_count() if mi.mesh != null else -1)


static func _apply_motor_tint(motor: Node, prop: Node, preset_index: int) -> void:
	var mat := StandardMaterial3D.new()
	var tint: Color = MOTOR_TINTS[preset_index % MOTOR_TINTS.size()]
	mat.albedo_color = tint
	mat.roughness = 0.42
	mat.metallic = 0.62
	_apply_material_skip(motor, prop, mat)


static func _apply_material_skip(node: Node, skip: Node, mat: Material) -> void:
	if node == skip:
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			mi.material_override = mat
	for child in node.get_children():
		_apply_material_skip(child, skip, mat)


static func _apply_body_matching_prop_material(node: Node, preset_index: int) -> void:
	if node == null:
		return
	
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.22
	mat.metallic = 0.15
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.4
	mat.clearcoat_roughness = 0.2
	
	match preset_index:
		0: # Golka
			mat.albedo_color = Color(0.20, 0.22, 0.24)
		1: # PinaPipe
			mat.albedo_color = Color(0.22, 0.22, 0.25)
		2: # Avata 2 (sleek dark graphite with crisp specular highlight)
			mat.albedo_color = Color(0.28, 0.30, 0.32)
		3: # Pisun VTOL (tactical olive tint)
			mat.albedo_color = Color(0.22, 0.28, 0.22)
		4: # Peleng
			mat.albedo_color = Color(0.22, 0.24, 0.22)
		5: # Grim-7
			mat.albedo_color = Color(0.20, 0.20, 0.22)
		6: # Grim-7M
			mat.albedo_color = Color(0.20, 0.20, 0.22)
		7: # Strila-8
			mat.albedo_color = Color(0.22, 0.23, 0.25)
		8: # Falcon-X Digital (sleek smoke tint with reflections)
			mat.albedo_color = Color(0.25, 0.27, 0.30)
		9: # Quad-5 Custom
			mat.albedo_color = Color(0.20, 0.22, 0.24)
		_:
			mat.albedo_color = Color(0.22, 0.22, 0.22)

	_apply_material_recursive(node, mat)


static func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			# Force the per-airframe tint.  The native props ship with a white
			# texture; keeping that texture was why every drone had white props.
			mi.material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)



