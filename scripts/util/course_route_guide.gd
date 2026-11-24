class_name CourseRouteGuide
extends Node3D
## Obstacle-aware Volt Yellow 3D route ribbon + directional chevrons linking
## sequential race/freestyle gates without clipping through buildings, cranes,
## piers, bridges, or terrain. Zero colliders, zero shadows.

const ACTIVE_COLOR := Color(1.0, 0.88, 0.08, 0.94)
const PREVIEW_COLOR := Color(1.0, 0.66, 0.14, 0.52)

var _active_mesh_inst: MeshInstance3D = null
var _preview_mesh_inst: MeshInstance3D = null
var _segment_cache: Dictionary = {}
var _last_signature: String = ""


func _init() -> void:
	name = "CourseRouteGuide"

	_active_mesh_inst = MeshInstance3D.new()
	_active_mesh_inst.name = "ActiveRouteRibbon"
	_active_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat_act := StandardMaterial3D.new()
	mat_act.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_act.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_act.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_act.albedo_color = ACTIVE_COLOR
	mat_act.no_depth_test = false
	_active_mesh_inst.material_override = mat_act
	add_child(_active_mesh_inst)

	_preview_mesh_inst = MeshInstance3D.new()
	_preview_mesh_inst.name = "PreviewRouteRibbon"
	_preview_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat_prev := StandardMaterial3D.new()
	mat_prev.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_prev.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_prev.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat_prev.albedo_color = PREVIEW_COLOR
	mat_prev.no_depth_test = false
	_preview_mesh_inst.material_override = mat_prev
	add_child(_preview_mesh_inst)


func clear_cache() -> void:
	_segment_cache.clear()
	_last_signature = ""
	if _active_mesh_inst != null:
		_active_mesh_inst.mesh = null
	if _preview_mesh_inst != null:
		_preview_mesh_inst.mesh = null


## `gates` entries: {"pos": Vector3, "dir": Vector3, "radius": float}
## `origin_anchor`: optional start point before gate 0 (e.g. spawn hover pos).
func update_route(gates: Array[Dictionary], active_idx: int,
		world_space: PhysicsDirectSpaceState3D,
		exclude_rids: Array[RID] = [],
		origin_anchor: Vector3 = Vector3.INF) -> void:
	if gates.is_empty() or active_idx < 0 or active_idx >= gates.size():
		if _active_mesh_inst != null:
			_active_mesh_inst.mesh = null
		if _preview_mesh_inst != null:
			_preview_mesh_inst.mesh = null
		return

	var sig := "%d|%d|%s" % [gates.size(), active_idx, str(origin_anchor.snapped(Vector3(2.0, 2.0, 2.0)))]
	if sig == _last_signature:
		return
	_last_signature = sig

	var active_paths: Array = []
	var preview_paths: Array = []

	# Active segment: from previous gate (or spawn anchor before gate 0) to active_idx.
	if active_idx > 0:
		var prev_g: Dictionary = gates[active_idx - 1]
		var cur_g: Dictionary = gates[active_idx]
		active_paths.append(_get_or_build_segment(
				"g_%d_%d" % [active_idx - 1, active_idx],
				prev_g, cur_g, world_space, exclude_rids))
	elif origin_anchor.is_finite():
		var cur_g0: Dictionary = gates[0]
		var anchor_g := {
			"pos": origin_anchor + Vector3(0.0, 1.4, 0.0),
			"dir": (cur_g0["pos"] as Vector3 - origin_anchor).normalized(),
			"radius": 2.0,
		}
		if (anchor_g["dir"] as Vector3).length_squared() < 0.01:
			anchor_g["dir"] = cur_g0.get("dir", Vector3.FORWARD)
		active_paths.append(_build_cleared_segment(anchor_g, cur_g0, world_space, exclude_rids))

	# Lookahead segments: active -> active+1 -> active+2
	for off in range(2):
		var a_i := active_idx + off
		var b_i := a_i + 1
		if b_i >= gates.size():
			break
		var seg := _get_or_build_segment(
				"g_%d_%d" % [a_i, b_i],
				gates[a_i], gates[b_i], world_space, exclude_rids)
		if off == 0 and active_idx == 0 and not origin_anchor.is_finite():
			active_paths.append(seg)
		else:
			preview_paths.append(seg)

	_active_mesh_inst.mesh = _build_ribbon_mesh(active_paths, 0.34, 14.0, 1.05)
	_preview_mesh_inst.mesh = _build_ribbon_mesh(preview_paths, 0.22, 18.0, 0.72)


func _get_or_build_segment(key: String, a: Dictionary, b: Dictionary,
		space: PhysicsDirectSpaceState3D, exclude_rids: Array[RID]) -> PackedVector3Array:
	if _segment_cache.has(key):
		return _segment_cache[key] as PackedVector3Array
	var pts := _build_cleared_segment(a, b, space, exclude_rids)
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
	var entry_a := p0 + dir0 * clampf(r0 * 0.75, 2.5, span * 0.25)
	var entry_b := p1 - dir1 * clampf(r1 * 0.75, 2.5, span * 0.25)

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
		for _pass in range(3):
			var next_pts: Array[Vector3] = [raw[0]]
			var modified := false
			for i in range(raw.size() - 1):
				var sa := raw[i]
				var sb := raw[i + 1]
				# Keep gate threshold portals untouched so we stay aligned with the ring center.
				var near_gate := (i == 0 or i == raw.size() - 2)
				if not near_gate and sa.distance_to(sb) > 3.5 and _segment_blocked(sa, sb, space, exclude_rids):
					var detour := _find_detour_point(sa, sb, space, exclude_rids)
					if detour.is_finite():
						next_pts.append(detour)
						modified = true
				next_pts.append(sb)
			raw = next_pts
			if not modified:
				break
		raw = _smooth_if_clear(raw, space, exclude_rids)

	var out := PackedVector3Array()
	out.resize(raw.size())
	for i in range(raw.size()):
		out[i] = raw[i]
	return out


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
	var inset := minf(0.8, d * 0.2)
	var rq := PhysicsRayQueryParameters3D.create(a + n * inset, b - n * inset)
	rq.collision_mask = 1
	rq.exclude = exclude_rids
	return not space.intersect_ray(rq).is_empty()


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
		-up * 0.7,
	]
	for dist: float in [6.0, 12.0, 20.0, 32.0, 46.0]:
		for dvec: Vector3 in dirs:
			var cand: Vector3 = mid + dvec * dist
			cand = _lift_above_ground(cand, space, exclude_rids)
			if not _point_clear(cand, space, exclude_rids, 1.7):
				continue
			if not _segment_blocked(a, cand, space, exclude_rids) \
					and not _segment_blocked(cand, b, space, exclude_rids):
				return cand
	# Fallback high clear point if horizontal detours are walled in.
	for extra_h: float in [14.0, 28.0, 44.0]:
		var hi: Vector3 = mid + Vector3(0.0, extra_h, 0.0)
		if _point_clear(hi, space, exclude_rids, 1.8):
			return hi
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
		var next_arrow := arrow_spacing * 0.45
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
				var wing := (side.normalized()) * (half_w * 3.1 * arrow_scale)
				var tail := ap - fwd * (1.25 * arrow_scale)
				var tip := ap + fwd * (0.95 * arrow_scale)
				st.add_vertex(tip)
				st.add_vertex(tail + wing)
				st.add_vertex(tail - wing)
				st.add_vertex(tip)
				st.add_vertex(tail - vup.normalized() * (half_w * 2.5 * arrow_scale))
				st.add_vertex(tail + vup.normalized() * (half_w * 2.5 * arrow_scale))
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
