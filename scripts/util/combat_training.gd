## Combat Training («БОЙОВЕ ТРЕНУВАННЯ»).
##
## A standalone three-step sortie for a first-time player, launched from the
## training entry points on the home screen / recon card:
##   1. ARM + climb to 8 m;
##   2. fly to the marker until the tank is 50 m away;
##   3. hover over it and release the payload (G).
##
## The sortie runs in PlayMode.TRAINING but replaces the freestyle ring course:
## BigLevel suppresses the rings, the ghost and the campaign debrief while
## `Global.combat_training` is set.  Completion is stored as a progress badge
## only (`combat_training` section) and never touches campaign stars.
class_name CombatTraining
extends Node

signal step_advanced(step: int)
signal training_completed

const MenuUI := preload("res://GUI/ui/MenuUI.gd")
const VoltThemeScript := preload("res://GUI/mobile/VoltTheme.gd")
const CombatTargetScript = preload("res://combat/combat_target.gd")

enum Step { ARM_TAKEOFF = 0, APPROACH = 1, DESTROY = 2, COMPLETED = 3 }
const TOTAL_STEPS := 3
## The tank sits on the clear north-field strip, 68 m from the training spawn.
const TARGET_DISTANCE := 68.0
const TAKEOFF_ALTITUDE := 8.0
const APPROACH_RANGE := 50.0
const TARGET_HEALTH := 240.0

const STEP_DATA := {
	Step.ARM_TAKEOFF: {
		"title": "КРОК 1 · ARM І ЗЛІТ",
		"inst": "Натисніть ARM (ПРОБІЛ / RS), плавно додайте газ і наберіть 8 м висоти над стартовим майданчиком.",
		"tip": "Спочатку ARM, потім газ. На землі газ має бути в нулі.",
	},
	Step.APPROACH: {
		"title": "КРОК 2 · ЗАХІД НА ЦІЛЬ",
		"inst": "Летіть до оранжевого маяка. Наблизьтесь до танка на 50 м, тримаючи висоту 15–30 м.",
		"tip": "Тримайте танк у центрі кадру, а висоту — газом.",
	},
	Step.DESTROY: {
		"title": "КРОК 3 · УРАЖЕННЯ ЦІЛІ",
		"inst": "Зависніть над танком на 15–25 м, наведіть центр кадру на ціль і натисніть G — скид. Радіус ураження 9.5 м.",
		"tip": "Скид летить уперед: зависніть майже над ціллю, тоді скидайте.",
	},
	Step.COMPLETED: {
		"title": "ТРЕНУВАННЯ ЗАВЕРШЕНО",
		"inst": "Ціль уражено. Ви виконали всі 3 кроки бойового тренування.",
		"tip": "Тепер спробуйте бойовий виліт у кампанії.",
	},
}

const STEP_DATA_EN := {
	Step.ARM_TAKEOFF: {
		"title": "STEP 1 · ARM & LIFT-OFF",
		"inst": "Press ARM (SPACE / RS), raise the throttle gently and climb to 8 m above the launch pad.",
		"tip": "ARM first, throttle second. Keep the throttle at zero on the ground.",
	},
	Step.APPROACH: {
		"title": "STEP 2 · APPROACH THE TARGET",
		"inst": "Fly to the orange beacon. Close to within 50 m of the tank while holding 15–30 m altitude.",
		"tip": "Keep the tank centred in the frame and control altitude with throttle.",
	},
	Step.DESTROY: {
		"title": "STEP 3 · DESTROY THE TARGET",
		"inst": "Hover 15–25 m above the tank, put the centre of the frame on it and press G to release. The blast radius is 9.5 m.",
		"tip": "The payload falls forward: hover almost directly above the tank, then release.",
	},
	Step.COMPLETED: {
		"title": "TRAINING COMPLETE",
		"inst": "Target destroyed. You completed all 3 combat-training steps.",
		"tip": "Now try a combat sortie in the campaign.",
	},
}

var step: int = Step.ARM_TAKEOFF
var is_active := false
## Tests disable the pause so the headless runner can keep processing frames.
var pause_on_completion := true

var level: Node3D = null
var drone: Drone = null
var world_root: Node3D = null
var target: CombatTarget = null
var target_pos := Vector3.ZERO
var elapsed := 0.0

var _marker: Label3D = null
var _beacon: MeshInstance3D = null
var _zone: MeshInstance3D = null

# HUD
var _hud_container: Control = null
var _card: PanelContainer = null
var _title_lbl: Label = null
var _inst_lbl: Label = null
var _metric_lbl: Label = null
var _progress_lbl: Label = null
var _dots_row: HBoxContainer = null
var _dots: Array[Label] = []
var _toast_panel: PanelContainer = null
var _toast_lbl: Label = null
var _toast_timer := 0.0
var _completion: Control = null

var _hud_tick := 0.0
var _spawn_frames := 0
var _was_armed := false


func _tx(ua: String, en: String) -> String:
	return en if MenuUI.is_english() else ua


func _step_data(which_step: int = -1) -> Dictionary:
	var data: Dictionary = STEP_DATA_EN if MenuUI.is_english() else STEP_DATA
	var key := step if which_step < 0 else which_step
	return data.get(key, {})


func initialize(p_level: Node3D, p_drone: Drone, _ground_y: float) -> void:
	level = p_level
	drone = p_drone
	is_active = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	step = Step.ARM_TAKEOFF
	elapsed = 0.0
	_toast_timer = 0.0
	# Screenshot QA runs must not pause the tree: DebugShot captures from an
	# autoload that would otherwise stop before rendering the completion panel.
	if OS.has_environment("SHOT_PATH") or OS.has_environment("DRONE_SCREENSHOT"):
		pause_on_completion = false
	var step_env := OS.get_environment("DRONE_COMBAT_TRAINING_STEP").strip_edges()
	if not step_env.is_empty():
		step = clampi(int(step_env), Step.ARM_TAKEOFF, Step.COMPLETED)
	_world_setup()


# ---------------------------------------------------------------------------
#  World: one tank on the clear training strip plus a readable beacon.
# ---------------------------------------------------------------------------
func _world_setup() -> void:
	if level == null:
		return
	world_root = Node3D.new()
	world_root.name = "CombatTrainingWorld"
	level.add_child(world_root)
	# Targets and props added during level construction become queryable after
	# a couple of physics frames; defer spawn so the dry-spot check is reliable.
	_spawn_frames = 2


func _process(delta: float) -> void:
	update_training(delta)


## Driven by this node's _process; QA suites also call it directly to step
## through the lesson deterministically.
func update_training(delta: float) -> void:
	if not is_active:
		return
	if _spawn_frames > 0:
		_spawn_frames -= 1
		if _spawn_frames == 0:
			_spawn_target()
	if get_tree().paused:
		return
	elapsed += delta
	_toast_timer = maxf(_toast_timer - delta, 0.0)
	if _toast_timer <= 0.0 and _toast_panel != null and _toast_panel.visible:
		_toast_panel.visible = false
	if step == Step.COMPLETED:
		return
	var fc = drone.flight_controller if drone != null and is_instance_valid(drone) else null
	var alt := _altitude()
	if step == Step.ARM_TAKEOFF:
		if fc != null and fc.state_armed and alt >= TAKEOFF_ALTITUDE:
			_advance(Step.APPROACH)
			_show_toast(_tx("✓ КРОК 1/3 · Двигуни увімкнено, висота 8 м. Курс на маяк.",
					"✓ STEP 1/3 · Motors armed, 8 m reached. Turn to the beacon."))
	elif step == Step.APPROACH:
		if _target_alive() and _horizontal_distance() <= APPROACH_RANGE:
			_advance(Step.DESTROY)
			_show_toast(_tx("✓ КРОК 2/3 · Ціль близько. Зависніть над танком і натисніть G.",
					"✓ STEP 2/3 · Target in range. Hover over the tank and press G."))
		elif not _target_alive():
			# A stray blast already killed it: fall through to the completion panel.
			_complete()
	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.083
		_update_hud()
		_update_marker()


func _advance(next_step: int) -> void:
	step = next_step
	_was_armed = step != Step.ARM_TAKEOFF
	_update_hud()
	_update_dots()
	step_advanced.emit(step)


func _altitude() -> float:
	if drone == null or not is_instance_valid(drone):
		return 0.0
	var ground := 0.0
	if level != null and level.has_method("_find_ground_y"):
		ground = float(level.call("_find_ground_y", drone.global_position.x,
				drone.global_position.z))
	return drone.global_position.y - ground


func _horizontal_distance() -> float:
	if drone == null or not is_instance_valid(drone) or not _target_alive():
		return 1e9
	return Vector2(drone.global_position.x - target.global_position.x,
			drone.global_position.z - target.global_position.z).length()


func _target_alive() -> bool:
	return target != null and is_instance_valid(target) and not target.is_destroyed


func _spawn_target(at_position: Vector3 = Vector3.INF) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var pos := at_position
	if pos == Vector3.INF:
		var origin := Vector3.ZERO
		var forward := Vector3(0.0, 0.0, -1.0)
		if drone != null and is_instance_valid(drone):
			origin = drone.global_position
			forward = -drone.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() < 0.01:
				forward = Vector3(0.0, 0.0, -1.0)
			forward = forward.normalized()
		var desired := Vector2(origin.x + forward.x * TARGET_DISTANCE,
				origin.z + forward.z * TARGET_DISTANCE)
		if level != null and level.has_method("_find_dry_spot"):
			desired = level.call("_find_dry_spot", desired.x, desired.y)
		var gy := 0.0
		if level != null and level.has_method("_find_ground_y"):
			gy = float(level.call("_find_ground_y", desired.x, desired.y))
		pos = Vector3(desired.x, gy + 0.02, desired.y)
	target_pos = pos
	if target != null and is_instance_valid(target):
		target.queue_free()
	target = CombatTargetScript.new()
	target.name = "CombatTrainingTarget"
	target.kind = CombatTargetScript.Kind.TANK
	target.max_health = TARGET_HEALTH
	target.points = 0
	world_root.add_child(target)
	target.global_position = pos
	var face := pos + Vector3(0.0, 0.0, 1.0)
	if drone != null and is_instance_valid(drone):
		face = Vector3(drone.global_position.x, pos.y, drone.global_position.z)
	if face.distance_squared_to(pos) > 0.01:
		target.look_at(face, Vector3.UP)
	if not target.destroyed.is_connected(_on_target_destroyed):
		target.destroyed.connect(_on_target_destroyed)
	_build_marker(pos)
	_update_hud()
	_update_dots()
	if step == Step.COMPLETED:
		# QA step hook / late session restore: show the debrief once the target
		# exists so the marker and the completion panel never overlap.
		_hide_marker()
		_show_completion()


func _build_marker(pos: Vector3) -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	if _beacon != null and is_instance_valid(_beacon):
		_beacon.queue_free()
	if _zone != null and is_instance_valid(_zone):
		_zone.queue_free()

	_marker = Label3D.new()
	_marker.name = "TrainingTargetMarker"
	_marker.text = _tx("ЦІЛЬ", "TARGET")
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = false
	_marker.pixel_size = 0.017
	_marker.font_size = 64
	_marker.outline_size = 28
	_marker.modulate = Color(1.0, 0.72, 0.24)
	_marker.outline_modulate = Color(0.0, 0.0, 0.0, 0.95)
	_marker.render_priority = 20
	_marker.position = pos + Vector3.UP * 6.0
	world_root.add_child(_marker)

	_beacon = MeshInstance3D.new()
	_beacon.name = "TrainingTargetBeacon"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 30.0
	cyl.radial_segments = 8
	cyl.rings = 1
	_beacon.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.52, 0.16, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.42, 0.10)
	mat.emission_energy_multiplier = 1.8
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	_beacon.material_override = mat
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.position = pos + Vector3.UP * 15.0
	world_root.add_child(_beacon)

	_zone = MeshInstance3D.new()
	_zone.name = "TrainingTargetBlastZone"
	var disc := CylinderMesh.new()
	disc.top_radius = 9.5
	disc.bottom_radius = 9.5
	disc.height = 0.06
	disc.radial_segments = 40
	_zone.mesh = disc
	var zmat := StandardMaterial3D.new()
	zmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	zmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	zmat.albedo_color = Color(1.0, 0.55, 0.18, 0.16)
	zmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_zone.material_override = zmat
	_zone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position = pos + Vector3.UP * 0.10
	world_root.add_child(_zone)


func _update_marker() -> void:
	if _marker == null or not is_instance_valid(_marker) or not _target_alive():
		return
	var dist := 0.0
	if drone != null and is_instance_valid(drone):
		dist = drone.global_position.distance_to(target.global_position)
	_marker.text = "%s\n%d %s" % [_tx("ЦІЛЬ", "TARGET"), int(round(dist)),
			_tx("м", "m")]


func _hide_marker() -> void:
	for n in [_marker, _beacon, _zone]:
		if n != null and is_instance_valid(n):
			n.visible = false


func _on_target_destroyed(_points: int) -> void:
	_hide_marker()
	_complete()


func _complete() -> void:
	if step == Step.COMPLETED:
		return
	step = Step.COMPLETED
	Global.set_combat_training_completed(true)
	_update_hud()
	_update_dots()
	_show_completion()
	training_completed.emit()


# ---------------------------------------------------------------------------
#  Session control
# ---------------------------------------------------------------------------
## Backspace respawn: restart the three steps but keep the tank on its strip.
func on_player_respawn() -> void:
	if not is_active or step == Step.COMPLETED:
		return
	step = Step.ARM_TAKEOFF
	if _target_alive():
		target.health = target.max_health
		if _marker != null and is_instance_valid(_marker):
			_marker.visible = true
		if _beacon != null and is_instance_valid(_beacon):
			_beacon.visible = true
		if _zone != null and is_instance_valid(_zone):
			_zone.visible = true
	_update_hud()
	_update_dots()


func restart_session() -> void:
	_hide_completion()
	step = Step.ARM_TAKEOFF
	elapsed = 0.0
	_toast_timer = 0.0
	_spawn_target(target_pos if target_pos != Vector3.ZERO else Vector3.INF)
	if level != null and level.has_method("_respawn_and_rearm"):
		level.call("_respawn_and_rearm")
	_update_hud()
	_update_dots()


func get_target_info() -> Dictionary:
	if not _target_alive():
		return {}
	return {"pos": target.global_position + Vector3.UP * 3.0,
			"label": _tx("ЦІЛЬ", "TARGET")}


## One-line OSD summary used by BigLevel's three-line HUD block.
func get_status_line() -> String:
	match step:
		Step.ARM_TAKEOFF:
			return _tx("КРОК 1/3 · ARM + 8 м", "STEP 1/3 · ARM + 8 m")
		Step.APPROACH:
			return _tx("КРОК 2/3 · ДО ЦІЛІ %d м", "STEP 2/3 · TARGET %d m") % [
					int(round(_horizontal_distance()))]
		Step.DESTROY:
			return _tx("КРОК 3/3 · G — СКИД · %d м", "STEP 3/3 · G — RELEASE · %d m") % [
					int(round(_horizontal_distance()))]
		_:
			return _tx("ТРЕНУВАННЯ ЗАВЕРШЕНО", "TRAINING COMPLETE")


# ---------------------------------------------------------------------------
#  HUD
# ---------------------------------------------------------------------------
func setup_hud(hud_root: Node) -> void:
	if hud_root == null:
		return
	_hud_container = Control.new()
	_hud_container.name = "CombatTrainingHUD"
	_hud_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.add_child(_hud_container)

	var vp_size := Vector2(1280, 720)
	if hud_root is Control:
		var r := (hud_root as Control).get_viewport_rect().size
		if r.x > 0.0 and r.y > 0.0:
			vp_size = r
	var safe := MenuUI.get_safe_margins(vp_size)
	var safe_top := float(safe.get("top", 0.0))
	var safe_left := float(safe.get("left", 0.0))
	var safe_right := float(safe.get("right", 0.0))
	var card_width := minf(640.0, vp_size.x - safe_left - safe_right - 28.0)
	card_width = maxf(300.0, card_width)

	_card = PanelContainer.new()
	_card.name = "CombatTrainingCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.offset_left = -card_width * 0.5
	_card.offset_right = card_width * 0.5
	_card.offset_top = safe_top + maxf(72.0, vp_size.y * 0.085)
	_card.offset_bottom = _card.offset_top + 146.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.045, 0.040, 0.028, 0.92)
	sb.border_color = Color(0.95, 0.68, 0.22, 0.90)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0.0, 4.0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	_card.add_theme_stylebox_override("panel", sb)
	_hud_container.add_child(_card)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 3)
	_card.add_child(vb)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 8)
	vb.add_child(top)
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_title_lbl.add_theme_color_override("font_color", MenuUI.WARN_AMBER)
	top.add_child(_title_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_dots_row = HBoxContainer.new()
	_dots_row.add_theme_constant_override("separation", 3)
	top.add_child(_dots_row)
	for i in range(TOTAL_STEPS):
		var d := Label.new()
		d.text = "●"
		d.add_theme_font_size_override("font_size", 10)
		d.add_theme_color_override("font_color", Color(0.35, 0.40, 0.36))
		_dots_row.add_child(d)
		_dots.append(d)
	_progress_lbl = Label.new()
	_progress_lbl.add_theme_font_size_override("font_size", 12)
	_progress_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	top.add_child(_progress_lbl)

	_inst_lbl = Label.new()
	_inst_lbl.add_theme_font_size_override("font_size", 13)
	_inst_lbl.add_theme_color_override("font_color", Color(0.96, 0.97, 0.95))
	_inst_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_inst_lbl)

	_metric_lbl = Label.new()
	_metric_lbl.add_theme_font_size_override("font_size", 13)
	_metric_lbl.add_theme_color_override("font_color", Color(0.72, 0.95, 0.74))
	_metric_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_metric_lbl)

	var toast_center := CenterContainer.new()
	toast_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var toast_width := minf(640.0, vp_size.x - safe_left - safe_right - 36.0)
	toast_center.offset_left = -toast_width * 0.5
	toast_center.offset_right = toast_width * 0.5
	toast_center.offset_top = _card.offset_bottom + 6.0
	toast_center.offset_bottom = toast_center.offset_top + 34.0
	_hud_container.add_child(toast_center)
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.09, 0.045, 0.96)
	tsb.border_color = MenuUI.ACCENT
	tsb.set_border_width_all(1)
	tsb.set_corner_radius_all(8)
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	tsb.content_margin_top = 3
	tsb.content_margin_bottom = 3
	_toast_panel.add_theme_stylebox_override("panel", tsb)
	toast_center.add_child(_toast_panel)
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_font_size_override("font_size", 13)
	_toast_lbl.add_theme_color_override("font_color", MenuUI.ACCENT)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_lbl)

	_build_completion(hud_root)
	_update_hud()
	_update_dots()


func _build_completion(hud_root: Node) -> void:
	_completion = Control.new()
	_completion.name = "CombatTrainingComplete"
	_completion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_completion.mouse_filter = Control.MOUSE_FILTER_STOP
	_completion.process_mode = Node.PROCESS_MODE_ALWAYS
	_completion.visible = false
	hud_root.add_child(_completion)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.025, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_completion.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_completion.add_child(center)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(640, 0)
	panel.add_theme_stylebox_override("panel",
			VoltThemeScript.panel_box(Color(0.055, 0.056, 0.064, 0.96),
			VoltThemeScript.YELLOW_BORDER, 2, 18, 30, 24, 18))
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	var title := Label.new()
	title.text = _tx("✓ ЦІЛЬ УРАЖЕНО", "✓ TARGET DESTROYED")
	title.add_theme_font_override("font", VoltThemeScript.font_display())
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", VoltThemeScript.YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var sub := Label.new()
	sub.text = _tx("БОЙОВЕ ТРЕНУВАННЯ ЗАВЕРШЕНО · 3/3 КРОКИ",
			"COMBAT TRAINING COMPLETE · 3/3 STEPS")
	sub.add_theme_font_override("font", VoltThemeScript.font_mono())
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", VoltThemeScript.STONE_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var body := Label.new()
	body.text = _tx("Ви пройшли шлях від першого ARM до першого ураження цілі. "
			+ "Наступний крок — бойовий виліт у кампанії.",
			"You went from the first ARM to your first target hit. "
			+ "The next step is a combat sortie in the campaign.")
	body.add_theme_font_override("font", VoltThemeScript.font_ui())
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", VoltThemeScript.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(body)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)

	var again := Button.new()
	again.text = _tx("↻ ЩЕ РАЗ", "↻ REPEAT")
	again.custom_minimum_size = Vector2(230, 54)
	again.add_theme_font_size_override("font_size", 15)
	VoltThemeScript.apply_button_variant(again, "primary", 12)
	again.pressed.connect(restart_session)
	row.add_child(again)

	var menu := Button.new()
	menu.text = _tx("У ГОЛОВНЕ МЕНЮ", "MAIN MENU")
	menu.custom_minimum_size = Vector2(230, 54)
	menu.add_theme_font_size_override("font_size", 15)
	VoltThemeScript.apply_button_variant(menu, "secondary", 12)
	menu.pressed.connect(_go_to_menu)
	row.add_child(menu)


func _show_completion() -> void:
	if _completion == null:
		return
	_completion.visible = true
	if pause_on_completion:
		get_tree().paused = true


func _hide_completion() -> void:
	if _completion != null:
		_completion.visible = false
	if pause_on_completion and get_tree().paused:
		get_tree().paused = false


func _go_to_menu() -> void:
	_hide_completion()
	# Phone builds boot into the finger-sized tactical menu; desktop uses the
	# cinematic terminal.  Returning to the wrong one after training was a
	# regression on iOS.
	var phone := MenuUI.is_mobile_ui() or OS.get_name() == "iOS" \
			or OS.has_feature("mobile")
	var path := "res://GUI/mobile/MobileMenu.tscn" if phone \
			else "res://GUI/MainMenu.tscn"
	get_tree().change_scene_to_file(path)


func _show_toast(msg: String) -> void:
	if _toast_lbl == null or _toast_panel == null:
		return
	_toast_lbl.text = msg
	_toast_panel.visible = true
	_toast_timer = 4.0


func _update_hud() -> void:
	if _title_lbl == null:
		return
	var data := _step_data()
	var shown := mini(step, TOTAL_STEPS - 1)
	_title_lbl.text = _tx("БОЙОВЕ ТРЕНУВАННЯ · КРОК %d/%d · %s",
			"COMBAT TRAINING · STEP %d/%d · %s") % [
			shown + 1, TOTAL_STEPS, str(data.get("title", ""))]
	var pct := int(round(float(shown) / float(TOTAL_STEPS) * 100.0))
	if step == Step.COMPLETED:
		pct = 100
	_progress_lbl.text = "%d%%" % pct
	_inst_lbl.text = str(data.get("inst", ""))
	_metric_lbl.text = _metric_text()
	var color := Color(0.72, 0.95, 0.74)
	if step == Step.ARM_TAKEOFF:
		var fc = drone.flight_controller if drone != null and is_instance_valid(drone) else null
		if fc != null and not fc.state_armed:
			color = MenuUI.WARN_AMBER
	elif step == Step.DESTROY:
		color = MenuUI.WARN_AMBER
	if step == Step.COMPLETED:
		color = MenuUI.ACCENT
	_metric_lbl.add_theme_color_override("font_color", color)


func _metric_text() -> String:
	match step:
		Step.ARM_TAKEOFF:
			var fc = drone.flight_controller if drone != null and is_instance_valid(drone) else null
			if fc == null or not fc.state_armed:
				return _tx("ДВИГУНИ ВИМКНЕНО · натисніть ARM (ПРОБІЛ / RS)",
						"MOTORS DISARMED · PRESS ARM (SPACE / RS)")
			return _tx("ВИСОТА %.1f / %.0f м · плавно додайте газ",
					"ALTITUDE %.1f / %.0f m · RAISE THE THROTTLE GENTLY") % [
					_altitude(), TAKEOFF_ALTITUDE]
		Step.APPROACH:
			return _tx("ДО ЦІЛІ %d м · ТРИМАЙТЕ 15–30 м",
					"DISTANCE TO TARGET %d m · HOLD 15–30 m") % [
					int(round(_horizontal_distance()))]
		Step.DESTROY:
			var tip := _tx("ПОРАДА: %s", "TIP: %s") % str(_step_data().get("tip", ""))
			return _tx("ДО ЦІЛІ %d м · G — СКИД · %s",
					"DISTANCE %d m · G — RELEASE · %s") % [
					int(round(_horizontal_distance())), tip]
		Step.COMPLETED:
			return _tx("КУРС ЗАВЕРШЕНО · 3/3 КРОКИ · ЧАС %s",
					"COURSE COMPLETE · 3/3 STEPS · TIME %s") % _format_time(elapsed)
	return ""


func _update_dots() -> void:
	for i in range(_dots.size()):
		var col := Color(0.30, 0.35, 0.31)
		if i < step:
			col = Color(0.40, 0.95, 0.50)
		elif i == step:
			col = MenuUI.WARN_AMBER
		_dots[i].add_theme_color_override("font_color", col)


func _format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%02d:%02d" % [total / 60, total % 60]
