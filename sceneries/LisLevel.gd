extends "res://sceneries/BigLevel.gd"
## Ліс (lis_forest_freestyle) — повноцінна карта BigLevel: фрістайль + всі місії.
## Географія — авторська сцена з maps/lis_forest_freestyle; усе інше (фізика,
## керування, HUD, місії, техніка, піхота, DVR) успадковується від BigLevel.

const MAP_SCENE := "res://maps/lis_forest_freestyle/lis_freestyle_map.tscn"
const LisWaterMaskScript = preload("res://maps/lis_forest_freestyle/scripts/lis_water_mask.gd")
const LisRingsScript = preload("res://maps/lis_forest_freestyle/scripts/lis_freestyle_rings.gd")
const DEFAULT_SPAWN := Vector3(-176.0, 9.0, 205.0)

## Маршрут із восьми зон карти (див. Spawn_Z01…Z08 у вихідній сцені).
const COURSE_WAYPOINTS := [
	Vector3(-176, 11, 205), Vector3(-160, 13, 120), Vector3(-48, 12, -45),
	Vector3(195, 42, -118), Vector3(-55, 18, -195), Vector3(-190, 26, -45),
	Vector3(226, 14, 95), Vector3(115, 17, 212),
]

var _map_instance: Node3D = null
var _water_mask: LisWaterMask = null
var _dry_ground_accum := 0.0
var _guard_probe_ms := 0
var _guard_probe_xz := Vector2(1.0e20, 1.0e20)
var _guard_probe_y := 0.0


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


func _tune_map_environment() -> void:
	super._tune_map_environment()
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.volumetric_fog_enabled = false
		env.volumetric_fog_density = 0.0
		env.fog_height_density = 0.0
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		env.glow_enabled = false
		if _weather != 3:
			env.fog_enabled = true
			env.fog_density = 0.00055
			env.fog_aerial_perspective = 0.32
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_volumetric_fog_energy = 0.0


func _authored_freestyle_waypoints() -> Array:
	if _map_instance != null:
		var gates := _map_instance.get_node_or_null("FPVGates")
		if gates != null and gates.get_child_count() > 0:
			var out: Array = []
			for ch in gates.get_children():
				if ch is Marker3D:
					out.append((ch as Marker3D).global_position)
			if not out.is_empty():
				return out
	return COURSE_WAYPOINTS


func _spawn_training_rings() -> void:
	_rings_total = 0
	for old_ring in _training_rings:
		if is_instance_valid(old_ring):
			old_ring.queue_free()
	_training_rings.clear()
	_training_ring_positions.clear()
	_freestyle_ring_specs.clear()
	if _next_ring_preview != null and is_instance_valid(_next_ring_preview):
		_next_ring_preview.queue_free()
	_next_ring_preview = null
	if _next_turn_arrow != null and is_instance_valid(_next_turn_arrow):
		_next_turn_arrow.queue_free()
	_next_turn_arrow = null
	_ring_clean_streak = 0
	if Global.play_mode != Global.PlayMode.TRAINING or Global.combat_training:
		return
	if _triggers == null or _map_instance == null:
		return
	var gates_node := _map_instance.get_node_or_null("FPVGates")
	if gates_node == null or gates_node.get_child_count() == 0:
		gates_node = LisRingsScript.build_markers(_map_instance, Callable(self, "_find_ground_y"))
	if gates_node == null:
		return
	var ring_mesh: ArrayMesh = LisRingsScript.get_ring_mesh(_map_instance)
	var markers: Array[Marker3D] = []
	for ch in gates_node.get_children():
		if ch is Marker3D:
			markers.append(ch as Marker3D)
	var total := markers.size()
	for i in range(total):
		var marker := markers[i]
		var radius := float(marker.get_meta("radius", 4.6))
		var style := String(marker.get_meta("style", "vertical"))
		var base_col := Color(0.08, 0.72, 0.58)
		if style == "dive" or style == "under_bridge" or style == "over_trestle":
			base_col = Color(0.86, 0.48, 0.12)
		elif i == 0:
			base_col = Color(0.14, 0.84, 0.44)
		elif i == total - 1:
			base_col = Color(0.92, 0.68, 0.16)

		var gate := Area3D.new()
		gate.name = "LisGate%02d" % (i + 1)
		_triggers.add_child(gate)
		gate.global_transform = Transform3D(marker.global_transform.basis.orthonormalized(), marker.global_position)

		var col_shape := CollisionShape3D.new()
		col_shape.name = "CoreTrigger"
		var sphere := SphereShape3D.new()
		sphere.radius = maxf(2.4, radius * 0.92)
		col_shape.shape = sphere
		gate.add_child(col_shape)

		var frame_mat := StandardMaterial3D.new()
		frame_mat.albedo_color = base_col
		frame_mat.metallic = 0.25
		frame_mat.roughness = 0.38
		frame_mat.emission_enabled = true
		frame_mat.emission = base_col
		frame_mat.emission_energy_multiplier = 1.0
		frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

		if ring_mesh != null:
			var mi := MeshInstance3D.new()
			mi.name = "RingMesh"
			mi.mesh = ring_mesh
			mi.scale = Vector3.ONE * radius
			mi.material_override = frame_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gate.add_child(mi)

		var lbl := Label3D.new()
		lbl.name = "GateNumber"
		if i == 0:
			lbl.text = "START 1/%d" % total
		elif i == total - 1:
			lbl.text = "FINISH %d/%d" % [total, total]
		else:
			lbl.text = "%d/%d" % [i + 1, total]
		lbl.font_size = 64
		lbl.pixel_size = 0.022
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = false
		lbl.modulate = Color(1.0, 0.97, 0.84, 0.96)
		lbl.outline_modulate = Color(0.02, 0.04, 0.06, 0.92)
		lbl.outline_size = 10
		lbl.position = Vector3(0.0, radius + 0.9, 0.0)
		gate.add_child(lbl)

		gate.set_meta("training_ring_index", i)
		gate.set_meta("ring_radius", radius)
		gate.set_meta("ring_frame_mat", frame_mat)
		gate.set_meta("ring_base_color", base_col)
		gate.visible = true
		gate.monitoring = (i == 0)
		gate.body_entered.connect(_on_ring_entered.bind(gate))
		_training_rings.append(gate)
		_training_ring_positions.append(marker.global_position)
		_freestyle_ring_specs.append({
			"pos": marker.global_position,
			"dir": -marker.global_transform.basis.z.normalized(),
			"size": radius,
			"shape": 0,
			"color": base_col,
		})
		_rings_total += 1
	_ensure_next_ring_preview()
	_sync_active_training_ring(false)
	call_deferred("_refresh_route_after_physics")
	print("[LisLevel] spawned %d authored kit_ring_gate checkpoints" % _rings_total)


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
	# Unit banking checks do not need physics-rate cadence: 4 Hz keeps the
	# whole vehicle/infantry group scan + water probes off the frame budget.
	_dry_ground_accum += delta
	if _dry_ground_accum >= 0.25:
		_dry_ground_accum = 0.0
		_enforce_dry_ground_units()
	_guard_drone_above_terrain()


func _guard_drone_above_terrain() -> void:
	var drone := get_node_or_null("Drone") as RigidBody3D
	if drone == null or not is_instance_valid(drone) or drone.freeze:
		return
	var p := drone.global_position
	if absf(p.x) > MAP_FLIGHT_BOUND or absf(p.z) > MAP_FLIGHT_BOUND:
		return
	# Reuse the last ground probe: one full-world raycast per 3 m of travel or
	# 0.5 s instead of one every physics frame.
	var now := Time.get_ticks_msec()
	var xz := Vector2(p.x, p.z)
	if now - _guard_probe_ms >= 500 or _guard_probe_xz.distance_squared_to(xz) > 9.0:
		_guard_probe_ms = now
		_guard_probe_xz = xz
		_guard_probe_y = _find_ground_y(p.x, p.z)
	var gy := _guard_probe_y
	if p.y < gy - 1.2:
		drone.global_position = Vector3(p.x, gy + 1.2, p.z)
		var lv := drone.linear_velocity
		if lv.y < 0.0:
			drone.linear_velocity = Vector3(lv.x, 0.0, lv.z)


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
		if (wps is Array or wps is PackedVector3Array) and wps.size() > 0:
			var idx := int(unit.get("_wp_index"))
			unit.set("_wp_index", (idx + 1) % wps.size())


func _find_lis_spawn() -> Dictionary:
	var raw_xz := Vector2(-176.0, 205.0)
	var yaw := 0.0
	if Global.play_mode == Global.PlayMode.TUTORIAL or (Global.play_mode == Global.PlayMode.TRAINING and Global.combat_training):
		# Open dry flat 190m west strip along -Z (z=240 -> z=50), well clear of structures & river.
		raw_xz = Vector2(-255.0, 240.0)
		yaw = 0.0
	elif Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission in [2, 11]:
		# Launch right behind Convoy A on the west ridge so the drone starts inside the escort leash.
		raw_xz = Vector2(-218.0, -232.0)
		yaw = PI
	elif Global.play_mode == Global.PlayMode.TRAINING:
		raw_xz = Vector2(-176.0, 205.0)
		yaw = deg_to_rad(14.0)
	else:
		# Combat / Special ops: dry Basecamp apron facing northeast toward the valley.
		raw_xz = Vector2(-176.0, 205.0)
		yaw = deg_to_rad(-28.0)

	if _water_mask != null and _water_mask.ready_ok:
		var dry := _water_mask.nearest_dry_spot(raw_xz.x, raw_xz.y, false, true)
		raw_xz = Vector2(dry.x, dry.z)
	var resolved := _resolve_spawn_position(raw_xz)
	var pos2: Vector2 = resolved["pos"]
	var gy := float(resolved["ground"])
	if LisWaterMaskScript.is_wet_point(pos2.x, pos2.y, gy, false) and _water_mask != null and _water_mask.ready_ok:
		var fallback := _water_mask.nearest_dry_spot(pos2.x, pos2.y, false, true)
		pos2 = Vector2(fallback.x, fallback.z)
		gy = fallback.y
	return {"xz": pos2, "ground": gy, "yaw": yaw}


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var sp := _find_lis_spawn()
	var pos2: Vector2 = sp["xz"]
	var gy := float(sp["ground"])
	var yaw := float(sp["yaw"])
	_ground_y = gy
	var barrel_top := _setup_launch_barrel(Vector3(pos2.x, gy, pos2.y))
	var spawn_y := maxf(gy + SPAWN_SAFE_OFFSET, gy + barrel_top + 0.03)
	var pos := Vector3(pos2.x, spawn_y, pos2.y)
	var spawn_basis := Basis(Vector3.UP, yaw)
	var spawn_xform := Transform3D(spawn_basis, pos)
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_xform
	_add_spawn_pad(pos2, gy)
	d.global_transform = spawn_xform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
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


func _on_drone_armed(mode: int) -> void:
	super._on_drone_armed(mode)


# ---------------------------------------------------------------------------
#  Freestyle / Combat / Special Mission overrides tuned for 600x600m Forest
# ---------------------------------------------------------------------------
func _spawn_vehicles() -> void:
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	var west_loop := [
		Vector3(-225.0, 0.0, -145.0), Vector3(-135.0, 0.0, -145.0),
		Vector3(-135.0, 0.0, 75.0), Vector3(-225.0, 0.0, 75.0),
	]
	var east_loop := [
		Vector3(135.0, 0.0, -110.0), Vector3(225.0, 0.0, -110.0),
		Vector3(225.0, 0.0, 115.0), Vector3(135.0, 0.0, 115.0),
	]
	_add_vehicle(Vehicle.Kind.TRUCK, west_loop, 8.5, false, false, 0.0, false)
	_add_vehicle(Vehicle.Kind.APC, east_loop, 9.2, false, false, 0.0, false)
	if not lowspec:
		_add_vehicle(Vehicle.Kind.TANK, [
			Vector3(-215.0, 0.0, -40.0), Vector3(-140.0, 0.0, -40.0),
			Vector3(-140.0, 0.0, 45.0), Vector3(-215.0, 0.0, 45.0),
		], 6.5, false, false, 0.0, false)
		_add_vehicle(Vehicle.Kind.HELI,
			_loop_waypoints(0.0, 0.0, 165.0, 8, 0.4), 12.0, false, false, 68.0, false)


func _spawn_combat_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	randomize()
	_offset_targets = false
	_mission_offset = Vector3(randf_range(-14.0, 14.0), 0.0, randf_range(-14.0, 14.0))

	match mission_id:
		1:
			var centers := [
				Vector3(-180.0, 0.0, -75.0),
				Vector3(172.0, 0.0, 80.0),
				Vector3(-150.0, 0.0, 75.0),
			]
			var base_center := (centers[randi() % centers.size()] as Vector3) + _mission_offset
			var dry_bc := _find_dry_spot(base_center.x, base_center.z)
			base_center = Vector3(dry_bc.x, 0.0, dry_bc.y)
			var sp_xz := _player_spawn_xz()
			if Vector2(base_center.x, base_center.z).distance_to(sp_xz) < 95.0:
				var safe_bc := _ensure_enemy_xz_clearance(
					Vector2(base_center.x, base_center.z), 98.0, MAP_GROUND_SAFE - 18.0, false)
				base_center = Vector3(safe_bc.x, 0.0, safe_bc.y)
			var inf_count := 6
			if Global.difficulty == Global.Difficulty.RECRUIT:
				inf_count = 4
			elif Global.difficulty == Global.Difficulty.ACE:
				inf_count = 8
			for i in range(inf_count):
				var angle := (float(i) / float(inf_count)) * TAU + randf_range(-0.2, 0.2)
				var dist := randf_range(12.0, 24.0)
				var raw_p := base_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
				var dry_i := _find_dry_spot(raw_p.x, raw_p.z)
				var pos := Vector3(dry_i.x, 0.0, dry_i.y)
				var patrol_ang := randf() * TAU
				var axis := Vector3(cos(patrol_ang), 0.0, sin(patrol_ang))
				var inf_var := "spetsnaz" if (Global.difficulty == Global.Difficulty.ACE and i >= 6) else ""
				_add_mission_infantry(pos, axis, randf_range(8.0, 12.0), randf_range(1.05, 1.35), true, inf_var)

		2:
			var tank_box := [
				Vector3(-220.0, 0.0, -85.0) + _mission_offset,
				Vector3(-135.0, 0.0, -85.0) + _mission_offset,
				Vector3(-135.0, 0.0, 75.0) + _mission_offset,
				Vector3(-220.0, 0.0, 75.0) + _mission_offset,
			]
			var apc_box := [
				Vector3(135.0, 0.0, -80.0) + _mission_offset,
				Vector3(220.0, 0.0, -80.0) + _mission_offset,
				Vector3(220.0, 0.0, 95.0) + _mission_offset,
				Vector3(135.0, 0.0, 95.0) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.TANK, tank_box, randf_range(5.4, 6.4), true, true)
			_mission_targets_total += 1
			_add_vehicle(Vehicle.Kind.APC, apc_box, randf_range(9.8, 11.2), true, true)
			_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var bmp_box := [
					Vector3(145.0, 0.0, -175.0) + _mission_offset,
					Vector3(225.0, 0.0, -175.0) + _mission_offset,
					Vector3(225.0, 0.0, -70.0) + _mission_offset,
					Vector3(145.0, 0.0, -70.0) + _mission_offset,
				]
				_add_vehicle(Vehicle.Kind.BMP, bmp_box, 8.8, true, true)
				_mission_targets_total += 1
			_add_mission_infantry(Vector3(-168.0, 0.0, 20.0), Vector3(1.0, 0.0, 0.0), 12.0, 1.7, false)
			if Global.difficulty != Global.Difficulty.RECRUIT:
				_add_mission_infantry(Vector3(168.0, 0.0, 25.0), Vector3(-1.0, 0.0, 0.0), 12.0, 1.7, false)
			_add_aa_gun(Vector3(-145.0, 0.0, -55.0), false)

		3:
			var heli_pts := _loop_waypoints(0.0, -10.0, 130.0, 8, 0.25)
			_add_vehicle(Vehicle.Kind.HELI, heli_pts, randf_range(11.5, 13.5), true, true, randf_range(56.0, 68.0))
			_mission_targets_total += 1
			var sam_box := [
				Vector3(140.0, 0.0, -55.0) + _mission_offset,
				Vector3(215.0, 0.0, -55.0) + _mission_offset,
				Vector3(215.0, 0.0, 75.0) + _mission_offset,
				Vector3(140.0, 0.0, 75.0) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SAM, sam_box, 4.4, true, true)
			_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var m3_bmp := [
					Vector3(-215.0, 0.0, -65.0) + _mission_offset,
					Vector3(-135.0, 0.0, 55.0) + _mission_offset,
				]
				_add_vehicle(Vehicle.Kind.BMP, m3_bmp, 8.6, true, true)
				_mission_targets_total += 1
			_add_aa_gun(Vector3(-175.0, 0.0, 45.0), false)
			_add_aa_gun(Vector3(172.0, 0.0, -75.0), false)

		4:
			var p_pts1 := [
				Vector3(-225.0, 0.0, -175.0), Vector3(215.0, 0.0, -120.0),
				Vector3(205.0, 0.0, 165.0), Vector3(-210.0, 0.0, 100.0),
			]
			var p_pts2 := [
				Vector3(220.0, 0.0, -170.0), Vector3(-200.0, 0.0, -135.0),
				Vector3(-220.0, 0.0, 180.0), Vector3(210.0, 0.0, 125.0),
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts1, randf_range(17.5, 21.5), true, false, randf_range(62.0, 76.0))
			_mission_targets_total += 1
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts2, randf_range(17.5, 21.5), true, false, randf_range(68.0, 82.0))
			_mission_targets_total += 1
			var m4_sam := [
				Vector3(-215.0, 0.0, -80.0), Vector3(-135.0, 0.0, 65.0),
			]
			_add_vehicle(Vehicle.Kind.SAM, m4_sam, 4.6, true, true)
			_mission_targets_total += 1
			if Global.difficulty != Global.Difficulty.RECRUIT:
				var m4_bmp := [
					Vector3(145.0, 0.0, -90.0), Vector3(220.0, 0.0, 70.0),
				]
				_add_vehicle(Vehicle.Kind.BMP, m4_bmp, 9.2, true, true)
				_mission_targets_total += 1
			if Global.difficulty == Global.Difficulty.ACE:
				var m4_apc := [
					Vector3(-215.0, 0.0, 95.0), Vector3(-135.0, 0.0, 165.0),
				]
				_add_vehicle(Vehicle.Kind.APC, m4_apc, 9.6, true, true, 0.0, true, "btr8")
				_mission_targets_total += 1
			_add_aa_gun(Vector3(-180.0, 0.0, 25.0), false)
			_add_aa_gun(Vector3(185.0, 0.0, 50.0), false)

	_offset_targets = false
	if mission_id != 1:
		_spawn_frontline_bonus_targets()
	print("[LisLevel] spawned Combat Mission %d/4 with %d required targets" % [mission_id, _mission_targets_total])


func _spawn_frontline_bonus_targets() -> void:
	var spots := [
		[Vector3(-160.0, 0.0, 145.0), Vector3(1.0, 0.0, 0.0), 12.0],
		[Vector3(-190.0, 0.0, -55.0), Vector3(0.0, 0.0, 1.0), 12.0],
		[Vector3(185.0, 0.0, 85.0), Vector3(-1.0, 0.0, 0.0), 12.0],
	]
	for spot in spots:
		var p: Vector3 = spot[0]
		_add_mission_infantry(p, spot[1] as Vector3, float(spot[2]), 1.65, false)


func _spawn_reinforcement_wave() -> void:
	if _mission_finished or _reinforcement_wave >= 4:
		return
	_reinforcement_wave += 1
	if _reinforcement_wave >= 4:
		var timer := get_node_or_null("ReinforcementTimer") as Timer
		if timer != null:
			timer.stop()
	var anchors := [Vector2(-170.0, 85.0), Vector2(175.0, -35.0), Vector2(-185.0, -70.0), Vector2(170.0, 95.0)]
	var anc: Vector2 = anchors[(_reinforcement_wave - 1) % anchors.size()]
	var dry := _find_dry_spot(anc.x + randf_range(-25.0, 25.0), anc.y + randf_range(-25.0, 25.0))
	_add_mission_infantry(Vector3(dry.x, 0.0, dry.y), Vector3(1.0, 0.0, 0.4), 10.0, 1.75, false)
	_set_flash("ПІДКРІПЛЕННЯ ПРОТИВНИКА · ПІХОТА" if not MenuUI.is_english()
			else "ENEMY REINFORCEMENTS · INFANTRY")


func _spawn_special_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	_special_index = 0
	_special_hold = 0.0
	_special_zones.clear()
	_special_beacons.clear()
	_special_convoy = null
	_special_convoy_far_timer = 0.0
	_special_convoy_warned = false
	_special_convoy_stall_anchor = Vector3.ZERO
	_special_convoy_stall = 0.0
	_special_convoy_recoveries = 0
	_special_convoy_b = null
	_special_convoy_b_dest = Vector3.ZERO
	_special_convoy_b_start = Vector3.ZERO
	_special_convoy_b_stall_anchor = Vector3.ZERO
	_special_convoy_b_stall = 0.0
	_special_convoy_b_recoveries = 0
	_dawn_defense_pos = Vector3.ZERO
	_dawn_defense_beacon = null
	_reserved_ground_route.clear()
	_special_extract_active = false
	_special_extract_hold = 0.0
	_special_extract_point = _special_ground_point(-176.0, 205.0)
	_special_extract_beacon = null
	_special_pickup_prop = null
	_offset_targets = false
	_intercept_wave = 0
	_intercept_timer = 0.0
	_intercept_warned = false
	_intercept_leaks = 0
	_intercept_missiles.clear()

	match mission_id:
		1:
			_add_special_zone(Vector3(-160.0, 0.0, 145.0), 42.0, 2.0, "РОЗВІДКА 1/3")
			_add_special_zone(Vector3(-185.0, 0.0, -95.0), 42.0, 2.0, "РОЗВІДКА 2/3")
			_add_special_zone(Vector3(185.0, 0.0, -135.0), 44.0, 2.0, "РОЗВІДКА 3/3")
			_spawn_special_guards([
				Vector3(-145.0, 0.0, 95.0), Vector3(-168.0, 0.0, -60.0), Vector3(165.0, 0.0, -95.0),
			])
		2:
			_setup_special_escort()
		3:
			_add_special_zone(Vector3(175.0, 0.0, 92.0), 38.0, 2.5, "ЕВАКУАЦІЯ · ПІЛОТ")
			_add_special_zone(Vector3(-176.0, 0.0, 205.0), 46.0, 2.5, "ЕВАКУАЦІЯ · БАЗА")
			_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], true)
			_spawn_special_guards([
				Vector3(155.0, 0.0, 68.0), Vector3(195.0, 0.0, 115.0),
			])
		4:
			_add_special_zone(Vector3(-150.0, 0.0, 130.0), 36.0, 2.0, "ВАНТАЖ · ЗАБРАТИ")
			_add_special_zone(Vector3(-188.0, 0.0, -100.0), 38.0, 2.0, "ВАНТАЖ · ДОСТАВИТИ")
			_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], false)
			_spawn_special_guards([
				Vector3(-165.0, 0.0, 45.0), Vector3(-195.0, 0.0, -55.0),
			])
		5:
			_spawn_special_strike(false)
		6:
			_spawn_special_strike(true)
		7:
			_spawn_special_rear_convoy()
		8:
			_spawn_special_oreshnik(false)
		9:
			_spawn_special_oreshnik(true)
		10:
			_spawn_special_missile_intercept()
		11:
			_setup_special_dual_escort()
		12:
			_setup_special_dawn_defense()
		13:
			_setup_special_sar_landing()

	if mission_id >= 5 and mission_id <= 10:
		_special_extract_beacon = _spawn_special_beacon(_special_extract_point,
				_txt("ВИХІД · БАЗА", "EXFIL · BASE"), Color(0.35, 0.95, 0.75))
		_special_extract_beacon.visible = false
	print("[LisLevel] spawned Special Operation %d (%s), targets=%d" % [
		mission_id, Global.get_special_mission_name(mission_id), _mission_targets_total
	])


func _build_lis_escort_route(raw_pts: Array) -> Array[Vector3]:
	var seed_pts: Array[Vector3] = []
	for p2 in raw_pts:
		var v2: Vector2 = p2 as Vector2
		seed_pts.append(_special_ground_point(v2.x, v2.y))
	if _water_mask != null and _water_mask.ready_ok:
		return _water_mask.build_dry_route(seed_pts, true, false)
	return seed_pts


func _setup_special_escort() -> void:
	var route := _build_lis_escort_route([
		Vector2(-222.0, -225.0), Vector2(-208.0, -125.0),
		Vector2(-195.0, -15.0), Vector2(-198.0, 105.0), Vector2(-208.0, 218.0),
	])
	var vehicle := VEHICLE.new()
	vehicle.kind = Vehicle.Kind.TRUCK
	vehicle.hostile = false
	vehicle.track_drone = false
	vehicle.move_speed = 11.5
	add_child(vehicle)
	vehicle.max_health = 480.0
	vehicle.health = 480.0
	vehicle.global_position = route[0] + Vector3.UP * 0.2
	vehicle.set_waypoints(route)
	vehicle.remove_from_group("combat_target")
	vehicle.add_to_group("escort_convoy")
	vehicle.destroyed.connect(_on_escort_destroyed)
	_special_convoy = vehicle
	_special_convoy_start = route[0]
	_special_convoy_dest = route[route.size() - 1]
	var guard_spots: Array = []
	for t in [0.28, 0.56, 0.82]:
		var p := _point_on_route(route, float(t))
		var dry_g := _find_dry_spot(p.x - 24.0, p.z)
		guard_spots.append(Vector3(dry_g.x, 0.0, dry_g.y))
	_spawn_special_guards(guard_spots)
	var ambush := _point_on_route(route, 0.70)
	var amb_dry := _find_dry_spot(ambush.x + 28.0, ambush.z)
	_add_vehicle(Vehicle.Kind.APC, [
		Vector3(amb_dry.x, 0.0, amb_dry.y),
		Vector3(amb_dry.x - 26.0, 0.0, amb_dry.y + 32.0),
	], 5.6, true, false, 0.0, false, "btr8")


func _update_escort_mission(delta: float, drone: Drone) -> void:
	if _special_convoy == null or not is_instance_valid(_special_convoy):
		_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")
		return
	var max_leash := maxf(280.0, MAP_GROUND_SAFE * 0.95)
	var dist := drone.global_position.distance_to(_special_convoy.global_position)
	if dist > max_leash:
		_special_convoy_far_timer += delta
		if _special_convoy_far_timer > 4.0 and not _special_convoy_warned:
			_special_convoy_warned = true
			_set_flash(_txt("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОНИ!", "STAY WITH THE CONVOY!"))
			_play_radio_callout(_txt("ТРИМАЙТЕСЬ БЛИЖЧЕ ДО КОЛОНИ", "KEEP CLOSER TO THE CONVOY"), true)
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
			return
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
		if _special_convoy_far_timer < 1.0:
			_special_convoy_warned = false
	if _special_convoy.global_position.distance_to(_special_convoy_dest) < 55.0:
		_finish_special_success()
		return
	if _special_convoy_stall_anchor == Vector3.ZERO:
		_special_convoy_stall_anchor = _special_convoy.global_position
	if _special_convoy.global_position.distance_to(_special_convoy_stall_anchor) < 0.35:
		_special_convoy_stall += delta
	else:
		_special_convoy_stall_anchor = _special_convoy.global_position
		_special_convoy_stall = 0.0
	if _special_convoy_stall >= 4.0:
		_special_convoy_stall = 0.0
		_special_convoy_recoveries += 1
		_special_convoy.call("escort_emergency_advance")
		if _special_convoy_recoveries >= 4 and _water_mask != null and _water_mask.ready_ok:
			_special_convoy_recoveries = 0
			var reroute := _water_mask.build_dry_route([_special_convoy.global_position, _special_convoy_dest], true, false)
			if reroute.size() >= 2:
				_special_convoy.call("set_waypoints", reroute)


func _setup_special_dual_escort() -> void:
	_setup_special_escort()
	var route_b := _build_lis_escort_route([
		Vector2(185.0, -210.0), Vector2(175.0, -90.0),
		Vector2(168.0, 25.0), Vector2(180.0, 145.0), Vector2(190.0, 215.0),
	])
	var vehicle_b := VEHICLE.new()
	vehicle_b.kind = Vehicle.Kind.TRUCK
	vehicle_b.hostile = false
	vehicle_b.track_drone = false
	vehicle_b.move_speed = 11.0
	add_child(vehicle_b)
	vehicle_b.max_health = 480.0
	vehicle_b.health = 480.0
	vehicle_b.global_position = route_b[0] + Vector3.UP * 0.2
	vehicle_b.set_waypoints(route_b)
	vehicle_b.remove_from_group("combat_target")
	vehicle_b.add_to_group("escort_convoy")
	vehicle_b.destroyed.connect(_on_escort_destroyed)
	_special_convoy_b = vehicle_b
	_special_convoy_b_start = route_b[0]
	_special_convoy_b_dest = route_b[route_b.size() - 1]


func _update_dual_escort_mission(delta: float, drone: Drone) -> void:
	if _special_convoy == null or not is_instance_valid(_special_convoy) \
			or _special_convoy_b == null or not is_instance_valid(_special_convoy_b):
		_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")
		return
	var max_leash := maxf(290.0, MAP_GROUND_SAFE)
	var dist := minf(drone.global_position.distance_to(_special_convoy.global_position),
			drone.global_position.distance_to(_special_convoy_b.global_position))
	if dist > max_leash:
		_special_convoy_far_timer += delta
		if _special_convoy_far_timer > 4.0 and not _special_convoy_warned:
			_special_convoy_warned = true
			_set_flash(_txt("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОН!", "STAY WITH THE CONVOYS!"))
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
			return
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
	var a_arrived := _special_convoy.global_position.distance_to(_special_convoy_dest) < 55.0
	var b_arrived := _special_convoy_b.global_position.distance_to(_special_convoy_b_dest) < 55.0
	if a_arrived and b_arrived:
		_finish_special_success()
		return
	if not a_arrived:
		if _special_convoy_stall_anchor == Vector3.ZERO:
			_special_convoy_stall_anchor = _special_convoy.global_position
		if _special_convoy.global_position.distance_to(_special_convoy_stall_anchor) < 0.35:
			_special_convoy_stall += delta
		else:
			_special_convoy_stall_anchor = _special_convoy.global_position
			_special_convoy_stall = 0.0
		if _special_convoy_stall >= 4.0:
			_special_convoy_stall = 0.0
			_special_convoy.call("escort_emergency_advance")
	if not b_arrived:
		if _special_convoy_b_stall_anchor == Vector3.ZERO:
			_special_convoy_b_stall_anchor = _special_convoy_b.global_position
		if _special_convoy_b.global_position.distance_to(_special_convoy_b_stall_anchor) < 0.35:
			_special_convoy_b_stall += delta
		else:
			_special_convoy_b_stall_anchor = _special_convoy_b.global_position
			_special_convoy_b_stall = 0.0
		if _special_convoy_b_stall >= 4.0:
			_special_convoy_b_stall = 0.0
			_special_convoy_b.call("escort_emergency_advance")


func _spawn_special_strike(ew_breach: bool) -> void:
	var sam_route := [
		Vector3(145.0, 0.0, -75.0), Vector3(215.0, 0.0, -75.0),
		Vector3(215.0, 0.0, 65.0), Vector3(145.0, 0.0, 65.0),
	]
	_add_vehicle(Vehicle.Kind.SAM, sam_route, 4.8, true, true)
	_mission_targets_total += 1
	var bmp_route := [
		Vector3(-220.0, 0.0, -45.0), Vector3(-135.0, 0.0, -45.0),
		Vector3(-135.0, 0.0, 75.0), Vector3(-220.0, 0.0, 75.0),
	]
	_add_vehicle(Vehicle.Kind.BMP, bmp_route, 9.2, true, true)
	_mission_targets_total += 1
	_spawn_special_guards([
		Vector3(-160.0, 0.0, 120.0), Vector3(165.0, 0.0, 45.0),
	], false, "spetsnaz" if ew_breach else "")
	_add_aa_gun(Vector3(-155.0, 0.0, -25.0), false)
	if ew_breach:
		_spawn_special_guards([Vector3(175.0, 0.0, -55.0)], false, "spetsnaz")
		_add_aa_gun(Vector3(185.0, 0.0, -90.0), false)


func _spawn_special_rear_convoy() -> void:
	var btr_route := [
		Vector3(-220.0, 0.0, 60.0), Vector3(-135.0, 0.0, -35.0),
		Vector3(-145.0, 0.0, -135.0), Vector3(-220.0, 0.0, -60.0),
	]
	_add_vehicle(Vehicle.Kind.APC, btr_route, 9.0, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	var mtsm_route := [
		Vector3(145.0, 0.0, -45.0), Vector3(220.0, 0.0, -45.0),
		Vector3(220.0, 0.0, 75.0), Vector3(145.0, 0.0, 75.0),
	]
	_add_vehicle(Vehicle.Kind.APC, mtsm_route, 7.2, true, true, 0.0, true, "mtsm")
	_mission_targets_total += 1
	var ural_route := [
		Vector3(-220.0, 0.0, -140.0), Vector3(-150.0, 0.0, -70.0),
		Vector3(-160.0, 0.0, 35.0),
	]
	_add_vehicle(Vehicle.Kind.TRUCK, ural_route, 8.0, true, false, 0.0, true, "ural")
	_mission_targets_total += 1
	_spawn_special_guards([
		Vector3(-165.0, 0.0, 25.0), Vector3(175.0, 0.0, -25.0),
	], true, "spetsnaz")
	_add_aa_gun(Vector3(-185.0, 0.0, -95.0), false)


func _spawn_special_oreshnik(deep_strike: bool) -> void:
	var oreshnik_route := [
		Vector3(145.0, 0.0, -110.0), Vector3(220.0, 0.0, -110.0),
		Vector3(220.0, 0.0, -180.0), Vector3(145.0, 0.0, -180.0),
	]
	_add_vehicle(Vehicle.Kind.SAM, oreshnik_route, 3.6 if deep_strike else 3.4, true, true, 0.0, true, "oreshnik")
	_mission_targets_total += 1
	var btr_route := [
		Vector3(-220.0, 0.0, -20.0), Vector3(-140.0, 0.0, -20.0),
		Vector3(-140.0, 0.0, -100.0), Vector3(-220.0, 0.0, -100.0),
	]
	_add_vehicle(Vehicle.Kind.APC, btr_route, 9.2 if deep_strike else 8.6, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	_add_aa_gun(Vector3(-165.0, 0.0, -45.0), false)
	if deep_strike:
		var sam_route := [
			Vector3(145.0, 0.0, -35.0), Vector3(215.0, 0.0, -35.0),
			Vector3(215.0, 0.0, 55.0), Vector3(145.0, 0.0, 55.0),
		]
		_add_vehicle(Vehicle.Kind.SAM, sam_route, 4.6, true, true)
		_mission_targets_total += 1
		var mtsm_route := [
			Vector3(-215.0, 0.0, 20.0), Vector3(-140.0, 0.0, 20.0),
			Vector3(-140.0, 0.0, 95.0), Vector3(-215.0, 0.0, 95.0),
		]
		_add_vehicle(Vehicle.Kind.APC, mtsm_route, 7.2, true, true, 0.0, true, "mtsm")
		_mission_targets_total += 1
		_spawn_special_guards([
			Vector3(-175.0, 0.0, 60.0), Vector3(175.0, 0.0, -65.0),
		], true, "spetsnaz")
		_add_aa_gun(Vector3(185.0, 0.0, -125.0), false)
	else:
		var ural_route := [
			Vector3(150.0, 0.0, -45.0), Vector3(215.0, 0.0, 45.0),
		]
		_add_vehicle(Vehicle.Kind.TRUCK, ural_route, 7.2, true, false, 0.0, true, "ural")
		_mission_targets_total += 1
		_spawn_special_guards([
			Vector3(-170.0, 0.0, -55.0), Vector3(175.0, 0.0, -75.0),
		], false, "spetsnaz")


func _spawn_missile_wave() -> void:
	var count: int = MISSILE_WAVE_COUNTS[_intercept_wave]
	var wave_no := _intercept_wave + 1
	var edge_x := 270.0
	var lane_half := 190.0
	var lane_step := (lane_half * 2.0) / maxf(float(count) - 1.0, 1.0)
	for i in range(count):
		var lane := randf_range(-lane_half, lane_half) if count == 1 \
				else -lane_half + lane_step * float(i) + randf_range(-8.0, 8.0)
		var goal_lane := clampf(lane + randf_range(-16.0, 16.0), -lane_half, lane_half)
		var altitude := randf_range(76.0, 96.0)
		var speed := randf_range(26.0, 36.0) * Global.get_difficulty_missile_speed_scale()
		var start := Vector3(-edge_x, 0.0, lane)
		var goal := Vector3(edge_x, 0.0, goal_lane)
		var missile := _add_vehicle(Vehicle.Kind.SHAHED, [start, goal], speed, false, false, altitude, true, "cruise_missile")
		if missile == null:
			continue
		var beacon := missile.get_node_or_null("FriendlyConvoyBeacon")
		if beacon != null:
			beacon.queue_free()
		missile.set_meta("intercept_target", true)
		_intercept_missiles.append({
			"vehicle": missile, "goal": goal, "start": start,
			"speed": speed, "spawned": _mission_time,
		})
	_intercept_wave += 1
	_set_flash(_txt("ХВИЛЯ %d — РАКЕТИ В ПОВІТРІ!" % wave_no, "WAVE %d — MISSILES AIRBORNE!" % wave_no))
	_play_alert("incoming")


func _setup_special_dawn_defense() -> void:
	_dawn_defense_pos = _special_ground_point(-176.0, 170.0)
	_dawn_defense_beacon = _spawn_special_beacon(_dawn_defense_pos, "ОПОРНИЙ ПУНКТ", Color(0.95, 0.76, 0.28))
	var bmp_route := [
		_special_ground_point(-230.0, -110.0),
		_special_ground_point(-180.0, 90.0),
	]
	_add_vehicle(Vehicle.Kind.BMP, bmp_route, 7.6, true, true)
	_mission_targets_total += 1
	var apc_route := [
		_special_ground_point(-125.0, -95.0),
		_special_ground_point(-160.0, 95.0),
	]
	_add_vehicle(Vehicle.Kind.APC, apc_route, 8.0, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	if Global.difficulty == Global.Difficulty.ACE:
		var tank_route := [
			_special_ground_point(-185.0, -160.0),
			_special_ground_point(-170.0, 75.0),
		]
		_add_vehicle(Vehicle.Kind.TANK, tank_route, 5.8, true, true)
		_mission_targets_total += 1
	_spawn_special_guards([
		Vector3(-200.0, 0.0, 35.0), Vector3(-148.0, 0.0, 45.0),
	], true, "spetsnaz")
	_add_aa_gun(Vector3(-195.0, 0.0, -25.0), false)


func _setup_special_sar_landing() -> void:
	_add_special_zone(Vector3(175.0, 0.0, 95.0), 38.0, 2.5, "РЯТУВАЛЬНА ЗОНА · ПОСАДКА")
	_add_special_zone(Vector3(-176.0, 0.0, 205.0), 44.0, 2.5, "БАЗА · ПОСАДКА")
	_special_pickup_prop = _spawn_special_pickup_marker(_special_zones[0]["pos"], true)
	_spawn_special_guards([
		Vector3(155.0, 0.0, 65.0), Vector3(198.0, 0.0, 120.0),
	], false)


func _spawn_kamikaze_drones() -> void:
	super._spawn_kamikaze_drones()
	for kz in get_tree().get_nodes_in_group("enemy_kamikaze"):
		if kz is Node3D:
			var n := kz as Node3D
			var p := n.global_position
			if p.y < 88.0:
				n.global_position = Vector3(p.x, 88.0, p.z)


func _setup_reb() -> void:
	super._setup_reb()
	if _reb != null:
		_reb.base_range_m = maxf(880.0, MAP_FLIGHT_BOUND * 2.6)
