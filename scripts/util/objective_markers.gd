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
	if int(phase_info.get("phase", 1)) == 1:
		_show_strike_markers(cam, drone)
		return
	_hide_all()
	return


func _safe_margins() -> Vector4:
	var vs := Vector2(1280, 720)
	if get_viewport() != null:
		vs = get_viewport().get_visible_rect().size
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x < 2.0 or win_size.y < 2.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var sx := vs.x / win_size.x
	var sy := vs.y / win_size.y
	return Vector4(
		maxf(0.0, float(safe.position.x) * sx),
		maxf(0.0, float(safe.position.y) * sy),
		maxf(0.0, (win_size.x - float(safe.end.x)) * sx),
		maxf(0.0, (win_size.y - float(safe.end.y)) * sy)
	)


func _collect_valid_targets(group_name: String, max_dist_m: float = -1.0,
		drone_pos: Vector3 = Vector3.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tree := get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group(group_name):
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var n3 := node as Node3D
		if not n3.visible or n3.get("is_destroyed") == true:
			continue
		var dist := drone_pos.distance_to(n3.global_position)
		if max_dist_m > 0.0 and dist > max_dist_m:
			continue
		out.append({"node": n3, "dist": dist})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["dist"]) < float(b["dist"])
	)
	return out


func _show_strike_markers(cam: Camera3D, drone: Node3D) -> void:
	var d_pos := drone.global_position
	var primaries := _collect_valid_targets("primary_combat_target", -1.0, d_pos)
	var bonuses := _collect_valid_targets("bonus_combat_target", 140.0, d_pos)
	if primaries.is_empty() and bonuses.is_empty():
		primaries = _collect_valid_targets("combat_target", -1.0, d_pos)
	var screen := get_viewport().get_visible_rect().size
	var safe := _safe_margins()
	var min_x := 110.0 + safe.x
	var max_x := maxf(screen.x - 110.0 - safe.z, min_x + 20.0)
	var min_y := 108.0 + safe.y
	var max_y := maxf(screen.y - 245.0 - safe.w, min_y + 20.0)
	var is_en := MenuUI.is_english()
	var slot := 0
	for entry in primaries:
		if slot >= _labels.size():
			break
		var n3: Node3D = entry["node"]
		var world := n3.global_position + Vector3.UP * 2.1
		if cam.is_position_behind(world):
			continue
		var pos := cam.unproject_position(world)
		var clamped := Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, min_y, max_y))
		var dist_m := int(round(float(entry["dist"])))
		var lbl := _labels[slot]
		lbl.text = ("◆ TGT  %d m" if is_en else "◆ ЦІЛЬ  %d м") % dist_m
		lbl.add_theme_color_override("font_color", Color(1.0, 0.36, 0.22, 0.96))
		lbl.position = Vector2(
				clampf(clamped.x - 90.0, safe.x + 8.0, screen.x - safe.z - 188.0),
				clamped.y - 13.0)
		lbl.visible = true
		slot += 1
	for entry in bonuses:
		if slot >= _labels.size():
			break
		var n3: Node3D = entry["node"]
		var world := n3.global_position + Vector3.UP * 2.0
		if cam.is_position_behind(world):
			continue
		var pos := cam.unproject_position(world)
		var clamped := Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, min_y, max_y))
		var dist_m := int(round(float(entry["dist"])))
		var lbl := _labels[slot]
		lbl.text = ("◇ BONUS  %d m" if is_en else "◇ БОНУС  %d м") % dist_m
		lbl.add_theme_color_override("font_color", Color(0.90, 0.85, 0.65, 0.45))
		lbl.position = Vector2(
				clampf(clamped.x - 90.0, safe.x + 8.0, screen.x - safe.z - 188.0),
				clamped.y - 13.0)
		lbl.visible = true
		slot += 1
	while slot < _labels.size():
		_labels[slot].visible = false
		slot += 1


func _show_primary(cam: Camera3D, drone: Node3D, info: Dictionary) -> void:
	var target_pos: Vector3 = info.get("pos", drone.global_position)
	var world := target_pos + Vector3.UP * 2.2
	var screen := get_viewport().get_visible_rect().size
	var safe := _safe_margins()
	var min_x := 130.0 + safe.x
	var max_x := maxf(screen.x - 130.0 - safe.z, min_x + 20.0)
	var min_y := 108.0 + safe.y
	var max_y := maxf(screen.y - 245.0 - safe.w, min_y + 20.0)
	var pos: Vector2
	if cam.is_position_behind(world):
		pos = Vector2(screen.x * 0.5, max_y)
	else:
		pos = cam.unproject_position(world)
	var clamped := Vector2(
			clampf(pos.x, min_x, max_x),
			clampf(pos.y, min_y, max_y))
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
	var obj_x := clampf(clamped.x - 235.0, safe.x + 12.0,
			maxf(screen.x - safe.z - 482.0, safe.x + 12.0))
	_objective_label.position = Vector2(obj_x, clamped.y - 16.0)
	_objective_label.visible = true


func _hide_all() -> void:
	for label in _labels:
		label.visible = false
	if _objective_label != null:
		_objective_label.visible = false
