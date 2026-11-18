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
		label.add_theme_font_size_override("font_size", 21)
		label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.02, 0.98))
		label.add_theme_constant_override("outline_size", 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.custom_minimum_size = Vector2(240, 32)
		label.size = Vector2(240, 32)
		label.visible = false
		add_child(label)
		_labels.append(label)
	_objective_label = Label.new()
	_objective_label.add_theme_font_size_override("font_size", 25)
	_objective_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.75))
	_objective_label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.02, 0.98))
	_objective_label.add_theme_constant_override("outline_size", 7)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_label.custom_minimum_size = Vector2(520, 36)
	_objective_label.size = Vector2(520, 36)
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

	var special_info: Dictionary = {}
	if _level.has_method("get_special_objective_info"):
		var sraw = _level.call("get_special_objective_info")
		if sraw is Dictionary:
			special_info = sraw
	if not special_info.is_empty() and special_info.has("pos"):
		_show_primary(cam, drone, special_info)
		_show_strike_markers(cam, drone)
		return

	var phase_info: Dictionary = {}
	if _level.has_method("get_mission_phase_info"):
		var raw = _level.call("get_mission_phase_info")
		if raw is Dictionary:
			phase_info = raw
	if not phase_info.is_empty() and phase_info.has("pos") \
			and int(phase_info.get("phase", 1)) != 1:
		_show_primary(cam, drone, phase_info)
		if int(phase_info.get("phase", 1)) == 0:
			# Also show enemy target markers during Recon so the pilot immediately
			# sees what needs to be destroyed.
			_show_strike_markers(cam, drone)
		else:
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


func _target_type_name(n3: Node3D, is_en: bool) -> String:
	if n3 == null:
		return "TGT" if is_en else "ЦІЛЬ"
	if n3.is_in_group("enemy_infantry") or n3 is EnemyRifleman:
		var v := String(n3.get("variant")) if n3.get("variant") != null else ""
		if v == "spetsnaz":
			return "SPETSNAZ" if is_en else "СПЕЦНАЗ"
		return "INFANTRY" if is_en else "ПІХОТА"
	if n3 is AAGun:
		return "AA GUN" if is_en else "ЗЕНІТКА"
	if n3.get("kind") != null:
		var k := int(n3.get("kind"))
		var v := String(n3.get("variant")) if n3.get("variant") != null else ""
		if v == "oreshnik":
			return "ORESHNIK" if is_en else "ОРЄШНІК"
		elif v == "ural":
			return "URAL TRUCK" if is_en else "ВАНТАЖІВКА УРАЛ"
		elif v == "mtsm":
			return "MT-SM" if is_en else "ТЯГАЧ МТ-СМ"
		elif v == "btr8":
			return "BTR-80" if is_en else "БТР-80"
		elif v == "cruise_missile":
			return "CRUISE MISSILE" if is_en else "КРИЛАТА РАКЕТА"
		match k:
			0: return "T-72 TANK" if is_en else "ТАНК Т-72"
			1: return "BMP-2M" if is_en else "БМП-2М"
			2: return "BTR-90" if is_en else "БТР-90"
			3: return "TIGR" if is_en else "БРОНЕАВТО ТИГР"
			4: return "SAM AA" if is_en else "ЗРК ППО"
			5: return "HELICOPTER" if is_en else "ГЕЛІКОПТЕР"
			6: return "SHAHED" if is_en else "ШАХЕД-136"
	return "TARGET" if is_en else "ЦІЛЬ"


func _project_with_edge_hint(cam: Camera3D, drone: Node3D, world: Vector3,
		min_x: float, max_x: float, min_y: float, max_y: float, screen: Vector2) -> Dictionary:
	var behind := cam.is_position_behind(world)
	var pos := Vector2.ZERO
	var arrow := ""
	if behind:
		var local_tgt := drone.global_transform.affine_inverse() * world
		pos = Vector2(max_x if local_tgt.x >= 0.0 else min_x, (min_y + max_y) * 0.5)
		arrow = " →" if local_tgt.x >= 0.0 else " ←"
	else:
		pos = cam.unproject_position(world)
		if pos.x < min_x:
			arrow = " ←"
		elif pos.x > max_x:
			arrow = " →"
		elif pos.y < min_y:
			arrow = " ↑"
		elif pos.y > max_y:
			arrow = " ↓"
	var clamped := Vector2(clampf(pos.x, min_x, max_x), clampf(pos.y, min_y, max_y))
	return {"pos": clamped, "arrow": arrow}


func _show_strike_markers(cam: Camera3D, drone: Node3D) -> void:
	var d_pos := drone.global_position
	var primaries := _collect_valid_targets("primary_combat_target", -1.0, d_pos)
	var bonuses := _collect_valid_targets("bonus_combat_target", 140.0, d_pos)
	if primaries.is_empty() and bonuses.is_empty():
		primaries = _collect_valid_targets("combat_target", -1.0, d_pos)
	var screen := get_viewport().get_visible_rect().size
	var safe := _safe_margins()
	var min_x := 125.0 + safe.x
	var max_x := maxf(screen.x - 125.0 - safe.z, min_x + 20.0)
	var min_y := 112.0 + safe.y
	var max_y := maxf(screen.y - 245.0 - safe.w, min_y + 20.0)
	var is_en := MenuUI.is_english()
	var placed_positions: Array[Vector2] = []
	var slot := 0
	for entry in primaries:
		if slot >= _labels.size():
			break
		var n3: Node3D = entry["node"]
		var world := n3.global_position + Vector3.UP * 2.1
		var proj := _project_with_edge_hint(cam, drone, world, min_x, max_x, min_y, max_y, screen)
		var clamped: Vector2 = proj["pos"]
		var arrow: String = proj["arrow"]
		var dist_m := int(round(float(entry["dist"])))
		var tname := _target_type_name(n3, is_en)
		var lbl := _labels[slot]
		lbl.text = ("◆ %s%s · %d m" if is_en else "◆ %s%s · %d м") % [tname, arrow, dist_m]
		lbl.add_theme_color_override("font_color", Color(1.0, 0.34, 0.20, 0.98))
		var lbl_pos := Vector2(
				clampf(clamped.x - 120.0, safe.x + 8.0, screen.x - safe.z - 248.0),
				clamped.y - 16.0)
		for _step in range(8):
			var collides := false
			for prev in placed_positions:
				if absf(lbl_pos.x - prev.x) < 185.0 and absf(lbl_pos.y - prev.y) < 30.0:
					collides = true
					break
			if not collides:
				break
			lbl_pos.y += 32.0
			if lbl_pos.y > max_y - 12.0:
				lbl_pos.y = min_y - 12.0 + float(_step) * 32.0
		placed_positions.append(lbl_pos)
		lbl.position = lbl_pos
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
		var tname := _target_type_name(n3, is_en)
		var lbl := _labels[slot]
		lbl.text = ("◇ %s · %d m" if is_en else "◇ %s · %d м") % [tname, dist_m]
		lbl.add_theme_color_override("font_color", Color(0.95, 0.86, 0.55, 0.72))
		var lbl_pos := Vector2(
				clampf(clamped.x - 120.0, safe.x + 8.0, screen.x - safe.z - 248.0),
				clamped.y - 16.0)
		for _step in range(8):
			var collides := false
			for prev in placed_positions:
				if absf(lbl_pos.x - prev.x) < 185.0 and absf(lbl_pos.y - prev.y) < 30.0:
					collides = true
					break
			if not collides:
				break
			lbl_pos.y += 32.0
			if lbl_pos.y > max_y - 12.0:
				lbl_pos.y = min_y - 12.0 + float(_step) * 32.0
		placed_positions.append(lbl_pos)
		lbl.position = lbl_pos
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
	_objective_label.text = ("◆ %s %s  %d m · %d%%" if MenuUI.is_english() else "◆ %s %s  %d м · %d%%") % [label_text, arrow, dist_m, progress]
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
