## Dynamic objective markers for combat missions.
##
## Phase 1/3 (recon) and 3/3 (extract) show one large primary marker with
## distance and hold progress.  Phase 2/3 (strike) shows the four nearest live
## enemy targets.  Projection and group scans are throttled to ~8 Hz so the FPV
## frame keeps its budget for physics and rendering.
class_name ObjectiveMarkers
extends Control

const MAX_MARKERS := 4
const UPDATE_INTERVAL := 0.12

var _level: Node = null
var _labels: Array[Label] = []
var _objective_label: Label = null
var _tick := 0.0


func setup(level: Node) -> void:
	_level = level
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(MAX_MARKERS):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.03, 0.95))
		label.add_theme_constant_override("outline_size", 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size = Vector2(180, 26)
		label.size = Vector2(180, 26)
		label.visible = false
		add_child(label)
		_labels.append(label)
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 21)
	_objective_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75))
	_objective_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.02, 0.98))
	_objective_label.add_theme_constant_override("outline_size", 6)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.custom_minimum_size = Vector2(470, 32)
	_objective_label.size = Vector2(470, 32)
	_objective_label.visible = false
	add_child(_objective_label)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = UPDATE_INTERVAL
	if _level == null or not is_instance_valid(_level):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.name != "FPVCamera":
		_hide_all()
		return
	var drone := _level.get_node_or_null("Drone") as Node3D
	if drone == null:
		_hide_all()
		return

	var phase_info: Dictionary = {}
	if _level.has_method("get_mission_phase_info"):
		var raw = _level.call("get_mission_phase_info")
		if raw is Dictionary:
			phase_info = raw
	if not phase_info.is_empty() and phase_info.has("pos") \
			and int(phase_info.get("phase", 1)) != 1:
		_show_primary(cam, drone, phase_info)
		for label in _labels:
			label.visible = false
		return
	_objective_label.visible = false
	# No floating "◆ N м" labels over enemy vehicles/infantry: the player
	# identifies targets visually and with the HUD threat warning.
	_hide_all()
	return


func _show_primary(cam: Camera3D, drone: Node3D, info: Dictionary) -> void:
	var target_pos: Vector3 = info.get("pos", drone.global_position)
	var world := target_pos + Vector3.UP * 2.2
	var screen := get_viewport().get_visible_rect().size
	var pos: Vector2
	if cam.is_position_behind(world):
		pos = Vector2(screen.x * 0.5, screen.y - 170.0)
	else:
		pos = cam.unproject_position(world)
	var clamped := Vector2(
			clampf(pos.x, 120.0, screen.x - 120.0),
			clampf(pos.y, 110.0, screen.y - 150.0))
	var dist_m := int(round(drone.global_position.distance_to(target_pos)))
	var label_text := str(info.get("label", "ЦІЛЬ"))
	# Distance + bearing arrow so the pilot can actually find the zone: the
	# old marker only showed the objective name and hold %, and a player who
	# flew the wrong way had no way to tell that the zone was 300 m behind.
	var flat := target_pos - drone.global_position
	flat.y = 0.0
	var fwd := -drone.global_transform.basis.z
	fwd.y = 0.0
	var right := drone.global_transform.basis.x
	right.y = 0.0
	var arrow := "↑"
	var flat_len := flat.length()
	if flat_len > 0.5:
		var ahead := flat.dot(fwd)
		var side := flat.dot(right)
		if ahead < -0.2 * flat_len:
			arrow = "↓"
		elif side > 0.38 * flat_len:
			arrow = "→"
		elif side < -0.38 * flat_len:
			arrow = "←"
	if MenuUI.is_english():
		match label_text:
			"РОЗВІДКА":
				label_text = "RECON"
			"ВИХІД":
				label_text = "EXTRACT"
			"УДАР":
				label_text = "STRIKE"
	var progress := int(clampf(float(info.get("progress", 0.0)), 0.0, 1.0) * 100.0)
	_objective_label.text = "◆ %s %s  %d м · %d%%" % [label_text, arrow, dist_m, progress]
	var col: Color = info.get("color", Color(0.35, 0.95, 0.75))
	_objective_label.add_theme_color_override("font_color", col)
	_objective_label.position = clamped - Vector2(235.0, 14.0)
	_objective_label.visible = true


func _hide_all() -> void:
	for label in _labels:
		label.visible = false
	if _objective_label != null:
		_objective_label.visible = false
