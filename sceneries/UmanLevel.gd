extends "res://sceneries/BigLevel.gd"
## Умань — фрістайл-карта (Софіївка + набережна).
## Як і AirportLevel, успадковуємо весь BigLevel (керування, HUD, фізику,
## якість, респавн) і підміняємо лише географію: замість процедурного терену
## завантажуємо authored GLB-карту з колізіями, водою та маркерами FX_.
## Бойові місії/техніка/піхота навмисно не створюються — карта тільки для
## вільного фрістайлу на трьох дронах з Assets/UmanFPV.

const UMAN_GLB := "res://Assets/maps/uman/Uman_FPV_Map.glb"
const UMAN_MODELS := "res://Assets/maps/uman/models/"
const UMAN_WATER_SHADER := "res://Assets/maps/uman/water_hq.gdshader"
const UMAN_PROPS := "res://Assets/maps/uman/props_library.glb"
const UMAN_POSTFX := "res://Assets/maps/uman/postfx.gdshader"
const UMAN_SKY := "res://Assets/maps/uman/sky_cloudy_1k.hdr"

const CC0_TREES := ["spruce-tree", "jungle-tree", "mangrove-tree",
		"spruce-tree", "jungle-tree"]
const CC0_BUILDINGS := ["city-block-filler", "general-store", "museum", "bank",
		"cinema", "grandstand", "pit-garage"]
const CC0_HERO_TREES := ["spruce-tree", "birch-grove", "jungle-tree",
		"mangrove-tree", "baobab-tree", "berry-bush"]

## Only compact, ground-seated props.  The old pool also contained full road
## pieces / loops / banked curves: their AABB is 20-40 m, so a single box
## collider sealed the whole loop and the meshes ended up hanging in the air
## when the height query hit another prop's roof.  They are decoration only.
const FREESTYLE_MODELS := [
	"sp_launchramp", "sp_grindbox", "sp_flatrail", "sp_kinkedrail",
	"sp_pad", "sp_stairs", "tire-barrier-wall", "catch-fence",
	"chain-link-fence", "concrete-barrier", "boost-pad",
	"sp_flatrail", "sp_pad",
]

var _uman_water_y := 0.0
var _uman_water_rect := Rect2()
var _uman_water_tris: Array = []
var _uman_prop_colliders: Array[RID] = []

## Віхи фрістайл-маршруту — петля навколо всієї карти (набережна →
## Софіївка → фонтани → місто → знову до старту). Кільця ставляться вздовж неї.
const COURSE_WAYPOINTS := [
	Vector3(122, 5, 118), Vector3(96, 5, 84), Vector3(60, 6, 70),
	Vector3(20, 5, 52), Vector3(-24, 4, 34), Vector3(-62, 5, -18),
	Vector3(-108, 6, 32), Vector3(-128, 5, 76), Vector3(-80, 5, 104),
	Vector3(-20, 6, 112), Vector3(40, 5, 118), Vector3(96, 4, 96),
	Vector3(140, 5, 48), Vector3(120, 6, -8), Vector3(72, 5, -48),
	Vector3(16, 5, -70), Vector3(-52, 6, -56), Vector3(-118, 5, -28),
	Vector3(-142, 6, 18), Vector3(-96, 5, 60), Vector3(-30, 5, 88),
	Vector3(38, 6, 86), Vector3(108, 5, 108),
]

var _uman_ripples: Array = []
var _uman_placed: Array = []
var _uman_fx_ready := false
var _uman_water_timer := 0.0


func _map_path() -> String:
	return UMAN_GLB


## GLB Умані вже має запечені PBR-матеріали — як і в аеропорту, не ховаємо меші.
func _apply_map_materials(_node: Node) -> void:
	pass


## Legacy-detail scattered не потрібен: карта повністю авторська.
func _scatter_legacy_map(_instance: Node3D) -> void:
	pass


func _ready() -> void:
	# Карта 360×360 м — стандартні межі BigLevel (152/182 м) занадто тісні.
	MAP_GROUND_SAFE = 176.0
	MAP_FLIGHT_BOUND = 196.0
	MAP_AIR_SAFE = 188.0
	_ground_y = 0.12
	set_meta("disable_procedural_grass", true)
	super._ready()
	# BigLevel re-applies the airframe preset later in its own _ready(), which
	# replaces every material override.  Re-apply the subtle accent afterwards.
	call_deferred("_uman_brighten_drone")
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set("hover_assist", false)
		radio.set("test_throttle", -1.0)


func _load_map() -> void:
	super._load_map()
	# Replace any imported convex/AABB blocker on named open structures with the
	# exact mesh shape *before* anything else queries physics for ground height.
	_uman_audit_glb_colliders()
	# Спочатку безпечні колізії — потім усе, що ставиться на землю.
	_uman_build_safety_collision()
	_uman_hide_static_jets()
	_uman_hide_old_gates()
	_uman_setup_water()
	_uman_hide_water_stunts()
	# Повний візуал демо: CC0-дерева/будівлі замість примітивів GLB.
	_uman_replace_vegetation()
	_uman_spawn_cc0_models()
	_uman_build_edge_world()
	_uman_build_themed_freestyle_parks()
	_uman_spawn_fountains()
	_uman_spawn_freestyle_props()
	_uman_populate_stunts()
	# Старий декоративний неон-маршрут більше не будуємо — його замінив
	# спільний course з контрольними точками (див. BigLevel._spawn_training_rings).
	_uman_build_landing_pad()
	_uman_setup_postfx()
	_uman_fx_ready = true


# GLB має власну поверхню ~y=0.1; процедурний height_at для "uman" даних не має.
func _find_ground_y(_x: float, _z: float) -> float:
	return 0.12


func _is_ground_spot_clear(x: float, z: float) -> bool:
	return absf(x) <= MAP_GROUND_SAFE and absf(z) <= MAP_GROUND_SAFE


func _special_ground_point(x: float, z: float) -> Vector3:
	return Vector3(clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.14,
			clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _map_water_level() -> float:
	return 0.0


## Старт — на маркері PlayerSpawn з GLB (набережна). Якщо маркера немає,
## безпечна запасна точка у повітрі над набережною.
func _place_drone_over_ground() -> void:
	_ground_y = 0.12
	var spawn := _uman_find_spawn()
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var pos := spawn + Vector3(0.0, 1.4, 0.0)
	var spawn_xform := Transform3D(Basis(), pos)
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
	_uman_brighten_drone()
	# Батьківський обробник ARM/respawn не підключиться (ми перевизначили метод),
	# тому робимо це самі — інакше дрон лишається замороженим.
	var fc = d.flight_controller
	if fc != null:
		if not fc.armed.is_connected(_uman_armed):
			fc.armed.connect(_uman_armed)
		if not fc.arm_failed.is_connected(_on_arm_failed):
			fc.arm_failed.connect(_on_arm_failed)
	if not d.respawned.is_connected(_on_respawned):
		d.respawned.connect(_on_respawned)


## Дуже легкий кольоровий акцент поверх рідних текстур дрона.  Стара версія
## давала emission 0.45 на КОЖНУ поверхню з соковитим салатовим кольором —
## дрон виглядав як неоновий ліхтар і перекривав FPV-картинку.  Тепер колір
## приглушений, енергія ~0.08, а factory-світлодіоди (які вже мають emission)
## взагалі не чіпаємо.
func _uman_brighten_drone() -> void:
	# BigLevel can keep several DroneModel roots (live, sensor preview, cached
	# respawn model).  Apply the shared catalog styling to all of them so
	# in-game appearance matches the menu/hangar showcase cleanly.
	var models := find_children("DroneModel", "Node3D", true, false)
	if models.is_empty():
		return
	var idx: int = int((models[0] as Node3D).get_meta("preset_index", 10))
	for model in models:
		DroneCatalog.apply_uman_drone_materials(model as Node3D, idx)


func _uman_find_spawn() -> Vector3:
	var root := get_node_or_null("MapRoot")
	if root != null:
		var marker := root.find_child("PlayerSpawn", true, false)
		if marker is Node3D:
			return (marker as Node3D).global_position
	return Vector3(120.0, 1.0, 118.0)


func _uman_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d.freeze = false
		d.linear_velocity = Vector3.UP * 0.1
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	if not _mission_started and not _mission_finished:
		_start_mission()


## Тільки фрістайл: ніяких місій, техніки, піхоти й спецоперацій.
## Неоновий маршрут тепер спільний для всіх карт і побудований у BigLevel як
## справжні контрольні точки (таймер, лічильник, персональний привид).
func _build_frontline_props() -> void:
	_queue_training_ring_spawn()


## Наступні заглуровки — страховка: навіть якщо батьківський код викличе
## бойові спавни з іншого шляху, на фрістайл-карті нічого не з'явиться.
## _start_mission НЕ заглушка: він запускає таймер, привида та підсвітку воріт.


func _spawn_vehicles() -> void:
	pass


func _spawn_frontline_bonus_targets() -> void:
	pass


func _spawn_special_or_campaign() -> void:
	pass


func _spawn_combat_mission(_mission_id: int) -> void:
	pass


func _start_reinforcements() -> void:
	pass


func _tune_map_environment() -> void:
	super._tune_map_environment()
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		var env := we.environment
		env.background_mode = Environment.BG_SKY
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_sky_contribution = 0.72
		env.ambient_light_energy = 1.00
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.20
		env.fog_enabled = true
		env.fog_light_color = Color(0.66, 0.74, 0.86, 1.0)
		env.fog_density = 0.00018
		env.glow_enabled = true
		env.glow_intensity = 0.30
		env.glow_bloom = 0.09
		env.glow_hdr_threshold = 1.05
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.06
		env.adjustment_contrast = 1.04
		if ResourceLoader.exists(UMAN_SKY):
			var hdr: Resource = load(UMAN_SKY)
			if hdr is Texture2D:
				var sky := Sky.new()
				var pano := PanoramaSkyMaterial.new()
				pano.panorama = hdr as Texture2D
				sky.sky_material = pano
				env.sky = sky
		env.background_energy_multiplier = 1.04
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 800.0
		sun.rotation_degrees = Vector3(-36.0, 45.0, 0.0)
		sun.light_color = Color(1.0, 0.86, 0.70, 1.0)
		sun.light_energy = 3.10
	var fill := get_node_or_null("UmanFill") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "UmanFill"
		add_child(fill)
	fill.rotation_degrees = Vector3(-26.0, -120.0, 0.0)
	fill.light_color = Color(0.57, 0.70, 0.89, 1.0)
	fill.light_energy = 0.58
	fill.shadow_enabled = false


# -------------------------------------------------- колізії / безпека --------

## Дві водойми карти (за даними демо). Використовується для авторестарту
## й щоб не ставити трюки/дерева просто у воді.
func _uman_is_water(p: Vector3) -> bool:
	# Exact test against the authored water triangles.  The old hand-written
	# ellipses missed parts of the lake (stunt boxes over water) and a plain
	# AABB wrongly marked the promenade / landing pad as water.
	if not _uman_water_tris.is_empty():
		var px := p.x
		var pz := p.z
		for t in _uman_water_tris:
			if px < float(t[0]) or px > float(t[1]) or pz < float(t[2]) or pz > float(t[3]):
				continue
			var ax := float(t[4]); var az := float(t[5])
			var bx := float(t[6]); var bz := float(t[7])
			var cx := float(t[8]); var cz := float(t[9])
			var d1 := (px - bx) * (az - bz) - (ax - bx) * (pz - bz)
			var d2 := (px - cx) * (bz - cz) - (bx - cx) * (pz - cz)
			var d3 := (px - ax) * (cz - az) - (cx - ax) * (pz - az)
			if (d1 >= 0.0 and d2 >= 0.0 and d3 >= 0.0) \
					or (d1 <= 0.0 and d2 <= 0.0 and d3 <= 0.0):
				return true
		return false
	var big := pow((p.x - 60.0) / 85.0, 2.0) + pow((p.z - 25.0) / 65.0, 2.0)
	var low := pow((p.x + 80.0) / 50.0, 2.0) + pow((p.z + 20.0) / 40.0, 2.0)
	return big < 1.06 or low < 1.06


func _uman_box_overlaps_water(box: AABB) -> bool:
	var c := box.get_center()
	if _uman_is_water(c):
		return true
	for dx in [0.0, 1.0]:
		for dz in [0.0, 1.0]:
			var p := box.position + Vector3(box.size.x * float(dx), 0.0,
					box.size.z * float(dz))
			if _uman_is_water(p):
				return true
	return false


## Промінь вниз по шару 1. Повертає реальну висоту поверхні (з урахуванням
## GLB-колізій і нашого безпечного ґрунту), щоб нічого не висіло в повітрі.
func _uman_ground_y(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
			Vector3(p.x, 320.0, p.z), Vector3(p.x, -60.0, p.z))
	q.collision_mask = 1
	var exclude: Array[RID] = []
	for rid in _uman_prop_colliders:
		exclude.append(rid)
	var drone := get_node_or_null("Drone")
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 0.14
	# Uman's authored terrain is essentially flat at y~0.12.  Any hit above
	# 2.5 m is a roof / road deck / stunt piece, not soil: planting a tree on
	# it is exactly what produced "trees hanging in the air".  Fall back to
	# the ground plane for every decoration.
	var y := (hit["position"] as Vector3).y
	if y > 2.5:
		return 0.14
	return y + 0.03


## Суцільний ґрунт під усією картою: дрон більше не провалюється крізь
## воду/терен і може нормально приземлитися будь-де.
func _uman_build_safety_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "UmanSafetyGround"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(420.0, 4.0, 420.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, -2.0, 0.0)  # верхня грань = y 0
	add_child(body)

	# Видима «спідниця» під картою — край більше не обрізається у порожнечу.
	var skirt := MeshInstance3D.new()
	skirt.name = "UmanGroundSkirt"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2600.0, 2600.0)
	skirt.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.40, 0.20, 1.0)
	mat.roughness = 1.0
	skirt.material_override = mat
	skirt.position = Vector3(0.0, -0.6, 0.0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)


## По периметру — ті самі CC0-будівлі, що й у місті: край карти виглядає
## забудованим, а не «обрізаним», і є фізичні перешкоди.
func _uman_build_edge_world() -> void:
	var count := 0
	for i in range(56):
		var a := TAU * float(i) / 56.0
		var r := 166.0 + randf_range(-4.0, 9.0)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if absf(p.x) > 178.0 or absf(p.z) > 178.0:
			continue
		if _uman_is_water(p):
			continue
		p.y = _uman_ground_y(p)
		var model: String = CC0_BUILDINGS[i % CC0_BUILDINGS.size()]
		var inst := _uman_simple_model(UMAN_MODELS + model + ".glb", p,
				-a + PI * 0.5, randf_range(0.85, 1.25), 2, 22.0)
		if inst != null:
			count += 1
	print("[UMAN] edge buildings=", count)


# ------------------------------------------------------------- неон-маршрут --

func _uman_neon_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.06, 0.02, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.08, 0.02)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## М'який додатковий ореол навколо неонової трубки (замість дорогого bloom).
func _uman_glow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.03, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.10, 0.02)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _uman_dark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.035, 0.04, 1.0)
	mat.roughness = 0.85
	mat.metallic = 0.35
	return mat


func _uman_beam(a: Vector3, b: Vector3, radius: float, mat: Material) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = len
	cyl.radial_segments = 10
	mesh.mesh = cyl
	mesh.material_override = mat
	add_child(mesh)
	mesh.position = (a + b) * 0.5
	mesh.look_at(b, Vector3.UP)
	mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)


## Одна яскрава рамка: коло/арка/шестикутник/трикутник із темною основою.
func _uman_neon_gate(pos: Vector3, yaw: float, shape: int, size: float) -> void:
	var neon := _uman_neon_material()
	var dark := _uman_dark_material()
	var glow := _uman_glow_material()
	var pts: Array[Vector3] = []
	if shape == 0:  # круг
		for i in range(24):
			var a := TAU * float(i) / 24.0
			pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
	elif shape == 1:  # арка
		for i in range(13):
			var a := PI * float(i) / 12.0
			pts.append(Vector3(-cos(a) * size, sin(a) * size * 1.25, 0.0))
		pts.append(Vector3(size, 0.0, 0.0))
	elif shape == 2:  # шестикутник
		for i in range(6):
			var a := TAU * float(i) / 6.0 + PI / 6.0
			pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
	elif shape == 3:  # трикутник
		for i in range(3):
			var a := TAU * float(i) / 3.0 + PI * 0.5
			pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
	else:  # широкий прямокутник (як на референсі)
		var w := size * 1.25
		var h := size * 0.85
		pts.append(Vector3(-w, -h, 0.0))
		pts.append(Vector3(w, -h, 0.0))
		pts.append(Vector3(w, h, 0.0))
		pts.append(Vector3(-w, h, 0.0))
	var basis := Basis(Vector3.UP, yaw)
	for i in range(pts.size()):
		var a0: Vector3 = pos + basis * pts[i]
		var b0: Vector3 = pos + basis * pts[(i + 1) % pts.size()]
		_uman_beam(a0, b0, 0.34, dark)   # темна каркасна основа
		_uman_beam(a0, b0, 0.22, neon)   # яскрава трубка
		_uman_beam(a0, b0, 0.48, glow)   # м'який ореол
	# Масивні «ступині» внизу — рамка стоїть на землі, як у референсі.
	for s in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = Vector3(1.1, 0.45, 1.1)
		foot.mesh = fb
		foot.material_override = dark
		add_child(foot)
		foot.position = pos + basis * Vector3(s * size * 0.86, -size + 0.12, 0.0)


## Ворота вздовж петлі + червона світлова доріжка на землі (як на референсі).
func _uman_build_neon_course() -> void:
	var neon := _uman_neon_material()
	var glow := _uman_glow_material()
	var trail_root := Node3D.new()
	trail_root.name = "UmanNeonTrail"
	add_child(trail_root)
	var gates := 0
	for i in range(COURSE_WAYPOINTS.size()):
		var wp: Vector3 = COURSE_WAYPOINTS[i]
		var nxt: Vector3 = COURSE_WAYPOINTS[(i + 1) % COURSE_WAYPOINTS.size()]
		var dir := (nxt - wp).normalized()
		var yaw := atan2(dir.x, dir.z)
		var gy := _uman_ground_y(wp)
		var center := Vector3(wp.x, gy + 4.5 + (i % 3) * 1.2, wp.z)
		_uman_neon_gate(center, yaw, i % 5, 4.4 + float(i % 3) * 0.6)
		gates += 1
		# Світлова лінія на поверхні між сусідніми воротами.
		var a := Vector3(wp.x, gy + 0.16, wp.z)
		var b := Vector3(nxt.x, _uman_ground_y(nxt) + 0.16, nxt.z)
		_uman_beam(a, b, 0.12, neon)
		_uman_beam(a, b, 0.26, glow)
		# Додаткові ворота посеред сегмента — маршрут петляє, а не прямий.
		var mid := wp.lerp(nxt, 0.5)
		var mgy := _uman_ground_y(mid)
		var mcenter := Vector3(mid.x, mgy + 4.0 + (i % 2) * 1.4, mid.z)
		_uman_neon_gate(mcenter, yaw + 0.45 * (1.0 if i % 2 == 0 else -1.0),
				(i + 2) % 5, 3.6 + float(i % 2) * 0.5)
		gates += 1
	print("[UMAN] neon gates=", gates)


## Помітний майданчик приземлення на старті.
func _uman_build_landing_pad() -> void:
	var p := _uman_find_spawn()
	var pad := MeshInstance3D.new()
	pad.name = "UmanLandingPad"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.2
	cyl.bottom_radius = 4.2
	cyl.height = 0.04
	cyl.radial_segments = 32
	pad.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.12, 0.11, 1.0)
	mat.metallic = 0.4
	mat.roughness = 0.7
	pad.material_override = mat
	add_child(pad)
	pad.position = Vector3(p.x, _uman_ground_y(p) + 0.025, p.z)


# --------------------------------------------------------------- scenery -----

func _uman_hide_and_disable_collision(node: Node3D) -> void:
	if node == null:
		return
	node.visible = false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionObject3D:
			var co := cur as CollisionObject3D
			co.collision_layer = 0
			co.collision_mask = 0
		for c in cur.get_children():
			stack.append(c)


func _uman_hide_static_jets() -> void:
	for n in _uman_find_with_prefix(self, "Fountain_Water_Jets"):
		var node := n as Node3D
		if node != null:
			node.visible = false


## Старі білі/рожеві ворота з GLB (Gate_01..14) та залишкові кільця Stunt_Ring_*
## заміняємо власними неоновими — вони виглядали слабко й плутали маршрут.
func _uman_hide_old_gates() -> void:
	var hidden := 0
	for prefix in ["Gate_", "FPV_Gate", "Stunt_Ring_"]:
		for n in _uman_find_with_prefix(self, prefix):
			var node := n as Node3D
			if node != null:
				_uman_hide_and_disable_collision(node)
				hidden += 1
	print("[UMAN] old gates hidden=", hidden)


func _uman_setup_water() -> void:
	var found := _uman_find_with_prefix(self, "Water_Surface")
	if found.is_empty():
		return
	var water: Variant = found[0]
	if not (water is MeshInstance3D):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(UMAN_WATER_SHADER) as Shader
	if mat.shader == null:
		return
	var noise := NoiseTexture2D.new()
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_PERLIN
	fnl.frequency = 0.045
	noise.noise = fnl
	noise.width = 256
	noise.height = 256
	noise.seamless = true
	noise.generate_mipmaps = true
	mat.set_shader_parameter("ripple_normal", noise)
	mat.set_shader_parameter("deep_color", Color(0.035, 0.10, 0.095))
	mat.set_shader_parameter("shallow_color", Color(0.11, 0.24, 0.21))
	mat.set_shader_parameter("ripple_scale", 0.055)
	mat.set_shader_parameter("ripple_speed", 1.0)
	mat.set_shader_parameter("ripple_strength", 0.55)
	mat.set_shader_parameter("wave_height", 0.035)
	mat.set_shader_parameter("sky_amount", 0.55)
	(water as MeshInstance3D).material_override = mat
	(water as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_uman_water_y = (water as MeshInstance3D).global_position.y
	var wa := (water as MeshInstance3D).mesh.get_aabb()
	_uman_water_rect = Rect2(wa.position.x + (water as MeshInstance3D).global_position.x,
			wa.position.z + (water as MeshInstance3D).global_position.z,
			wa.size.x, wa.size.z)
	# Cache the water surface as world-space XZ triangles.  ~1900 triangles,
	# queried a few hundred times while placing scenery - cheap and exact.
	_uman_water_tris.clear()
	if (water as MeshInstance3D).mesh is ArrayMesh:
		var arrays := ((water as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var inds: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if inds.is_empty():
			inds = PackedInt32Array()
			for vi in range(verts.size()):
				inds.append(vi)
		var xf := (water as MeshInstance3D).global_transform
		var i := 0
		while i + 2 < inds.size():
			var a := xf * verts[inds[i]]
			var b := xf * verts[inds[i + 1]]
			var c := xf * verts[inds[i + 2]]
			_uman_water_tris.append([
					minf(a.x, minf(b.x, c.x)), maxf(a.x, maxf(b.x, c.x)),
					minf(a.z, minf(b.z, c.z)), maxf(a.z, maxf(b.z, c.z)),
					a.x, a.z, b.x, b.z, c.x, c.z,
			])
			i += 3


## Authored GLB stunt props can sit over the lake (e.g. Stunt_QuarterPipe_01
## at x~87 z~76).  They look like floating black boxes and their colliders
## create invisible walls above the water.  Hide the mesh AND disable its
## collision so the airspace stays flyable.
func _uman_hide_water_stunts() -> void:
	var hidden := 0
	for node in _uman_find_with_prefix(self, "Stunt_"):
		var n := node as Node3D
		if n == null or not n.visible:
			continue
		var box := _uman_visual_aabb(n)
		if box.size.length() < 0.05 or not _uman_box_overlaps_water(box):
			continue
		n.visible = false
		var stack: Array[Node] = [n]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is CollisionObject3D:
				(cur as CollisionObject3D).collision_layer = 0
			for c in cur.get_children():
				stack.append(c)
		hidden += 1
	if hidden > 0:
		print("[UMAN] water stunts hidden=", hidden)


func _uman_spawn_fountains() -> void:
	var mobile := OS.has_feature("mobile") or OS.get_name() == "iOS"
	for n in _uman_find_with_prefix(self, "FX_"):
		var marker := n as Node3D
		if marker == null:
			continue
		var pos := marker.global_position
		var tall := marker.name == "FX_SnakeFountain"
		_uman_add_jet(pos, marker.name + "_core", tall, 0, mobile)
		_uman_add_jet(pos, marker.name + "_mist", tall, 1, mobile)
		if not mobile:
			_uman_add_jet(pos, marker.name + "_splash", tall, 2, false)
		if mobile:
			continue
		for k in range(3):
			var ring := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.55 + k * 0.45
			torus.outer_radius = 0.70 + k * 0.45
			torus.rings = 6
			ring.mesh = torus
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.82, 0.96, 1.0, 0.34)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.8, 1.0)
			ring.material_override = mat
			add_child(ring)
			ring.position = pos + Vector3(0, 0.12, 0)
			_uman_ripples.append({"node": ring, "phase": k * 0.33})


func _uman_add_jet(pos: Vector3, nm: String, tall: bool, kind: int, mobile: bool) -> void:
	var p := GPUParticles3D.new()
	p.name = "VFX_" + nm
	add_child(p)
	p.position = pos
	p.local_coords = false
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.gravity = Vector3(0, -9.8, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	var mesh := SphereMesh.new()
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	var scale := 0.5 if mobile else 1.0
	if kind == 0:
		p.amount = int((260 if tall else 170) * scale)
		p.lifetime = 2.5 if tall else 1.8
		pm.spread = 9.0
		pm.emission_sphere_radius = 0.22
		pm.initial_velocity_min = 20.0 if tall else 10.0
		pm.initial_velocity_max = 30.0 if tall else 16.0
		pm.scale_min = 0.55
		pm.scale_max = 1.25
		pm.color = Color(0.92, 0.98, 1.0, 0.88)
		mesh.radius = 0.085
		mesh.height = 0.17
		m.albedo_color = Color(0.94, 0.99, 1.0, 0.88)
		m.emission = Color(0.65, 0.85, 1.0)
	elif kind == 1:
		p.amount = int(220 * scale)
		p.lifetime = 1.25
		pm.spread = 34.0
		pm.emission_sphere_radius = 0.7
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 11.0
		pm.scale_min = 0.18
		pm.scale_max = 0.55
		pm.color = Color(0.80, 0.93, 1.0, 0.38)
		mesh.radius = 0.12
		mesh.height = 0.24
		m.albedo_color = Color(0.88, 0.96, 1.0, 0.34)
		m.emission = Color(0.5, 0.75, 1.0)
	else:
		p.amount = 130
		p.lifetime = 0.85
		pm.spread = 68.0
		pm.emission_sphere_radius = 0.35
		pm.initial_velocity_min = 4.0
		pm.initial_velocity_max = 8.0
		pm.scale_min = 0.3
		pm.scale_max = 0.8
		pm.color = Color(0.88, 0.97, 1.0, 0.6)
		mesh.radius = 0.1
		mesh.height = 0.2
		m.albedo_color = Color(0.9, 0.98, 1.0, 0.6)
		m.emission = Color(0.6, 0.85, 1.0)
	p.process_material = pm
	mesh.material = m
	p.draw_pass_1 = mesh


## Замінює примітивні крони GLB на текстуровані CC0-дерева й кущі
## (рівно як у демо-проєкті карти — саме це дає «красивий» вигляд).
func _uman_replace_vegetation() -> void:
	var heights := {}
	for m in CC0_TREES:
		var inst := _uman_simple_model(UMAN_MODELS + m + ".glb", Vector3.ZERO, 0.0, 1.0)
		if inst != null:
			heights[m] = maxf(_uman_visual_aabb(inst).size.y, 1.0)
			inst.queue_free()
	var placed := 0
	for n in _uman_find_with_prefix(self, "Tree_"):
		var node := n as Node3D
		if node == null or node.name.contains("Collider"):
			continue
		if placed >= 380:
			break
		var h := _uman_visual_aabb(node).size.y
		if h < 2.0:
			continue
		_uman_hide_and_disable_collision(node)
		var gp := node.global_position
		if _uman_is_water(gp):
			continue
		var m: String = CC0_TREES[placed % CC0_TREES.size()]
		var s := clampf(h / maxf(float(heights.get(m, 1.0)), 1.0), 0.55, 2.1)
		_uman_simple_model(UMAN_MODELS + m + ".glb",
				Vector3(gp.x, _uman_ground_y(gp), gp.z), randf() * TAU, s, 1)
		placed += 1
	var shrubs := 0
	for n in _uman_find_with_prefix(self, "Shrub_"):
		var node := n as Node3D
		if node == null:
			continue
		_uman_hide_and_disable_collision(node)
		if shrubs < 150 and not _uman_is_water(node.global_position):
			var gp := node.global_position
			_uman_simple_model(UMAN_MODELS + "berry-bush.glb",
					Vector3(gp.x, _uman_ground_y(gp), gp.z),
					randf() * TAU, randf_range(0.8, 1.6))
		shrubs += 1
	print("[UMAN] CC0 trees=", placed, " bushes=", shrubs)


func _uman_spawn_cc0_models() -> void:
	var used := 0
	for n in _uman_find_with_prefix(self, "City_Building"):
		var node := n as Node3D
		if node == null:
			continue
		_uman_hide_and_disable_collision(node)
		if _uman_is_water(node.global_position):
			continue
		var model: String = CC0_BUILDINGS[used % CC0_BUILDINGS.size()]
		var gp := node.global_position
		var inst := _uman_simple_model(UMAN_MODELS + model + ".glb",
				Vector3(gp.x, _uman_ground_y(gp), gp.z), randf() * TAU, 1.0, 2, 22.0)
		used += 1
	var tree_spots := [
		Vector3(-30, 1, -38), Vector3(-18, 1, -46), Vector3(-45, 1, -30),
		Vector3(-62, 1, -22), Vector3(-105, 1, -18), Vector3(-128, 1, -8),
		Vector3(-40, 1, 44), Vector3(-12, 1, 55), Vector3(28, 1, 62),
		Vector3(70, 1, 78), Vector3(110, 1, 70), Vector3(138, 1, 55),
		Vector3(96, 1, 8), Vector3(130, 1, -14), Vector3(-85, 1, 92),
	]
	for i in range(tree_spots.size()):
		var model: String = CC0_HERO_TREES[i % CC0_HERO_TREES.size()]
		var tp: Vector3 = tree_spots[i]
		if _uman_is_water(tp):
			continue
		_uman_simple_model(UMAN_MODELS + model + ".glb",
				Vector3(tp.x, _uman_ground_y(tp), tp.z),
				randf() * TAU, randf_range(0.8, 1.35), 1)
	print("[UMAN] CC0 buildings=", used, " hero trees=", tree_spots.size())


## `solid`: 0 = decoration, 1 = tree trunk cylinder, 2 = building box.
## CC0 trees/buildings imported as plain GLB had no collider at all, which is
## why the drone flew straight through them.
func _uman_simple_model(path: String, pos: Vector3, yaw: float, s: float,
		solid: int = 0, target_height: float = 0.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	if target_height > 0.0:
		var raw_box := _uman_visual_aabb(inst)
		if raw_box.size.y > 0.5:
			inst.scale = Vector3.ONE * clampf(target_height / raw_box.size.y, 0.55, 1.8)
	if solid == 1:
		var box := _uman_visual_aabb(inst)
		if box.size.length() > 0.05:
			var body := StaticBody3D.new()
			body.name = "uman_scenery_col_%d" % _uman_prop_colliders.size()
			body.collision_layer = 1
			body.collision_mask = 1
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = clampf(box.size.x * 0.055, 0.35, 1.3)
			cyl.height = minf(box.size.y * 0.62, 9.0)
			cs.shape = cyl
			body.position = Vector3(box.get_center().x,
					box.position.y + cyl.height * 0.5, box.get_center().z)
			body.add_child(cs)
			add_child(body)
			_uman_prop_colliders.append(body.get_rid())
	elif solid == 2:
		# Buildings used to get one unrotated world-AABB box.  On a yawed GLB
		# that box stuck out past the corners and sealed every doorway.  Exact
		# per-mesh trimeshes follow the rotated walls instead.
		_uman_attach_mesh_collider(inst)
	return inst


func _uman_visual_aabb(node: Node) -> AABB:
	# A freshly add_child()'d GLB has a stale global_transform until the next
	# physics tick.  Force it here so the AABB matches what physics will see.
	if node is Node3D and (node as Node3D).is_inside_tree():
		(node as Node3D).force_update_transform()
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and (n as Node3D).is_inside_tree():
			(n as Node3D).force_update_transform()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var xf: Transform3D = mi.global_transform if mi.is_inside_tree() else mi.transform
			var b := xf * mi.mesh.get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
		for c in n.get_children():
			stack.append(c)
	return result


## Легкий кольоровий грейд демо (без SSAO/volumetric — тільки для LOWSPEC/mobile).
func _uman_setup_postfx() -> void:
	if not ResourceLoader.exists(UMAN_POSTFX):
		return
	var layer := CanvasLayer.new()
	layer.name = "UmanPostFX"
	layer.layer = 10
	add_child(layer)
	var rect := ColorRect.new()
	rect.name = "UmanGrade"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = load(UMAN_POSTFX) as Shader
	rect.material = mat
	layer.add_child(rect)


func _uman_spawn_freestyle_props() -> void:
	if not ResourceLoader.exists(UMAN_PROPS):
		return
	var packed := load(UMAN_PROPS) as PackedScene
	if packed == null:
		return
	var lib := packed.instantiate()
	var names := ["prop_crate", "prop_barrier", "prop_tires", "prop_barrel",
			"prop_oil_drum", "prop_pipe", "prop_sandbags", "prop_fence",
			"prop_pallet", "prop_generator"]
	var anchors := [Vector3(140, 1, 62), Vector3(96, 1, 18), Vector3(-42, 1, 82),
			Vector3(128, 1, 4), Vector3(62, 1, 8), Vector3(18, 1, 92)]
	var count := 0
	for a in anchors:
		for k in range(4):
			var anchor: Vector3 = a as Vector3
			var nm: String = names[(count + k) % names.size()]
			var src := lib.find_child(nm, true, false)
			if src == null:
				continue
			var inst := src.duplicate() as Node3D
			if inst == null:
				continue
			var pp: Vector3 = anchor + Vector3((k - 1.5) * 3.2, 0.0, float(count % 2) * 2.5)
			if _uman_is_water(pp):
				continue
			add_child(inst)
			inst.position = Vector3(pp.x, _uman_ground_y(pp), pp.z)
			inst.rotation.y = randf() * TAU
			var pbox := _uman_visual_aabb(inst)
			if _uman_box_overlaps_water(pbox):
				inst.queue_free()
				continue
			_uman_attach_mesh_collider(inst)
			count += 1
	lib.queue_free()


## Verified dry-land site for a 16 m park footprint.  Tests candidate offsets
## around the zone anchor so the FULL footprint (centre + four corners) clears
## every pond, landmark, spawn/course waypoint and already-placed park.
func _uman_pick_park_site(base: Vector2, footprint: float) -> Vector3:
	var half := footprint * 0.5
	for ring in range(0, 7):
		var radius := 0.0 if ring == 0 else 13.0 * float(ring)
		var steps := 1 if ring == 0 else 16
		for i in range(steps):
			var a := TAU * float(i) / float(steps) + float(ring) * 0.31
			var c := base + Vector2(cos(a), sin(a)) * radius
			if absf(c.x) > 158.0 or absf(c.y) > 158.0:
				continue
			if Vector2(c.x - 120.0, c.y - 118.0).length() < 44.0:
				continue
			var center := Vector3(c.x, 0.0, c.y)
			if _uman_is_water(center) or _uman_near_landmark(center):
				continue
			var box := AABB(Vector3(c.x - half, -1.0, c.y - half),
					Vector3(footprint, 24.0, footprint))
			if _uman_box_overlaps_water(box):
				continue
			var course_clear := true
			for wp in COURSE_WAYPOINTS:
				var w: Vector3 = wp
				if Vector2(c.x - w.x, c.y - w.z).length() < 24.0:
					course_clear = false
					break
			if not course_clear:
				continue
			var packed := false
			for q in _uman_placed:
				if q.y <= 0.0:
					continue
				if Vector2(c.x - q.x, c.y - q.z).length() < footprint + q.y:
					packed = true
					break
			if packed:
				continue
			return Vector3(c.x, _uman_ground_y(center) - 0.12, c.y)
	return Vector3(-9999.0, 0.0, -9999.0)


## Five competitor-style, park-themed freestyle flow lines for Uman: connected
## pergola arches -> hollow conduit tunnels -> dive tower -> Split-S frames ->
## slalom sprint lane.  All use the low-poly military kit with true fly-through
## collision, warm limestone/timber styling, and sit flush on verified lawn.
func _uman_build_themed_freestyle_parks() -> void:
	if get_node_or_null("UmanThemedFreestyleParks") != null:
		return
	var ms = load("res://scripts/util/military_structures.gd")
	if ms == null:
		return
	var root := Node3D.new()
	root.name = "UmanThemedFreestyleParks"
	add_child(root)

	var specs: Array = [
		# [anchor, footprint, yaw, builder, id]
		[Vector2(124.0, -92.0), 16.0, 0.35, "build_park_pergola_arches", "pergola"],
		[Vector2(-140.0, 116.0), 16.0, -0.25, "build_park_tunnel_pipes", "tunnel_pipes"],
		[Vector2(154.0, 86.0), 16.0, 0.60, "build_park_gazebo_tower", "gazebo_tower"],
		[Vector2(8.0, -112.0), 16.0, 0.15, "build_park_split_s_frames", "split_s_frames"],
		[Vector2(-124.0, -88.0), 16.0, -0.40, "build_fpv_slalom_gate_course", "slalom_lane"],
	]
	var placed := 0
	for spec in specs:
		var anchor: Vector2 = spec[0]
		var footprint: float = float(spec[1])
		var yaw: float = float(spec[2])
		var builder: String = String(spec[3])
		var id: String = String(spec[4])
		var site := _uman_pick_park_site(anchor, footprint)
		if site.x < -9000.0:
			continue
		var park := Node3D.new()
		park.name = "UmanPark_" + id
		park.position = site
		park.rotation.y = yaw
		root.add_child(park)
		ms.call(builder, park, Vector3.ZERO, 0.0)
		# All authored members must have final transforms before colliders are
		# queried by the flight/physics broadphase.
		park.force_update_transform()
		for child in park.get_children(true):
			if child is Node3D:
				(child as Node3D).force_update_transform()
		# Register the park's solid bodies so ground queries / later decoration
		# do not plant props on a roof or collide with the fly-through frames.
		var stack: Array[Node] = [park]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for ch in n.get_children():
				stack.append(ch)
			if n is StaticBody3D:
				var body_rid: RID = (n as StaticBody3D).get_rid()
				if not _uman_prop_colliders.has(body_rid):
					_uman_prop_colliders.append(body_rid)
		# y carries the reserve radius so small random stunts keep clear.
		_uman_placed.append(Vector3(site.x, footprint * 0.5, site.z))
		placed += 1
	print("[UMAN] themed freestyle parks=", placed)


func _uman_populate_stunts() -> void:
	var mobile := OS.has_feature("mobile") or OS.get_name() == "iOS"
	var zones = [
		{"c": Vector3(132, 0, 62), "n": 30}, {"c": Vector3(58, 0, 112), "n": 28},
		{"c": Vector3(112, 0, -18), "n": 26}, {"c": Vector3(-62, 0, -32), "n": 30},
		{"c": Vector3(-112, 0, 52), "n": 28}, {"c": Vector3(24, 0, 42), "n": 26},
		{"c": Vector3(-30, 0, -92), "n": 24}, {"c": Vector3(148, 0, 18), "n": 22},
		{"c": Vector3(-130, 0, -70), "n": 22}, {"c": Vector3(20, 0, -40), "n": 24},
	]
	var total := 0
	# Fewer, smaller props: the old 240-object soup hid the course and its
	# box colliders made the map feel like a wall.  Phones get an even lighter
	# budget so the 3-fps DVR and the ghost stay smooth.
	var limit := 64 if mobile else 130
	for zone in zones:
		var made := 0
		var tries := 0
		while made < int(zone.n) and total < limit and tries < int(zone.n) * 18:
			tries += 1
			var a := randf() * TAU
			var rr: float = sqrt(randf()) * 46.0
			var p: Vector3 = (zone.c as Vector3) + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
			if absf(p.x) > 174.0 or absf(p.z) > 174.0:
				continue
			if _uman_is_water(p):  # у воді трюки не ставимо — не будуть висіти
				continue
			var too_close := false
			for q in _uman_placed:
				# q.y > 0 marks a themed park and carries its reserve radius;
				# plain small stunts keep the original 4.5 m spacing.
				var keep_out := 4.5
				if q.y > 0.0:
					keep_out = q.y + 6.0
				if Vector2(p.x - q.x, p.z - q.z).length() < keep_out:
					too_close = true
					break
			if too_close or _uman_near_landmark(p):
				continue
			p.y = _uman_ground_y(p)
			var model: String = FREESTYLE_MODELS[total % FREESTYLE_MODELS.size()]
			var inst := _uman_spawn_model(UMAN_MODELS + model + ".glb", p,
					randf() * TAU, randf_range(0.9, 1.35), false)
			if inst == null:
				continue
			var box := _uman_visual_aabb(inst)
			if box.size.x > 9.0 or box.size.z > 9.0 or box.size.y > 3.8 \
					or _uman_box_overlaps_water(box):
				inst.queue_free()
				continue
			_uman_attach_mesh_collider(inst)
			_uman_placed.append(Vector3(p.x, 0.0, p.z))
			made += 1
			total += 1
	print("[UMAN] freestyle stunts=", total)


func _uman_near_landmark(p: Vector3) -> bool:
	var sp := _uman_find_spawn()
	if Vector2(p.x - sp.x, p.z - sp.z).length() < 12.0:
		return true
	if Vector2(p.x + 24.0, p.z + 34.0).length() < 19.0:
		return true
	if Vector2(p.x - 70.0, p.z - 55.0).length() < 26.0:
		return true
	if Vector2(p.x + 85.0, p.z + 20.0).length() < 12.0:
		return true
	return false


func _uman_spawn_model(path: String, pos: Vector3, yaw: float, s: float,
		add_collider: bool = true) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	add_child(inst)
	inst.position = pos
	inst.rotation.y = yaw
	inst.scale = Vector3.ONE * s
	if add_collider:
		_uman_attach_mesh_collider(inst)
	return inst


func _uman_attach_prop_collider(box: AABB) -> void:
	# Декоративні великі рампи/дуги НЕ отримують box-колайдера: суцільний box
	# закривав отвір і не давав пролітати крізь них. Малі пропси лишаються
	# фізичними, але з трохи меншим колайдером, щоб не чіпляти повітря.
	if box.size.length() < 0.05:
		return
	if box.size.x > 12.0 or box.size.z > 12.0 or box.size.y > 4.5:
		return
	var body := StaticBody3D.new()
	body.name = "uman_obj_col_%d" % _uman_prop_colliders.size()
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size * 0.82
	cs.shape = shape
	body.add_child(cs)
	body.position = box.get_center()
	add_child(body)
	_uman_prop_colliders.append(body.get_rid())


## Exact mesh collision for every visible mesh under `inst`.  Attached as a
## StaticBody child of the MeshInstance3D so the shape inherits the mesh's own
## (possibly rotated / scaled) transform.  Never an unrotated AABB: that is
## what used to plug pipes, arches, fences, ramps and rails.
func _uman_attach_mesh_collider(inst: Node3D) -> void:
	if inst == null:
		return
	if inst is Node3D and inst.is_inside_tree():
		inst.force_update_transform()
	for node in _uman_find_meshes(inst):
		if node is MeshInstance3D:
			_uman_add_trimesh_to_mesh(node as MeshInstance3D)


func _uman_add_trimesh_to_mesh(mi: MeshInstance3D) -> bool:
	if mi == null or mi.mesh == null or not mi.visible:
		return false
	if bool(mi.get_meta("uman_trimesh_col", false)):
		return false
	var mesh_name := String(mi.name).to_lower()
	if mesh_name.contains("-col") or mesh_name.contains("-convcol"):
		return false
	var shape := _uman_combined_trimesh(mi.mesh)
	if shape == null:
		return false
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "uman_mesh_col_%d" % _uman_prop_colliders.size()
	body.collision_layer = 1
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	mi.add_child(body)
	mi.set_meta("uman_trimesh_col", true)
	_uman_prop_colliders.append(body.get_rid())
	return true


## create_trimesh_shape() on a multi-surface ArrayMesh only keeps one surface
## in some importer outputs; merge them explicitly so holes stay holes.
func _uman_combined_trimesh(mesh: Mesh) -> ConcavePolygonShape3D:
	if mesh == null:
		return null
	if mesh.get_surface_count() <= 1:
		return mesh.create_trimesh_shape() as ConcavePolygonShape3D
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in range(mesh.get_surface_count()):
		st.append_from(mesh, s, Transform3D.IDENTITY)
	var merged := st.commit()
	if merged == null:
		return null
	return merged.create_trimesh_shape() as ConcavePolygonShape3D


## Authored GLB colliders on pipes / arches / rings / bridges are often a
## single convex hull or box that seals the opening.  Swap those for the exact
## visible mesh whenever the shape overlaps one.
func _uman_audit_glb_colliders() -> void:
	var root := get_node_or_null("MapRoot")
	if root == null:
		return
	var keys := ["pipe", "tunnel", "arch", "gate", "ring", "rotunda",
			"pavilion", "bridge", "stunt", "ramp", "pergola"]
	var patched := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var lname := String(n.name).to_lower()
		var matched := false
		for k in keys:
			if lname.contains(k):
				matched = true
				break
		if matched:
			patched += _uman_replace_blocking_shapes(n)
		for c in n.get_children():
			stack.append(c)
	if patched > 0:
		print("[UMAN] glb blocker colliders replaced=", patched)
	var landmark_keys := ["tower", "cathedral", "church", "monument", "obelisk",
			"gazebo", "rotunda", "pavilion", "lighthouse", "pier", "wall",
			"bridge", "arch", "pergola", "facade"]
	var added_landmarks := 0
	for found in root.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var lnm := String(mi.name).to_lower()
		if lnm.contains("-col") or lnm.contains("city_building") \
				or lnm.contains("gate") or lnm.contains("stunt") \
				or lnm.contains("ground") or lnm.contains("path") or lnm.contains("road"):
			continue
		var is_landmark := false
		for lk in landmark_keys:
			if lnm.contains(lk):
				is_landmark = true
				break
		if not is_landmark:
			continue
		var has_col := (mi.get_parent() is StaticBody3D) \
				or not mi.find_children("*", "StaticBody3D", true, false).is_empty() \
				or (mi.get_parent() != null and not mi.get_parent().find_children("*", "StaticBody3D", false, false).is_empty())
		if not has_col and _uman_add_trimesh_to_mesh(mi):
			added_landmarks += 1
	if added_landmarks > 0:
		print("[UMAN] added trimesh colliders for GLB landmarks=", added_landmarks)


func _uman_replace_blocking_shapes(node: Node) -> int:
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		var self_mi := node as MeshInstance3D
		if self_mi.visible and self_mi.mesh != null:
			meshes.append(self_mi)
	for found in node.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		if mi != null and mi.visible and mi.mesh != null:
			meshes.append(mi)
	if meshes.is_empty():
		return 0
	var removed := 0
	for found in node.find_children("*", "CollisionShape3D", true, false):
		var cs := found as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		if not (cs.shape is ConvexPolygonShape3D or cs.shape is BoxShape3D):
			continue
		var sbox := _uman_shape_world_aabb(cs)
		if sbox.size.length_squared() <= 0.0:
			continue
		var blocking := false
		for mi in meshes:
			if (mi.global_transform * mi.mesh.get_aabb()).intersects(sbox):
				blocking = true
				break
		if not blocking:
			continue
		cs.disabled = true
		cs.queue_free()
		removed += 1
	if removed == 0:
		return 0
	var added := 0
	for mi in meshes:
		if _uman_add_trimesh_to_mesh(mi):
			added += 1
	return added


func _uman_shape_world_aabb(cs: CollisionShape3D) -> AABB:
	var shp := cs.shape
	var local := AABB()
	if shp is BoxShape3D:
		var sz := (shp as BoxShape3D).size
		local = AABB(-sz * 0.5, sz)
	elif shp is ConvexPolygonShape3D:
		var pts := (shp as ConvexPolygonShape3D).get_points()
		var first := true
		for p in pts:
			if first:
				local = AABB(p, Vector3.ZERO)
				first = false
			else:
				local = local.expand(p)
	else:
		return AABB()
	if cs.is_inside_tree():
		cs.force_update_transform()
	return cs.global_transform * local


func _uman_find_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_uman_find_meshes(c))
	return out


func _uman_find_with_prefix(node: Node, prefix: String) -> Array:
	var out: Array = []
	if node.name.begins_with(prefix):
		out.append(node)
	for c in node.get_children():
		out.append_array(_uman_find_with_prefix(c, prefix))
	return out


func _process(delta: float) -> void:
	super._process(delta)
	if not _uman_fx_ready:
		return
	# Рестарт тільки якщо дрон справді нижче поверхні води.  Раніше будь-яка
	# платформа/палуба над water-еліпсом з y<0.9 вважалася «водою» і кидала
	# пілота на старт.  Платформи мають.collider вище води — перевіряємо його.
	var drone := get_node_or_null("Drone") as Drone
	if drone != null and is_instance_valid(drone):
		var p := drone.global_position
		var below_water := p.y < _uman_water_y + 0.9
		var supported := false
		if below_water and _uman_is_water(p):
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(
					p, p + Vector3.DOWN * 2.0)
			q.collision_mask = 1
			q.exclude = [(drone as CollisionObject3D).get_rid()]
			var support := space.intersect_ray(q)
			if not support.is_empty():
				var sy := (support["position"] as Vector3).y
				var col = support.get("collider")
				var is_safety_ground := col is CollisionObject3D \
						and (col as CollisionObject3D).name == "UmanSafetyGround"
				supported = not is_safety_ground \
						and sy > _uman_water_y - 0.2 and sy <= p.y + 0.05
		var in_water := (below_water and _uman_is_water(p) and not supported) \
				or p.y < -6.0
		if in_water:
			_uman_water_timer += delta
			if _uman_water_timer > 1.2:
				drone.reset()
				_uman_water_timer = 0.0
		else:
			_uman_water_timer = 0.0
	for r in _uman_ripples:
		var node := r.node as MeshInstance3D
		if node == null:
			continue
		var phase: float = fmod(Time.get_ticks_msec() * 0.00045 + float(r.phase), 1.0)
		node.scale = Vector3.ONE * (0.55 + phase * 2.4)
		var mat := node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = (1.0 - phase) * 0.38
