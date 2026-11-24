extends "res://sceneries/BigLevel.gd"
## Нафтова платформа — тільки фрістайл, заміняє Умань у меню.
## Географія з maps/oil_rig (49 гейтів, 5 спавнів, WaterKillZone), усе інше —
## BigLevel. Бойові спавни навмисно заглушені, як в UmanLevel.

const MAP_SCENE := "res://maps/oil_rig/oil_rig_map.tscn"
const MapRuntimeScript = preload("res://maps/oil_rig/scripts/map_runtime.gd")
const RIG_SCALE: float = 0.35
const DEFAULT_SPAWN := Vector3(0.0, 144.0, 0.0) * RIG_SCALE
const ORDERED_GATE_INDICES: Array[int] = [
	44, 13, 14, 18, 15, 16, 11, 20, 45,
	24, 25, 29, 26, 27, 22, 46,
	35, 36, 40, 37, 38, 33, 47,
	2, 3, 7, 4, 5, 0, 48,
]

var _map_instance: Node3D = null
var _water_zone: Area3D = null
var _rig_gates_passed: Dictionary = {}
var _rig_lap_start: float = -1.0
var _rig_best_lap: float = 0.0
var _rig_gate_triggers: Array[Area3D] = []
var _rig_ordered_indices: Array[int] = []
var _rig_gate_labels: Dictionary = {}
var _rig_next_order_pos: int = 0
var _rig_active_gate_idx: int = -1
var _rig_markers_root: Node3D = null
var _rig_spawn_xform: Transform3D = Transform3D(Basis.IDENTITY, DEFAULT_SPAWN)
var _rig_has_spawn: bool = false
var _rig_active_torus: MeshInstance3D = null
var _rig_active_mat: StandardMaterial3D = null
var _rig_active_halo: MeshInstance3D = null
var _rig_active_halo_mat: StandardMaterial3D = null
var _rig_next_torus: MeshInstance3D = null
var _rig_pulse: float = 0.0
var _rig_route_refresh_seq: int = 0


func _map_path() -> String:
	return MAP_SCENE


func _apply_map_materials(_node: Node) -> void:
	pass


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	MAP_GROUND_SAFE = 420.0
	MAP_FLIGHT_BOUND = 560.0
	MAP_AIR_SAFE = 500.0
	_ground_y = 0.0
	set_meta("disable_procedural_grass", true)
	skip_material_upgrade = true
	super._ready()


func _load_map() -> void:
	super._load_map()
	var root := get_node_or_null("MapRoot")
	if root != null:
		for c in root.get_children():
			if c is Node3D and c.name == "OilRigMap":
				_map_instance = c
				break
	if _map_instance != null:
		_map_instance.scale = Vector3.ONE * RIG_SCALE
		_map_instance.position = Vector3.ZERO
		var ocean := _map_instance.find_child("Ocean", true, false) as Node3D
		if ocean != null:
			ocean.scale = Vector3.ONE / RIG_SCALE
	_neutralize_map_extras()
	# BigLevel's fallback ground plane (3600x3600, brown) is far below a 400 m
	# offshore deck and was rendering over/through the authored ocean shader.
	var fallback_ground := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if fallback_ground != null:
		fallback_ground.visible = false
	_attach_atlas_materials()
	_nudge_clear_hangar_gates()
	_build_steel_colliders()
	_connect_water_kill()
	_setup_oilrig_gate_triggers()


func _nudge_clear_hangar_gates() -> void:
	if _map_instance == null:
		return
	var gates_node := _map_instance.get_node_or_null("FPVGates")
	if gates_node == null:
		return
	# At RIG_SCALE = 0.35, the 4 outer hangar gates sit too close to the bay floor/wall
	# (-10m sweep clips the deck); nudge them outward along their exit normal before
	# VisibleGateRings populates so meshes, triggers and sweeps align cleanly.
	for idx in [5, 16, 27, 38]:
		var m := gates_node.get_node_or_null("Gate_%02d" % idx) as Marker3D
		if m != null:
			var nrm := m.transform.basis.y.normalized()
			m.position += nrm * (8.0 / RIG_SCALE)


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


## Вихідна сцена НЕ активує oil_rig_materials.gd (скрипт є, але не підвішений),
## тому GLB-модулі імпортуються без текстур і виглядають білими. Підвішуємо
## відновлювач атласних матеріалів інакше карта пересвічена й без деталей.
func _attach_atlas_materials() -> void:
	if _map_instance == null:
		return
	# The source mini-project shipped oil_rig_materials.gd but never attached it
	# to a node, so a plain import of the GLBs is untextured/white.  Apply the
	# shared atlas materials on EVERY surface (the helper script only searched
	# its own children, which is why a child-node fixer did nothing).
	var shared := {
		"MAT_Structures": load("res://maps/oil_rig/materials/structures.tres"),
		"MAT_Deck": load("res://maps/oil_rig/materials/deck.tres"),
		"MAT_Emissive": load("res://maps/oil_rig/materials/emissive.tres"),
		"MAT_FlameCore": load("res://maps/oil_rig/materials/flame.tres"),
		"MAT_Light": load("res://maps/oil_rig/materials/light.tres"),
	}
	var flame_outer: Material = load("res://maps/oil_rig/materials/flame_outer.tres")
	var applied := 0
	for child in _map_instance.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for surface in range(mi.mesh.get_surface_count()):
			if mi.name == "MS_flare_emissive" and surface == 0 and flame_outer != null:
				mi.set_surface_override_material(surface, flame_outer)
				applied += 1
				continue
			var src: Material = mi.get_surface_override_material(surface)
			if src == null:
				src = mi.mesh.surface_get_material(surface)
			if src == null:
				continue
			var key := String(src.resource_name)
			if shared.has(key):
				mi.set_surface_override_material(surface, shared[key])
				applied += 1
	print("[OILRIG] atlas materials applied to %d surfaces" % applied)


## Світло BigLevel розраховане на ліси/цехи — для морської платформи воно
## спалює білі металеві палуби. Мʼякший контраст і нижча експозиція.
func _tune_map_environment() -> void:
	super._tune_map_environment()
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.tonemap_exposure = 1.05
		env.tonemap_white = 1.45
		env.ambient_light_energy = 0.62
		env.ambient_light_sky_contribution = 0.65
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.04
		env.adjustment_saturation = 1.06
		# Source Environment_env: linear fog, colour 0.55/0.70/0.80, density
		# 0.00085.  BigLevel's height fog is centred at _ground_y + 16 (~411 m)
		# and drowned the sea (at y=0) in grey — restore the authored fog mode.
		env.fog_height_density = 0.0
		env.fog_aerial_perspective = 0.0
		env.volumetric_fog_enabled = false
		env.volumetric_fog_density = 0.0
		env.ssr_enabled = false
		env.sdfgi_enabled = false
		env.ssao_enabled = false
		# The 0.00085 value in the source .tscn is authored for close FPV views;
		# from the review camera (1 km up) it whites out the whole rig.  Keep
		# the authored fog colour but only a trace of distance haze so the rig
		# reads like the Blender reference render.
		env.fog_light_color = Color(0.55, 0.70, 0.80, 1.0)
		env.fog_light_energy = 0.25
		env.fog_density = 0.000015
		env.glow_enabled = false
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = load("res://maps/oil_rig/textures/kloofendal_sky.png")
		var sky := Sky.new()
		sky.sky_material = pano
		env.sky = sky
		env.background_mode = Environment.BG_SKY
		env.background_color = Color(0.53, 0.70, 0.86, 1.0)
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-38.0, 120.0, 0.0)
		sun.light_energy = 1.65
		sun.light_color = Color(1.0, 0.94, 0.85, 1.0)
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.24


func _connect_water_kill() -> void:
	if _map_instance == null:
		return
	_water_zone = _map_instance.find_child("WaterKillZone", true, false) as Area3D
	if _water_zone != null and not _water_zone.body_entered.is_connected(_on_oilrig_water_body):
		_water_zone.body_entered.connect(_on_oilrig_water_body)


func _on_oilrig_water_body(body: Node3D) -> void:
	if body != null and (body == get_node_or_null("Drone") or body.is_in_group("drone")):
		request_respawn()


func _authored_freestyle_waypoints() -> Array:
	var out: Array = []
	if _map_instance != null:
		var gates := _map_instance.find_child("FPVGates", true, false)
		if gates != null:
			var markers := gates.get_children()
			var step: int = maxi(1, markers.size() / 16)
			for i in range(0, markers.size(), step):
				var m = markers[i]
				if m is Node3D:
					out.append((m as Node3D).global_position)
			if out.size() >= 8:
				return out
	return [
		Vector3(-120, 177, -80), Vector3(0, 182, -180), Vector3(180, 177, -60),
		Vector3(240, 182, 120), Vector3(40, 187, 200), Vector3(-160, 182, 140),
		Vector3(-280, 177, 0), Vector3(-80, 179, -200),
	]


func _find_ground_y(_x: float, _z: float) -> float:
	return 0.0


func _map_water_level() -> float:
	return 0.0


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.0,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _find_oilrig_spawn() -> Vector3:
	return _find_oilrig_spawn_transform().origin


func _find_oilrig_spawn_transform() -> Transform3D:
	if _rig_has_spawn:
		return _rig_spawn_xform
	if _map_instance != null:
		var points := _map_instance.find_child("SpawnPoints", true, false)
		if points != null:
			var marker := points.get_node_or_null("Spawn_Tanker") as Node3D
			if marker == null:
				marker = points.get_node_or_null("Spawn_Helipad_P1") as Node3D
			if marker == null and points.get_child_count() > 0:
				marker = points.get_child(0) as Node3D
			if marker != null:
				var basis_xform := marker.global_transform.basis.orthonormalized()
				var gates_node := _map_instance.get_node_or_null("FPVGates")
				if gates_node != null and not ORDERED_GATE_INDICES.is_empty():
					var gate0 := gates_node.get_node_or_null("Gate_%02d" % ORDERED_GATE_INDICES[0]) as Node3D
					if gate0 != null:
						var flat_dir := gate0.global_position - marker.global_position
						flat_dir.y = 0.0
						if flat_dir.length_squared() > 0.25:
							basis_xform = Basis.looking_at(flat_dir.normalized(), Vector3.UP)
				_rig_spawn_xform = Transform3D(basis_xform, marker.global_position)
				_rig_has_spawn = true
				return _rig_spawn_xform
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		return Transform3D(respawn.global_transform.basis.orthonormalized(), respawn.global_position)
	return Transform3D(Basis.IDENTITY, DEFAULT_SPAWN)


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone")
	if d == null:
		return
	var sp := _find_oilrig_spawn_transform()
	var pos := sp.origin + Vector3(0.0, 2.0, 0.0)
	var spawn_xform := Transform3D(sp.basis, pos)
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
	call_deferred("_refresh_oilrig_route_after_sync")


# --- фрістайл-карта: жодних місій, техніки, піхоти чи руйнованих цілей. ---
## The source map removed all visual neon rings — FPVGates are invisible
## Marker3D only.  BigLevel would otherwise spawn a 24-ring cyan course that
## does not exist in the authored scene, so keep this empty.
func _build_frontline_props() -> void:
	pass


func _spawn_training_rings() -> void:
	pass


func _update_course_route_guide() -> void:
	pass


func _refresh_route_after_physics() -> void:
	pass


func _setup_oilrig_gate_triggers() -> void:
	for old in _rig_gate_triggers:
		if is_instance_valid(old):
			old.queue_free()
	_rig_gate_triggers.clear()
	_rig_gates_passed.clear()
	_rig_ordered_indices.clear()
	_rig_gate_labels.clear()
	_rig_next_order_pos = 0
	_rig_active_gate_idx = -1
	_rig_lap_start = -1.0
	if _rig_markers_root != null and is_instance_valid(_rig_markers_root):
		_rig_markers_root.queue_free()
		_rig_markers_root = null
		_route_guide = null
	_rig_active_torus = null
	_rig_active_mat = null
	_rig_active_halo = null
	_rig_active_halo_mat = null
	_rig_next_torus = null
	if _triggers == null or _map_instance == null:
		return
	var gates_node := _map_instance.get_node_or_null("FPVGates")
	if gates_node == null:
		return
	_build_ordered_rig_course(gates_node)
	_rig_markers_root = Node3D.new()
	_rig_markers_root.name = "RigGateMarkers"
	add_child(_rig_markers_root)
	var total := _rig_ordered_indices.size()
	for ord_i in range(total):
		var idx: int = _rig_ordered_indices[ord_i]
		var marker := gates_node.get_node_or_null("Gate_%02d" % idx) as Marker3D
		if marker == null:
			continue
		var area := Area3D.new()
		area.name = "RigGateTrigger_%02d" % idx
		area.set_meta("gate_idx", idx)
		_triggers.add_child(area)
		area.global_transform = Transform3D(marker.global_transform.basis.orthonormalized(), marker.global_position)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		var s := marker.global_transform.basis.x.length()
		sp.radius = maxf(4.2, s * 4.5)
		cs.shape = sp
		area.add_child(cs)
		area.monitoring = (ord_i == 0)
		area.body_entered.connect(_on_oilrig_gate_entered.bind(idx))
		_rig_gate_triggers.append(area)

		var lbl := Label3D.new()
		lbl.name = "RigLabel_%02d" % (ord_i + 1)
		if ord_i == 0:
			lbl.text = "START 1/%d" % total
			lbl.modulate = Color(1.0, 0.90, 0.12, 0.98)
		elif ord_i == total - 1:
			lbl.text = "FINISH %d/%d" % [total, total]
			lbl.modulate = Color(0.28, 0.96, 1.0, 0.98)
		else:
			lbl.text = "%d/%d" % [ord_i + 1, total]
			lbl.modulate = Color(1.0, 0.96, 0.82, 0.94)
		lbl.font_size = 64
		lbl.pixel_size = 0.022
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = false
		lbl.outline_modulate = Color(0.02, 0.04, 0.06, 0.94)
		lbl.outline_size = 10
		_rig_markers_root.add_child(lbl)
		lbl.global_position = marker.global_position + Vector3(0.0, maxf(4.6, s * 4.6) + 1.0, 0.0)
		_rig_gate_labels[idx] = lbl
	_build_rig_active_highlights()
	_sync_oilrig_active_gate()
	print("[OilRigLevel] active gate triggers ready: %d/30 (_rings_total=%d)" % [_rig_gate_triggers.size(), _rings_total])


func _build_steel_colliders() -> void:
	if _map_instance == null:
		return
	var mc := _map_instance.get_node_or_null("MapColliders")
	if mc != null:
		for cs_node in mc.find_children("*", "CollisionShape3D", true, false):
			var cs := cs_node as CollisionShape3D
			if cs.shape is ConcavePolygonShape3D:
				(cs.shape as ConcavePolygonShape3D).backface_collision = true
	var existing := _map_instance.get_node_or_null("SteelMeshColliders") as Node3D
	if existing != null:
		existing.queue_free()
	var modules := _map_instance.get_node_or_null("Modules") as Node3D
	if modules == null:
		return
	var container := Node3D.new()
	container.name = "SteelMeshColliders"
	_map_instance.add_child(container)
	var added := 0
	var root_inv := _map_instance.global_transform.affine_inverse()
	for mod in modules.get_children():
		for child in mod.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.visible:
				continue
			var lnm := String(mi.name).to_lower()
			if lnm.contains("flare") or lnm.contains("glow") or lnm.contains("light"):
				continue
			var faces := mi.mesh.get_faces()
			if faces.is_empty():
				continue
			var tri := ConcavePolygonShape3D.new()
			tri.set_faces(faces)
			tri.backface_collision = true
			var sb := StaticBody3D.new()
			sb.name = "%s_%s_col" % [mod.name, mi.name]
			sb.collision_layer = 1
			sb.collision_mask = 0
			sb.transform = root_inv * mi.global_transform
			var cs := CollisionShape3D.new()
			cs.shape = tri
			sb.add_child(cs)
			container.add_child(sb)
			added += 1
	print("[OilRigLevel] SteelMeshColliders ready: %d steel trimeshes (MapColliders=%d)" % [
		added, mc.get_child_count() if mc != null else -1
	])


func _build_ordered_rig_course(gates_node: Node) -> void:
	for raw_idx: int in ORDERED_GATE_INDICES:
		if gates_node.get_node_or_null("Gate_%02d" % raw_idx) != null:
			_rig_ordered_indices.append(raw_idx)
	for raw_idx in MapRuntimeScript.SELECTED_GATE_INDICES:
		var idx := int(raw_idx)
		if not _rig_ordered_indices.has(idx) and gates_node.get_node_or_null("Gate_%02d" % idx) != null:
			_rig_ordered_indices.append(idx)


func _build_rig_active_highlights() -> void:
	if _rig_markers_root == null:
		return
	_rig_active_torus = MeshInstance3D.new()
	_rig_active_torus.name = "ActiveRigGateHighlight"
	var t_act := TorusMesh.new()
	t_act.inner_radius = 3.55
	t_act.outer_radius = 4.20
	t_act.rings = 28
	t_act.ring_segments = 8
	_rig_active_torus.mesh = t_act
	_rig_active_mat = StandardMaterial3D.new()
	_rig_active_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rig_active_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rig_active_mat.albedo_color = Color(1.0, 0.96, 0.40, 1.0)
	_rig_active_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rig_active_torus.material_override = _rig_active_mat
	_rig_active_torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig_markers_root.add_child(_rig_active_torus)

	_rig_active_halo = MeshInstance3D.new()
	_rig_active_halo.name = "ActiveRigGateHalo"
	var t_halo := TorusMesh.new()
	t_halo.inner_radius = 4.95
	t_halo.outer_radius = 5.55
	t_halo.rings = 28
	t_halo.ring_segments = 8
	_rig_active_halo.mesh = t_halo
	_rig_active_halo_mat = StandardMaterial3D.new()
	_rig_active_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rig_active_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rig_active_halo_mat.albedo_color = Color(1.0, 0.94, 0.25, 0.92)
	_rig_active_halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rig_active_halo.material_override = _rig_active_halo_mat
	_rig_active_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig_active_torus.add_child(_rig_active_halo)

	_rig_next_torus = MeshInstance3D.new()
	_rig_next_torus.name = "NextRigGateHighlight"
	var t_nxt := TorusMesh.new()
	t_nxt.inner_radius = 4.10
	t_nxt.outer_radius = 4.55
	t_nxt.rings = 22
	t_nxt.ring_segments = 6
	_rig_next_torus.mesh = t_nxt
	var next_mat := StandardMaterial3D.new()
	next_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	next_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	next_mat.albedo_color = Color(1.0, 0.64, 0.14, 0.85)
	next_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rig_next_torus.material_override = next_mat
	_rig_next_torus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig_markers_root.add_child(_rig_next_torus)


func _active_oilrig_gate_marker() -> Marker3D:
	if _map_instance == null or _rig_ordered_indices.is_empty():
		return null
	var gates_node := _map_instance.get_node_or_null("FPVGates")
	if gates_node == null:
		return null
	var total := _rig_ordered_indices.size()
	for off in range(total):
		var pos_idx := (_rig_next_order_pos + off) % total
		var gidx := _rig_ordered_indices[pos_idx]
		if not _rig_gates_passed.has(gidx):
			return gates_node.get_node_or_null("Gate_%02d" % gidx) as Marker3D
	return gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[0]) as Marker3D


func _sync_oilrig_active_gate() -> void:
	if _map_instance == null or _rig_ordered_indices.is_empty():
		return
	var gates_node := _map_instance.get_node_or_null("FPVGates")
	if gates_node == null:
		return
	var total := _rig_ordered_indices.size()
	var active_ord := -1
	var next_ord := -1
	for off in range(total):
		var ord_i := (_rig_next_order_pos + off) % total
		var gidx := _rig_ordered_indices[ord_i]
		if not _rig_gates_passed.has(gidx):
			if active_ord < 0:
				active_ord = ord_i
			elif next_ord < 0:
				next_ord = ord_i
				break
	_rig_active_gate_idx = _rig_ordered_indices[active_ord] if active_ord >= 0 else -1
	for trig in _rig_gate_triggers:
		if is_instance_valid(trig):
			var tg := int(trig.get_meta("gate_idx", -1))
			trig.set_deferred("monitoring", tg == _rig_active_gate_idx)
	for ord_i in range(total):
		var gidx := _rig_ordered_indices[ord_i]
		var lbl := _rig_gate_labels.get(gidx) as Label3D
		if lbl != null:
			if ord_i != active_ord:
				lbl.scale = Vector3.ONE
			if _rig_gates_passed.has(gidx):
				lbl.modulate = Color(0.45, 0.95, 0.52, 0.42)
			elif ord_i == active_ord:
				lbl.modulate = Color(1.0, 0.96, 0.35, 1.0)
			elif ord_i == total - 1:
				lbl.modulate = Color(0.28, 0.96, 1.0, 0.96)
			else:
				lbl.modulate = Color(1.0, 0.96, 0.82, 0.88)
	if _rig_active_torus != null:
		if active_ord >= 0:
			var m_act := gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[active_ord]) as Marker3D
			if m_act != null:
				var s_act := m_act.global_transform.basis.x.length()
				_rig_active_torus.visible = true
				_rig_active_torus.global_transform = Transform3D(
						m_act.global_transform.basis.orthonormalized(), m_act.global_position)
				_rig_active_torus.scale = Vector3.ONE * maxf(0.5, s_act)
			else:
				_rig_active_torus.visible = false
		else:
			_rig_active_torus.visible = false
	if _rig_next_torus != null:
		if next_ord >= 0:
			var m_nxt := gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[next_ord]) as Marker3D
			if m_nxt != null:
				var s_nxt := m_nxt.global_transform.basis.x.length()
				_rig_next_torus.visible = true
				_rig_next_torus.global_transform = Transform3D(
						m_nxt.global_transform.basis.orthonormalized(), m_nxt.global_position)
				_rig_next_torus.scale = Vector3.ONE * maxf(0.5, s_nxt)
			else:
				_rig_next_torus.visible = false
		else:
			_rig_next_torus.visible = false


	var d := get_node_or_null("Drone") as Node3D
	if _route_guide == null or not is_instance_valid(_route_guide):
		_route_guide = CourseRouteGuideScript.new()
		_rig_markers_root.add_child(_route_guide)
	_route_guide.visible = true
	var rig_gates: Array[Dictionary] = []
	var rig_exclude: Array[RID] = []
	if d is CollisionObject3D:
		rig_exclude.append((d as CollisionObject3D).get_rid())
	for trig in _rig_gate_triggers:
		if is_instance_valid(trig):
			rig_exclude.append(trig.get_rid())
	var active_chain_idx := maxi(active_ord, 0)
	for ord_i in range(total):
		var m_g := gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[ord_i]) as Marker3D
		if m_g == null:
			continue
		var dir_g := m_g.global_transform.basis.y.normalized()
		if ord_i + 1 < total:
			var m_n := gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[ord_i + 1]) as Marker3D
			if m_n != null and dir_g.dot(m_n.global_position - m_g.global_position) < 0.0:
				dir_g = -dir_g
		elif ord_i > 0:
			var m_p := gates_node.get_node_or_null("Gate_%02d" % _rig_ordered_indices[ord_i - 1]) as Marker3D
			if m_p != null and dir_g.dot(m_g.global_position - m_p.global_position) < 0.0:
				dir_g = -dir_g
		rig_gates.append({
			"pos": m_g.global_position,
			"dir": dir_g,
			"radius": maxf(4.2, m_g.global_transform.basis.x.length() * 4.5),
		})
	var rig_space := get_world_3d().direct_space_state if get_world_3d() != null else null
	var rig_origin: Vector3 = d.global_position if d != null else _find_oilrig_spawn_transform().origin
	if rig_space != null and not rig_gates.is_empty():
		_route_guide.call("update_route",
				rig_gates, mini(active_chain_idx, rig_gates.size() - 1), rig_space, rig_exclude, rig_origin)


func _refresh_oilrig_route_after_sync() -> void:
	_rig_route_refresh_seq += 1
	var seq := _rig_route_refresh_seq
	for _i in range(2):
		if not is_inside_tree():
			return
		await get_tree().physics_frame
		if seq != _rig_route_refresh_seq or not is_inside_tree():
			return
	if _route_guide != null and is_instance_valid(_route_guide):
		_route_guide.call("clear_cache")
	_sync_oilrig_active_gate()


func _process(delta: float) -> void:
	super._process(delta)
	_rig_pulse += delta * 7.2
	var blink := 0.5 + 0.5 * sin(_rig_pulse)
	if _rig_active_mat != null:
		_rig_active_mat.albedo_color = Color(0.50, 0.24, 0.02, 0.95).lerp(
				Color(1.0, 0.98, 0.46, 1.0), blink)
	if _rig_active_halo_mat != null:
		_rig_active_halo_mat.albedo_color = Color(1.0, 0.52, 0.04, 0.12).lerp(
				Color(1.0, 0.96, 0.34, 0.96), blink)
	if _rig_active_halo != null and is_instance_valid(_rig_active_halo):
		_rig_active_halo.scale = Vector3.ONE * lerpf(0.96, 1.08, blink)
	if _rig_active_gate_idx >= 0 and _rig_gate_labels.has(_rig_active_gate_idx):
		var act_lbl := _rig_gate_labels[_rig_active_gate_idx] as Label3D
		if act_lbl != null and is_instance_valid(act_lbl):
			act_lbl.scale = Vector3.ONE * lerpf(0.94, 1.18, blink)
			act_lbl.modulate = Color(1.0, 0.58, 0.08, 0.92).lerp(
					Color(1.0, 0.99, 0.62, 1.0), blink)
	if _route_guide != null and is_instance_valid(_route_guide):
		_route_guide.call("set_pulse", blink)


func _hud_training_counts() -> Vector2i:
	return Vector2i(_rig_gates_passed.size(), maxi(_rig_gate_triggers.size(), 1))


func _hud_training_next_pos() -> Vector3:
	var m := _active_oilrig_gate_marker()
	return m.global_position if m != null else Vector3.ZERO


func _reset_custom_training_course() -> void:
	_rig_gates_passed.clear()
	_rig_next_order_pos = 0
	_rig_lap_start = -1.0
	_rig_has_spawn = false
	if _route_guide != null and is_instance_valid(_route_guide):
		_route_guide.call("clear_cache")
	_sync_oilrig_active_gate()
	call_deferred("_refresh_oilrig_route_after_sync")


func _hud_custom_training_target() -> Dictionary:
	var m := _active_oilrig_gate_marker()
	if m == null:
		return {}
	var total := maxi(_rig_ordered_indices.size(), 1)
	var passed := _rig_gates_passed.size()
	var step_num := mini(passed + 1, total)
	var tag := "START" if passed == 0 else ("FINISH" if step_num == total else _txt("ВОРОТА", "GATE"))
	return {
		"pos": m.global_position,
		"label": "%s %d/%d" % [tag, step_num, total],
	}


func _on_oilrig_gate_entered(body: Node3D, gate_idx: int) -> void:
	if body == null:
		return
	if not (body == get_node_or_null("Drone") or body.is_in_group("drone")):
		return
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	if _rig_gates_passed.is_empty():
		_rig_lap_start = now_s
	if _rig_gates_passed.has(gate_idx):
		return
	_rig_gates_passed[gate_idx] = true
	var ord_pos := _rig_ordered_indices.find(gate_idx)
	if ord_pos >= 0:
		_rig_next_order_pos = (ord_pos + 1) % maxi(_rig_ordered_indices.size(), 1)
	var passed := _rig_gates_passed.size()
	var total := maxi(_rig_gate_triggers.size(), 1)
	var elapsed := maxf(0.0, now_s - _rig_lap_start)
	_score += 50
	if Audio != null and Audio.has_method("play_radio_confirm_beep"):
		Audio.call("play_radio_confirm_beep", -9.0)
	Haptics.trigger_ui_tap()
	if passed >= total:
		if _rig_best_lap <= 0.0 or elapsed < _rig_best_lap:
			_rig_best_lap = elapsed
		if Global.has_method("record_training_result"):
			Global.call("record_training_result", "oilrig", elapsed, passed, total)
		var coin_note := ""
		if Progress != null and Progress.has_method("award_activity"):
			var c_awarded := int(Progress.call("award_activity", "training_oilrig", passed, elapsed, false))
			if c_awarded > 0:
				coin_note = " · +%d" % c_awarded
		_set_flash(_txt(
			"ВОРОТА %d/%d · КОЛО %.1fs · РЕКОРД %.1fs%s" % [passed, total, elapsed, _rig_best_lap, coin_note],
			"GATES %d/%d · LAP %.1fs · BEST %.1fs%s" % [passed, total, elapsed, _rig_best_lap, coin_note]
		))
		_rig_gates_passed.clear()
		_rig_next_order_pos = 0
		_rig_lap_start = now_s
	else:
		_set_flash(_txt("ВОРОТА %d/%d · %.1fs" % [passed, total, elapsed],
				"GATES %d/%d · %.1fs" % [passed, total, elapsed]))
	_sync_oilrig_active_gate()


func _spawn_vehicles() -> void:
	pass


func _spawn_frontline_bonus_targets() -> void:
	pass


func _spawn_special_or_campaign() -> void:
	pass


func _spawn_combat_mission(_mission_id: int) -> void:
	pass


func _spawn_kamikaze_drones() -> void:
	pass


func _start_reinforcements() -> void:
	pass
