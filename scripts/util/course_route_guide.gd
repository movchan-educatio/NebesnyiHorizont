class_name CourseRouteGuide
extends Node3D
## Obstacle-aware Volt Yellow 3D route ribbon + directional chevrons linking
## sequential race/freestyle gates without clipping through buildings, cranes,
## piers, bridges, or terrain. Zero colliders, zero shadows.

const ACTIVE_COLOR := Color(1.0, 0.90, 0.06, 0.96)
const ACTIVE_PEAK_COLOR := Color(1.0, 0.99, 0.56, 1.0)
const PREVIEW_COLOR := Color(1.0, 0.72, 0.10, 0.66)

var _active_mesh_inst: MeshInstance3D = null
var _preview_mesh_inst: MeshInstance3D = null
var _active_mat: StandardMaterial3D = null
var _preview_mat: StandardMaterial3D = null
var _segment_cache: Dictionary = {}
var _last_paths: Array = []
var _last_signature: String = ""


func _init() -> void:
	name = "CourseRouteGuide"

	_active_mesh_inst = MeshInstance3D.new()
	_active_mesh_inst.name = "ActiveRouteRibbon"
	_active_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_active_mat = StandardMaterial3D.new()
	_active_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_active_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_active_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_active_mat.albedo_color = ACTIVE_COLOR
	_active_mat.no_depth_test = false
	_active_mesh_inst.material_override = _active_mat
	add_child(_active_mesh_inst)

	_preview_mesh_inst = MeshInstance3D.new()
	_preview_mesh_inst.name = "PreviewRouteRibbon"
	_preview_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview_mat = StandardMaterial3D.new()
	_preview_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_preview_mat.albedo_color = PREVIEW_COLOR
	_preview_mat.no_depth_test = false
	_preview_mesh_inst.material_override = _preview_mat
	add_child(_preview_mesh_inst)


func clear_cache() -> void:
	_segment_cache.clear()
	_last_paths.clear()
	_last_signature = ""
	if _active_mesh_inst != null:
		_active_mesh_inst.mesh = null
	if _preview_mesh_inst != null:
		_preview_mesh_inst.mesh = null


func set_pulse(pulse01: float) -> void:
	var p := clampf(pulse01, 0.0, 1.0)
	if _active_mat != null:
		_active_mat.albedo_color = ACTIVE_COLOR.lerp(ACTIVE_PEAK_COLOR, p * 0.65)
	if _preview_mat != null:
		_preview_mat.albedo_color = Color(
				PREVIEW_COLOR.r, PREVIEW_COLOR.g, PREVIEW_COLOR.b, lerpf(0.52, 0.78, p))


func count_blocked_segments(space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID] = []) -> int:
	if space == null or _last_paths.is_empty():
		return 0
	var blocked := 0
	for path_v in _last_paths:
		var pts := path_v as PackedVector3Array
		if pts.size() < 2:
			continue
		for i in range(pts.size() - 1):
			if _segment_blocked(pts[i], pts[i + 1], space, exclude_rids):
				blocked += 1
	return blocked


## `gates` entries: {"pos": Vector3, "dir": Vector3, "radius": float}
## `origin_anchor`: optional start point before gate 0 (e.g. spawn hover pos).
func update_route(gates: Array[Dictionary], active_idx: int,
		world_space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID] = [],
		origin_anchor: Vector3 = Vector3.INF) -> void:
	if gates.is_empty() or active_idx < 0 or active_idx >= gates.size():
		_last_paths.clear()
		if _active_mesh_inst != null:
			_active_mesh_inst.mesh = null
		if _preview_mesh_inst != null:
			_preview_mesh_inst.mesh = null
		return

	var has_space_tag := "1" if world_space != null else "0"
	var sig := "%d|%d|%s|%s" % [
		gates.size(),
		active_idx,
		has_space_tag,
		str(origin_anchor.snapped(Vector3(2.0, 2.0, 2.0))) if origin_anchor.is_finite() else "inf",
	]
	if sig == _last_signature:
		return
	_last_signature = sig

	var active_paths: Array = []
	var preview_paths: Array = []

	if active_idx > 0:
		var prev_g: Dictionary = gates[active_idx - 1]
		var cur_g: Dictionary = gates[active_idx]
		active_paths.append(_get_or_build_segment(
				"g_%d_%d" % [active_idx - 1, active_idx],
				prev_g, cur_g, world_space, exclude_rids))
		for off in range(4):
			var a_i := active_idx + off
			var b_i := a_i + 1
			if b_i >= gates.size():
				break
			preview_paths.append(_get_or_build_segment(
					"g_%d_%d" % [a_i, b_i],
					gates[a_i], gates[b_i], world_space, exclude_rids))
	else:
		if origin_anchor.is_finite():
			var cur_g0: Dictionary = gates[0]
			var to_g0 := (cur_g0["pos"] as Vector3) - origin_anchor
			var span0 := to_g0.length()
			var anchor_dir := to_g0.normalized() if span0 > 0.01 else (cur_g0.get("dir", Vector3.FORWARD) as Vector3)
			var lead_dist := minf(5.0, span0 * 0.28)
			var anchor_g := {
				"pos": origin_anchor + anchor_dir * lead_dist + Vector3(0.0, 0.55, 0.0),
				"dir": anchor_dir,
				"radius": 1.5,
			}
			active_paths.append(_build_cleared_segment(anchor_g, cur_g0, world_space, exclude_rids))
		if gates.size() > 1:
			active_paths.append(_get_or_build_segment(
					"g_0_1", gates[0], gates[1], world_space, exclude_rids))
		for off in range(1, 5):
			var a_i := off
			var b_i := a_i + 1
			if b_i >= gates.size():
				break
			preview_paths.append(_get_or_build_segment(
					"g_%d_%d" % [a_i, b_i],
					gates[a_i], gates[b_i], world_space, exclude_rids))

	_last_paths.clear()
	for p_act in active_paths:
		_last_paths.append(p_act)
	for p_prev in preview_paths:
		_last_paths.append(p_prev)

	_active_mesh_inst.mesh = _build_ribbon_mesh(active_paths, 0.34, 12.0, 0.95)
	_preview_mesh_inst.mesh = _build_ribbon_mesh(preview_paths, 0.22, 15.0, 0.72)


func _get_or_build_segment(key: String, a: Dictionary, b: Dictionary,
		space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID]) -> PackedVector3Array:
	if space != null and _segment_cache.has(key):
		return _segment_cache[key] as PackedVector3Array
	var pts := _build_cleared_segment(a, b, space, exclude_rids)
	if space != null:
		_segment_cache[key] = pts
	return pts


func _build_cleared_segment(a: Dictionary, b: Dictionary,
		space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID]) -> PackedVector3Array:
	var p0: Vector3 = a.get("pos", Vector3.ZERO)
	var p1: Vector3 = b.get("pos", Vector3.ZERO)
	var span := p0.distance_to(p1)
	if span < 1.0:
		return PackedVector3Array([p0, p1])

	var dir0: Vector3 = (a.get("dir", (p1 - p0).normalized()) as Vector3).normalized()
	var dir1: Vector3 = (b.get("dir", (p1 - p0).normalized()) as Vector3).normalized()
	var r0 := float(a.get("radius", 4.5))
	var r1 := float(b.get("radius", 4.5))

	# Exit straight through gate A and enter straight into gate B.
	var entry_a := p0 + dir0 * clampf(r0 * 0.65, 3.0, minf(8.0, span * 0.22))
	var entry_b := p1 - dir1 * clampf(r1 * 0.65, 3.0, minf(8.0, span * 0.22))
	if space != null:
		if not _point_clear(entry_a, space, exclude_rids, 1.0) or _segment_blocked(p0, entry_a, space, exclude_rids):
			var short_a := p0 + dir0 * minf(2.0, span * 0.14)
			if _point_clear(short_a, space, exclude_rids, 0.9) and not _segment_blocked(p0, short_a, space, exclude_rids):
				entry_a = short_a
			else:
				entry_a = p0
		if not _point_clear(entry_b, space, exclude_rids, 1.0) or _segment_blocked(entry_b, p1, space, exclude_rids):
			var short_b := p1 - dir1 * minf(2.0, span * 0.14)
			if _point_clear(short_b, space, exclude_rids, 0.9) and not _segment_blocked(short_b, p1, space, exclude_rids):
				entry_b = short_b
			else:
				entry_b = p1

	var mid_span := entry_a.distance_to(entry_b)
	var tan_len := clampf(mid_span * 0.42, 6.0, 42.0)
	var t0 := dir0 * tan_len
	var t1 := dir1 * tan_len

	var steps := clampi(int(ceil(mid_span / 8.0)), 6, 18)
	var raw: Array[Vector3] = [p0]
	for i in range(steps + 1):
		var u := float(i) / float(steps)
		var pt := _hermite(entry_a, t0, entry_b, t1, u)
		if space != null and i > 0 and i < steps:
			pt = _lift_above_ground(pt, space, exclude_rids)
		raw.append(pt)
	raw.append(p1)

	if space != null:
		var pruned: Array[Vector3] = [raw[0]]
		for i in range(1, raw.size() - 1):
			if _point_clear(raw[i], space, exclude_rids, 1.0):
				pruned.append(raw[i])
		pruned.append(raw[raw.size() - 1])
		raw = pruned

		for _pass in range(6):
			var next_pts: Array[Vector3] = [raw[0]]
			var modified := false
			for i in range(raw.size() - 1):
				var sa := next_pts[next_pts.size() - 1]
				var sb := raw[i + 1]
				if sa.distance_to(sb) > 1.3 and _segment_blocked(sa, sb, space, exclude_rids):
					var detour := _find_detour_point(sa, sb, space, exclude_rids)
					if detour.is_finite():
						next_pts.append(detour)
						modified = true
					else:
						var pair := _find_bypass_pair(sa, sb, space, exclude_rids)
						if pair.size() == 2:
							next_pts.append(pair[0])
							next_pts.append(pair[1])
							modified = true
						elif i + 1 < raw.size() - 1:
							modified = true
							continue
				next_pts.append(sb)
			raw = next_pts
			if not modified:
				break
		raw = _smooth_if_clear(raw, space, exclude_rids)
		if _has_blocked_segment(raw, space, exclude_rids):
			raw = _build_direct_clear_route(p0, p1, entry_a, entry_b, space, exclude_rids)

	var out := PackedVector3Array()
	out.resize(raw.size())
	for i in range(raw.size()):
		out[i] = raw[i]
	return out


func _has_blocked_segment(pts: Array[Vector3], space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> bool:
	for i in range(pts.size() - 1):
		if _segment_blocked(pts[i], pts[i + 1], space, exclude_rids):
			return true
	return false


func _build_direct_clear_route(p0: Vector3, p1: Vector3, entry_a: Vector3, entry_b: Vector3,
		space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID]) -> Array[Vector3]:
	var ea := entry_a if entry_a != p0 else p0
	var eb := entry_b if entry_b != p1 else p1
	if not _segment_blocked(ea, eb, space, exclude_rids):
		var ok_direct: Array[Vector3] = [p0]
		if ea.distance_to(p0) > 0.2:
			ok_direct.append(ea)
		if eb.distance_to(p1) > 0.2:
			ok_direct.append(eb)
		ok_direct.append(p1)
		return ok_direct

	var single := _find_detour_point(ea, eb, space, exclude_rids)
	if single.is_finite():
		var ok_single: Array[Vector3] = [p0]
		if ea.distance_to(p0) > 0.2:
			ok_single.append(ea)
		ok_single.append(single)
		if eb.distance_to(p1) > 0.2:
			ok_single.append(eb)
		ok_single.append(p1)
		return ok_single

	var pair := _find_bypass_pair(ea, eb, space, exclude_rids)
	if pair.size() == 2:
		var ok_pair: Array[Vector3] = [p0]
		if ea.distance_to(p0) > 0.2:
			ok_pair.append(ea)
		ok_pair.append(pair[0])
		ok_pair.append(pair[1])
		if eb.distance_to(p1) > 0.2:
			ok_pair.append(eb)
		ok_pair.append(p1)
		return ok_pair

	var diff := eb - ea
	var fwd := diff.normalized() if diff.length_squared() > 0.25 else Vector3.FORWARD
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var outward := Vector3(fwd.x, 0.0, fwd.z)
	outward = outward.normalized() if outward.length_squared() > 0.01 else Vector3.FORWARD

	for r: float in [0.0, 14.0, 28.0, 46.0]:
		var lat_dirs: Array[Vector3] = [Vector3.ZERO]
		if r > 0.0:
			lat_dirs = [right * r, -right * r, outward * r, -outward * r]
		for lat: Vector3 in lat_dirs:
			for h: float in [10.0, 22.0, 38.0, 62.0, 95.0]:
				var off: Vector3 = Vector3(0.0, h, 0.0) + lat
				var wp1: Vector3 = _lift_above_ground(ea + off, space, exclude_rids)
				var wp2: Vector3 = _lift_above_ground(eb + off, space, exclude_rids)
				if not _point_clear(wp1, space, exclude_rids, 1.3) or not _point_clear(wp2, space, exclude_rids, 1.3):
					continue
				if not _segment_blocked(ea, wp1, space, exclude_rids) \
						and not _segment_blocked(wp1, wp2, space, exclude_rids) \
						and not _segment_blocked(wp2, eb, space, exclude_rids):
					var ok_sky: Array[Vector3] = [p0]
					if ea.distance_to(p0) > 0.2:
						ok_sky.append(ea)
					ok_sky.append(wp1)
					ok_sky.append(wp2)
					if eb.distance_to(p1) > 0.2:
						ok_sky.append(eb)
					ok_sky.append(p1)
					return ok_sky

	return [p0, p1]


func _hermite(p0: Vector3, m0: Vector3, p1: Vector3, m1: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	var h00 := 2.0 * t3 - 3.0 * t2 + 1.0
	var h10 := t3 - 2.0 * t2 + t
	var h01 := -2.0 * t3 + 3.0 * t2
	var h11 := t3 - t2
	return p0 * h00 + m0 * h10 + p1 * h01 + m1 * h11


func _lift_above_ground(pt: Vector3, space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> Vector3:
	var rq := PhysicsRayQueryParameters3D.create(
			pt + Vector3(0.0, 2.0, 0.0), pt - Vector3(0.0, 6.0, 0.0))
	rq.collision_mask = 1
	rq.exclude = exclude_rids
	var hit := space.intersect_ray(rq)
	if not hit.is_empty():
		var floor_y := (hit["position"] as Vector3).y + 2.4
		if pt.y < floor_y:
			return Vector3(pt.x, floor_y, pt.z)
	return pt


func _segment_blocked(a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> bool:
	var dir := b - a
	var d := dir.length()
	if d < 1.2:
		return false
	var n := dir / d
	# Inset slightly from endpoints so exact endpoint clearances don't false-trigger.
	var inset := minf(1.2, d * 0.22)
	var p_from := a + n * inset
	var p_to := b - n * inset
	var right := n.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = n.cross(Vector3.FORWARD)
	right = right.normalized()
	var up := right.cross(n).normalized()
	var corridor_r := 0.72
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		up * corridor_r,
		-up * corridor_r,
		right * corridor_r,
		-right * corridor_r,
	]
	for off: Vector3 in offsets:
		var rq := PhysicsRayQueryParameters3D.create(p_from + off, p_to + off)
		rq.collision_mask = 1
		rq.exclude = exclude_rids
		if not space.intersect_ray(rq).is_empty():
			return true
	return false


func _find_bypass_pair(a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> Array[Vector3]:
	var diff := b - a
	if diff.length_squared() < 1.0:
		return []
	var fwd := diff.normalized()
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var tries: Array[Vector3] = [
		Vector3(0.0, 5.0, 0.0),
		right * 5.0,
		-right * 5.0,
		right * 5.0 + Vector3(0.0, 4.0, 0.0),
		-right * 5.0 + Vector3(0.0, 4.0, 0.0),
		Vector3(0.0, 12.0, 0.0),
		Vector3(0.0, 22.0, 0.0),
		Vector3(0.0, 36.0, 0.0),
		Vector3(0.0, 52.0, 0.0),
		right * 14.0 + Vector3(0.0, 6.0, 0.0),
		-right * 14.0 + Vector3(0.0, 6.0, 0.0),
		right * 26.0 + Vector3(0.0, 10.0, 0.0),
		-right * 26.0 + Vector3(0.0, 10.0, 0.0),
	]
	for off: Vector3 in tries:
		var clr_r := 1.0 if off.length() <= 7.0 else 1.4
		var candidates := [
			[_lift_above_ground(a.lerp(b, 0.28) + off, space, exclude_rids),
			 _lift_above_ground(a.lerp(b, 0.72) + off, space, exclude_rids)],
			[_lift_above_ground(a + off, space, exclude_rids),
			 _lift_above_ground(b + off, space, exclude_rids)],
		]
		for pair_v in candidates:
			var wp1: Vector3 = pair_v[0]
			var wp2: Vector3 = pair_v[1]
			if not _point_clear(wp1, space, exclude_rids, clr_r) or not _point_clear(wp2, space, exclude_rids, clr_r):
				continue
			if not _segment_blocked(a, wp1, space, exclude_rids) \
					and not _segment_blocked(wp1, wp2, space, exclude_rids) \
					and not _segment_blocked(wp2, b, space, exclude_rids):
				return [wp1, wp2]
	for d: float in [8.0, 18.0, 30.0, 44.0]:
		for side_dir: Vector3 in [right, -right]:
			var wp1: Vector3 = _lift_above_ground(a + side_dir * d, space, exclude_rids)
			var wp2: Vector3 = _lift_above_ground(b + side_dir * d, space, exclude_rids)
			if not _point_clear(wp1, space, exclude_rids, 1.4) or not _point_clear(wp2, space, exclude_rids, 1.4):
				continue
			if not _segment_blocked(a, wp1, space, exclude_rids) \
					and not _segment_blocked(wp1, wp2, space, exclude_rids) \
					and not _segment_blocked(wp2, b, space, exclude_rids):
				return [wp1, wp2]
	return []


func _point_clear(pt: Vector3, space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID], radius: float = 1.6) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sp := SphereShape3D.new()
	sp.radius = radius
	q.shape = sp
	q.collision_mask = 1
	q.exclude = exclude_rids
	q.transform = Transform3D(Basis.IDENTITY, pt)
	return space.intersect_shape(q, 1).is_empty()


func _find_detour_point(a: Vector3, b: Vector3, space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> Vector3:
	var diff := b - a
	var fwd := diff.normalized()
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := right.cross(fwd).normalized()
	var mid := (a + b) * 0.5
	var dirs: Array[Vector3] = [
		up,
		right,
		-right,
		(up + right).normalized(),
		(up - right).normalized(),
		(up * 0.5 + right * 0.85).normalized(),
		(up * 0.5 - right * 0.85).normalized(),
		-up,
		(-up + right).normalized(),
		(-up - right).normalized(),
	]
	for dist: float in [2.5, 4.5, 8.0, 14.0, 22.0, 34.0, 48.0]:
		var clr_r := 0.95 if dist <= 4.5 else 1.5
		for dvec: Vector3 in dirs:
			var cand: Vector3 = mid + dvec * dist
			cand = _lift_above_ground(cand, space, exclude_rids)
			if not _point_clear(cand, space, exclude_rids, clr_r):
				continue
			if not _segment_blocked(a, cand, space, exclude_rids) \
					and not _segment_blocked(cand, b, space, exclude_rids):
				return cand
	return Vector3.INF


func _smooth_if_clear(pts: Array[Vector3], space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID]) -> Array[Vector3]:
	if pts.size() < 4:
		return pts
	var out: Array[Vector3] = [pts[0], pts[1]]
	for i in range(1, pts.size() - 2):
		var c := pts[i] * 0.25 + pts[i + 1] * 0.5 + pts[i + 2] * 0.25
		c = _lift_above_ground(c, space, exclude_rids)
		var prev_p := out[out.size() - 1]
		if not _segment_blocked(prev_p, c, space, exclude_rids) \
				and not _segment_blocked(c, pts[i + 2], space, exclude_rids):
			out.append(c)
		else:
			out.append(pts[i + 1])
	out.append(pts[pts.size() - 1])
	return out


func _build_ribbon_mesh(paths: Array, half_w: float, arrow_spacing: float,
		arrow_scale: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_verts := false

	for path_v in paths:
		var pts := path_v as PackedVector3Array
		if pts.size() < 2:
			continue
		var accum_dist := 0.0
		var next_arrow := maxf(arrow_spacing * 0.55, 7.0)
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var seg := b - a
			var len_s := seg.length()
			if len_s < 0.05:
				continue
			var fwd := seg / len_s
			var side := fwd.cross(Vector3.UP)
			if side.length_squared() < 0.001:
				side = fwd.cross(Vector3.FORWARD)
			side = side.normalized() * half_w
			var vup := side.cross(fwd).normalized() * half_w
			# Crossed X-ribbon so line width reads clearly from every roll angle.
			_emit_quad(st, a - side, a + side, b + side, b - side)
			_emit_quad(st, a - vup, a + vup, b + vup, b - vup)
			has_verts = true

			var seg_end_dist := accum_dist + len_s
			while next_arrow <= seg_end_dist - 1.5:
				var local_t := (next_arrow - accum_dist) / len_s
				var ap := a.lerp(b, local_t)
				var wing := (side.normalized()) * (half_w * 2.4 * arrow_scale)
				var tail := ap - fwd * (1.15 * arrow_scale)
				var tip := ap + fwd * (0.90 * arrow_scale)
				st.add_vertex(tip)
				st.add_vertex(tail + wing)
				st.add_vertex(tail - wing)
				st.add_vertex(tip)
				st.add_vertex(tail - vup.normalized() * (half_w * 2.0 * arrow_scale))
				st.add_vertex(tail + vup.normalized() * (half_w * 2.0 * arrow_scale))
				next_arrow += arrow_spacing
			accum_dist = seg_end_dist

	if not has_verts:
		return null
	return st.commit()


func _emit_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)
