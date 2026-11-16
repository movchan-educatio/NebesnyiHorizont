## Flight School & Interactive Pilot Training Course («ШКОЛА ПІЛОТА»).
##
## A ten-module beginner course on a dedicated 190 m training strip:
##   1. ARM/DISARM  — arm, disarm on the ground, arm again;
##   2. HOVER       — throttle to 2–4 m and hold altitude;
##   3. STICK BASICS— pitch/roll excursions and returning the right stick to centre;
##   4. YAW         — turn ~70° with the left stick and return to the start heading;
##   5. GATE 1      — fly forward through a wide arch;
##   6. SLALOM      — two offset gates, roll left/right;
##   7. ALTITUDE    — a low gate followed by a high gate (throttle + pitch);
##   8. WINDOW      — pass through a 3.6 × 3.2 m opening in a solid wall;
##   9. BRAKE       — stop inside the marked zone;
##  10. LANDING     — soft touchdown and disarm.
##
## The course is built relative to the tutorial spawn on the north field of
## the village map.  Trees and props are excluded from the strip by
## frontline_terrain.gd, so the runway is always readable.
class_name FlightSchool
extends Node

const MenuUI := preload("res://GUI/ui/MenuUI.gd")

signal lesson_advanced(step: int, title: String)
signal course_completed

enum Step {
	ARMING = 0,
	HOVER = 1,
	STICK_BASICS = 2,
	YAW_CONTROL = 3,
	FORWARD_GATE = 4,
	SLALOM = 5,
	ALTITUDE_GATES = 6,
	WINDOW_PASS = 7,
	BRAKE_STOP = 8,
	LANDING = 9,
	COMPLETED = 10
}

const TOTAL_MODULES := 10
const HOVER_HOLD := 4.0
const HOVER_MIN := 2.0
const HOVER_MAX := 4.2

const STEP_DATA := {
	Step.ARMING: {
		"title": "УВІМКНЕННЯ / ВИМКНЕННЯ ДВИГУНІВ",
		"inst": "Натисніть ПРОБІЛ — двигуни увімкнено. Не злітаючи, натисніть ПРОБІЛ ще раз, щоб вимкнути. Потім увімкніть двигуни знову.",
		"tip": "ПРОБІЛ — це головний вимикач. Спочатку завжди перевіряйте, що дрон на землі.",
		"focus": "none"
	},
	Step.HOVER: {
		"title": "ГАЗ ТА УТРИМАННЯ ВИСОТИ",
		"inst": "Плавно піднімайте газ (W або лівий стік ↑). Тримайте дрон на висоті 2–4 м у зеленому маяку 4 секунди.",
		"tip": "Газ у FPV прямий: 0% — двигуни стоять, ~45% — висіння. Не смикайте стік.",
		"focus": "left"
	},
	Step.STICK_BASICS: {
		"title": "ПРАВИЙ СТІК: ТАНГАЖ І КРЕН",
		"inst": "Нахиліть дрон носом уперед або назад (↑/↓), поверніть стік у центр. Потім — крен ліворуч/праворуч (←/→) і знову в центр.",
		"tip": "Правий стік керує нахилом. Після кожного руху повертайте його в центр — дрон вирівняється.",
		"focus": "right"
	},
	Step.YAW_CONTROL: {
		"title": "РИСКАННЯ (YAW)",
		"inst": "Поверніть дрон лівим стіком ←/→ приблизно на 70°. Потім поверніть його назад на початковий курс і втримайте висоту.",
		"tip": "Рискання — це поворот навколо вертикальної осі. Лівий стік ←/→, не нахиляйте дрон.",
		"focus": "left"
	},
	Step.FORWARD_GATE: {
		"title": "ПЕРШИЙ ПОЛІТ УПЕРЕД · ВОРОТА 1",
		"inst": "Нахиліть ніс уперед (правий стік ↑) і пролетіть крізь широкі ворота. Після воріт вирівняйте дрон і пригальмуйте.",
		"tip": "Ворота широкі навмисно. Дивіться на просвіт, а не на стійки.",
		"focus": "right"
	},
	Step.SLALOM: {
		"title": "СЛАЛОМ · КРЕН ЛІВОРУЧ / ПРАВОРУЧ",
		"inst": "Пройдіть два зміщені ворота: спочатку ліві, потім праві. Крен — правий стік ←/→, газ — лівий стік.",
		"tip": "У віражі додавайте трохи газу, інакше дрон просівде і зачепить нижню стійку.",
		"focus": "right"
	},
	Step.ALTITUDE_GATES: {
		"title": "ВИСОТА · НИЗЬКІ ТА ВИСОКІ ВОРОТА",
		"inst": "Спочатку пролетіть низько (газ менше), потім підніміться і пролетіть високі ворота. Дивіться на цифри висоти.",
		"tip": "Висота змінюється газом, а не нахилом. Піднімайтесь плавно, за 1–2 секунди до воріт.",
		"focus": "left"
	},
	Step.WINDOW_PASS: {
		"title": "ТОЧНИЙ ПРОЛІТ КРІЗЬ ВІКНО",
		"inst": "Попереду стіна з вікном 3.6 x 3.2 м. Наведіть дрон у центр отвору і пролетіть крізь нього. Обліт стіни не зараховується.",
		"tip": "Це вже справжня точність: вирівняйте крен, тримайте висоту і не поспішайте.",
		"focus": "right"
	},
	Step.BRAKE_STOP: {
		"title": "ГАЛЬМУВАННЯ У ЗОНІ",
		"inst": "Загальмуйте в жовтій зоні: відхиліть ніс назад (правий стік ↓) і додайте газу. Утримайте швидкість нижче 2.5 м/с.",
		"tip": "Дрон не має гальм: щоб зупинитись, нахиліть його назад і компенсуйте втрату висоти газом.",
		"focus": "both"
	},
	Step.LANDING: {
		"title": "М'ЯКА ПОСАДКА ТА ВИМКНЕННЯ ДВИГУНІВ",
		"inst": "Опустіться на майданчик зі швидкістю < 2 м/с, торкніться землі та вимкніть двигуни (ПРОБІЛ) на висоті < 0.7 м.",
		"tip": "Перед вимкненням двигунів переконайтеся, що дрон стоїть. Це фінальний модуль курсу.",
		"focus": "left"
	},
	Step.COMPLETED: {
		"title": "КУРС ЗАВЕРШЕНО",
		"inst": "Ви пройшли всі 10 модулів: від першого увімкнення двигунів до точної посадки.",
		"tip": "Сертифікат оператора FPV здобуто. Тепер можна переходити до бойових вильотів.",
		"focus": "none"
	}
}

const STEP_DATA_EN := {
	Step.ARMING: {
		"title": "ARM / DISARM MOTORS",
		"inst": "Press SPACE to arm. Without taking off, press SPACE again to disarm, then arm once more.",
		"tip": "SPACE is the master switch. Always confirm the drone is on the ground before disarming.",
		"focus": "none"
	},
	Step.HOVER: {
		"title": "THROTTLE & ALTITUDE HOLD",
		"inst": "Raise the throttle gently (W or left stick ↑). Hold 2–4 m inside the green beacon for 4 seconds.",
		"tip": "FPV throttle is direct: 0% is stopped; about 45% is hover. Make smooth inputs.",
		"focus": "left"
	},
	Step.STICK_BASICS: {
		"title": "RIGHT STICK: PITCH & ROLL",
		"inst": "Pitch the nose forward or back (↑/↓), then centre the stick. Next, roll left or right (←/→) and centre it again.",
		"tip": "The right stick controls attitude. Centre it after each input and the drone will level out.",
		"focus": "right"
	},
	Step.YAW_CONTROL: {
		"title": "YAW CONTROL",
		"inst": "Use the left stick (←/→) to turn about 70°. Return to your original heading while maintaining altitude.",
		"tip": "Yaw rotates around the vertical axis. Use the left stick; do not bank the drone.",
		"focus": "left"
	},
	Step.FORWARD_GATE: {
		"title": "FIRST FORWARD FLIGHT · GATE 1",
		"inst": "Pitch forward (right stick ↑) and fly through the wide gate. Level out and slow down after passing it.",
		"tip": "The gate is deliberately wide. Aim through the opening, not at the posts.",
		"focus": "right"
	},
	Step.SLALOM: {
		"title": "SLALOM · LEFT / RIGHT BANK",
		"inst": "Fly through two offset gates: left first, then right. Roll with the right stick; control throttle with the left.",
		"tip": "Add a little throttle in a turn or the drone may sink and clip the lower post.",
		"focus": "right"
	},
	Step.ALTITUDE_GATES: {
		"title": "ALTITUDE · LOW & HIGH GATES",
		"inst": "Fly through the low gate first, then climb for the high gate. Watch the altitude readout.",
		"tip": "Altitude is controlled with throttle, not pitch. Start climbing 1–2 seconds before the gate.",
		"focus": "left"
	},
	Step.WINDOW_PASS: {
		"title": "PRECISION WINDOW PASS",
		"inst": "A wall ahead has a 3.6 × 3.2 m opening. Line up with the centre and fly through it; going around does not count.",
		"tip": "This requires precision: level the drone, hold altitude, and take your time.",
		"focus": "right"
	},
	Step.BRAKE_STOP: {
		"title": "BRAKE INSIDE THE ZONE",
		"inst": "Brake in the yellow zone: pitch back (right stick ↓), add throttle, and hold speed below 2.5 m/s.",
		"tip": "There are no brakes. Pitch back to slow down and add throttle to offset the altitude loss.",
		"focus": "both"
	},
	Step.LANDING: {
		"title": "SOFT LANDING & DISARM",
		"inst": "Touch down on the pad below 2 m/s, then disarm below 0.7 m altitude.",
		"tip": "Make sure the drone has settled before disarming. This is the final lesson.",
		"focus": "left"
	},
	Step.COMPLETED: {
		"title": "COURSE COMPLETE",
		"inst": "You completed all 10 modules, from arming the motors to a precision landing.",
		"tip": "FPV pilot certificate earned. You are ready for operational sorties.",
		"focus": "none"
	}
}


func _tx(ua: String, en: String) -> String:
	return en if MenuUI.is_english() else ua


func _step_data(step: int = -1) -> Dictionary:
	var data: Dictionary = STEP_DATA_EN if MenuUI.is_english() else STEP_DATA
	var key := current_step if step < 0 else step
	return data.get(key, {})

var current_step: int = Step.ARMING
var is_active: bool = false
var ground_y: float = 0.0

# Scene & drone
var level: Node3D = null
var drone: Drone = null
var school_root: Node3D = null
var start_pos := Vector3.ZERO

# Course objects / gates
var hover_pos := Vector3.ZERO
var hover_beacon: MeshInstance3D = null
var gate_forward: Dictionary = {}
var gate_slalom_a: Dictionary = {}
var gate_slalom_b: Dictionary = {}
var gate_low: Dictionary = {}
var gate_high: Dictionary = {}
var gate_window: Dictionary = {}
var window_node: Node3D = null
var brake_pos := Vector3.ZERO
var brake_node: Node3D = null
var landing_pos := Vector3.ZERO
var landing_node: Node3D = null
var _guide_node: MultiMeshInstance3D = null
var _overview_cam: Camera3D = null

# Progress / timing
var hover_timer := 0.0
var flare_timer := 0.0
var settle_timer := 0.0
var course_time := 0.0
var retries := 0
var help_opens := 0
var gate_misses := 0

# Internal phase state
var _prev_pos := Vector3.ZERO
var _has_prev := false
var _step_alt := 0.0
var _step_speed := 0.0
var _step_heading := 0.0
var _step_yaw_start := 0.0
var _yaw_turned := false
var _yaw_dir := 0.0
var _arm_phase := 0
var _was_armed := false
var _basic_phase := 0
var _basic_hold := 0.0
var _slalom_stage := 0
var _altitude_stage := 0
var _miss_cooldown := 0.0
var _toast_timer := 0.0
var _toast_panel: PanelContainer = null
var _toast_lbl: Label = null
var _error_cooldown := 0.0
var _help_open := false
var _help_cooldown := 0.0

# HUD
var hud_container: Control = null
var panel_card: PanelContainer = null
var title_lbl: Label = null
var progress_lbl: Label = null
var inst_lbl: Label = null
var metric_lbl: Label = null
var _dots_row: HBoxContainer = null
var _dots: Array[Label] = []
var _help_overlay: Control = null


func initialize(p_level: Node3D, p_drone: Drone, p_ground_y: float) -> void:
	level = p_level
	drone = p_drone
	ground_y = p_ground_y
	is_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_step = Step.ARMING
	hover_timer = 0.0
	flare_timer = 0.0
	settle_timer = 0.0
	course_time = 0.0
	retries = 0
	help_opens = 0
	gate_misses = 0
	_arm_phase = 0
	_basic_phase = 0
	_basic_hold = 0.0
	_slalom_stage = 0
	_altitude_stage = 0
	_prev_pos = drone.global_position if drone != null else Vector3.ZERO
	_has_prev = true
	_build_world_track()
	if OS.has_environment("DRONE_TUTORIAL_STEP"):
		_qa_jump_to_step(int(OS.get_environment("DRONE_TUTORIAL_STEP")))


# ---------------------------------------------------------------------------
#  World: a readable 190 m strip with rectangular arches, a window wall,
#  a brake circle and a landing pad.
# ---------------------------------------------------------------------------
func _build_world_track() -> void:
	if level == null:
		return
	school_root = Node3D.new()
	school_root.name = "FlightSchoolTrack"
	level.add_child(school_root)

	var source := drone.global_position if drone != null else Vector3.ZERO
	start_pos = Vector3(source.x, ground_y, source.z)

	# Hover beacon 8 m ahead, 2.8 m above the grass.
	hover_pos = Vector3(start_pos.x, _ground_at(start_pos.x, start_pos.z - 8.0) + 2.8,
			start_pos.z - 8.0)
	hover_beacon = _create_hover_beacon(hover_pos)
	school_root.add_child(hover_beacon)

	# Gate sequence.  Offsets are relative to the spawn and run south (-Z).
	gate_forward = _create_arch(Vector2(start_pos.x, start_pos.z - 35.0),
			7.0, 4.2, 2.6, _tx("ВОРОТА 1 · ШИРОКІ", "GATE 1 · WIDE"), Color(0.20, 0.85, 0.95))
	gate_slalom_a = _create_arch(Vector2(start_pos.x - 9.0, start_pos.z - 60.0),
			4.2, 3.6, 2.4, _tx("СЛАЛОМ A · ЛІВО", "SLALOM A · LEFT"), Color(0.95, 0.70, 0.20))
	gate_slalom_b = _create_arch(Vector2(start_pos.x + 9.0, start_pos.z - 80.0),
			4.2, 3.6, 2.4, _tx("СЛАЛОМ B · ПРАВО", "SLALOM B · RIGHT"), Color(0.95, 0.70, 0.20))
	gate_low = _create_arch(Vector2(start_pos.x, start_pos.z - 105.0),
			6.0, 2.8, 2.0, _tx("НИЗЬКО · 2 м", "LOW · 2 m"), Color(0.75, 0.55, 0.95))
	gate_high = _create_arch(Vector2(start_pos.x, start_pos.z - 123.0),
			6.0, 3.2, 5.0, _tx("ВИСОКО · 5 м", "HIGH · 5 m"), Color(0.75, 0.55, 0.95))
	gate_window = _create_window_wall(Vector2(start_pos.x, start_pos.z - 150.0))
	brake_pos = Vector3(start_pos.x, _surface_ground_at(start_pos.x, start_pos.z - 166.0, 2.8) + 0.08,
			start_pos.z - 166.0)
	brake_node = _create_brake_zone(brake_pos)
	landing_pos = Vector3(start_pos.x, _surface_ground_at(start_pos.x, start_pos.z - 180.0, 3.25) + 0.14,
			start_pos.z - 180.0)
	landing_node = _create_landing_pad(landing_pos)

	for node in [gate_forward, gate_slalom_a, gate_slalom_b, gate_low, gate_high,
			gate_window]:
		if node.has("node") and node["node"] != null:
			school_root.add_child(node["node"])
	school_root.add_child(brake_node)
	school_root.add_child(landing_node)
	_build_guide_path()
	_update_progress_dots()

	if OS.has_environment("DRONE_TUTORIAL_OVERVIEW"):
		_spawn_overview_camera()


func _ground_at(x: float, z: float) -> float:
	if level != null and level.has_method("_find_ground_y"):
		return float(level.call("_find_ground_y", x, z))
	return ground_y


## Samples both analytic/mesh terrain height and local physics colliders across
## `half_extent` so landing/brake markers sit cleanly above the visible surface.
func _surface_ground_at(x: float, z: float, half_extent: float = 0.0) -> float:
	var best := _ground_at(x, z)
	var fmap := ""
	if level != null and level.get("frontline_map") != null:
		fmap = String(level.get("frontline_map"))
	var ft = load("res://scripts/util/frontline_terrain.gd") if not fmap.is_empty() else null
	var wl := -999.0
	if ft != null:
		wl = float(ft.water_level(fmap))
	var offsets := [0.0] if half_extent <= 0.01 else [-half_extent, 0.0, half_extent]
	var excl: Array[RID] = []
	if drone is CollisionObject3D:
		excl.append((drone as CollisionObject3D).get_rid())
	var space: PhysicsDirectSpaceState3D = null
	if level != null and level.is_inside_tree():
		space = level.get_world_3d().direct_space_state
	for ox in offsets:
		for oz in offsets:
			var px: float = x + float(ox)
			var pz: float = z + float(oz)
			var h := _ground_at(px, pz)
			best = maxf(best, h)
			if ft != null:
				best = maxf(best, float(ft.mesh_surface_height(fmap, px, pz)))
			if space != null:
				var q := PhysicsRayQueryParameters3D.create(
						Vector3(px, h + 2.8, pz), Vector3(px, h - 3.0, pz))
				q.collision_mask = 1
				q.exclude = excl
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					var hy := (hit["position"] as Vector3).y
					if hy <= h + 2.5 and hy >= h - 2.0:
						best = maxf(best, hy)
	if wl > -100.0:
		best = maxf(best, wl + 0.35)
	return best


func _emissive(color: Color, alpha: float = 1.0, energy: float = 3.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _create_hover_beacon(pos: Vector3) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.name = "HoverBeacon"
	root.position = pos
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.55
	root.mesh = torus
	root.rotation_degrees.x = 90.0
	root.material_override = _emissive(Color(0.25, 1.0, 0.45), 0.85, 3.5)

	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.1
	cyl.bottom_radius = 2.1
	cyl.height = 5.6
	beam.mesh = cyl
	beam.position = Vector3(0.0, -2.8, 0.0)
	var beam_mat := _emissive(Color(0.18, 0.95, 0.40), 0.10, 1.2)
	beam.material_override = beam_mat
	root.add_child(beam)

	var lbl := Label3D.new()
	lbl.text = _tx("ВИСІННЯ 2–4 м", "HOVER 2–4 m")
	lbl.font_size = 30
	lbl.pixel_size = 0.010
	lbl.outline_size = 7
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.55, 1.0, 0.65)
	lbl.position = Vector3(0.0, 3.6, 0.0)
	root.add_child(lbl)
	return root


func _create_arch(at: Vector2, width: float, height: float, center_h: float,
		label_text: String, color: Color) -> Dictionary:
	var gy := _ground_at(at.x, at.y)
	var root := Node3D.new()
	root.name = "TrainingGate"
	root.position = Vector3(at.x, gy, at.y)

	var top := center_h + height * 0.5
	var post_mat := _emissive(color, 1.0, 2.2)
	var post := BoxMesh.new()
	var size := Vector3(0.16, top + 0.6, 0.16)
	post.size = size
	for sx in [-1.0, 1.0]:
		var m := MeshInstance3D.new()
		m.mesh = post
		m.position = Vector3(sx * (width * 0.5 + 0.08), (top - 0.6) * 0.5, 0.0)
		m.material_override = post_mat
		root.add_child(m)

	var lintel := BoxMesh.new()
	lintel.size = Vector3(width + 0.5, 0.16, 0.16)
	var lm := MeshInstance3D.new()
	lm.mesh = lintel
	lm.position = Vector3(0.0, top, 0.0)
	lm.material_override = post_mat
	root.add_child(lm)

	# Soft vertical light column so the next gate is visible over the field.
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.28
	cyl.bottom_radius = 0.28
	cyl.height = 24.0
	beam.mesh = cyl
	# The plume sits beside the right post, above the lintel: never inside the
	# opening and never behind the gate label.
	beam.position = Vector3(width * 0.5 + 1.2, top + 12.0, 0.0)
	beam.material_override = _emissive(color, 0.09, 1.0)
	root.add_child(beam)

	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 56
	lbl.pixel_size = 0.022
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = color.lightened(0.25)
	lbl.position = Vector3(0.0, top + 1.4, 0.0)
	root.add_child(lbl)

	return {
		"node": root,
		"pos": Vector3(at.x, gy + center_h, at.y),
		"z": at.y,
		"half_w": width * 0.5 - 0.25,
		"half_h": height * 0.5 - 0.2,
		"name": label_text
	}


func _create_window_wall(at: Vector2) -> Dictionary:
	var gy := _ground_at(at.x, at.y)
	var root := Node3D.new()
	root.name = "TrainingWindowWall"
	root.position = Vector3(at.x, gy, at.y)

	var wall_w := 12.0
	var wall_h := 7.0
	var hole_w := 3.6
	var hole_h := 3.2
	var hole_cy := 2.8
	var hole_bottom := hole_cy - hole_h * 0.5
	var hole_top := hole_cy + hole_h * 0.5
	var side_w := (wall_w - hole_w) * 0.5
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.32, 0.33, 0.31)
	wall_mat.roughness = 0.94
	wall_mat.metallic = 0.05
	var body := StaticBody3D.new()
	body.name = "WindowWallBody"
	root.add_child(body)

	_add_wall_box(root, body, Vector3(-(hole_w * 0.5 + side_w * 0.5), wall_h * 0.5, 0.0),
			Vector3(side_w, wall_h, 0.35), wall_mat)
	_add_wall_box(root, body, Vector3(hole_w * 0.5 + side_w * 0.5, wall_h * 0.5, 0.0),
			Vector3(side_w, wall_h, 0.35), wall_mat)
	_add_wall_box(root, body, Vector3(0.0, hole_bottom * 0.5, 0.0),
			Vector3(hole_w, hole_bottom, 0.35), wall_mat)
	_add_wall_box(root, body, Vector3(0.0, (hole_top + wall_h) * 0.5, 0.0),
			Vector3(hole_w, wall_h - hole_top, 0.35), wall_mat)

	var frame_mat := _emissive(Color(1.0, 0.92, 0.45), 1.0, 3.0)
	var hw := hole_w * 0.5
	for spec in [
		[Vector3(-hw - 0.07, hole_cy, 0.19), Vector3(0.14, hole_h + 0.3, 0.14)],
		[Vector3(hw + 0.07, hole_cy, 0.19), Vector3(0.14, hole_h + 0.3, 0.14)],
		[Vector3(0.0, hole_top + 0.07, 0.19), Vector3(hole_w + 0.3, 0.14, 0.14)],
		[Vector3(0.0, hole_bottom - 0.07, 0.19), Vector3(hole_w + 0.3, 0.14, 0.14)],
	]:
		var fm := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = spec[1]
		fm.mesh = fb
		fm.position = spec[0]
		fm.material_override = frame_mat
		root.add_child(fm)

	var lbl := Label3D.new()
	lbl.text = _tx("ВІКНО 3.6 x 3.2 м", "WINDOW 3.6 × 3.2 m")
	lbl.font_size = 58
	lbl.pixel_size = 0.022
	lbl.outline_size = 12
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.95, 0.60)
	lbl.position = Vector3(0.0, wall_h + 1.2, 0.0)
	root.add_child(lbl)

	return {
		"node": root,
		"pos": Vector3(at.x, gy + hole_cy, at.y),
		"z": at.y,
		"half_w": hw - 0.15,
		"half_h": hole_h * 0.5 - 0.15,
		"name": _tx("ВІКНО", "WINDOW")
	}


func _add_wall_box(root: Node3D, body: StaticBody3D, pos: Vector3, size: Vector3,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.position = pos
	mi.material_override = mat
	root.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _create_brake_zone(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "BrakeZone"
	root.position = pos + Vector3.UP * 0.04
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 7.0
	cyl.bottom_radius = 7.0
	cyl.height = 0.06
	disc.mesh = cyl
	disc.material_override = _emissive(Color(1.0, 0.72, 0.15), 0.28, 1.4)
	root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 6.7
	torus.outer_radius = 7.2
	ring.mesh = torus
	ring.rotation_degrees.x = 90.0
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.material_override = _emissive(Color(1.0, 0.75, 0.2), 0.9, 2.4)
	root.add_child(ring)
	var lbl := Label3D.new()
	lbl.text = _tx("ЗОНА ГАЛЬМУВАННЯ", "BRAKING ZONE")
	lbl.font_size = 52
	lbl.pixel_size = 0.020
	lbl.outline_size = 11
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.82, 0.35)
	lbl.position = Vector3(0.0, 2.2, 0.0)
	root.add_child(lbl)
	return root


func _create_landing_pad(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "LandingPad"
	root.position = pos

	# Solid deck collider whose top face sits exactly at local y = 0.0 (= landing_pos.y)
	var body := StaticBody3D.new()
	body.name = "LandingPadCollider"
	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(7.0, 0.30, 7.0)
	col.shape = col_shape
	col.position = Vector3(0.0, -0.15, 0.0)
	body.add_child(col)
	root.add_child(body)

	# Concrete top deck flush at local y = 0.0
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.8, 0.16, 6.8)
	pad.mesh = box
	pad.position = Vector3(0.0, -0.08, 0.0)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.16, 0.19, 0.16)
	pad_mat.roughness = 0.85
	pad.material_override = pad_mat
	root.add_child(pad)

	# Visual foundation plinth reaching into uneven perimeter terrain (no extra collision)
	var plinth := MeshInstance3D.new()
	var plinth_box := BoxMesh.new()
	plinth_box.size = Vector3(7.4, 2.2, 7.4)
	plinth.mesh = plinth_box
	plinth.position = Vector3(0.0, -1.25, 0.0)
	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color(0.11, 0.13, 0.11)
	plinth_mat.roughness = 0.92
	plinth.material_override = plinth_mat
	root.add_child(plinth)

	# Painted "H" helipad markings flush above top deck
	var h_mat := _emissive(Color(0.85, 1.0, 0.72), 0.95, 1.8)
	for x_off in [-0.75, 0.75]:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.24, 0.02, 2.2)
		bar.mesh = bm
		bar.position = Vector3(x_off, 0.02, 0.0)
		bar.material_override = h_mat
		root.add_child(bar)
	var cross := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.74, 0.02, 0.24)
	cross.mesh = cm
	cross.position = Vector3(0.0, 0.02, 0.0)
	cross.material_override = h_mat
	root.add_child(cross)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 2.8
	torus.outer_radius = 3.05
	ring.mesh = torus
	ring.position = Vector3(0.0, 0.04, 0.0)
	ring.material_override = _emissive(Color(0.35, 1.0, 0.45), 1.0, 3.0)
	root.add_child(ring)
	var lbl := Label3D.new()
	lbl.text = _tx("МАЙДАНЧИК [H] · ВИМКНЕННЯ ДВИГУНІВ",
			"LANDING PAD [H] · DISARM MOTORS")
	lbl.font_size = 52
	lbl.pixel_size = 0.020
	lbl.outline_size = 11
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.55, 1.0, 0.60)
	lbl.position = Vector3(0.0, 2.2, 0.0)
	root.add_child(lbl)
	return root


func _build_guide_path() -> void:
	var points: Array[Vector3] = [start_pos,
			Vector3(start_pos.x, 0.0, start_pos.z - 8.0)]
	for gate in [gate_forward, gate_slalom_a, gate_slalom_b, gate_low, gate_high,
			gate_window]:
		points.append(Vector3(gate["pos"].x, 0.0, gate["z"]))
	points.append(Vector3(brake_pos.x, 0.0, brake_pos.z))
	points.append(Vector3(landing_pos.x, 0.0, landing_pos.z))

	var transforms: Array = []
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var count := int(length / 5.0)
		for k in range(1, count):
			var p := a + dir * (float(k) * 5.0)
			var gy := _ground_at(p.x, p.z)
			var yaw := atan2(-dir.z, dir.x)
			transforms.append(Transform3D(Basis(Vector3.UP, yaw),
					Vector3(p.x, gy + 0.07, p.z)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = Vector3(2.2, 0.035, 0.42)
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	_guide_node = MultiMeshInstance3D.new()
	_guide_node.name = "GuideDashes"
	_guide_node.multimesh = mm
	_guide_node.material_override = _emissive(Color(0.25, 0.85, 0.95), 0.42, 1.0)
	_guide_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	school_root.add_child(_guide_node)


func _spawn_overview_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "TutorialOverviewCamera"
	cam.fov = 70.0
	cam.far = 3000.0
	cam.position = Vector3(start_pos.x + 20.0, ground_y + 42.0, start_pos.z + 45.0)
	add_child(cam)
	cam.look_at(Vector3(start_pos.x, ground_y + 2.0, start_pos.z - 95.0), Vector3.UP)
	_overview_cam = cam
	cam.current = true


## Re-assert the QA overview camera after the level has finished its own camera
## setup.  Without this the drone FPV camera wins the last `current` race.
func show_overview_camera() -> void:
	if _overview_cam != null and is_instance_valid(_overview_cam):
		_overview_cam.current = true


# ---------------------------------------------------------------------------
#  HUD: compact bottom card + progress dots + first-flight help overlay.
# ---------------------------------------------------------------------------
func setup_hud(hud_root: Node) -> void:
	if hud_root == null:
		return
	hud_container = Control.new()
	hud_container.name = "FlightSchoolHUD"
	hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(hud_container)

	var vp_size := Vector2(1280, 720)
	if hud_root is Control:
		var r := (hud_root as Control).get_viewport_rect().size
		if r.x > 0.0 and r.y > 0.0:
			vp_size = r
	var safe := MenuUI.get_safe_margins(vp_size)
	var safe_top := float(safe.get("top", 0.0))

	var card_anchor := PanelContainer.new()
	card_anchor.name = "InstructorCard"
	card_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_anchor.set_anchors_preset(Control.PRESET_CENTER_TOP)
	card_anchor.offset_left = -320.0
	card_anchor.offset_right = 320.0
	card_anchor.offset_top = safe_top + 78.0
	card_anchor.offset_bottom = safe_top + 172.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.055, 0.040, 0.90)
	sb.border_color = MenuUI.WARN_AMBER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card_anchor.add_theme_stylebox_override("panel", sb)
	hud_container.add_child(card_anchor)
	panel_card = card_anchor

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 3)
	card_anchor.add_child(vb)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	title_lbl = Label.new()
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	top.add_child(title_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_dots_row = HBoxContainer.new()
	_dots_row.add_theme_constant_override("separation", 3)
	top.add_child(_dots_row)
	for i in range(TOTAL_MODULES):
		var d := Label.new()
		d.text = "●"
		d.add_theme_font_size_override("font_size", 10)
		d.add_theme_color_override("font_color", Color(0.35, 0.40, 0.36))
		_dots_row.add_child(d)
		_dots.append(d)
	progress_lbl = Label.new()
	progress_lbl.add_theme_font_size_override("font_size", 12)
	progress_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	top.add_child(progress_lbl)

	var help_btn := Button.new()
	help_btn.name = "TutorialHelpBtn"
	help_btn.text = "?"
	help_btn.tooltip_text = "ДОВІДКА"
	help_btn.custom_minimum_size = Vector2(36, 28)
	help_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.add_theme_font_size_override("font_size", 14)
	help_btn.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(0.08, 0.14, 0.10, 0.92)
	hsb.border_color = MenuUI.WARN_AMBER
	hsb.set_border_width_all(1)
	hsb.set_corner_radius_all(4)
	help_btn.add_theme_stylebox_override("normal", hsb)
	help_btn.add_theme_stylebox_override("hover", hsb)
	help_btn.add_theme_stylebox_override("pressed", hsb)
	help_btn.pressed.connect(open_help)
	top.add_child(help_btn)

	inst_lbl = Label.new()
	inst_lbl.add_theme_font_size_override("font_size", 13)
	inst_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 0.95))
	inst_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(inst_lbl)

	metric_lbl = Label.new()
	metric_lbl.add_theme_font_size_override("font_size", 12)
	metric_lbl.add_theme_color_override("font_color", Color(0.70, 0.95, 0.72))
	vb.add_child(metric_lbl)

	# Feedback toast sits cleanly below the top instructor card, clear of touch sticks.
	var toast_center := CenterContainer.new()
	toast_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_center.offset_left = -310.0
	toast_center.offset_right = 310.0
	toast_center.offset_top = safe_top + 178.0
	toast_center.offset_bottom = safe_top + 206.0
	hud_container.add_child(toast_center)
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.14, 0.07, 0.94)
	tsb.border_color = MenuUI.ACCENT
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(3)
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	tsb.content_margin_top = 3
	tsb.content_margin_bottom = 3
	_toast_panel.add_theme_stylebox_override("panel", tsb)
	toast_center.add_child(_toast_panel)
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_font_size_override("font_size", 12)
	_toast_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_lbl)

	_build_help_overlay(hud_root)
	_update_hud_content()
	_update_progress_dots()
	_apply_stick_focus()
	var tc_node := get_node_or_null("/root/TouchControls")
	var is_mobile_hud := MenuUI.is_mobile_ui() \
			or (tc_node != null and bool(tc_node.get("touch_mode")))
	if OS.has_environment("DRONE_TUTORIAL_SHOW_HELP"):
		open_help()
	elif not is_mobile_hud and not OS.has_environment("DRONE_TUTORIAL_SKIP_BRIEF"):
		open_help()
	if OS.has_environment("DRONE_TUTORIAL_OVERVIEW"):
		get_tree().create_timer(0.7).timeout.connect(show_overview_camera)


func _build_help_overlay(hud_root: Node) -> void:
	_help_overlay = Control.new()
	_help_overlay.name = "FlightSchoolHelp"
	_help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_help_overlay.visible = false
	hud_root.add_child(_help_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.015, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).pressed:
			close_help()
		elif ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			close_help()
	)
	_help_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_overlay.add_child(center)

	var vp_sz := Vector2(1280, 720)
	if hud_root is Control:
		var r := (hud_root as Control).get_viewport_rect().size
		if r.x > 0.0 and r.y > 0.0:
			vp_sz = r
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(minf(860.0, vp_sz.x * 0.88), minf(520.0, vp_sz.y * 0.86))
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.035, 0.055, 0.040, 0.97)
	psb.border_color = MenuUI.WARN_AMBER
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(6)
	psb.content_margin_left = 26
	psb.content_margin_right = 26
	psb.content_margin_top = 18
	psb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := Label.new()
	title.text = _tx("ШКОЛА ПІЛОТА · ПЕРШИЙ ПОЛІТ",
			"FPV FLIGHT SCHOOL · FIRST FLIGHT")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	vb.add_child(title)
	var sub := Label.new()
	sub.text = _tx("10 коротких модулів · орієнтовно 25–40 хвилин · помилки не караються",
			"10 short modules · about 25–40 minutes · mistakes are part of learning")
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.72, 0.85, 0.74))
	vb.add_child(sub)

	var diagrams := HBoxContainer.new()
	diagrams.alignment = BoxContainer.ALIGNMENT_CENTER
	diagrams.add_theme_constant_override("separation", 44)
	vb.add_child(diagrams)
	diagrams.add_child(_make_stick_diagram(_tx("ЛІВИЙ СТІК", "LEFT STICK"),
			_tx("ГАЗ", "THROTTLE"), _tx("РИСКАННЯ", "YAW"),
			Color(0.45, 0.90, 0.55)))
	diagrams.add_child(_make_stick_diagram(_tx("ПРАВИЙ СТІК", "RIGHT STICK"),
			_tx("ТАНГАЖ", "PITCH"), _tx("КРЕН", "ROLL"),
			Color(0.95, 0.72, 0.25)))

	var tc_node := get_node_or_null("/root/TouchControls")
	var is_mobile := MenuUI.is_mobile_ui() \
			or (tc_node != null and bool(tc_node.get("touch_mode")))
	var controls := Label.new()
	if is_mobile:
		controls.text = _tx("СЕНСОР:  лівий стік — газ/рискання   ·   правий стік — тангаж/крен\n" \
				+ "АРМ — двигуни   ·   РЕСЕТ — респавн   ·   ВІДЕО — режим зображення\n" \
				+ "ПУЛЬТ ELRS:  лівий стік — газ/рискання   ·   правий стік — тангаж/крен\n" \
				+ "START — довідка   ·   B — повторити модуль   ·   CH5/ARM — двигуни\n" \
				+ "ГОЛОВНЕ: рухи плавні, після кожного руху повертайте стік у центр. Висоту тримайте газом, а не нахилом.",
				"TOUCH: left stick — throttle/yaw · right stick — pitch/roll\n" \
				+ "ARM — motors · RESET — respawn · VIDEO — display mode\n" \
				+ "ELRS RADIO: left stick — throttle/yaw · right stick — pitch/roll\n" \
				+ "START — help · B — repeat module · CH5/ARM — motors\n" \
				+ "KEY TIP: Use smooth inputs and centre the sticks after each move. Control altitude with throttle, not tilt.")
	else:
		controls.text = _tx("КЛАВІАТУРА:  W / S — газ   ·   A / D — рискання   ·   ↑ / ↓ — тангаж   ·   ← / → — крен\n" \
				+ "ПРОБІЛ — увімкнути / вимкнути двигуни   ·   C/V — нахил FPV-камери   ·   T — повторити модуль   ·   F2 — ця довідка   ·   ESC — пауза\n" \
				+ "ПУЛЬТ:  лівий стік — газ/рискання   ·   правий стік — тангаж/крен   ·   RS — двигуни   ·   LB — респавн\n" \
				+ "X — скид   ·   Y — активація БЧ   ·   B — повторити модуль   ·   Start — довідка\n" \
				+ "ГОЛОВНЕ: рухи плавні, після кожного руху повертайте стік у центр. Висоту тримайте газом, а не нахилом.",
				"KEYBOARD: W / S — throttle · A / D — yaw · ↑ / ↓ — pitch · ← / → — roll\n" \
				+ "SPACE — arm/disarm · C/V — FPV camera tilt · T — repeat module · F2 — help · ESC — pause\n" \
				+ "RADIO: left stick — throttle/yaw · right stick — pitch/roll · RS — motors · LB — respawn\n" \
				+ "X — payload drop · Y — activate warhead · B — repeat module · Start — help\n" \
				+ "KEY TIP: Use smooth inputs and centre the sticks after each move. Control altitude with throttle, not tilt.")
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color(0.88, 0.93, 0.88))
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(controls)

	var hint := Label.new()
	hint.text = _tx("ПЕРШИЙ МОДУЛЬ: увімкнути двигуни → вимкнути → увімкнути знову. Дрон стоїть на стартовому майданчику.",
			"FIRST MODULE: arm → disarm → arm again. The drone is on the launch pad.")
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.95, 0.60))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hint)

	var close_btn_row := CenterContainer.new()
	vb.add_child(close_btn_row)
	var close_btn := Button.new()
	close_btn.name = "StartFlightCloseBtn"
	close_btn.text = _tx("ПОЧАТИ ПОЛІТ / ЗАКРИТИ", "START FLIGHT / CLOSE")
	close_btn.custom_minimum_size = Vector2(280, 56)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 17)
	close_btn.add_theme_color_override("font_color", Color(0.05, 0.08, 0.06))
	var csb := StyleBoxFlat.new()
	csb.bg_color = MenuUI.ACCENT
	csb.set_corner_radius_all(8)
	csb.content_margin_left = 18
	csb.content_margin_right = 18
	close_btn.add_theme_stylebox_override("normal", csb)
	var csb_hover := csb.duplicate() as StyleBoxFlat
	csb_hover.bg_color = MenuUI.ACCENT.lightened(0.12)
	close_btn.add_theme_stylebox_override("hover", csb_hover)
	close_btn.add_theme_stylebox_override("pressed", csb_hover)
	close_btn.pressed.connect(close_help)
	close_btn_row.add_child(close_btn)

	var footer := Label.new()
	footer.text = _tx("НАТИСНІТЬ КНОПКУ АБО ЕКРАН, ЩОБ ПОЧАТИ",
			"TAP A BUTTON OR THE SCREEN TO BEGIN") if is_mobile \
			else _tx("ENTER — ПОЧАТИ / ПРОДОВЖИТИ", "ENTER — START / RESUME")
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", MenuUI.ACCENT)
	vb.add_child(footer)


func _make_stick_diagram(title: String, axis_y: String, axis_x: String,
		color: Color) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	var cap := Label.new()
	cap.text = title
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", color)
	root.add_child(cap)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(108, 108)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.06, 0.09, 0.07, 1.0)
	bsb.border_color = color
	bsb.set_border_width_all(1)
	bsb.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", bsb)
	root.add_child(box)
	var grid := GridContainer.new()
	grid.columns = 3
	box.add_child(grid)
	for i in range(3):
		for j in range(3):
			var l := Label.new()
			l.custom_minimum_size = Vector2(30, 30)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.add_theme_font_size_override("font_size", 16)
			var txt := ""
			if i == 0 and j == 1:
				txt = "↑"
			elif i == 1 and j == 0:
				txt = "←"
			elif i == 1 and j == 1:
				txt = "●"
			elif i == 1 and j == 2:
				txt = "→"
			elif i == 2 and j == 1:
				txt = "↓"
			l.text = txt
			l.add_theme_color_override("font_color", color)
			grid.add_child(l)

	var captions := Label.new()
	captions.text = "↑/↓ — %s\n←/→ — %s" % [axis_y, axis_x]
	captions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	captions.add_theme_font_size_override("font_size", 11)
	captions.add_theme_color_override("font_color", Color(0.82, 0.88, 0.82))
	root.add_child(captions)
	return root


func _apply_stick_focus() -> void:
	var focus := "none"
	if current_step < Step.COMPLETED:
		focus = str(_step_data().get("focus", "none"))
	var overlay = level.get("_stick_overlay") if level != null else null
	if overlay != null and overlay.has_method("set_tutorial_focus"):
		overlay.call("set_tutorial_focus", focus)


func _update_progress_dots() -> void:
	for i in range(_dots.size()):
		var col := Color(0.30, 0.35, 0.31)
		if i < current_step:
			col = Color(0.40, 0.95, 0.50)
		elif i == current_step:
			col = MenuUI.WARN_AMBER
		_dots[i].add_theme_color_override("font_color", col)


func _update_hud_content() -> void:
	if title_lbl == null:
		return
	var d: Dictionary = _step_data()
	var shown_step: int = mini(current_step, TOTAL_MODULES - 1)
	title_lbl.text = _tx("МОДУЛЬ %d/%d · %s", "MODULE %d/%d · %s") % [
			shown_step + 1, TOTAL_MODULES, str(d.get("title", ""))]
	var pct := int(round(float(shown_step) / float(TOTAL_MODULES) * 100.0))
	if current_step == Step.COMPLETED:
		pct = 100
	progress_lbl.text = "%d%%" % pct
	inst_lbl.text = str(d.get("inst", ""))
	var tip := str(d.get("tip", ""))
	if current_step == Step.COMPLETED:
		metric_lbl.text = _tx("КУРС ЗАВЕРШЕНО · СЕРТИФІКАТ ОПЕРАТОРА FPV",
				"COURSE COMPLETE · FPV PILOT CERTIFICATE")
		metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	else:
		metric_lbl.text = _tx("ПОРАДА: %s", "TIP: %s") % tip
		metric_lbl.add_theme_color_override("font_color",
				Color(0.72, 0.86, 0.74))
	_update_progress_dots()


func open_help() -> void:
	if _help_overlay == null or _help_open:
		return
	_help_open = true
	help_opens += 1
	_help_cooldown = 0.6
	_help_overlay.visible = true
	if not OS.has_environment("DRONE_TUTORIAL_OVERVIEW"):
		get_tree().paused = true


func close_help() -> void:
	if _help_overlay == null or not _help_open:
		return
	_help_open = false
	_help_overlay.visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("tutorial_help"):
		if _help_open:
			close_help()
		else:
			open_help()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tutorial_retry") and not _help_open \
			and current_step < Step.COMPLETED:
		reset_step()
		get_viewport().set_input_as_handled()
		return
	if _help_open and event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ENTER \
				or key.keycode == KEY_KP_ENTER or key.keycode == KEY_F2):
			close_help()
			get_viewport().set_input_as_handled()


func show_toast(msg: String, is_error: bool = false) -> void:
	if _toast_lbl == null or _toast_panel == null:
		return
	_toast_lbl.text = MenuUI.translate_text(msg)
	_toast_panel.visible = true
	_toast_timer = 4.0
	var sb: StyleBoxFlat = _toast_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = Color(0.20, 0.05, 0.05, 0.95) if is_error \
				else Color(0.05, 0.15, 0.07, 0.95)
		sb.border_color = MenuUI.DANGER if is_error else MenuUI.ACCENT
	_toast_lbl.add_theme_color_override("font_color",
			Color(1.0, 0.78, 0.74) if is_error else MenuUI.ACCENT)


func _update_toast(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false
	if _help_cooldown > 0.0:
		_help_cooldown -= delta


# ---------------------------------------------------------------------------
#  Per-frame lesson state machine.
# ---------------------------------------------------------------------------
func update_flight_school(delta: float) -> void:
	if not is_active or drone == null or _help_open or get_tree().paused:
		return
	course_time += delta
	_update_toast(delta)
	_check_pilot_errors(delta)

	var pos := drone.global_position
	var surface_y := _ground_at(pos.x, pos.z)
	if current_step == Step.LANDING:
		var pad_dist := Vector2(pos.x - landing_pos.x, pos.z - landing_pos.z).length()
		if pad_dist < 5.0:
			surface_y = landing_pos.y
	_step_alt = pos.y - surface_y
	_step_speed = drone.linear_velocity.length()
	_step_heading = drone.global_transform.basis.get_euler().y
	if _miss_cooldown > 0.0:
		_miss_cooldown -= delta

	match current_step:
		Step.ARMING:
			_process_arming()
		Step.HOVER:
			_process_hover(delta)
		Step.STICK_BASICS:
			_process_stick_basics(delta)
		Step.YAW_CONTROL:
			_process_yaw(delta)
		Step.FORWARD_GATE:
			if _crossed_opening(gate_forward):
				_pass_gate(gate_forward)
				show_toast("✓ ВОРОТА 1 ПРОЙДЕНО. Тепер слалом — крен ліворуч/праворуч.")
				advance_to_step(Step.SLALOM)
			else:
				_show_gate_metric(gate_forward, "ВОРОТА 1")
				_report_gate_miss(gate_forward)
		Step.SLALOM:
			var target: Dictionary = gate_slalom_a if _slalom_stage == 0 else gate_slalom_b
			if _crossed_opening(target):
				_pass_gate(target)
				if _slalom_stage == 0:
					_slalom_stage = 1
					show_toast("✓ СЛАЛОМ A. Тепер праві ворота — крен праворуч.")
				else:
					show_toast("✓ СЛАЛОМ ПРОЙДЕНО. Далі — низькі та високі ворота.")
					advance_to_step(Step.ALTITUDE_GATES)
			else:
				_show_gate_metric(target, "СЛАЛОМ A" if _slalom_stage == 0 else "СЛАЛОМ B")
				_report_gate_miss(target)
		Step.ALTITUDE_GATES:
			var target: Dictionary = gate_low if _altitude_stage == 0 else gate_high
			if _crossed_opening(target):
				_pass_gate(target)
				if _altitude_stage == 0:
					_altitude_stage = 1
					show_toast("✓ НИЗЬКІ ВОРОТА. Тепер підніміться до 5 м — високі ворота.")
				else:
					show_toast("✓ ВИСОТА ПРОЙДЕНА. Попереду стіна з вікном.")
					advance_to_step(Step.WINDOW_PASS)
			else:
				_show_gate_metric(target, "НИЗЬКІ" if _altitude_stage == 0 else "ВИСОКІ")
				_report_gate_miss(target)
		Step.WINDOW_PASS:
			if _crossed_opening(gate_window):
				show_toast("✓ ВІКНО ПРОЙДЕНО! Тепер загальмуйте в жовтій зоні.")
				advance_to_step(Step.BRAKE_STOP)
			else:
				_show_gate_metric(gate_window, "ВІКНО 3.6x3.2")
				_report_gate_miss(gate_window)
		Step.BRAKE_STOP:
			_process_brake(delta)
		Step.LANDING:
			_process_landing()

	_has_prev = true
	_prev_pos = pos


func _process_arming() -> void:
	var fc = drone.flight_controller
	if fc == null:
		return
	var armed: bool = fc.state_armed
	match _arm_phase:
		0:
			metric_lbl.text = _tx("ДВИГУНИ ВИМКНЕНО · натисніть ПРОБІЛ, щоб увімкнути",
					"MOTORS DISARMED · PRESS SPACE TO ARM")
			metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
			if armed:
				_arm_phase = 1
				show_toast("✓ Двигуни увімкнено. Тепер вимкніть їх (ПРОБІЛ), не злітаючи.")
		1:
			metric_lbl.text = _tx("ДВИГУНИ УВІМКНЕНО · тепер ПРОБІЛ — вимкнути на землі",
					"MOTORS ARMED · PRESS SPACE TO DISARM ON THE GROUND")
			metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
			if not armed:
				if _step_alt > 3.0:
					show_toast("⚠ Спочатку приземліться, потім вимикайте двигуни.", true)
				else:
					_arm_phase = 2
					show_toast("✓ Двигуни вимкнено. Тепер увімкніть їх знову — і до зльоту.")
		2:
			metric_lbl.text = _tx("ФІНАЛЬНЕ УВІМКНЕННЯ · натисніть ПРОБІЛ",
					"FINAL ARM · PRESS SPACE")
			metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
			if armed:
				show_toast("✓ УВІМКНЕННЯ ЗАСВОЄНО. Плавно додайте газ — дрон має піднятися.")
				advance_to_step(Step.HOVER)


func _process_hover(delta: float) -> void:
	var dx := drone.global_position.x - hover_pos.x
	var dz := drone.global_position.z - hover_pos.z
	var in_zone := Vector2(dx, dz).length() < 8.0
	var in_band := _step_alt >= HOVER_MIN and _step_alt <= HOVER_MAX
	if in_zone and in_band:
		hover_timer += delta
		metric_lbl.text = _tx(
				"ВИСОТА %.1f м · УТРИМАННЯ %.1f / %.0f с · ГАЗ %d%%",
				"ALTITUDE %.1f m · HOLD %.1f / %.0f s · THROTTLE %d%%") % [
				_step_alt, hover_timer, HOVER_HOLD, _throttle_percent()]
		metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
		if hover_timer >= HOVER_HOLD:
			if hover_beacon != null:
				hover_beacon.visible = false
			show_toast("✓ ВИСОТУ УТРИМАНО. Тепер спробуйте правий стік — тангаж і крен.")
			advance_to_step(Step.STICK_BASICS)
	else:
		hover_timer = maxf(0.0, hover_timer - delta * 0.5)
		var hint := _tx("ЗАНИЗЬКО — додайте газ", "TOO LOW — ADD THROTTLE") \
				if _step_alt < HOVER_MIN else _tx("ЗАВИСОКО — скиньте газ", "TOO HIGH — REDUCE THROTTLE")
		if not in_zone:
			hint = _tx("Поверніться до зеленого маяка", "RETURN TO THE GREEN BEACON")
		metric_lbl.text = _tx("ВИСОТА %.1f м · %s · УТРИМАННЯ %.1f / %.0f с",
				"ALTITUDE %.1f m · %s · HOLD %.1f / %.0f s") % [
				_step_alt, hint, hover_timer, HOVER_HOLD]
		metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)


func _process_stick_basics(delta: float) -> void:
	var e := drone.global_transform.basis.get_euler()
	var pitch := e.x
	var roll := e.z
	if _step_alt < 1.2 or _step_alt > 6.5:
		metric_lbl.text = _tx("ВИСОТА %.1f м · тримайте 2–5 м газом",
				"ALTITUDE %.1f m · HOLD 2–5 m WITH THROTTLE") % _step_alt
		metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		return
	match _basic_phase:
		0:
			metric_lbl.text = _tx("ТАНГАЖ · нахиліть ніс (↑ або ↓) · зараз %.0f°",
					"PITCH · TILT THE NOSE (↑ OR ↓) · NOW %.0f°") % rad_to_deg(pitch)
			if absf(pitch) > 0.14:
				_basic_phase = 1
				_basic_hold = 0.0
		1:
			metric_lbl.text = _tx("ПОВЕРНІТЬ ПРАВИЙ СТІК У ЦЕНТР · тангаж %.0f°",
					"CENTRE THE RIGHT STICK · PITCH %.0f°") % rad_to_deg(pitch)
			if absf(pitch) < 0.05:
				_basic_hold += delta
				if _basic_hold >= 0.7:
					_basic_phase = 2
					_basic_hold = 0.0
					show_toast("✓ Тангаж і центрування засвоєно. Тепер крен.")
			else:
				_basic_hold = 0.0
		2:
			metric_lbl.text = _tx("КРЕН · нахиліть дрон ліворуч/праворуч (← або →) · %.0f°",
					"ROLL · BANK LEFT/RIGHT (← OR →) · %.0f°") % rad_to_deg(roll)
			if absf(roll) > 0.14:
				_basic_phase = 3
				_basic_hold = 0.0
		3:
			metric_lbl.text = _tx("ПОВЕРНІТЬ СТІК У ЦЕНТР · крен %.0f°",
					"CENTRE THE STICK · ROLL %.0f°") % rad_to_deg(roll)
			if absf(roll) < 0.05:
				_basic_hold += delta
				if _basic_hold >= 0.7:
					show_toast("✓ Правий стік засвоєно. Тепер рискання лівим стіком.")
					_step_yaw_start = _step_heading
					advance_to_step(Step.YAW_CONTROL)
			else:
				_basic_hold = 0.0
	metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)


func _process_yaw(delta: float) -> void:
	if _step_alt < 1.2 or _step_alt > 7.0:
		metric_lbl.text = _tx("ВИСОТА %.1f м · тримайте 2–5 м перед поворотом",
				"ALTITUDE %.1f m · HOLD 2–5 m BEFORE TURNING") % _step_alt
		metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
		return
	var rel := wrapf(_step_heading - _step_yaw_start, -PI, PI)
	if not _yaw_turned:
		metric_lbl.text = _tx("ПОВОРОТ · лівий стік ←/→ · %.0f° / 70°",
				"YAW TURN · LEFT STICK ←/→ · %.0f° / 70°") % absf(rad_to_deg(rel))
		if absf(rel) > deg_to_rad(70.0):
			_yaw_turned = true
			_yaw_dir = signf(rel)
			settle_timer = 0.0
			show_toast("✓ Поворот виконано. Тепер поверніться на початковий курс.")
	else:
		metric_lbl.text = _tx("ПОВЕРНЕННЯ · залишилось %.0f° · висота %.1f м",
				"RETURN TO HEADING · %.0f° LEFT · ALTITUDE %.1f m") % [
				absf(rad_to_deg(rel)), _step_alt]
		if absf(rel) < deg_to_rad(15.0):
			settle_timer += delta
			if settle_timer >= 0.8:
				show_toast("✓ Рискання засвоєно. Тепер перший політ уперед — ворота 1.")
				advance_to_step(Step.FORWARD_GATE)
		else:
			settle_timer = 0.0
	metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)


func _show_gate_metric(gate: Dictionary, label: String) -> void:
	var target: Vector3 = gate.get("pos", drone.global_position)
	var d := Vector2(drone.global_position.x - target.x,
			drone.global_position.z - target.z).length()
	metric_lbl.text = _tx("%s · %.0f м · висота %.1f м · швидкість %.0f км/г",
			"%s · %.0f m · ALTITUDE %.1f m · SPEED %.0f km/h") % [
			MenuUI.translate_text(label), d, _step_alt, _step_speed * 3.6]
	metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)


func _process_brake(delta: float) -> void:
	var d := Vector2(drone.global_position.x - brake_pos.x,
			drone.global_position.z - brake_pos.z).length()
	if d < 8.5:
		if _step_speed < 2.5:
			flare_timer += delta
			metric_lbl.text = _tx("ГАЛЬМУВАННЯ %.1f / 1.5 с · %.1f м/с · утримуйте",
					"BRAKING %.1f / 1.5 s · %.1f m/s · HOLD") % [
					flare_timer, _step_speed]
			metric_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
			if flare_timer >= 1.5:
				show_toast("✓ Інерцію погашено. Тепер посадка на майданчик [H].")
				advance_to_step(Step.LANDING)
		else:
			flare_timer = 0.0
			metric_lbl.text = _tx("ЗАШВИДКО %.1f м/с · ніс назад (↓) + газ",
					"TOO FAST %.1f m/s · PITCH BACK (↓) + THROTTLE") % _step_speed
			metric_lbl.add_theme_color_override("font_color", MenuUI.DANGER)
	else:
		metric_lbl.text = _tx("ЗОНА ГАЛЬМУВАННЯ · %.0f м · %.1f м/с",
				"BRAKING ZONE · %.0f m · %.1f m/s") % [d, _step_speed]
		metric_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)


func _process_landing() -> void:
	var d := Vector2(drone.global_position.x - landing_pos.x,
			drone.global_position.z - landing_pos.z).length()
	var vy := absf(drone.linear_velocity.y)
	var armed: bool = drone.flight_controller != null and drone.flight_controller.state_armed
	var pad_alt := (drone.global_position.y - landing_pos.y) if d < 5.0 else _step_alt
	if d < 4.5 and pad_alt < 0.85 and vy < 2.2 and not armed:
		complete_course()
		return
	if not armed and pad_alt >= 0.85:
		metric_lbl.text = _tx("ЗАВИСОКО ДЛЯ ВИМКНЕННЯ · висота %.1f м · сідайте нижче",
				"TOO HIGH TO DISARM · ALTITUDE %.1f m · LAND LOWER") % pad_alt
		metric_lbl.add_theme_color_override("font_color", MenuUI.DANGER)
		return
	metric_lbl.text = _tx("МАЙДАНЧИК %.0f м · висота %.2f м · спуск %.1f м/с · ПРОБІЛ — вимкнути двигуни",
			"LANDING PAD %.0f m · ALTITUDE %.2f m · DESCENT %.1f m/s · SPACE — DISARM") % [
			d, _step_alt, vy]
	metric_lbl.add_theme_color_override("font_color",
			MenuUI.ACCENT if vy < 2.0 else MenuUI.WARN_AMBER)


func _crossed_opening(gate: Dictionary) -> bool:
	if not _has_prev:
		return false
	var z := float(gate.get("z", 0.0))
	var z0 := _prev_pos.z
	var z1 := drone.global_position.z
	if not (z0 > z and z1 <= z):
		return false
	var denom := z0 - z1
	if denom < 0.0001:
		return false
	var t := (z0 - z) / denom
	var hit := _prev_pos.lerp(drone.global_position, t)
	var center: Vector3 = gate.get("pos", Vector3.ZERO)
	return absf(hit.x - center.x) <= float(gate.get("half_w", 2.0)) \
			and absf(hit.y - center.y) <= float(gate.get("half_h", 1.5))


func _report_gate_miss(gate: Dictionary) -> void:
	if _miss_cooldown > 0.0 or not _has_prev:
		return
	var z := float(gate.get("z", 0.0))
	if _prev_pos.z > z and drone.global_position.z <= z:
		gate_misses += 1
		_miss_cooldown = 5.0
		show_toast("⚠ Пролетіли повз отвір. R — повторити модуль або розверніться.", true)


func _pass_gate(gate: Dictionary) -> void:
	var node: Node = gate.get("node", null)
	if node != null and is_instance_valid(node):
		node.visible = false


func advance_to_step(next_step: int) -> void:
	current_step = next_step
	hover_timer = 0.0
	flare_timer = 0.0
	settle_timer = 0.0
	_basic_phase = 0
	_basic_hold = 0.0
	_slalom_stage = 0
	_altitude_stage = 0
	_yaw_turned = false
	if next_step == Step.YAW_CONTROL:
		_step_yaw_start = _step_heading
	if next_step == Step.FORWARD_GATE:
		_force_fpv_camera()
	_update_hud_content()
	_apply_stick_focus()
	var data: Dictionary = _step_data(next_step)
	emit_signal("lesson_advanced", next_step, str(data.get("title", "")))


func _force_fpv_camera() -> void:
	if level == null:
		return
	var cam = level.get("camera")
	for _i in range(3):
		if cam != null and String(cam.name) == "FPVCamera":
			break
		if not level.has_method("change_camera"):
			break
		level.call("change_camera")
		cam = level.get("camera")
	if cam != null and String(cam.name) == "FPVCamera":
		show_toast("Камера FPV увімкнена · C/V — нахил об'єктива")


func complete_course() -> void:
	current_step = Step.COMPLETED
	_update_hud_content()
	_apply_stick_focus()
	Global.set_tutorial_completed(true)
	emit_signal("course_completed")
	if level != null and level.has_method("_finish_mission"):
		level.call("_finish_mission", "КУРС ЗАВЕРШЕНО")


func get_current_target_info() -> Dictionary:
	match current_step:
		Step.ARMING:
			return {"pos": start_pos, "label": _tx("СТАРТ", "START")}
		Step.HOVER:
			return {"pos": hover_pos, "label": _tx("МАЯК ВИСІННЯ", "HOVER BEACON")}
		Step.STICK_BASICS:
			return {"pos": hover_pos, "label": _tx("ЗОНА СТІКІВ", "STICK CONTROL ZONE")}
		Step.YAW_CONTROL:
			return {"pos": hover_pos, "label": _tx("КУРС", "HEADING")}
		Step.FORWARD_GATE:
			return {"pos": gate_forward.get("pos", start_pos), "label": _tx("ВОРОТА 1", "GATE 1")}
		Step.SLALOM:
			var g := gate_slalom_a if _slalom_stage == 0 else gate_slalom_b
			return {"pos": g.get("pos", start_pos),
					"label": MenuUI.translate_text(str(g.get("name", "СЛАЛОМ")))}
		Step.ALTITUDE_GATES:
			var g := gate_low if _altitude_stage == 0 else gate_high
			return {"pos": g.get("pos", start_pos),
					"label": MenuUI.translate_text(str(g.get("name", "ВИСОТА")))}
		Step.WINDOW_PASS:
			return {"pos": gate_window.get("pos", start_pos), "label": _tx("ВІКНО", "WINDOW")}
		Step.BRAKE_STOP:
			return {"pos": brake_pos, "label": _tx("ЗОНА ГАЛЬМУВАННЯ", "BRAKING ZONE")}
		Step.LANDING:
			return {"pos": landing_pos, "label": _tx("МАЙДАНЧИК", "LANDING PAD")}
		_:
			return {}


func _throttle_percent() -> int:
	if level == null:
		return 0
	var radio := level.get_node_or_null("RadioController")
	if radio == null:
		return 0
	var input_arr = radio.get("input")
	if input_arr is Array and input_arr.size() > 0:
		return int(round(clampf(float(input_arr[0]), 0.0, 1.0) * 100.0))
	return 0


# ---------------------------------------------------------------------------
#  Retry: put the student back on the last checkpoint, keep the module.
# ---------------------------------------------------------------------------
func reset_step() -> void:
	if drone == null:
		return
	retries += 1
	close_help()
	var cp := _checkpoint_for_step()
	var safe_y := cp.y
	if current_step != Step.ARMING:
		safe_y = maxf(cp.y, _ground_at(cp.x, cp.z) + 2.6)
	drone.global_position = Vector3(cp.x, safe_y, cp.z)
	drone.rotation = Vector3(0.0, 0.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.freeze = false
	var fc := drone.flight_controller
	if fc != null:
		if current_step == Step.ARMING:
			fc.set_armed(false)
			_arm_phase = 0
		elif not fc.state_armed:
			fc.set_armed(true)
	hover_timer = 0.0
	flare_timer = 0.0
	settle_timer = 0.0
	_basic_phase = 0
	_basic_hold = 0.0
	_yaw_turned = false
	_slalom_stage = 0
	_altitude_stage = 0
	_has_prev = true
	_prev_pos = drone.global_position
	_update_hud_content()
	show_toast("↻ Модуль перезапущено. Не поспішайте.")


func _checkpoint_for_step() -> Vector3:
	match current_step:
		Step.ARMING:
			return Vector3(start_pos.x, _ground_at(start_pos.x, start_pos.z) + 0.3,
					start_pos.z)
		Step.HOVER, Step.STICK_BASICS, Step.YAW_CONTROL:
			return Vector3(start_pos.x, _ground_at(start_pos.x, start_pos.z) + 3.0,
					start_pos.z - 4.0)
		Step.FORWARD_GATE:
			return gate_forward.get("pos", start_pos) + Vector3(0.0, 0.0, 14.0)
		Step.SLALOM:
			var g := gate_slalom_a if _slalom_stage == 0 else gate_slalom_b
			return g.get("pos", start_pos) + Vector3(0.0, 0.0, 14.0)
		Step.ALTITUDE_GATES:
			var g := gate_low if _altitude_stage == 0 else gate_high
			return g.get("pos", start_pos) + Vector3(0.0, 0.0, 14.0)
		Step.WINDOW_PASS:
			return gate_window.get("pos", start_pos) + Vector3(0.0, 0.0, 16.0)
		Step.BRAKE_STOP:
			return brake_pos + Vector3(0.0, 3.0, 18.0)
		Step.LANDING:
			return landing_pos + Vector3(0.0, 3.0, 16.0)
		_:
			return start_pos


# ---------------------------------------------------------------------------
#  Real-time beginner error assistant.
# ---------------------------------------------------------------------------
func _check_pilot_errors(delta: float) -> void:
	if _error_cooldown > 0.0:
		_error_cooldown -= delta
		return
	if drone == null or drone.flight_controller == null \
			or not drone.flight_controller.state_armed:
		return
	var lin := drone.linear_velocity
	var alt := _step_alt
	var rot := drone.rotation
	if lin.y > 6.5 and alt > 15.0 and absf(rot.x) < 0.25:
		show_toast("⚠ ПЕРЕГАЗОВКА: ви занадто різко додали газ. Скиньте до 45% і вирівняйте дрон.", true)
		_error_cooldown = 6.0
		return
	if (absf(rot.z) > 1.85 or absf(rot.x) > 1.85) and alt < 18.0 and lin.y < -1.5:
		show_toast("⚠ ВТРАТА ГОРИЗОНТУ: дрон перевернувся. Відхиліть правий стік у протилежний бік.", true)
		_error_cooldown = 5.0
		return
	if lin.y < -5.5 and absf(lin.x) < 2.0 and absf(lin.z) < 2.0 and alt > 4.0:
		show_toast("⚠ ВИХРОВЕ КІЛЬЦЕ: не спускайтесь вертикально. Додайте трохи нахилу вперед.", true)
		_error_cooldown = 5.5
		return
	var local_v := drone.global_transform.basis.inverse() * lin
	if absf(local_v.x) > absf(local_v.z) * 2.2 and local_v.length() > 5.5:
		show_toast("💡 БІЧНИЙ ЗНОС: у повороті додавайте крен правим стіком, а не лише рискання.", false)
		_error_cooldown = 6.0


# ---------------------------------------------------------------------------
#  QA hooks: jump to a module (screenshots) / a clean overview camera.
# ---------------------------------------------------------------------------
func _qa_jump_to_step(step: int) -> void:
	step = clampi(step, 0, Step.LANDING)
	current_step = step
	if drone == null:
		return
	var cp := _checkpoint_for_step()
	var y := maxf(cp.y, _ground_at(cp.x, cp.z) + 2.8)
	drone.global_position = Vector3(cp.x, y, cp.z)
	drone.rotation = Vector3.ZERO
	if drone.flight_controller != null:
		drone.flight_controller.set_armed(true)
	# QA screenshots must not fall to the ground while the shutter is open.
	drone.freeze = true
	drone.linear_velocity = Vector3.ZERO
	_has_prev = true
	_prev_pos = drone.global_position
	_update_hud_content()
	if OS.has_environment("DRONE_TUTORIAL_FPV"):
		_force_fpv_camera()
