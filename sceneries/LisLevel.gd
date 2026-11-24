extends "res://sceneries/BigLevel.gd"
## Ліс (lis_forest_freestyle) — повноцінна карта BigLevel: фрістайль + всі місії.
## Географія — авторська сцена з maps/lis_forest_freestyle; усе інше (фізика,
## керування, HUD, місії, техніка, піхота, DVR) успадковується від BigLevel.

const MAP_SCENE := "res://maps/lis_forest_freestyle/lis_freestyle_map.tscn"
const LisWaterMaskScript = preload("res://maps/lis_forest_freestyle/scripts/lis_water_mask.gd")
const DEFAULT_SPAWN := Vector3(-176.0, 9.0, 205.0)

## Маршрут із восьми зон карти (див. Spawn_Z01…Z08 у вихідній сцені).
const COURSE_WAYPOINTS := [
	Vector3(-176, 11, 205), Vector3(-160, 13, 120), Vector3(-48, 12, -45),
	Vector3(195, 42, -118), Vector3(-55, 18, -195), Vector3(-190, 26, -45),
	Vector3(226, 14, 95), Vector3(115, 17, 212),
]

var _map_instance: Node3D = null
var _water_mask: LisWaterMask = null


func _map_path() -> String:
	return MAP_SCENE


func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	MAP_GROUND_SAFE = 286.0
	MAP_FLIGHT_BOUND = 340.0
	MAP_AIR_SAFE = 315.0
	_ground_y = 8.0
	set_meta("disable_procedural_grass", true)
	skip_material_upgrade = true
	super._ready()


func _load_map() -> void:
	super._load_map()
	var fallback_ground := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if fallback_ground != null:
		fallback_ground.visible = false
	var root := get_node_or_null("MapRoot")
	if root != null:
		for c in root.get_children():
			if c is Node3D and c.name == "LisFreestyleMap":
				_map_instance = c
				break
	if _map_instance != null and _map_instance.has_method("_build"):
		_map_instance.call("_build")
	_neutralize_map_extras()
	_water_mask = LisWaterMaskScript.new()
	_water_mask.build(self, _map_instance)


func _neutralize_map_extras() -> void:
	if _map_instance == null:
		return
	for cam in _map_instance.find_children("FPVCamera", "Camera3D", true, false):
		var camera := cam as Camera3D
		camera.current = false
		camera.set_process(false)
	for we in _map_instance.find_children("WorldEnvironment", "WorldEnvironment", true, false):
		(we as WorldEnvironment).environment = null
	for light in _map_instance.find_children("Sun", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).visible = false


func _authored_freestyle_waypoints() -> Array:
	return COURSE_WAYPOINTS


func _find_ground_y(x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return DEFAULT_SPAWN.y
	var ground_root: Node = null
	if _map_instance != null:
		ground_root = _map_instance.get_node_or_null("Terrain")
	if ground_root == null:
		ground_root = get_node_or_null("MapRoot")
	var exclude: Array[RID] = []
	var drone := get_node_or_null("Drone")
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())
	var tree := get_tree()
	if tree != null:
		for grp in ["drone", "combat_target", "enemy_infantry", "enemy_vehicle", "kamikaze_drone"]:
			for n in tree.get_nodes_in_group(grp):
				if n is CollisionObject3D:
					var rid := (n as CollisionObject3D).get_rid()
					if not exclude.has(rid):
						exclude.append(rid)
	for _i in range(16):
		var query := PhysicsRayQueryParameters3D.create(
				Vector3(x, 400.0, z), Vector3(x, -200.0, z))
		query.collision_mask = 1
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return DEFAULT_SPAWN.y
		var collider: Object = hit.get("collider")
		var is_map_hit := ground_root == null
		if ground_root != null and collider is Node:
			var col_node := collider as Node
			is_map_hit = col_node == ground_root or ground_root.is_ancestor_of(col_node)
		if is_map_hit:
			return (hit["position"] as Vector3).y
		if collider is CollisionObject3D:
			var hit_rid := (collider as CollisionObject3D).get_rid()
			if not exclude.has(hit_rid):
				exclude.append(hit_rid)
				continue
		break
	return DEFAULT_SPAWN.y


func _is_ground_spot_clear(x: float, z: float) -> bool:
	if absf(x) > MAP_GROUND_SAFE or absf(z) > MAP_GROUND_SAFE:
		return false
	if _water_mask != null and _water_mask.ready_ok:
		return _water_mask.is_spot_valid(x, z, true)
	return not LisWaterMaskScript.is_wet_point(x, z, _find_ground_y(x, z), true)


func _spawn_is_wet(x: float, z: float, ground: float) -> bool:
	return LisWaterMaskScript.is_wet_point(x, z, ground, false)


func _find_dry_spot(x: float, z: float) -> Vector2:
	if _water_mask != null and _water_mask.ready_ok:
		var dry := _water_mask.nearest_dry_spot(x, z, true, true)
		return Vector2(dry.x, dry.z)
	return super._find_dry_spot(x, z)


func _special_ground_point(x: float, z: float) -> Vector3:
	var px := clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	var pz := clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	if _water_mask != null and _water_mask.ready_ok:
		var dry := _water_mask.nearest_dry_spot(px, pz, true, true)
		return Vector3(dry.x, dry.y + 0.05, dry.z)
	if not _is_ground_spot_clear(px, pz):
		var dry2 := _find_dry_spot(px, pz)
		px = dry2.x
		pz = dry2.y
	return Vector3(px, _find_ground_y(px, pz) + 0.05, pz)


func _sanitize_ground_waypoints(wps: Array, closed_loop: bool = true) -> Array:
	if wps.is_empty():
		return wps
	if _water_mask != null and _water_mask.ready_ok:
		return _water_mask.build_dry_route(wps, true, closed_loop)
	return super._sanitize_ground_waypoints(wps, closed_loop)


func _map_water_level() -> float:
	return LisWaterMaskScript.WATER_LEVEL


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_enforce_dry_ground_units()


func _enforce_dry_ground_units() -> void:
	var tree := get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("vehicle"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var v := n as Node3D
		if bool(v.get("is_destroyed")):
			continue
		var k := int(v.get("kind"))
		if k == Vehicle.Kind.HELI or k == Vehicle.Kind.SHAHED:
			continue
		_keep_unit_on_dry_bank(v, true)
	for n in tree.get_nodes_in_group("enemy_infantry"):
		if not is_instance_valid(n) or not (n is Node3D):
			continue
		var inf := n as Node3D
		if bool(inf.get("is_destroyed")):
			continue
		_keep_unit_on_dry_bank(inf, false)


func _keep_unit_on_dry_bank(unit: Node3D, is_vehicle: bool) -> void:
	var p := unit.global_position
	var buf := LisWaterMaskScript.SHORE_BUFFER_VEH if is_vehicle else LisWaterMaskScript.SHORE_BUFFER_INF
	var look := 3.2 if is_vehicle else 1.6
	var fwd := -unit.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.001:
		fwd = fwd.normalized()
	else:
		fwd = Vector3.FORWARD
	var ahead := p + fwd * look
	var cur_wet := LisWaterMaskScript.is_wet_point(p.x, p.z, p.y, is_vehicle)
	var ahead_near := LisWaterMaskScript.distance_to_water_edge(ahead.x, ahead.z) < buf
	if not cur_wet and not ahead_near:
		return
	var bank := LisWaterMaskScript.bank_side(p.x, p.z)
	var inland_dir := Vector3(float(bank), 0.0, 0.0)
	if cur_wet:
		var rx := LisWaterMaskScript.river_center_x(p.z)
		var hw := LisWaterMaskScript.river_half_width(p.z)
		var target_x := clampf(rx + float(bank) * (hw + buf + 2.5), -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
		var dry := _water_mask.nearest_dry_spot(target_x, p.z, is_vehicle, true) if (_water_mask != null and _water_mask.ready_ok) \
				else Vector3(target_x, _find_ground_y(target_x, p.z), p.z)
		unit.global_position = Vector3(dry.x, dry.y + (0.1 if is_vehicle else 0.0), dry.z)
	var inland_yaw := atan2(-inland_dir.x, -inland_dir.z)
	unit.rotation.y = inland_yaw
	if not is_vehicle:
		unit.set("_patrol_dir", -float(unit.get("_patrol_dir")) if unit.get("_patrol_dir") != null else -1.0)
		unit.set("_strafe_dir", -float(unit.get("_strafe_dir")) if unit.get("_strafe_dir") != null else -1.0)
		if unit.get("_panic_dir") is Vector3:
			unit.set("_panic_dir", inland_dir)
	else:
		var wps = unit.get("_waypoints")
		if wps is Array and not (wps as Array).is_empty():
			var idx := int(unit.get("_wp_index"))
			unit.set("_wp_index", (idx + 1) % (wps as Array).size())


func _find_lis_spawn() -> Vector3:
	if _map_instance != null:
		var points := _map_instance.find_child("SpawnPoints", true, false)
		if points != null:
			var markers := points.get_children()
			if not markers.is_empty():
				var marker := markers[randi() % markers.size()] as Node3D
				if marker != null:
					var p := marker.global_position
					p.y = maxf(p.y, _find_ground_y(p.x, p.z) + 4.0)
					return p
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		return respawn.global_position
	return DEFAULT_SPAWN


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone")
	if d == null:
		return
	var pos := _find_lis_spawn() + Vector3(0.0, 2.0, 0.0)
	var spawn_xform := Transform3D(Basis.IDENTITY, pos)
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_xform
	d.global_transform = spawn_xform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.set("linear_velocity", Vector3.ZERO)
	d.set("angular_velocity", Vector3.ZERO)
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	var fc = d.get("flight_controller")
	if fc != null and fc.has_method("reset"):
		fc.reset()
	d.freeze = true
	var existing_model := d.get_node_or_null("DroneModel")
	if existing_model == null or int(existing_model.get_meta("preset_index", -1)) != Global.drone_preset:
		DroneCatalog.apply_to_drone(d, Global.drone_preset)
	else:
		_sync_fpv_drone_model(false, false, true)
	if fc != null:
		if not fc.armed.is_connected(_on_drone_armed):
			fc.armed.connect(_on_drone_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


func _on_drone_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone")
	if d != null:
		d.freeze = false
		d.set("linear_velocity", Vector3.UP * 0.1)
	if not _mission_started and not _mission_finished:
		_start_mission()
