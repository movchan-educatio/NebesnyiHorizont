class_name OpenTower
extends RefCounted

## Hollow, open-top tower shell used for chimneys, cooling towers and silos.
##
## The player explicitly asked to be able to dive into the top of these towers
## (the reference is a wide chimney with a thick sooty rim).  A plain
## CylinderMesh is capped and solid, so it cannot be entered.  This builder
## creates:
##   * an outer wall following a (radius, height) profile,
##   * an inner wall offset inward by `wall`, with a dark material,
##   * a thick top rim, and no top cap at all,
##   * an optional large side bay / base opening,
##   * trimesh collision matching every face, so the openings are flyable.
##
## Two opposite openings can be requested for a through-tunnel; one opening is
## used for a top-dive plus a base exit.

static func build_cylinder(root: Node3D, base: Vector3, radius: float,
		wall: float, height: float, outer_mat: Material, inner_mat: Material,
		opening := {}, segments := 32, node_name := "OpenTower") -> MeshInstance3D:
	var open_min: float = float(opening.get("min_h", 0.0))
	var open_max: float = float(opening.get("max_h", 0.0))
	var heights: Array[float] = [0.0]
	if open_min > 0.01 and open_min < height - 0.01:
		heights.append(open_min)
	if open_max > open_min + 0.01 and open_max < height - 0.01:
		heights.append(open_max)
	heights.append(height)
	heights.sort()
	var profile: Array[Vector2] = []
	for h in heights:
		if profile.is_empty() or absf(profile[profile.size() - 1].y - h) > 0.01:
			profile.append(Vector2(radius, h))
	return build_profile(root, base, profile, wall, outer_mat, inner_mat,
			opening, segments, node_name)


static func build_profile(root: Node3D, base: Vector3,
		profile: Array[Vector2], wall: float, outer_mat: Material,
		inner_mat: Material, opening := {}, segments := 32,
		node_name := "OpenTower") -> MeshInstance3D:
	if root == null or profile.size() < 2:
		return null
	wall = clampf(wall, 0.55, profile[0].x * 0.42)
	# Foundation skirt: the shell keeps going deep below the pivot (at least 8m)
	# so a tower on any slope is firmly anchored and never hovers above ground.
	if profile[0].y >= -0.01:
		var skirt := maxf(8.0, profile[0].x * 0.85)
		var buried: Array[Vector2] = [Vector2(profile[0].x, -skirt)]
		buried.append_array(profile)
		profile = buried
	var open_deg: float = float(opening.get("deg", 0.0))
	var open_min: float = float(opening.get("min_h", 0.0))
	var open_max: float = float(opening.get("max_h", 0.0))
	var open_count: int = maxi(1, int(opening.get("count", 1)))
	var outer_verts := PackedVector3Array()
	var outer_norms := PackedVector3Array()
	var outer_uvs := PackedVector2Array()
	var outer_idx := PackedInt32Array()
	var inner_verts := PackedVector3Array()
	var inner_norms := PackedVector3Array()
	var inner_uvs := PackedVector2Array()
	var inner_idx := PackedInt32Array()

	for row in range(profile.size()):
		var r: float = profile[row].x
		var h: float = profile[row].y
		var r_next: float = profile[mini(row + 1, profile.size() - 1)].x
		var h_next: float = profile[mini(row + 1, profile.size() - 1)].y
		var r_prev: float = profile[maxi(row - 1, 0)].x
		var h_prev: float = profile[maxi(row - 1, 0)].y
		var slope := (r_next - r_prev) / maxf(h_next - h_prev, 0.001)
		var r_in := maxf(r - wall, 0.05)
		for i in range(segments + 1):
			var a := TAU * float(i % segments) / float(segments)
			var nx := cos(a)
			var nz := sin(a)
			var n := Vector3(nx, -slope, nz).normalized()
			outer_verts.append(base + Vector3(nx * r, h, nz * r))
			outer_norms.append(n)
			outer_uvs.append(Vector2(float(i) / float(segments) * 8.0, h / 6.0))
			inner_verts.append(base + Vector3(nx * r_in, h, nz * r_in))
			inner_norms.append(-n)
			inner_uvs.append(Vector2(float(i) / float(segments) * 8.0, h / 6.0))

	for row in range(profile.size() - 1):
		var h_mid := (profile[row].y + profile[row + 1].y) * 0.5
		for i in range(segments):
			if open_deg > 0.01 and h_mid >= open_min and h_mid <= open_max:
				var mid_a := TAU * (float(i) + 0.5) / float(segments)
				var cut := false
				for k in range(open_count):
					var centre := PI * float(k)
					if absf(wrapf(mid_a - centre, -PI, PI)) < deg_to_rad(open_deg) * 0.5:
						cut = true
						break
				if cut:
					continue
			var a_i := row * (segments + 1) + i
			var b_i := a_i + segments + 1
			outer_idx.append_array([a_i, b_i, a_i + 1, a_i + 1, b_i, b_i + 1])
			# Inner wall is wound the other way so it is visible from inside the
			# tube; with the same winding the interior rendered see-through.
			inner_idx.append_array([a_i, a_i + 1, b_i, a_i + 1, b_i + 1, b_i])

	# Thick top rim: connects the outer and inner top rings.  The centre stays
	# open, which is the whole point of the tower.
	var top_row := profile.size() - 1
	var top_h: float = profile[top_row].y
	var outer_r: float = profile[top_row].x
	var inner_r := maxf(outer_r - wall, 0.05)
	var rim_start := outer_verts.size()
	for i in range(segments + 1):
		var a := TAU * float(i % segments) / float(segments)
		var nx := cos(a)
		var nz := sin(a)
		outer_verts.append(base + Vector3(nx * outer_r, top_h, nz * outer_r))
		outer_norms.append(Vector3.UP)
		outer_uvs.append(Vector2(float(i) / float(segments) * 8.0, 0.0))
	for i in range(segments + 1):
		var a := TAU * float(i % segments) / float(segments)
		var nx := cos(a)
		var nz := sin(a)
		outer_verts.append(base + Vector3(nx * inner_r, top_h, nz * inner_r))
		outer_norms.append(Vector3.UP)
		outer_uvs.append(Vector2(float(i) / float(segments) * 8.0, 0.3))
	for i in range(segments):
		var o0 := rim_start + i
		var o1 := o0 + 1
		var i0 := rim_start + segments + 1 + i
		var i1 := i0 + 1
		outer_idx.append_array([o0, i0, o1, o1, i0, i1])

	# Close doorway jambs and lintels so base openings have solid wall thickness
	# instead of exposing gap between outer and inner shells.
	if open_deg > 0.01 and open_max > open_min:
		var cut_flags: Array[bool] = []
		for i in range(segments):
			var mid_a := TAU * (float(i) + 0.5) / float(segments)
			var is_cut := false
			for k in range(open_count):
				var centre := PI * float(k)
				if absf(wrapf(mid_a - centre, -PI, PI)) < deg_to_rad(open_deg) * 0.5:
					is_cut = true
					break
			cut_flags.append(is_cut)
		for row in range(profile.size() - 1):
			var h0: float = profile[row].y
			var h1: float = profile[row + 1].y
			var h_mid := (h0 + h1) * 0.5
			if h_mid < open_min or h_mid > open_max:
				continue
			var r0: float = profile[row].x
			var r1: float = profile[row + 1].x
			var r0_in := maxf(r0 - wall, 0.05)
			var r1_in := maxf(r1 - wall, 0.05)
			for i in range(segments):
				if not cut_flags[i]:
					continue
				var prev_cut := cut_flags[(i - 1 + segments) % segments]
				var next_cut := cut_flags[(i + 1) % segments]
				if not prev_cut:
					var a := TAU * float(i) / float(segments)
					var nx := cos(a)
					var nz := sin(a)
					var jn := Vector3(-nz, 0.0, nx)
					var jb := outer_verts.size()
					outer_verts.append_array([
						base + Vector3(nx * r0, h0, nz * r0),
						base + Vector3(nx * r1, h1, nz * r1),
						base + Vector3(nx * r0_in, h0, nz * r0_in),
						base + Vector3(nx * r1_in, h1, nz * r1_in),
					])
					outer_norms.append_array([jn, jn, jn, jn])
					outer_uvs.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)])
					outer_idx.append_array([jb, jb + 1, jb + 2, jb + 2, jb + 1, jb + 3, jb, jb + 2, jb + 1, jb + 2, jb + 3, jb + 1])
				if not next_cut:
					var a := TAU * float((i + 1) % segments) / float(segments)
					var nx := cos(a)
					var nz := sin(a)
					var jn := Vector3(nz, 0.0, -nx)
					var jb := outer_verts.size()
					outer_verts.append_array([
						base + Vector3(nx * r0, h0, nz * r0),
						base + Vector3(nx * r1, h1, nz * r1),
						base + Vector3(nx * r0_in, h0, nz * r0_in),
						base + Vector3(nx * r1_in, h1, nz * r1_in),
					])
					outer_norms.append_array([jn, jn, jn, jn])
					outer_uvs.append_array([Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(1, 1)])
					outer_idx.append_array([jb, jb + 2, jb + 1, jb + 2, jb + 3, jb + 1, jb, jb + 1, jb + 2, jb + 2, jb + 1, jb + 3])
				# Lintel soffit at the top of the opening
				if absf(h1 - open_max) < 0.05:
					var a0 := TAU * float(i) / float(segments)
					var a1 := TAU * float((i + 1) % segments) / float(segments)
					var lb := outer_verts.size()
					outer_verts.append_array([
						base + Vector3(cos(a0) * r1, h1, sin(a0) * r1),
						base + Vector3(cos(a1) * r1, h1, sin(a1) * r1),
						base + Vector3(cos(a0) * r1_in, h1, sin(a0) * r1_in),
						base + Vector3(cos(a1) * r1_in, h1, sin(a1) * r1_in),
					])
					outer_norms.append_array([Vector3.DOWN, Vector3.DOWN, Vector3.DOWN, Vector3.DOWN])
					outer_uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
					outer_idx.append_array([lb, lb + 1, lb + 2, lb + 2, lb + 1, lb + 3, lb, lb + 2, lb + 1, lb + 2, lb + 3, lb + 1])

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = outer_verts
	arrays[Mesh.ARRAY_NORMAL] = outer_norms
	arrays[Mesh.ARRAY_TEX_UV] = outer_uvs
	arrays[Mesh.ARRAY_INDEX] = outer_idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, outer_mat)
	var inner_arrays := []
	inner_arrays.resize(Mesh.ARRAY_MAX)
	inner_arrays[Mesh.ARRAY_VERTEX] = inner_verts
	inner_arrays[Mesh.ARRAY_NORMAL] = inner_norms
	inner_arrays[Mesh.ARRAY_TEX_UV] = inner_uvs
	inner_arrays[Mesh.ARRAY_INDEX] = inner_idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, inner_arrays)
	mesh.surface_set_material(1, inner_mat)

	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("no_batch", true)
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.name = node_name + "Col"
	body.collision_layer = 1
	body.collision_mask = 1
	# Build the collision from ONE combined surface.  A two-surface ArrayMesh
	# gave the player a one-sided collider: rays/players passed through the
	# outer wall and only hit the inner wall.  Combine outer + inner + rim and
	# enable back-face collision so the tube is solid from both sides.
	var col_verts := outer_verts.duplicate()
	col_verts.append_array(inner_verts)
	var col_norms := outer_norms.duplicate()
	col_norms.append_array(inner_norms)
	var col_idx := outer_idx.duplicate()
	var index_offset := outer_verts.size()
	for idx in inner_idx:
		col_idx.append(idx + index_offset)
	var col_mesh := ArrayMesh.new()
	var col_arrays := []
	col_arrays.resize(Mesh.ARRAY_MAX)
	col_arrays[Mesh.ARRAY_VERTEX] = col_verts
	col_arrays[Mesh.ARRAY_NORMAL] = col_norms
	col_arrays[Mesh.ARRAY_INDEX] = col_idx
	col_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, col_arrays)
	var shape := col_mesh.create_trimesh_shape()
	if shape != null:
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	root.add_child(body)
	return mi
