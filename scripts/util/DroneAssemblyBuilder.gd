## DroneAssemblyBuilder: Shared procedural assembly engine for modular FPV drones.
## Converts database specs and Marker3D mount points into fully interactive 3D drone models.
class_name DroneAssemblyBuilder
extends RefCounted

const PARTS_JSON := "res://Assets/drone_parts/drone_parts_data.json"
const SAVE_PATH := "user://custom_drone_builder.json"

static var _cached_db: Dictionary = {}
static var _cached_parts_by_id: Dictionary = {}


static func _paint_colors(scheme: String) -> Dictionary:
	match scheme:
		"race_orange":
			return {
				"frame": Color("e77b3e"), "motor": Color("a4adb2"),
				"prop": Color("3c4246"), "battery": Color("e0bf4d"),
				"camera": Color("101417"), "payload": Color("bb5534")
			}
		"search_sand":
			return {
				"frame": Color("d5c89b"), "motor": Color("7d888d"),
				"prop": Color("41484b"), "battery": Color("cb5940"),
				"camera": Color("121619"), "payload": Color("71833f")
			}
		_:
			return {
				"frame": Color("829363"), "motor": Color("9aa5a8"),
				"prop": Color("3d4447"), "battery": Color("a1aa62"),
				"camera": Color("161c1f"), "payload": Color("c2a357")
			}


## Loads and caches the drone parts database from JSON.
static func get_parts_db() -> Dictionary:
	if not _cached_db.is_empty():
		return _cached_db
	if not FileAccess.file_exists(PARTS_JSON):
		printerr("[DroneAssemblyBuilder] Database not found: ", PARTS_JSON)
		return {}
	var f := FileAccess.open(PARTS_JSON, FileAccess.READ)
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		_cached_db = json.data
		_cached_parts_by_id.clear()
		for p in _cached_db.get("parts", []):
			var id: String = p.get("id", "")
			_cached_parts_by_id[id] = p
	return _cached_db


static func get_parts_by_id() -> Dictionary:
	if _cached_parts_by_id.is_empty():
		get_parts_db()
	return _cached_parts_by_id


## Converts Blender coordinates [x, y, z] to Godot coordinates Vector3(x, z, -y).
static func to_godot_pos(b: Array) -> Vector3:
	if b.size() < 3:
		return Vector3.ZERO
	return Vector3(float(b[0]), float(b[2]), -float(b[1]))


## Instantiates a 3D PackedScene safely from path.
static func instantiate_mesh(path: String) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


## Assembles a complete 3D Node3D drone model from configuration dictionary.
## config keys: "frame", "motor", "prop", "battery", "camera", "payload".
static func build_drone_node(config: Dictionary) -> Node3D:
	var parts: Dictionary = get_parts_by_id()
	var frame_id: String = str(config.get("frame", "frame_race_5"))
	if not parts.has(frame_id):
		frame_id = "frame_race_5"
	var frame_data: Dictionary = parts.get(frame_id, {})
	var motor_data: Dictionary = parts.get(str(config.get("motor", "motor_2207_highkv")), {})
	var prop_data: Dictionary = parts.get(str(config.get("prop", "prop_5x4x3")), {})
	var batt_data: Dictionary = parts.get(str(config.get("battery", "battery_4s_1500")), {})
	var cam_data: Dictionary = parts.get(str(config.get("camera", "camera_analog")), {})
	var payload_data: Dictionary = parts.get(str(config.get("payload", "payload_empty")), {})
	var paint: Dictionary = _paint_colors(str(config.get("paint_scheme", "field_olive")))

	var root := Node3D.new()
	root.name = "DroneModel"
	root.add_to_group("drone_model")

	# 1. Frame mesh
	var frame_node := instantiate_mesh(frame_data.get("mesh_path", ""))
	if frame_node != null:
		frame_node.name = "FrameMesh"
		_apply_mat(frame_node, paint["frame"], 0.08, 0.48)
		root.add_child(frame_node)

	# 2. Dynamic Marker3D hardpoints
	var mounts: Dictionary = frame_data.get("mounts", {})
	var markers: Dictionary = {}
	for mount_key in mounts.keys():
		var marker := Marker3D.new()
		marker.name = "Marker_" + mount_key.to_pascal_case()
		marker.position = to_godot_pos(mounts[mount_key])
		root.add_child(marker)
		markers[mount_key] = marker

	# 3. 4 Motors & 4 Propellers
	var motor_corners := [
		{"key": "motor_fl", "code": "FL", "ccw": false},
		{"key": "motor_fr", "code": "FR", "ccw": true},
		{"key": "motor_bl", "code": "BL", "ccw": true},
		{"key": "motor_br", "code": "BR", "ccw": false}
	]

	var prop_pivots: Array[Node3D] = []

	for c in motor_corners:
		var marker: Marker3D = markers.get(c["key"], null)
		if marker == null:
			continue

		var motor_pivot := Node3D.new()
		motor_pivot.name = "motor_" + str(c["code"])
		marker.add_child(motor_pivot)

		var motor_mesh := instantiate_mesh(motor_data.get("mesh_path", ""))
		if motor_mesh != null:
			_apply_mat(motor_mesh, paint["motor"], 0.38, 0.30)
			motor_pivot.add_child(motor_mesh)

		var prop_pivot := Node3D.new()
		prop_pivot.name = "propeller_" + str(c["code"])
		prop_pivot.position = Vector3(0.0, 0.020, 0.0)
		motor_pivot.add_child(prop_pivot)

		var prop_mesh := instantiate_mesh(prop_data.get("mesh_path", ""))
		if prop_mesh != null:
			if c["ccw"]:
				prop_mesh.scale.x = -1.0
			_apply_mat(prop_mesh, paint["prop"], 0.04, 0.34)
			prop_pivot.add_child(prop_mesh)

		var spin_dir: float = -1.0 if c["ccw"] else 1.0
		motor_pivot.set_meta("spin_dir", spin_dir)
		motor_pivot.set_meta("spin_axis", Vector3.UP)
		prop_pivots.append(motor_pivot)

	root.set_meta("prop_pivots", prop_pivots)
	root.set_meta("preset_index", 9)

	# 4. Battery
	var batt_marker: Marker3D = markers.get("battery", null)
	if batt_marker != null:
		var batt_mesh := instantiate_mesh(batt_data.get("mesh_path", ""))
		if batt_mesh != null:
			batt_mesh.name = "BatteryMesh"
			_apply_mat(batt_mesh, paint["battery"], 0.03, 0.48)
			batt_marker.add_child(batt_mesh)

	# 5. Camera
	var cam_marker: Marker3D = markers.get("camera", null)
	if cam_marker != null:
		var cam_mesh := instantiate_mesh(cam_data.get("mesh_path", ""))
		if cam_mesh != null:
			cam_mesh.name = "CameraMesh"
			cam_mesh.rotation_degrees.x = 20.0
			_apply_mat(cam_mesh, paint["camera"], 0.18, 0.28)
			cam_marker.add_child(cam_mesh)

	# 6. Payload
	var payload_marker: Marker3D = markers.get("payload", null)
	if payload_marker != null and str(payload_data.get("id")) != "payload_empty":
		var payload_mesh := instantiate_mesh(payload_data.get("mesh_path", ""))
		if payload_mesh != null:
			payload_mesh.name = "PayloadMesh"
			_apply_mat(payload_mesh, paint["payload"], 0.28, 0.43)
			payload_marker.add_child(payload_mesh)

	# Turn off shadow casting on small visual instances for performance & clarity
	for child in root.find_children("*", "GeometryInstance3D"):
		if child is GeometryInstance3D:
			(child as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return root


static func _apply_mat(node: Node3D, col: Color, metallic: float, roughness: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = metallic
	mat.roughness = roughness
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.22
	mat.clearcoat_roughness = 0.28
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat


## Calculates real-time physical telemetry and balance stats.
static func calculate_ttx(config: Dictionary) -> Dictionary:
	var parts: Dictionary = get_parts_by_id()
	var frame: Dictionary = parts.get(str(config.get("frame", "frame_race_5")), {})
	var motor: Dictionary = parts.get(str(config.get("motor", "motor_2207_highkv")), {})
	var prop: Dictionary = parts.get(str(config.get("prop", "prop_5x4x3")), {})
	var battery: Dictionary = parts.get(str(config.get("battery", "battery_4s_1500")), {})
	var camera: Dictionary = parts.get(str(config.get("camera", "camera_analog")), {})
	var payload: Dictionary = parts.get(str(config.get("payload", "payload_empty")), {})

	var dry_g := float(frame.get("weight_g", 70)) + \
			float(motor.get("weight_g", 32)) * 4.0 + \
			float(prop.get("weight_g", 4.2)) * 4.0 + \
			float(camera.get("weight_g", 8.5)) + 35.0
	var batt_g := float(battery.get("weight_g", 180))
	var payload_g := float(payload.get("weight_g", 0))

	var total_mass_g := dry_g + batt_g + payload_g
	var total_mass_kg := total_mass_g / 1000.0

	var total_thrust_g := float(motor.get("thrust_g", 1600)) * 4.0
	var twr := total_thrust_g / maxf(1.0, total_mass_g)
	var hover_throttle := clampf((1.0 / twr) * 100.0, 8.0, 99.0)

	var mah := float(battery.get("capacity_mah", 1500))
	var volts := float(battery.get("voltage_v", 14.8))
	var energy_wh := (mah / 1000.0) * volts * 0.80
	var hover_power_w := total_mass_kg * 165.0
	var flight_time_min := (energy_wh / maxf(10.0, hover_power_w)) * 60.0

	var is_combat := (str(payload.get("id")) != "payload_empty")
	var has_drop := (str(payload.get("id")) == "payload_drop_vog")

	return {
		"dry_mass_g": dry_g,
		"battery_mass_g": batt_g,
		"payload_mass_g": payload_g,
		"total_mass_g": total_mass_g,
		"total_mass_kg": total_mass_kg,
		"total_thrust_g": total_thrust_g,
		"twr": twr,
		"hover_throttle_pct": hover_throttle,
		"flight_time_min": flight_time_min,
		"is_combat": is_combat,
		"has_drop": has_drop,
		"frame": frame,
		"motor": motor,
		"prop": prop,
		"battery": battery,
		"camera": camera,
		"payload": payload
	}
