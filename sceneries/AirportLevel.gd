extends "res://sceneries/BigLevel.gd"
## Покинутий аеропорт — ПОВНА паритетність з іншими картами.
## Успадковуємо весь BigLevel (місії, бойову систему, БЧ, льотну школу,
## РЕБ, погоду, HUD, треки, якість) і підміняємо лише географію карти.

const AIRPORT_GLB := "res://Assets/maps/abandoned_airport.glb"
const AIRPORT_LANDMARKS_GLB := "res://Assets/maps/airport_landmarks.glb"
const GATE_BIG := "res://tracks/gates/Gate_7x6_Simple.tscn"
const GATE_SMALL := "res://tracks/gates/Gate_5x5_Simple.tscn"
const TREE_OAK := "res://Assets/frontline/oak.glb"
const TREE_PINE := "res://Assets/frontline/pine.glb"
const VegAssetsScript := preload("res://scripts/util/vegetation_assets.gd")

const HIDDEN_DEC := ["DEC__M_Green", "DEC__M_Ground", "DEC__M_Hill",
	"DEC__M_Corrugated", "DEC__M_Rust", "DEC__M_Steel", "DEC__M_Concrete", "DEC__M_Rubber",
	"DEC__M_Yellow", "COL__M_Yellow", "DEC__M_Marking"]

var _grass_hide_attempts := 0
var _landmark_meshes_cache: Dictionary = {}




func _map_path() -> String:
	return AIRPORT_GLB


## Оновлюємо процедурні Voronoi-матеріали карти на повноцінні 2K Triplanar PBR
## (бетон, злітний асфальтобетон перону, гофрований метал ангарів, іржа, фарбована штукатурка).
func _apply_map_materials(node: Node) -> void:
	if node == null:
		return
	var tarmac_mat := (FrontlineTerrainScript._pbr("hall_concrete", Color(0.65, 0.64, 0.61), 0.06) as StandardMaterial3D).duplicate() as StandardMaterial3D
	tarmac_mat.uv1_triplanar = true
	tarmac_mat.uv1_world_triplanar = true
	tarmac_mat.uv1_scale = Vector3(0.06, 0.06, 0.06)
	tarmac_mat.roughness = 0.88
	var pbr_by_mesh := {
		"COL__M_Concrete": FrontlineTerrainScript._pbr("hall_concrete", Color(0.76, 0.74, 0.70), 0.16),
		"DEC__M_FarConc": FrontlineTerrainScript._pbr("hall_concrete", Color(0.72, 0.70, 0.66), 0.14),
		"COL__M_Tarmac": tarmac_mat,
		"DEC__M_Tarmac": tarmac_mat,
		"COL__M_Ground": tarmac_mat,
		"COL__M_Corrugated": FrontlineTerrainScript._pbr("steel", Color(0.64, 0.66, 0.68), 0.24),
		"COL__M_Rust": FrontlineTerrainScript._pbr("hall_rust", Color(0.70, 0.50, 0.38), 0.28),
		"COL__M_Steel": FrontlineTerrainScript._pbr("hall_metal", Color(0.62, 0.65, 0.68), 0.26),
		"COL__M_Paint": FrontlineTerrainScript._pbr("plaster", Color(0.74, 0.71, 0.65), 0.22),
		"DEC__M_Paint": FrontlineTerrainScript._pbr("plaster", Color(0.72, 0.69, 0.63), 0.22),
		"COL__M_Brick": FrontlineTerrainScript._pbr("brick", Color(0.68, 0.44, 0.36), 0.38),
		"DEC__M_Brick": FrontlineTerrainScript._pbr("brick", Color(0.68, 0.44, 0.36), 0.38),
		"COL__M_Wood": FrontlineTerrainScript._pbr("wood", Color(0.62, 0.48, 0.34), 0.32),
		"DEC__M_Wood": FrontlineTerrainScript._pbr("wood", Color(0.62, 0.48, 0.34), 0.32),
	}
	var all_meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, all_meshes)
	for mi in all_meshes:
		if mi.name in HIDDEN_DEC:
			mi.visible = false
			continue
		if pbr_by_mesh.has(mi.name):
			var pmat := pbr_by_mesh[mi.name] as Material
			if pmat != null:
				mi.material_override = pmat
				if mi.name in ["COL__M_Tarmac", "DEC__M_Tarmac", "COL__M_Ground"]:
					mi.set_meta("no_batch", true)


func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


var _airport_props_built := false


func _ensure_airport_props_built() -> void:
	if _airport_props_built:
		return
	_airport_props_built = true
	_hide_procedural_grass()
	_replace_trees()
	_spawn_detailed_props()
	_build_airport_historical_landmarks()
	_build_airport_freestyle_zones()


func _ready() -> void:
	# Карта 900×900 м — стандартні межі BigLevel (152/182 м) занадто тісні.
	MAP_GROUND_SAFE = 430.0
	MAP_FLIGHT_BOUND = 470.0
	MAP_AIR_SAFE = 450.0
	_ground_y = 0.12
	set_meta("disable_procedural_grass", true)
	_defer_loading_dismiss = true
	_defer_training_rings = true
	super._ready()
	_force_touch_mode()
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set("hover_assist", false)
		radio.set("test_throttle", -1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_connect_horizon_assist()
	_ensure_airport_props_built()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if Global.play_mode == Global.PlayMode.TRAINING and not Global.combat_training \
			and not _mission_finished:
		_spawn_training_rings()
	call_deferred("_dismiss_global_loading_overlay")


## Стартовий баррель BigLevel стоїть біля початку координат і ставить дрон
## нижче рівня нашого GLB-ґрунту. Для аеропорту використовуємо власну безпечну
## точку в повітрі над льотним полем.
func _place_drone_over_ground() -> void:
	_ground_y = 0.12
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var spawn_xform := Transform3D(Basis(), Vector3(0.0, 62.0, 255.0))
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		respawn.global_transform = spawn_xform
	d.global_transform = spawn_xform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	if d.has_method("reset_motion_history"):
		d.reset_motion_history()
	if d.flight_controller != null and d.flight_controller.has_method("reset"):
		d.flight_controller.reset()
	d.freeze = true
	var existing_model := d.get_node_or_null("DroneModel")
	if existing_model == null or int(existing_model.get_meta("preset_index", -1)) != Global.drone_preset:
		DroneCatalog.apply_to_drone(d, Global.drone_preset)
	else:
		_sync_fpv_drone_model(false, false, true)
	# Ми перевизначили _place_drone_over_ground, тому батьківський обробник ARM/respawn
	# підключаємо тут самі, інакше дрон лишається замороженим і респавн не скидає БК/ліміти.
	var fc = d.flight_controller
	if fc != null:
		if not fc.armed.is_connected(_on_airport_armed):
			fc.armed.connect(_on_airport_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


## Обробник ARM без примусової зміни режиму: BigLevel викликає
## restore_preferred_flight_mode(), який перезаписує вибір кнопкою режиму
## (HORIZON не зберігається як preferred). Тут просто знімаємо freeze,
## запускаємо місію й лишаємо режим, обраний пілотом.
func _connect_horizon_assist() -> void:
	var d := get_node_or_null("Drone")
	if d == null or d.flight_controller == null:
		return
	var armed = d.flight_controller.armed
	if not armed.is_connected(_on_airport_armed):
		armed.connect(_on_airport_armed)


func _on_airport_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d.freeze = false
		d.linear_velocity = Vector3.UP * 0.1
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	if not _mission_started and not _mission_finished:
		_start_mission()


## Трава BigLevel розрахована на процедурний height_field і на нашій карті
## висіла в повітрі — вимикаємо її повністю.
func _hide_procedural_grass() -> void:
	_grass_hide_attempts += 1
	for n in ["DenseGrassFoliage", "DenseGrassFar", "FollowGrass"]:
		var node := get_node_or_null(n)
		if node != null:
			node.visible = false
	# BigLevel створює частину трави відкладено — перестраховуємося кількома кадрами.
	if _grass_hide_attempts < 6:
		call_deferred("_hide_procedural_grass")


func _process(delta: float) -> void:
	super._process(delta)
	var d := get_node_or_null("Drone") as RigidBody3D
	var radio := get_node_or_null("RadioController")
	if d == null or radio == null or d.freeze:
		return
	var inp: Array = radio.get("input")
	if inp.is_empty():
		return
	var throttle: float = float(inp[0])  # input[0] = газ, [1]=йав, [2]=рол, [3]=пігч
	var fc = d.get("flight_controller")
	var armed := fc != null and bool(fc.get("state_armed"))
	# Газ 0 або двигуни вимкнені — гальмуємо ковзання біля землі.
	if (throttle <= 0.05 or not armed) and d.global_position.y < 15.0:
		var v := d.linear_velocity
		var flat := Vector2(v.x, v.z)
		if flat.length() > 0.05:
			var damped := flat * 0.80
			d.linear_velocity = Vector3(damped.x, v.y, damped.y)
		if d.global_position.y < 2.0 and flat.length() < 1.5:
			d.linear_velocity = Vector3(0.0, v.y, 0.0)


## На телефоні стіки мають працювати завжди, якщо немає активного ELRS-пульту.
func _force_touch_mode() -> void:
	var touch := get_node_or_null("/root/TouchControls")
	if touch == null or not bool(touch.get("enabled")):
		return
	# Якщо пульт (ELRS Wi-Fi) активний — НЕ перемикаємо на сенсор, інакше
	# TouchControls перехоплює ввід і пульт «відвалюється».
	var wifi := get_node_or_null("/root/ElrsWifiInput")
	var elrs_ok := wifi != null and (bool(wifi.get("valid"))
			or bool(wifi.call("was_recently_active", 20000)))
	if elrs_ok:
		if bool(touch.get("touch_mode")):
			touch.call("set_controller_only", true)
		return
	if OS.get_name() == "iOS" or OS.has_environment("TOUCH_CONTROLS"):
		touch.call("set_controller_only", false)


# Наш GLB має власну плоску поверхню y≈0.1; процедурний height_at для
# "airport" повертає хибні висоти — через це техніка й піхота були під/над ґрунтом.
func _find_ground_y(_x: float, _z: float) -> float:
	return 0.12


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.14,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _replace_trees() -> void:
	var found: Array[MeshInstance3D] = []
	var root := get_node_or_null("MapRoot")
	if root != null:
		_find_dec_mesh(root, found)
	for m in found:
		if m.name == "COL__M_Ground":
			# Беремо той самий PBR матеріал, що й у льотного поля, — межі не буде видно.
			var tarmac := _find_named_mesh(get_node_or_null("MapRoot"), "COL__M_Tarmac")
			var mat: Material = null
			if tarmac != null:
				mat = tarmac.material_override
				if mat == null and tarmac.mesh != null and tarmac.mesh.get_surface_count() > 0:
					mat = tarmac.mesh.surface_get_material(0)
			if mat != null:
				m.material_override = mat
			continue
		# DEC__M_Ground — схил із «травою», DEC__M_Green — конус-дерева,
		# DEC__M_Hill — штучна темна смуга на обрії.
		m.visible = false
	var oak := load(TREE_OAK) as PackedScene
	var pine := load(TREE_PINE) as PackedScene
	if oak == null and pine == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var oak_xforms: Array[Transform3D] = []
	var pine_xforms: Array[Transform3D] = []
	var q := QualityManagerScript.get_active_level()
	var tree_count := 48 if q == QualityManagerScript.Level.LOW else (110 if q == QualityManagerScript.Level.MEDIUM else 150)
	for i in range(tree_count):
		var use_pine := ((i % 3 != 0) if q == QualityManagerScript.Level.LOW else (i % 3 == 0)) and pine != null
		if oak == null:
			use_pine = pine != null
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(220.0, 560.0)
		var x := cos(a) * r
		var z := sin(a) * r
		var yaw := rng.randf_range(0.0, TAU)
		var s := rng.randf_range(0.85, 1.35)
		if _is_in_reserved_corridor(x, z):
			continue
		var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, 0.05, z))
		if use_pine:
			pine_xforms.append(xf)
		else:
			oak_xforms.append(xf)
	var veg_range := float(QualityManagerScript.get_value("veg_range", 560.0))
	var tree_shadows := QualityManagerScript.get_active_level() >= QualityManagerScript.Level.HIGH
	var veg_trees: Array[Dictionary] = VegAssetsScript.trees()
	var oak_entry: Dictionary = {}
	var pine_entry: Dictionary = {}
	for t_entry in veg_trees:
		if bool(t_entry.get("pine", false)):
			if pine_entry.is_empty():
				pine_entry = t_entry
		else:
			if oak_entry.is_empty():
				oak_entry = t_entry
	if not oak_entry.is_empty() and not pine_entry.is_empty():
		_batch_veg_tree_entry(oak_entry, "AirportOak", oak_xforms, tree_shadows, veg_range)
		_batch_veg_tree_entry(pine_entry, "AirportPine", pine_xforms, tree_shadows, veg_range)
	else:
		_batch_tree_group(oak, "AirportOak", oak_xforms, tree_shadows, veg_range)
		_batch_tree_group(pine, "AirportPine", pine_xforms, tree_shadows, veg_range)
	var all_trees: Array[Transform3D] = []
	all_trees.append_array(oak_xforms)
	all_trees.append_array(pine_xforms)
	_add_airport_tree_colliders(all_trees)


func _batch_veg_tree_entry(entry: Dictionary, label: String,
		xforms: Array[Transform3D], cast_shadows: bool, veg_range: float) -> void:
	if xforms.is_empty():
		return
	var part_keys := ["trunk", "leaves"]
	for p_idx in range(part_keys.size()):
		var mesh := entry.get(part_keys[p_idx]) as Mesh
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_MM_%d" % [label, p_idx]
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = veg_range
		mmi.visibility_range_end_margin = 60.0
		add_child(mmi)


func _batch_tree_group(packed: PackedScene, label: String,
		xforms: Array[Transform3D], cast_shadows: bool, veg_range: float) -> void:
	if packed == null or xforms.is_empty():
		return
	var tmpl := packed.instantiate() as Node3D
	if tmpl == null:
		return
	var parts: Array[Dictionary] = []
	_collect_tree_visual_parts(tmpl, Transform3D.IDENTITY, parts)
	for p_idx in range(parts.size()):
		var part: Dictionary = parts[p_idx]
		var mesh := part["mesh"] as Mesh
		var rel_xf: Transform3D = part["rel_xf"]
		var mat := part.get("mat") as Material
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xforms.size()
		for i in range(xforms.size()):
			mm.set_instance_transform(i, xforms[i] * rel_xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_MM_%d" % [label, p_idx]
		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = veg_range
		mmi.visibility_range_end_margin = 60.0
		add_child(mmi)
	tmpl.free()


func _collect_tree_visual_parts(node: Node, parent_xf: Transform3D,
		out: Array[Dictionary]) -> void:
	if node == null or node is StaticBody3D:
		return
	var cur_xf := parent_xf * (node as Node3D).transform if node is Node3D else parent_xf
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var lname := String(mi.name).to_lower()
		if mi.mesh != null and not lname.contains("-col") and not lname.contains("-convcol"):
			var mesh_copy := mi.mesh.duplicate() as Mesh
			for s in range(mi.mesh.get_surface_count()):
				var surf_mat := mi.get_surface_override_material(s)
				if surf_mat != null:
					mesh_copy.surface_set_material(s, surf_mat)
			out.append({
				"mesh": mesh_copy,
				"rel_xf": cur_xf,
				"mat": mi.material_override,
			})
	for c in node.get_children():
		_collect_tree_visual_parts(c, cur_xf, out)


func _add_airport_tree_colliders(xforms: Array[Transform3D]) -> void:
	var cells: Dictionary = {}
	for xf in xforms:
		var s := xf.basis.get_scale().x
		var cell := Vector2i(int(floor(xf.origin.x / 128.0)), int(floor(xf.origin.z / 128.0)))
		if not cells.has(cell):
			cells[cell] = [] as Array[Vector3]
		var faces: Array[Vector3] = cells[cell]
		var centre := xf.origin + Vector3(0.0, 2.5 * s, 0.0)
		var half := Vector3(0.38 * s, 2.5 * s, 0.38 * s)
		_append_box_faces(faces, centre, half)
	for cell in cells.keys():
		var faces: Array[Vector3] = cells[cell]
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(PackedVector3Array(faces))
		var body := StaticBody3D.new()
		body.name = "AirportTreeCol_%d_%d" % [cell.x, cell.y]
		body.collision_layer = 1
		body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)


func _append_box_faces(faces: Array[Vector3], centre: Vector3, half: Vector3) -> void:
	var p := [
		centre + Vector3(-half.x, -half.y, -half.z),
		centre + Vector3(half.x, -half.y, -half.z),
		centre + Vector3(half.x, half.y, -half.z),
		centre + Vector3(-half.x, half.y, -half.z),
		centre + Vector3(-half.x, -half.y, half.z),
		centre + Vector3(half.x, -half.y, half.z),
		centre + Vector3(half.x, half.y, half.z),
		centre + Vector3(-half.x, half.y, half.z),
	]
	for tri in [
		[0, 1, 2], [0, 2, 3], [5, 4, 7], [5, 7, 6],
		[4, 0, 3], [4, 3, 7], [1, 5, 6], [1, 6, 2],
		[3, 2, 6], [3, 6, 7], [4, 5, 1], [4, 1, 0],
	]:
		faces.append(p[tri[0]])
		faces.append(p[tri[1]])
		faces.append(p[tri[2]])


## Деталізовані пропси з бібліотеки основного проєкту замість наших
## примітивних коробок. spawn_prop сам дає кожному пропсу колізію.
func _spawn_detailed_props() -> void:
	var assets = load("res://scripts/util/frontline_assets.gd")
	if assets == null:
		return
	var names := ["prop_barrel", "prop_crate", "prop_pallet", "prop_tires",
		"prop_fuel_tank", "prop_barrier", "prop_generator", "prop_pipe",
		"prop_sandbags", "prop_sign", "prop_antenna", "prop_car_wreck"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	var spawned := 0
	var prop_count := 44 if QualityManagerScript.get_active_level() == QualityManagerScript.Level.LOW else 96
	for i in range(prop_count):
		var nm: String = str(names[i % names.size()])
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(25.0, 390.0)
		var x := cos(a) * r
		var z := sin(a) * r
		if Vector2(x, z).distance_to(Vector2(0.0, 255.0)) < 45.0:
			continue
		if _is_in_reserved_corridor(x, z, 4.0):
			continue
		var prop = assets.spawn_prop(self, nm, Vector3(x, 0.12, z),
				rng.randf_range(0.0, TAU), rng.randf_range(0.85, 1.25))
		if prop != null:
			prop.name = "DetailedProp%d" % i
			# spawn_prop дає convex-hull колізію — у тонких антен/знаків вона
			# затовста, тому замінюємо її на вузький BoxShape3D замість видалення.
			if nm == "prop_antenna" or nm == "prop_sign":
				for c in prop.get_children():
					if c is StaticBody3D:
						for cs in c.get_children():
							if cs is CollisionShape3D:
								var box_s := BoxShape3D.new()
								var h := 2.2
								var cen := Vector3(0.0, 1.1, 0.0)
								if prop is MeshInstance3D and (prop as MeshInstance3D).mesh != null:
									var ab := (prop as MeshInstance3D).mesh.get_aabb()
									h = maxf(ab.size.y * 0.92, 1.6)
									cen = ab.get_center()
								box_s.size = Vector3(0.45, h, 0.45)
								(cs as CollisionShape3D).shape = box_s
								(cs as CollisionShape3D).position = cen
			spawned += 1
	print("[Airport] detailed props: ", spawned)


## Mission props and trees are spawned *after* the escort route is planned,
## so they must honour the same reserved corridor the planner used.
func _is_in_reserved_corridor(x: float, z: float, pad: float = 0.0) -> bool:
	var route: Array[Vector3] = get("_reserved_ground_route")
	if route.size() < 2:
		return false
	var p := Vector2(x, z)
	var need := RESERVED_ROUTE_CLEARANCE + pad
	for i in range(route.size() - 1):
		var a := Vector2(route[i].x, route[i].z)
		var ab := Vector2(route[i + 1].x, route[i + 1].z) - a
		if ab.length_squared() < 0.01:
			continue
		var u := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * u) <= need:
			return true
	return false


func _find_named_mesh(node: Node, target: String) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D and node.name == target:
		return node
	for c in node.get_children():
		var found := _find_named_mesh(c, target)
		if found != null:
			return found
	return null


func _find_dec_mesh(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node.name in HIDDEN_DEC or node.name == "COL__M_Ground"):
		out.append(node)
	for c in node.get_children():
		_find_dec_mesh(c, out)


func _load_map() -> void:
	super._load_map()
	_build_airport_collision()
	_spawn_airport_gates()
	_apply_airport_grade()


## Замість процедурної фронтової/local_procedural карти — наш GLB уже містить
## усі будівлі, техніку й перешкоди. Але місії/тренування/школа лишаються.
func _build_frontline_props() -> void:
	var d := get_node_or_null("Drone") as Drone
	if Global.play_mode == Global.PlayMode.COMBAT:
		_spawn_special_or_campaign()
		_start_reinforcements()
		_ensure_airport_props_built()
	else:
		_ensure_airport_props_built()
	if Global.play_mode == Global.PlayMode.TRAINING:
		if Global.combat_training:
			_combat_training = CombatTrainingScript.new()
			add_child(_combat_training)
			_combat_training.initialize(self, d, _ground_y)
		else:
			_queue_training_ring_spawn()
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		_flight_school = FlightSchool.new()
		add_child(_flight_school)
		_flight_school.initialize(self, d, _ground_y)


func _tune_map_environment() -> void:
	super._tune_map_environment()
	_apply_airport_grade()


func _apply_airport_grade() -> void:
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.fog_enabled = true
		env.fog_light_color = Color(0.74, 0.67, 0.57, 1.0)
		env.fog_density = 0.00055
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.20
		env.ambient_light_energy = 0.96
		env.ambient_light_sky_contribution = 0.76
		env.background_energy_multiplier = 1.04
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.06
		env.adjustment_contrast = 1.04
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.rotation_degrees = Vector3(-38.0, -28.0, 12.0)
		sun.light_color = Color(1.0, 0.86, 0.72, 1.0)
		sun.light_energy = 3.05
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill != null:
		fill.light_energy = 0.56


func _build_airport_collision() -> void:
	var t0 := Time.get_ticks_usec()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(get_node_or_null("MapRoot"), meshes)
	var flat_dec := ["DEC__M_Marking", "DEC__M_Oil", "DEC__M_Yellow",
		"DEC__M_Glass", "DEC__M_Paint", "DEC__M_FarConc"]
	var flat_floor_names := ["COL__M_Ground", "COL__M_Tarmac", "DEC__M_Tarmac"]
	var flat_surface_names := ["COL__M_Paint", "COL__M_Glass"]
	var solid_cells: Dictionary = {}
	var flat_cells: Dictionary = {}
	var has_floor := false
	for mi in meshes:
		if mi.name in HIDDEN_DEC or mi.name == "COL__M_Glass":
			continue
		if mi.name in ["DEC__M_Hill", "DEC__M_FarHill", "DEC__M_FarConc",
			"DEC__M_Green", "DEC__M_Ground"]:
			mi.cast_shadow = MeshInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.name.begins_with("DEC__") and (mi.name in HIDDEN_DEC or mi.name in flat_dec):
			continue
		if not mi.name.begins_with("COL__") and not mi.name.begins_with("DEC__"):
			continue
		if mi.name in flat_floor_names:
			has_floor = true
			continue
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		var faces := mesh.get_faces()
		if faces.is_empty():
			continue
		var xf := mi.global_transform
		var target_cells := flat_cells if mi.name in flat_surface_names else solid_cells
		var tri_count := faces.size() / 3
		for t in range(tri_count):
			var idx := t * 3
			var v0 := xf * faces[idx]
			var v1 := xf * faces[idx + 1]
			var v2 := xf * faces[idx + 2]
			var cx := (v0.x + v1.x + v2.x) / 3.0
			var cz := (v0.z + v1.z + v2.z) / 3.0
			var cell := Vector2i(int(floor(cx / 128.0)), int(floor(cz / 128.0)))
			if not target_cells.has(cell):
				target_cells[cell] = PackedVector3Array()
			var bucket: PackedVector3Array = target_cells[cell]
			bucket.append(v0)
			bucket.append(v1)
			bucket.append(v2)
			target_cells[cell] = bucket
	var built := 0
	if has_floor:
		var floor_body := StaticBody3D.new()
		floor_body.name = "Collision_COL__M_Tarmac"
		floor_body.collision_layer = 1
		floor_body.collision_mask = 1
		var box := BoxShape3D.new()
		box.size = Vector3(2200.0, 2.0, 2200.0)
		var fcs := CollisionShape3D.new()
		fcs.shape = box
		floor_body.add_child(fcs)
		add_child(floor_body)
		floor_body.global_position = Vector3(0.0, -0.88, 0.0)
		built += 1
	built += _emit_collision_cells(solid_cells, "Collision_AirportCell")
	built += _emit_collision_cells(flat_cells, "Collision_COL__M_Paint_Cell")
	print("[Airport] collision bodies: ", built, " (",
			"%.1f ms)" % [(Time.get_ticks_usec() - t0) / 1000.0])


func _emit_collision_cells(cells: Dictionary, prefix: String) -> int:
	var count := 0
	for cell in cells.keys():
		var faces: PackedVector3Array = cells[cell]
		if faces.is_empty():
			continue
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var body := StaticBody3D.new()
		body.name = "%s_%d_%d" % [prefix, cell.x, cell.y]
		body.collision_layer = 1
		body.collision_mask = 1
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		add_child(body)
		count += 1
	return count


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _spawn_airport_gates() -> void:
	# Old decorative FreestyleGate nodes are removed in freestyle: BigLevel now
	# builds real neon checkpoints at the hangar arches and landmark facades.
	if Global.play_mode == Global.PlayMode.TRAINING and not Global.combat_training:
		return
	var gates := [
		[Vector3(-150, 6, 90), 0.0], [Vector3(-90, 9, 40), 0.2],
		[Vector3(-30, 7, -20), -0.3], [Vector3(30, 10, -70), 0.35],
		[Vector3(90, 8, -120), -0.2], [Vector3(150, 12, -170), 0.5],
		[Vector3(210, 7, -215), 0.1], [Vector3(-200, 9, -150), 0.7],
		[Vector3(-120, 8, -220), -0.4], [Vector3(60, 11, 150), 0.25],
		[Vector3(250, 10, 60), -0.6], [Vector3(-260, 7, 30), 0.15],
	]
	for i in gates.size():
		var path := GATE_BIG if i % 3 == 0 else GATE_SMALL
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var gate := packed.instantiate()
		gate.name = "FreestyleGate%d" % i
		add_child(gate)
		gate.global_position = gates[i][0]
		gate.global_rotation.y = float(gates[i][1])


var _landmark_box_mesh: BoxMesh = null
var _landmark_cyl_mesh: CylinderMesh = null


func _get_landmark_box_mesh() -> BoxMesh:
	if _landmark_box_mesh == null:
		_landmark_box_mesh = BoxMesh.new()
		_landmark_box_mesh.size = Vector3.ONE
	return _landmark_box_mesh


func _get_landmark_cyl_mesh() -> CylinderMesh:
	if _landmark_cyl_mesh == null:
		_landmark_cyl_mesh = CylinderMesh.new()
		_landmark_cyl_mesh.top_radius = 1.0
		_landmark_cyl_mesh.bottom_radius = 1.0
		_landmark_cyl_mesh.height = 1.0
		_landmark_cyl_mesh.radial_segments = 12
		_landmark_cyl_mesh.rings = 1
	return _landmark_cyl_mesh


func _append_box_to_st(st: SurfaceTool, center: Vector3, size: Vector3,
		rot: Vector3 = Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(rot).scaled(size), center)
	st.append_from(_get_landmark_box_mesh(), 0, xf)


func _append_cyl_to_st(st: SurfaceTool, center: Vector3, radius: float,
		height: float, rot: Vector3 = Vector3.ZERO) -> void:
	var xf := Transform3D(Basis.from_euler(rot).scaled(Vector3(radius, height, radius)), center)
	st.append_from(_get_landmark_cyl_mesh(), 0, xf)


func _commit_st_mesh(parent: Node3D, node_name: String, st: SurfaceTool,
		mat: Material, cast_shadows: bool = true) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh == null:
		return null
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 1100.0
	mi.visibility_range_end_margin = 80.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


func _tag_airport_landmark(node: Node3D, id: String) -> void:
	if node == null:
		return
	node.add_to_group("map_signature_landmark")
	node.set_meta("landmark_id", id)


func _pick_clear_airport_landmark_pos(base: Vector2, radius: float) -> Vector3:
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	var units: Array[Vector2] = []
	for gname in ["enemies", "friendly_convoy"]:
		for u in get_tree().get_nodes_in_group(gname):
			if u is Node3D:
				var up := (u as Node3D).global_position
				units.append(Vector2(up.x, up.z))
	for ring in range(0, 8):
		var r := float(ring) * 26.0
		var steps := 1 if ring == 0 else 12
		for i in range(steps):
			var ang := TAU * float(i) / float(steps) + float(ring) * 0.35
			var cand := base + Vector2(cos(ang), sin(ang)) * r
			if absf(cand.x) > 375.0 or absf(cand.y) > 345.0:
				continue
			if cand.distance_to(Vector2(0.0, 255.0)) < 54.0:
				continue
			if _is_in_reserved_corridor(cand.x, cand.y, radius + 8.0):
				continue
			var unit_conflict := false
			for up2 in units:
				if cand.distance_to(up2) < radius + 16.0:
					unit_conflict = true
					break
			if unit_conflict:
				continue
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(
						Vector3(cand.x, 45.0, cand.y), Vector3(cand.x, 0.8, cand.y))
				q.collision_mask = 1
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					continue
			return Vector3(cand.x, _ground_y, cand.y)
	return Vector3(base.x, _ground_y, base.y)


func _get_airport_landmark_mesh(mesh_name: String) -> Mesh:
	if _landmark_meshes_cache.is_empty():
		var packed := load(AIRPORT_LANDMARKS_GLB) as PackedScene
		if packed != null:
			var inst := packed.instantiate()
			if inst != null:
				var found_mi: Array[MeshInstance3D] = []
				_collect_meshes(inst, found_mi)
				for mi in found_mi:
					if mi.mesh != null:
						_landmark_meshes_cache[String(mi.name)] = mi.mesh.duplicate()
				inst.free()
	return _landmark_meshes_cache.get(mesh_name) as Mesh


func _make_airport_mat(albedo: Color, rough: float = 0.86,
		metal: float = 0.08, unshaded: bool = false,
		pbr_kind: String = "hall_concrete", use_vcol: bool = false) -> StandardMaterial3D:
	if not unshaded:
		var base_pbr := FrontlineTerrainScript._pbr(pbr_kind, albedo, 0.24)
		if base_pbr != null:
			var pm := base_pbr.duplicate() as StandardMaterial3D
			pm.uv1_triplanar = true
			pm.uv1_world_triplanar = true
			if use_vcol:
				# Keep PBR normal/roughness/AO relief while letting baked vertex colors + AO drive albedo cleanly.
				pm.albedo_texture = null
				pm.albedo_color = Color(1.04, 1.03, 1.01) if albedo == Color.WHITE or (albedo.r > 0.99 and albedo.g > 0.99 and albedo.b > 0.99) else albedo
			else:
				pm.albedo_color = albedo
			pm.roughness = rough
			pm.metallic = metal
			pm.metallic_specular = 0.28
			pm.vertex_color_use_as_albedo = use_vcol
			return pm
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.25
	m.vertex_color_use_as_albedo = use_vcol
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _add_sculpted_landmark_mesh(parent: Node3D, node_name: String,
		mesh: Mesh, mat: Material, cast_shadows: bool = true) -> MeshInstance3D:
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 1100.0
	mi.visibility_range_end_margin = 80.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


## 5 фірмових історичних орієнтирів аеропорту (ЗПС з розміткою, руїни диспетчерської
## вежі, паливний термінал, вантажний контейнерний двір, зруйнований ангар з літаками).
## Використовує деталізовані Blender-меші з airport_landmarks.glb + 2K Triplanar PBR.
func _build_airport_historical_landmarks() -> void:
	if get_node_or_null("AirportLandmark_RunwayStrip") != null:
		return
	var mat_white := _make_airport_mat(Color(0.86, 0.85, 0.80), 0.92, 0.0, false, "hall_concrete", false)
	var mat_yellow := _make_airport_mat(Color(0.86, 0.68, 0.18), 0.90, 0.0, false, "hall_concrete", false)
	var mat_concrete := _make_airport_mat(Color(0.72, 0.70, 0.66), 0.90, 0.04, false, "hall_concrete", false)
	var mat_tower_vcol := _make_airport_mat(Color(1.06, 1.05, 1.02), 0.86, 0.08, false, "hall_concrete", true)
	var mat_depot_vcol := _make_airport_mat(Color(1.06, 1.05, 1.02), 0.76, 0.24, false, "hall_metal", true)
	var mat_hangar_vcol := _make_airport_mat(Color(1.06, 1.06, 1.08), 0.74, 0.34, false, "hall_metal", true)
	var mat_aircraft_vcol := _make_airport_mat(Color(1.08, 1.10, 1.12), 0.70, 0.30, false, "hall_metal", true)
	var mat_edge_vcol := _make_airport_mat(Color(1.10, 1.06, 0.90), 0.65, 0.20, false, "hall_metal", true)

	# 1. Злітно-посадкова смуга 09/27 + руліжні доріжки + вертолітні майданчики перону
	var runway := Node3D.new()
	runway.name = "AirportLandmark_RunwayStrip"
	runway.position = Vector3(0.0, _ground_y + 0.025, -180.0)
	add_child(runway)
	_tag_airport_landmark(runway, "airport_runway_strip")

	var st_white := SurfaceTool.new()
	st_white.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		var tx: float = side * 325.0
		for b in range(-4, 4):
			var tz := (float(b) + 0.5) * 3.4
			_append_box_to_st(st_white, Vector3(tx, 0.01, tz), Vector3(22.0, 0.02, 1.6))
		for aim_s in [-1.0, 1.0]:
			_append_box_to_st(st_white, Vector3(side * 245.0, 0.01, aim_s * 8.5),
					Vector3(34.0, 0.02, 4.0))
	for d in range(-10, 11):
		_append_box_to_st(st_white, Vector3(float(d) * 20.0, 0.01, 0.0),
				Vector3(11.0, 0.02, 0.85))
	_commit_st_mesh(runway, "RunwayMarkingsWhite", st_white, mat_white, false)

	var st_yellow := SurfaceTool.new()
	st_yellow.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_box_to_st(st_yellow, Vector3(0.0, 0.010, 82.0), Vector3(520.0, 0.02, 0.45))
	for turn_x in [-180.0, 0.0, 180.0]:
		_append_box_to_st(st_yellow, Vector3(turn_x, 0.015, 41.0),
				Vector3(0.45, 0.02, 82.0), Vector3(0.0, 0.22, 0.0))
	for h_x in [-130.0, 0.0, 130.0]:
		var hz := 118.0
		_append_box_to_st(st_yellow, Vector3(h_x - 3.2, 0.010, hz), Vector3(0.9, 0.02, 7.6))
		_append_box_to_st(st_yellow, Vector3(h_x + 3.2, 0.010, hz), Vector3(0.9, 0.02, 7.6))
		_append_box_to_st(st_yellow, Vector3(h_x, 0.010, hz), Vector3(5.4, 0.02, 0.9))
	_commit_st_mesh(runway, "TaxiwayApronYellow", st_yellow, mat_yellow, false)

	var edge_mm := MultiMesh.new()
	edge_mm.transform_format = MultiMesh.TRANSFORM_3D
	var edge_mesh := _get_airport_landmark_mesh("RunwayEdgeLight")
	if edge_mesh == null:
		var light_box := BoxMesh.new()
		light_box.size = Vector3(0.35, 0.42, 0.35)
		edge_mesh = light_box
	edge_mm.mesh = edge_mesh
	var light_xfs: Array[Transform3D] = []
	for side_z in [-21.0, 21.0]:
		for i in range(-9, 10):
			light_xfs.append(Transform3D(Basis.IDENTITY,
					Vector3(float(i) * 34.0, 0.0, side_z)))
	edge_mm.instance_count = light_xfs.size()
	for i in range(light_xfs.size()):
		edge_mm.set_instance_transform(i, light_xfs[i])
	var edge_mmi := MultiMeshInstance3D.new()
	edge_mmi.name = "RunwayEdgeLights_MM"
	edge_mmi.multimesh = edge_mm
	edge_mmi.material_override = mat_edge_vcol
	edge_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge_mmi.visibility_range_end = 700.0
	runway.add_child(edge_mmi)

	# 2. Руїни диспетчерської вежі (Control Tower Ruins)
	var tower_pos := _pick_clear_airport_landmark_pos(Vector2(-285.0, 175.0), 14.0)
	var tower := Node3D.new()
	tower.name = "AirportLandmark_ControlTowerRuins"
	tower.position = tower_pos
	add_child(tower)
	_tag_airport_landmark(tower, "airport_control_tower_ruins")

	var tower_mesh := _get_airport_landmark_mesh("ControlTowerRuins")
	if tower_mesh != null:
		_add_sculpted_landmark_mesh(tower, "TowerConcrete", tower_mesh, mat_tower_vcol, true)
	# Segmented colliders so the octagonal ATC cab (y = 19.8..23.4 m) has open fly-through windows on all 8 faces
	_add_airport_landmark_collider(tower, Vector3(0.0, 3.85, 0.0), Vector3(9.6, 7.7, 9.6))
	_add_airport_landmark_collider(tower, Vector3(0.0, 13.7, 0.0), Vector3(6.8, 12.1, 6.8))
	_add_airport_landmark_collider(tower, Vector3(0.0, 19.35, 0.0), Vector3(10.4, 0.85, 10.4))
	_add_airport_landmark_collider(tower, Vector3(0.0, 26.0, 0.0), Vector3(10.4, 5.2, 10.4))
	for mi in range(8):
		var mang := float(mi) * TAU / 8.0
		_add_airport_landmark_collider(tower, Vector3(cos(mang) * 4.65, 21.55, -sin(mang) * 4.65),
				Vector3(0.32, 3.85, 0.32))
	FrontlineTerrainScript.register_structure_exclusion(
			Vector2(tower_pos.x, tower_pos.z), Vector2(6.5, 6.5), 29.0)

	# 3. Паливний термінал ПММ (Aviation Fuel Depot)
	var depot_pos := _pick_clear_airport_landmark_pos(Vector2(295.0, 165.0), 16.0)
	var depot := Node3D.new()
	depot.name = "AirportLandmark_FuelDepot"
	depot.position = depot_pos
	add_child(depot)
	_tag_airport_landmark(depot, "airport_fuel_depot")

	var depot_mesh := _get_airport_landmark_mesh("FuelDepot")
	if depot_mesh != null:
		var depot_mi := _add_sculpted_landmark_mesh(depot, "FuelDepotCisterns",
				depot_mesh, mat_depot_vcol, true)
		# An exact trimesh keeps the passages between / above the cisterns open.
		_add_trimesh_collider_to_mesh(depot_mi)
	FrontlineTerrainScript.register_structure_exclusion(
			Vector2(depot_pos.x, depot_pos.z), Vector2(13.0, 9.0), 6.0)

	# 4. Вантажний контейнерний двір (Cargo Container Yard з каньйоном для прольоту)
	var yard_pos := _pick_clear_airport_landmark_pos(Vector2(-290.0, -145.0), 18.0)
	var yard := Node3D.new()
	yard.name = "AirportLandmark_CargoContainerYard"
	yard.position = yard_pos
	add_child(yard)
	_tag_airport_landmark(yard, "airport_cargo_containers")

	var st_yd_pad := SurfaceTool.new()
	st_yd_pad.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append_box_to_st(st_yd_pad, Vector3(0.0, 0.16, 0.0), Vector3(26.0, 0.32, 22.0))
	_commit_st_mesh(yard, "ContainerYardPad", st_yd_pad, mat_concrete, false)

	var cont_mesh := _get_airport_landmark_mesh("CargoContainer")
	if cont_mesh == null:
		var cont_box := BoxMesh.new()
		cont_box.size = Vector3(6.2, 2.6, 2.5)
		cont_mesh = cont_box
	var cont_mat := _make_airport_mat(Color.WHITE, 0.78, 0.26, false, "steel", true)
	var palette: Array[Color] = [
		Color(0.32, 0.40, 0.28),
		Color(0.58, 0.26, 0.19),
		Color(0.24, 0.38, 0.52),
		Color(0.62, 0.50, 0.24),
	]
	var cont_xfs: Array[Transform3D] = []
	var cont_cols: Array[Color] = []
	for side_z in [-6.5, 6.5]:
		for slot_x in [-6.8, 0.0, 6.8]:
			var tiers := 2 if absf(slot_x) < 1.0 or side_z < 0.0 else 1
			for tier in range(tiers):
				var yaw := 0.04 * float(tier) * signf(side_z)
				var pos := Vector3(slot_x, 0.32 + 1.3 + float(tier) * 2.62, side_z)
				cont_xfs.append(Transform3D(Basis(Vector3.UP, yaw), pos))
				cont_cols.append(palette[(cont_xfs.size() + tier) % palette.size()])
	var cont_mm := MultiMesh.new()
	cont_mm.transform_format = MultiMesh.TRANSFORM_3D
	cont_mm.use_colors = true
	cont_mm.mesh = cont_mesh
	cont_mm.instance_count = cont_xfs.size()
	for i in range(cont_xfs.size()):
		cont_mm.set_instance_transform(i, cont_xfs[i])
		cont_mm.set_instance_color(i, cont_cols[i])
	var cont_mmi := MultiMeshInstance3D.new()
	cont_mmi.name = "CargoContainers_MM"
	cont_mmi.multimesh = cont_mm
	cont_mmi.material_override = cont_mat
	cont_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	cont_mmi.visibility_range_end = 950.0
	yard.add_child(cont_mmi)
	_add_airport_landmark_collider(yard, Vector3(0.0, 2.8, -6.5), Vector3(20.5, 5.4, 3.0))
	_add_airport_landmark_collider(yard, Vector3(0.0, 2.8, 6.5), Vector3(20.5, 5.4, 3.0))
	FrontlineTerrainScript.register_structure_exclusion(
			Vector2(yard_pos.x, yard_pos.z), Vector2(12.5, 10.0), 6.0)

	# 5. Зруйнований ангар та остови транспортних літаків (Hangar & Aircraft Wrecks)
	var wrecks_pos := _pick_clear_airport_landmark_pos(Vector2(285.0, -145.0), 22.0)
	var wrecks := Node3D.new()
	wrecks.name = "AirportLandmark_HangarAircraftWrecks"
	wrecks.position = wrecks_pos
	add_child(wrecks)
	_tag_airport_landmark(wrecks, "airport_hangar_aircraft_wrecks")

	var hangar_mesh := _get_airport_landmark_mesh("RuinedHangarFrame")
	if hangar_mesh != null:
		var hangar_mi := _add_sculpted_landmark_mesh(wrecks, "RuinedHangarFrame",
				hangar_mesh, mat_hangar_vcol, true)
		_add_trimesh_collider_to_mesh(hangar_mi)

	var aircraft_mesh := _get_airport_landmark_mesh("AircraftWreck")
	if aircraft_mesh != null:
		var st_planes := SurfaceTool.new()
		st_planes.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p_spec in [
			[Vector3(-5.5, 0.0, -3.5), 0.18],
			[Vector3(6.2, 0.0, 4.5), -0.28],
		]:
			var p_off: Vector3 = p_spec[0]
			var yaw: float = float(p_spec[1])
			var xf := Transform3D(Basis(Vector3.UP, yaw), p_off)
			st_planes.append_from(aircraft_mesh, 0, xf)
		var bodies_mi := _commit_st_mesh(wrecks, "RuinedAircraftBodies",
				st_planes, mat_aircraft_vcol, true)
		_add_trimesh_collider_to_mesh(bodies_mi)
	FrontlineTerrainScript.register_structure_exclusion(
			Vector2(wrecks_pos.x, wrecks_pos.z), Vector2(15.5, 13.5), 12.5)


## Aviation / airfield-themed freestyle flow zones across the open apron and
## field sectors.  Each site is verified by _pick_clear_airport_landmark_pos
## (spawn, runway corridor, units and existing colliders) and anchored at
## _ground_y - 0.15 so foundations sit flush in the tarmac.  Exclusions keep
## later world-detail passes from growing through the fly-through structures.
func _build_airport_freestyle_zones() -> void:
	if get_node_or_null("AirportFreestyleZones") != null:
		return
	var ms = load("res://scripts/util/military_structures.gd")
	if ms == null:
		return
	var zones := Node3D.new()
	zones.name = "AirportFreestyleZones"
	add_child(zones)

	var specs: Array = [
		# [anchor, footprint radius, builder name, id]
		[Vector2(-165.0, -75.0), 16.0, "build_fpv_slalom_gate_course", "slalom"],
		[Vector2(165.0, -75.0), 18.0, "build_fortified_helipad_hangar", "helipad"],
		[Vector2(-165.0, 90.0), 16.0, "build_pipeline_powerloop_arch", "powerloop"],
		[Vector2(165.0, 95.0), 16.0, "build_concrete_pipe_culvert_course", "culverts"],
		[Vector2(-90.0, 170.0), 18.0, "build_heavy_radar_gci_complex", "radar_dive"],
		[Vector2(110.0, 175.0), 16.0, "build_damaged_hangar_arch", "hangar_arch"],
		[Vector2(0.0, 75.0), 16.0, "build_scaffolding_freestyle_cube", "scaffold_cube"],
	]
	for spec in specs:
		var anchor: Vector2 = spec[0]
		var radius: float = float(spec[1])
		var builder: String = String(spec[2])
		var id: String = String(spec[3])
		var site := _pick_clear_airport_landmark_pos(anchor, radius)
		var pos := Vector3(site.x, _ground_y - 0.15, site.z)
		var zone := Node3D.new()
		zone.name = "AirportFreestyle_" + id
		zone.position = pos
		zones.add_child(zone)
		zone.rotation.y = atan2(anchor.x, anchor.y)
		ms.call(builder, zone, Vector3.ZERO, 0.0)
		FrontlineTerrainScript.register_structure_exclusion(
				Vector2(pos.x, pos.z), Vector2(radius, radius), 34.0)
	return


## Exact hollow collision for the sculpted landmark meshes: a single convex /
## AABB hull used to seal the gaps between fuel cisterns and the whole interior
## bay of the ruined hangar.  All surfaces are merged so multi-material GLBs
## keep every opening, and the shape lives under the mesh it describes.
func _add_trimesh_collider_to_mesh(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or not mi.is_inside_tree():
		return
	if mi.find_child("LandmarkTrimeshCol", true, false) != null:
		return
	mi.force_update_transform()
	var mesh := mi.mesh
	var shape: ConcavePolygonShape3D = null
	if mesh.get_surface_count() <= 1:
		shape = mesh.create_trimesh_shape() as ConcavePolygonShape3D
	else:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for s in range(mesh.get_surface_count()):
			st.append_from(mesh, s, Transform3D.IDENTITY)
		var merged := st.commit()
		if merged != null:
			shape = merged.create_trimesh_shape() as ConcavePolygonShape3D
	if shape == null:
		return
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "LandmarkTrimeshCol"
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)


func _add_airport_landmark_collider(parent: Node3D, local_pos: Vector3,
		box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "LandmarkCol"
	body.position = local_pos
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box_size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
