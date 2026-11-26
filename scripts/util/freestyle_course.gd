class_name FreestyleCourse
extends RefCounted

const RING_COUNT := 24
const PROMPZONA_RING_COUNT := 28
const SHAPE_SQUARE := 0
const SHAPE_ARCH := 1
const SHAPE_DIAMOND := 2
const SHAPE_HEXAGON := 3
const SHAPE_UGATE := 4
const ARCH_MAX_AGL_MULT := 1.40
const ARCH_MAX_SLOPE_DIFF := 2.6

const GATE_PINK := Color(1.0, 0.09, 0.52, 1.0)
const GATE_PINK_HOT := Color(1.0, 0.16, 0.60, 1.0)
const GATE_PINK_DIM := Color(0.28, 0.02, 0.14, 1.0)
const GATE_TEX_PATH := "res://Assets/textures/gate_horizon_face.png"

static var _cached_gate_tex: Texture2D = null
static var _cached_gate_mesh_z: ArrayMesh = null
static var _cached_gate_mesh_y: ArrayMesh = null
static var _cached_halo_mesh_z: ArrayMesh = null
static var _cached_halo_mesh_y: ArrayMesh = null
static var _cached_bezel_mat: StandardMaterial3D = null

## 24-gate Sofiyivka / Uman freestyle park loop starting straight ahead of GLB PlayerSpawn (-5.05, 1.6, 75.91).
const UMAN_WAYPOINTS: Array[Vector3] = [
	Vector3(-5.0, 4.4, 54.0),
	Vector3(-18.0, 5.2, 34.0),
	Vector3(-42.0, 5.6, 22.0),
	Vector3(-72.0, 6.0, 12.0),
	Vector3(-92.0, 6.4, -8.0),
	Vector3(-86.0, 7.0, -38.0),
	Vector3(-62.0, 7.4, -62.0),
	Vector3(-28.0, 7.6, -74.0),
	Vector3(10.0, 7.6, -74.0),
	Vector3(48.0, 8.2, -64.0),
	Vector3(82.0, 8.2, -44.0),
	Vector3(114.0, 7.6, -24.0),
	Vector3(128.0, 8.8, -2.0),
	Vector3(132.0, 10.2, 28.0),
	Vector3(134.0, 7.0, 60.0),
	Vector3(132.0, 6.8, 90.0),
	Vector3(120.0, 6.4, 114.0),
	Vector3(98.0, 6.0, 118.0),
	Vector3(74.0, 5.8, 118.0),
	Vector3(50.0, 5.8, 116.0),
	Vector3(38.0, 5.8, 114.0),
	Vector3(18.0, 6.0, 104.0),
	Vector3(2.0, 5.8, 95.0),
	Vector3(-5.0, 5.2, 85.0),
]


static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios") \
			or OS.has_environment("MOBILE_UI")


## Dynamic course length per map: the merged Promzona/Plavni arena runs a
## 28-gate loop, the legacy maps keep their authored 24-gate courses.
static func expected_ring_count(map_id: String) -> int:
	if map_id == "promzona_plavni":
		return PROMPZONA_RING_COUNT
	if map_id == "ruins":
		return 29
	return RING_COUNT


static func _neon_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.2
	mat.metallic = 0.08
	mat.roughness = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func _glow_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.26)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	return mat


static func _dark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.09, 0.11, 1.0)
	mat.metallic = 0.55
	mat.roughness = 0.45
	return mat


static func get_horizon_gate_texture() -> Texture2D:
	if _cached_gate_tex != null:
		return _cached_gate_tex
	if ResourceLoader.exists(GATE_TEX_PATH):
		var res := load(GATE_TEX_PATH)
		if res is Texture2D:
			_cached_gate_tex = res as Texture2D
			return _cached_gate_tex
	var abs_p := ProjectSettings.globalize_path(GATE_TEX_PATH)
	if FileAccess.file_exists(abs_p):
		var img := Image.load_from_file(abs_p)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			_cached_gate_tex = ImageTexture.create_from_image(img)
	return _cached_gate_tex


static func create_horizon_bezel_material() -> StandardMaterial3D:
	if _cached_bezel_mat != null:
		return _cached_bezel_mat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.058, 0.068, 1.0)
	mat.metallic = 0.22
	mat.roughness = 0.46
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cached_bezel_mat = mat
	return mat


static func create_horizon_face_material(base_col: Color = GATE_PINK) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := get_horizon_gate_texture()
	mat.albedo_color = base_col
	if tex != null:
		mat.albedo_texture = tex
	mat.emission_enabled = true
	mat.emission = base_col
	if tex != null:
		mat.emission_texture = tex
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_energy_multiplier = 0.95
	mat.metallic = 0.0
	mat.roughness = 0.82
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func apply_gate_blink(frame_mat: StandardMaterial3D, glow_mat: StandardMaterial3D,
		pulse_time: float, state: int, phase_idx: int = 0) -> void:
	if frame_mat == null:
		return
	match state:
		0:  # Active target gate: rapid high-contrast LED strobe (saturated hot-pink, dark letters)
			var s := 0.5 + 0.5 * sin(pulse_time * 2.2)
			var k := smoothstep(0.16, 0.84, s)
			frame_mat.albedo_color = GATE_PINK_DIM.lerp(GATE_PINK_HOT, k)
			frame_mat.emission = GATE_PINK.lerp(GATE_PINK_HOT, k)
			frame_mat.emission_energy_multiplier = lerpf(0.05, 1.35, k)
			if glow_mat != null:
				glow_mat.albedo_color = Color(1.0, 0.14, 0.56, lerpf(0.04, 0.35, k))
				glow_mat.emission = GATE_PINK_HOT
				glow_mat.emission_energy_multiplier = lerpf(0.10, 1.2, k)
		1:  # On-deck gate: brisk rhythmic pink blink
			var s := 0.5 + 0.5 * sin(pulse_time * 1.25 - 0.5)
			var k := smoothstep(0.15, 0.85, s)
			frame_mat.albedo_color = GATE_PINK_DIM.lerp(GATE_PINK, k)
			frame_mat.emission = GATE_PINK
			frame_mat.emission_energy_multiplier = lerpf(0.05, 0.95, k)
			if glow_mat != null:
				glow_mat.albedo_color = Color(1.0, 0.12, 0.54, lerpf(0.03, 0.22, k))
				glow_mat.emission = GATE_PINK
				glow_mat.emission_energy_multiplier = lerpf(0.10, 0.85, k)
		3:  # Already passed gate: calm dim magenta
			var passed_col := Color(0.26, 0.04, 0.14)
			frame_mat.albedo_color = passed_col
			frame_mat.emission = passed_col
			frame_mat.emission_energy_multiplier = 0.08
			if glow_mat != null:
				glow_mat.albedo_color = Color(passed_col.r, passed_col.g, passed_col.b, 0.03)
				glow_mat.emission_energy_multiplier = 0.06
		_:  # Upcoming course gates: cascading wave blink
			var s := 0.5 + 0.5 * sin(pulse_time * 1.05 - float(phase_idx) * 0.48)
			var k := smoothstep(0.18, 0.82, s)
			frame_mat.albedo_color = GATE_PINK_DIM.lerp(GATE_PINK, k)
			frame_mat.emission = GATE_PINK
			frame_mat.emission_energy_multiplier = lerpf(0.04, 0.78, k)
			if glow_mat != null:
				glow_mat.albedo_color = Color(1.0, 0.12, 0.54, lerpf(0.02, 0.16, k))
				glow_mat.emission = GATE_PINK
				glow_mat.emission_energy_multiplier = lerpf(0.08, 0.65, k)


static func _rounded_trapezoid_ring(w_bot: float, w_top: float, y_bot: float, y_top: float,
		fillet: float, segs_per_corner: int = 4) -> PackedVector2Array:
	var corners := [
		Vector2(-w_bot, y_bot),
		Vector2(w_bot, y_bot),
		Vector2(w_top, y_top),
		Vector2(-w_top, y_top),
	]
	var ring := PackedVector2Array()
	for i in range(4):
		var p_prev: Vector2 = corners[(i + 3) % 4]
		var p_cur: Vector2 = corners[i]
		var p_next: Vector2 = corners[(i + 1) % 4]
		var len_in := p_cur.distance_to(p_prev)
		var len_out := p_next.distance_to(p_cur)
		var d_in := (p_cur - p_prev) / maxf(len_in, 1e-5)
		var d_out := (p_next - p_cur) / maxf(len_out, 1e-5)
		var trim := minf(fillet, minf(len_in, len_out) * 0.42)
		var t1 := p_cur - d_in * trim
		var t2 := p_cur + d_out * trim
		for s in range(segs_per_corner + 1):
			var t := float(s) / float(segs_per_corner)
			ring.append(t1.lerp(p_cur, t).lerp(p_cur.lerp(t2, t), t))
	return ring


static func _orient_gate_pt(p: Vector3, normal_up_y: bool) -> Vector3:
	if normal_up_y:
		return Vector3(p.x, p.z, -p.y)
	return p


static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2 = Vector2.ZERO, ub: Vector2 = Vector2.ZERO,
		uc: Vector2 = Vector2.ZERO, ud: Vector2 = Vector2.ZERO,
		normal_up_y: bool = false) -> void:
	var va := _orient_gate_pt(a, normal_up_y)
	var vb := _orient_gate_pt(b, normal_up_y)
	var vc := _orient_gate_pt(c, normal_up_y)
	var vd := _orient_gate_pt(d, normal_up_y)
	st.set_uv(ua)
	st.add_vertex(va)
	st.set_uv(ub)
	st.add_vertex(vb)
	st.set_uv(uc)
	st.add_vertex(vc)
	st.set_uv(ua)
	st.add_vertex(va)
	st.set_uv(uc)
	st.add_vertex(vc)
	st.set_uv(ud)
	st.add_vertex(vd)


static func build_horizon_gate_mesh(scale_r: float = 1.0, normal_up_y: bool = false) -> ArrayMesh:
	if absf(scale_r - 1.0) < 1e-4:
		if not normal_up_y and _cached_gate_mesh_z != null:
			return _cached_gate_mesh_z
		if normal_up_y and _cached_gate_mesh_y != null:
			return _cached_gate_mesh_y

	var s := scale_r
	var inner := _rounded_trapezoid_ring(0.88 * s, 1.06 * s, -0.84 * s, 0.84 * s, 0.16 * s, 4)
	var pink := _rounded_trapezoid_ring(1.11 * s, 1.29 * s, -1.07 * s, 1.28 * s, 0.18 * s, 4)
	var outer := _rounded_trapezoid_ring(1.19 * s, 1.37 * s, -1.15 * s, 1.36 * s, 0.20 * s, 4)
	var z_box := 0.095 * s
	var z_face := 0.099 * s
	var n := inner.size()

	var out := ArrayMesh.new()
	out.resource_name = "SkyHorizonGateMesh"

	# Surface 0: Dark matte anodized outer bezel + extrusion thickness
	var st_bezel := SurfaceTool.new()
	st_bezel.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var j := (i + 1) % n
		var p0 := pink[i]
		var p1 := pink[j]
		var o0 := outer[i]
		var o1 := outer[j]
		var q0 := inner[i]
		var q1 := inner[j]
		# Front and back black bezel border strip (pink -> outer)
		_add_quad(st_bezel, Vector3(p0.x, p0.y, z_box), Vector3(o0.x, o0.y, z_box),
				Vector3(o1.x, o1.y, z_box), Vector3(p1.x, p1.y, z_box),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
		_add_quad(st_bezel, Vector3(p1.x, p1.y, -z_box), Vector3(o1.x, o1.y, -z_box),
				Vector3(o0.x, o0.y, -z_box), Vector3(p0.x, p0.y, -z_box),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
		# Outer rim depth wall
		_add_quad(st_bezel, Vector3(o0.x, o0.y, -z_box), Vector3(o1.x, o1.y, -z_box),
				Vector3(o1.x, o1.y, z_box), Vector3(o0.x, o0.y, z_box),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
		# Inner opening depth wall
		_add_quad(st_bezel, Vector3(q0.x, q0.y, z_box), Vector3(q1.x, q1.y, z_box),
				Vector3(q1.x, q1.y, -z_box), Vector3(q0.x, q0.y, -z_box),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
	st_bezel.generate_normals()
	st_bezel.commit(out)

	# Surface 1: Hot-pink panel face with crisp "НЕБЕСНИЙ ГОРИЗОНТ" header UV on BOTH sides
	var st_face := SurfaceTool.new()
	st_face.begin(Mesh.PRIMITIVE_TRIANGLES)
	var u_span := 2.0 * (1.29 * s)
	var u_min := -1.29 * s
	var y_top_f := 1.28 * s
	var v_span := (1.28 - (-1.07)) * s
	for i in range(n):
		var j := (i + 1) % n
		var q0 := inner[i]
		var q1 := inner[j]
		var p0 := pink[i]
		var p1 := pink[j]
		# Front (+Z): left-to-right when viewed from +Z toward -Z
		var uq0 := Vector2((q0.x - u_min) / u_span, (y_top_f - q0.y) / v_span)
		var uq1 := Vector2((q1.x - u_min) / u_span, (y_top_f - q1.y) / v_span)
		var up0 := Vector2((p0.x - u_min) / u_span, (y_top_f - p0.y) / v_span)
		var up1 := Vector2((p1.x - u_min) / u_span, (y_top_f - p1.y) / v_span)
		_add_quad(st_face, Vector3(q0.x, q0.y, z_face), Vector3(p0.x, p0.y, z_face),
				Vector3(p1.x, p1.y, z_face), Vector3(q1.x, q1.y, z_face),
				uq0, up0, up1, uq1, normal_up_y)
		# Back (-Z): mirrored X in UV so text reads un-mirrored from the opposite side
		var bq0 := Vector2(1.0 - uq0.x, uq0.y)
		var bq1 := Vector2(1.0 - uq1.x, uq1.y)
		var bp0 := Vector2(1.0 - up0.x, up0.y)
		var bp1 := Vector2(1.0 - up1.x, up1.y)
		_add_quad(st_face, Vector3(q1.x, q1.y, -z_face), Vector3(p1.x, p1.y, -z_face),
				Vector3(p0.x, p0.y, -z_face), Vector3(q0.x, q0.y, -z_face),
				bq1, bp1, bp0, bq0, normal_up_y)
	st_face.generate_normals()
	st_face.commit(out)

	if absf(scale_r - 1.0) < 1e-4:
		if normal_up_y:
			_cached_gate_mesh_y = out
		else:
			_cached_gate_mesh_z = out
	return out


static func build_horizon_halo_mesh(scale_r: float = 1.0, normal_up_y: bool = false) -> ArrayMesh:
	if absf(scale_r - 1.0) < 1e-4:
		if not normal_up_y and _cached_halo_mesh_z != null:
			return _cached_halo_mesh_z
		if normal_up_y and _cached_halo_mesh_y != null:
			return _cached_halo_mesh_y
	var s := scale_r
	var r_in := _rounded_trapezoid_ring(1.22 * s, 1.40 * s, -1.18 * s, 1.39 * s, 0.20 * s, 4)
	var r_out := _rounded_trapezoid_ring(1.30 * s, 1.48 * s, -1.26 * s, 1.47 * s, 0.22 * s, 4)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := r_in.size()
	var z_off := 0.04 * s
	for i in range(n):
		var j := (i + 1) % n
		var i0 := r_in[i]
		var i1 := r_in[j]
		var o0 := r_out[i]
		var o1 := r_out[j]
		_add_quad(st, Vector3(i0.x, i0.y, z_off), Vector3(o0.x, o0.y, z_off),
				Vector3(o1.x, o1.y, z_off), Vector3(i1.x, i1.y, z_off),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
		_add_quad(st, Vector3(i1.x, i1.y, -z_off), Vector3(o1.x, o1.y, -z_off),
				Vector3(o0.x, o0.y, -z_off), Vector3(i0.x, i0.y, -z_off),
				Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, normal_up_y)
	st.generate_normals()
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	if absf(scale_r - 1.0) < 1e-4:
		if normal_up_y:
			_cached_halo_mesh_y = mesh
		else:
			_cached_halo_mesh_z = mesh
	return mesh


static func _beam(a: Vector3, b: Vector3, thickness: float, mat: Material) -> MeshInstance3D:
	var diff := b - a
	var length := diff.length()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, maxf(length + thickness * 0.35, 0.05))
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	var dir := diff.normalized() if length > 0.0001 else Vector3.RIGHT
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	mi.transform = Transform3D(basis, mid)
	return mi


static func _shape_points(shape: int, size: float,
		left_foot_y: float = NAN, right_foot_y: float = NAN) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	match shape:
		SHAPE_SQUARE:  # square
			pts = [
				Vector3(-size, -size, 0.0),
				Vector3(size, -size, 0.0),
				Vector3(size, size, 0.0),
				Vector3(-size, size, 0.0),
			]
		SHAPE_ARCH:  # arch centered on (0,0,0), open along bottom between feet
			var r := size * 0.92
			var crown_y := -size * 0.05
			var lf := (-size * 0.72 if is_nan(left_foot_y) else left_foot_y)
			var rf := (-size * 0.72 if is_nan(right_foot_y) else right_foot_y)
			lf = minf(lf, crown_y - 0.25)
			rf = minf(rf, crown_y - 0.25)
			pts.append(Vector3(-r, lf, 0.0))
			var n := 9 if is_mobile() else 13
			for i in range(n):
				var a := PI * float(i) / float(n - 1)
				pts.append(Vector3(-cos(a) * r, crown_y + sin(a) * r, 0.0))
			pts.append(Vector3(r, rf, 0.0))
		SHAPE_DIAMOND:  # diamond
			pts = [
				Vector3(0.0, size, 0.0),
				Vector3(size, 0.0, 0.0),
				Vector3(0.0, -size, 0.0),
				Vector3(-size, 0.0, 0.0),
			]
		SHAPE_HEXAGON:  # hexagon
			for i in range(6):
				var a := TAU * float(i) / 6.0 + PI / 6.0
				pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
		_:  # u_gate (open at top)
			pts = [
				Vector3(-size, size * 0.88, 0.0),
				Vector3(-size, -size * 0.78, 0.0),
				Vector3(size, -size * 0.78, 0.0),
				Vector3(size, size * 0.88, 0.0),
			]
	return pts


static func _add_gate_visual(root: Node3D, shape: int, size: float,
		frame_mat: StandardMaterial3D, glow_mat: StandardMaterial3D,
		left_ground_off: float = NAN, right_ground_off: float = NAN) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "GatePanel"
	panel.mesh = build_horizon_gate_mesh(1.0, false)
	panel.scale = Vector3.ONE * size
	panel.set_surface_override_material(0, create_horizon_bezel_material())
	panel.set_surface_override_material(1, frame_mat)
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(panel)

	var glow := MeshInstance3D.new()
	glow.name = "InnerGlow"
	glow.mesh = build_horizon_halo_mesh(1.0, false)
	glow.scale = Vector3.ONE * size
	glow.material_override = glow_mat
	glow.visible = false
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow)

	if shape == SHAPE_ARCH:
		var is_grounded := (not is_nan(left_ground_off)) and (not is_nan(right_ground_off))
		if is_grounded:
			var dark_mat := _dark_material()
			var foot_x := size * 0.92
			var bot_y := -size * 1.12
			var tube := clampf(size * 0.068, 0.16, 0.32)
			var feet := [
				["FootLeft", -foot_x, left_ground_off],
				["FootRight", foot_x, right_ground_off],
			]
			for f in feet:
				var fx := float(f[1])
				var gy_off := float(f[2])
				if gy_off < bot_y - 0.05:
					var leg := _beam(Vector3(fx, bot_y, 0.0), Vector3(fx, gy_off + 0.12, 0.0), tube * 0.85, dark_mat)
					root.add_child(leg)
				var foot := MeshInstance3D.new()
				foot.name = str(f[0])
				var cyl := CylinderMesh.new()
				cyl.top_radius = tube * 1.05
				cyl.bottom_radius = tube * 1.75
				cyl.height = 0.70
				cyl.radial_segments = 10
				foot.mesh = cyl
				foot.material_override = dark_mat
				foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				foot.position = Vector3(fx, gy_off + 0.12, 0.0)
				root.add_child(foot)


static func make_checkpoint(parent: Node3D, spec: Dictionary, idx: int,
		total: int = RING_COUNT) -> Area3D:
	var gate := Area3D.new()
	gate.name = "NeonGate%02d" % (idx + 1)
	if parent != null:
		parent.add_child(gate)
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	var dir: Vector3 = spec.get("dir", Vector3.FORWARD)
	var size: float = float(spec.get("size", 4.5))
	var shape: int = int(spec.get("shape", SHAPE_ARCH))
	var roll: float = float(spec.get("roll", 0.0))
	var col: Color = spec.get("color", Color(0.08, 0.92, 0.88))
	var gy: float = float(spec.get("ground_y", pos.y - size * 0.78))
	var lgy: float = float(spec.get("left_ground_y", gy))
	var rgy: float = float(spec.get("right_ground_y", gy))
	var over_water: bool = bool(spec.get("over_water", false))

	if shape == SHAPE_ARCH:
		var lowest_gy := minf(gy, minf(lgy, rgy))
		var agl := pos.y - lowest_gy
		var slope_diff := absf(lgy - rgy)
		if over_water or agl < 1.2 or agl > size * ARCH_MAX_AGL_MULT + 0.8 \
				or slope_diff > ARCH_MAX_SLOPE_DIFF + 0.4:
			shape = [SHAPE_SQUARE, SHAPE_DIAMOND, SHAPE_HEXAGON][idx % 3]
			spec["shape"] = shape

	gate.position = pos
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	if flat_dir.length_squared() < 0.0001:
		flat_dir = Vector3.FORWARD
	var look_dir := dir.normalized() if shape != SHAPE_ARCH else flat_dir.normalized()
	if absf(look_dir.dot(Vector3.UP)) > 0.97:
		look_dir = Vector3.FORWARD
	var basis := Basis.looking_at(look_dir, Vector3.UP)
	if absf(roll) > 0.001 and shape != SHAPE_ARCH:
		basis = basis.rotated(look_dir, roll)
	gate.transform.basis = basis

	var col_shape := CollisionShape3D.new()
	col_shape.name = "CoreTrigger"
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(1.85, size * 0.90 + 0.45)
	col_shape.shape = sphere
	gate.add_child(col_shape)

	col = GATE_PINK
	var frame_mat := create_horizon_face_material(col)
	var glow_mat := _glow_material(GATE_PINK_HOT)
	if shape == SHAPE_ARCH:
		_add_gate_visual(gate, shape, size, frame_mat, glow_mat,
				lgy - pos.y, rgy - pos.y)
	else:
		_add_gate_visual(gate, shape, size, frame_mat, glow_mat)

	var lbl := Label3D.new()
	lbl.name = "GateNumber"
	if idx == 0:
		lbl.text = "START 1/%d" % total
	elif idx == total - 1:
		lbl.text = "FINISH %d/%d" % [total, total]
	else:
		lbl.text = "%d/%d" % [idx + 1, total]
	lbl.font_size = 64
	lbl.pixel_size = 0.022
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = false
	lbl.modulate = Color(1.0, 0.97, 0.82, 0.96)
	lbl.outline_modulate = Color(0.02, 0.04, 0.06, 0.92)
	lbl.outline_size = 10
	lbl.position = Vector3(0.0, size * 1.48 + 0.85, 0.0)
	gate.add_child(lbl)

	if (idx == 0 or idx == total - 1) and not over_water and (pos.y - gy) <= size * 1.65:
		var pad := MeshInstance3D.new()
		pad.name = "StartFinishPad"
		var box := BoxMesh.new()
		box.size = Vector3(size * 1.15, 0.03, 2.0)
		pad.mesh = box
		var pmat := _glow_material(Color(0.25, 1.0, 0.62) if idx == 0 else Color(1.0, 0.72, 0.18))
		pmat.albedo_color.a = 0.75
		pad.material_override = pmat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pad.position = Vector3(0.0, gy - pos.y + 0.065, 0.0)
		gate.add_child(pad)

	gate.set_meta("ring_index", idx)
	gate.set_meta("ring_total", total)
	gate.set_meta("ring_radius", size)
	gate.set_meta("ring_shape", shape)
	gate.set_meta("arch_grounded", shape == SHAPE_ARCH)
	gate.set_meta("ground_y", gy)
	gate.set_meta("left_ground_y", lgy)
	gate.set_meta("right_ground_y", rgy)
	gate.set_meta("ring_material", frame_mat)
	gate.set_meta("ring_frame_mat", frame_mat)
	gate.set_meta("ring_glow_mat", glow_mat)
	gate.set_meta("ring_base_color", col)
	return gate


static func _ground_y_at(ground_fn: Callable, x: float, z: float, fallback: float = 0.0) -> float:
	if ground_fn.is_valid():
		return float(ground_fn.call(x, z))
	return fallback


static func _build_specs_from_raw(raw_pts: Array, sizes: Array, shapes: Array,
		ground_ys: Array, col_primary: Color, col_accent: Color) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var total := raw_pts.size()
	for i in range(total):
		var cur: Vector3 = raw_pts[i]
		var prev: Vector3 = raw_pts[(i - 1 + total) % total]
		var nxt: Vector3 = raw_pts[(i + 1) % total]
		var dir: Vector3
		if i == 0:
			dir = nxt - cur
		elif i == total - 1:
			dir = cur - prev
		else:
			dir = (nxt - cur).normalized() + (cur - prev).normalized()
		if dir.length_squared() < 0.0001:
			dir = Vector3.FORWARD
		dir = dir.normalized()
		var sz := float(sizes[i]) if i < sizes.size() else 4.6
		var shp := int(shapes[i]) if i < shapes.size() else 1
		var gy := float(ground_ys[i]) if i < ground_ys.size() else (cur.y - sz * 0.78)
		var c := col_primary.lerp(col_accent, float(i % 4) / 3.0)
		if i == 0:
			c = Color(0.18, 0.98, 0.62)
		elif i == total - 1:
			c = Color(1.0, 0.76, 0.22)
		specs.append({
			"pos": cur,
			"dir": dir,
			"size": sz,
			"shape": shp,
			"roll": 0.0,
			"ground_y": gy,
			"color": c,
		})
	return specs


static func hall_waypoints(map_id: String, ground_fn: Callable) -> Array[Dictionary]:
	var raw_coords: Array = []
	var primary := Color(0.08, 0.88, 0.95)
	var accent := Color(0.24, 0.98, 0.64)
	var water_floor := -999.0

	if map_id == "industrial":
		# Starts straight ahead (+Z) of industrial spawn (46, 130, yaw PI) and loops all industrial landmarks cleanly.
		primary = Color(0.10, 0.90, 0.98)
		accent = Color(1.0, 0.62, 0.16)
		raw_coords = [
			[46.0, 150.0, 6.2, 1, 5.6],
			[66.0, 160.0, 7.6, 2, 5.4],
			[100.0, 158.0, 9.5, 0, 5.2],
			[122.0, 136.0, 15.0, 2, 5.2],
			[126.0, 102.0, 22.0, 3, 5.2],
			[128.0, 62.0, 25.0, 0, 5.4],
			[128.0, 20.0, 26.0, 3, 5.4],
			[126.0, -24.0, 22.0, 2, 5.4],
			[130.0, -78.0, 22.0, 0, 5.4],
			[112.0, -134.0, 19.0, 2, 5.2],
			[58.0, -148.0, 17.5, 3, 5.2],
			[0.0, -150.0, 18.0, 0, 5.0],
			[-62.0, -152.0, 17.5, 3, 5.0],
			[-114.0, -152.0, 18.0, 2, 5.2],
			[-154.0, -104.0, 19.0, 0, 5.2],
			[-156.0, -34.0, 18.0, 4, 5.4],
			[-148.0, 34.0, 13.0, 3, 5.2],
			[-104.0, 78.0, 12.0, 0, 5.0],
			[-62.0, 114.0, 13.0, 2, 5.2],
			[-32.0, 126.0, 14.0, 3, 5.2],
			[-6.0, 134.0, 11.0, 0, 5.0],
			[14.0, 134.0, 9.0, 2, 5.2],
			[32.0, 128.0, 7.6, 4, 5.2],
			[46.0, 118.0, 6.4, 1, 5.4],
		]
	elif map_id == "promzona_plavni":
		# 28-gate Promzona/Plavni loop: marsh launch -> West Concrete Bridge ->
		# cranes/chimney/silos -> Hero Hall flyover -> East Timber Bridge ->
		# marsh slalom -> Pump Hall -> finish on the western dike.
		primary = Color(0.12, 0.94, 0.88)
		accent = Color(1.0, 0.72, 0.12)
		water_floor = -1.2
		raw_coords = [
			[-110.0, 205.0, 4.4, 1, 4.6],
			[-112.0, 170.0, 3.8, 2, 4.2],
			[-110.0, 135.0, 4.2, 0, 4.0],
			[-110.0, 100.0, 3.6, 3, 4.2],
			[-112.0, 65.0, 3.4, 4, 4.4],
			[-110.0, 35.0, 3.2, 2, 3.8],
			[-110.0, 15.0, 3.2, 3, 4.0],
			[-110.0, -10.0, 3.4, 3, 3.6],
			[-118.0, -45.0, 4.8, 0, 4.2],
			[-145.0, -85.0, 20.0, 4, 3.8],
			[-175.0, -130.0, 26.0, 2, 4.0],
			[-150.0, -175.0, 24.0, 0, 3.6],
			[-125.0, -205.0, 18.0, 3, 4.0],
			[-40.0, -285.0, 13.0, 4, 4.2],
			[-5.0, -235.0, 12.0, 0, 4.0],
			[52.0, -240.0, 9.0, 1, 4.2],
			[52.0, -180.0, 28.0, 2, 3.8],
			[52.0, -125.0, 9.0, 0, 4.2],
			[130.0, -160.0, 12.0, 3, 4.0],
			[160.0, -120.0, 15.0, 4, 4.4],
			[150.0, -70.0, 9.0, 0, 4.0],
			[125.0, -25.0, 5.0, 2, 3.9],
			[110.0, 18.0, 3.4, 3, 3.8],
			[110.0, 50.0, 3.8, 1, 4.0],
			[125.0, 85.0, 5.0, 0, 4.0],
			[75.0, 125.0, 4.6, 3, 3.8],
			[-35.0, 175.0, 4.2, 4, 4.0],
			[-110.0, 220.0, 4.6, 1, 4.6],
		]
	elif map_id == "wetlands":
		# Starts straight ahead (+Z) of wetlands spawn (72, 110, yaw PI) above dry south ridge and marsh loop.
		primary = Color(0.10, 0.94, 0.80)
		accent = Color(0.32, 0.98, 0.44)
		water_floor = -1.2
		raw_coords = [
			[72.0, 134.0, 5.4, 1, 5.4],
			[56.0, 152.0, 6.4, 1, 5.2],
			[22.0, 156.0, 7.5, 0, 5.0],
			[-16.0, 150.0, 8.0, 2, 5.0],
			[-54.0, 136.0, 8.5, 3, 5.2],
			[-88.0, 110.0, 9.0, 3, 5.2],
			[-114.0, 74.0, 9.5, 2, 5.2],
			[-128.0, 32.0, 9.5, 0, 5.0],
			[-128.0, -14.0, 10.0, 3, 5.2],
			[-112.0, -58.0, 10.0, 2, 5.2],
			[-80.0, -96.0, 10.5, 0, 5.4],
			[-38.0, -118.0, 10.5, 0, 5.2],
			[10.0, -122.0, 10.5, 3, 5.2],
			[58.0, -112.0, 10.0, 2, 5.2],
			[98.0, -88.0, 10.0, 0, 5.0],
			[128.0, -50.0, 9.5, 4, 5.2],
			[142.0, -8.0, 9.5, 3, 5.2],
			[146.0, 34.0, 10.0, 0, 5.2],
			[144.0, 72.0, 10.0, 2, 5.2],
			[136.0, 102.0, 11.0, 2, 5.2],
			[122.0, 122.0, 11.5, 0, 5.0],
			[104.0, 128.0, 11.0, 3, 5.0],
			[88.0, 124.0, 9.5, 4, 5.2],
			[88.0, 96.0, 5.8, 1, 5.4],
		]
	else:
		# Fallback / legacy village loop
		water_floor = -1.8
		raw_coords = [
			[88.0, 130.0, 5.5, 1, 5.2],
			[62.0, 146.0, 7.0, 1, 5.0],
			[22.0, 144.0, 8.0, 0, 5.0],
			[-20.0, 128.0, 9.0, 2, 5.0],
			[-58.0, 102.0, 9.5, 1, 5.0],
			[-92.0, 66.0, 10.0, 3, 5.0],
			[-114.0, 20.0, 10.5, 1, 5.0],
			[-116.0, -28.0, 10.5, 0, 5.0],
			[-98.0, -76.0, 10.0, 1, 5.0],
			[-62.0, -110.0, 10.0, 2, 5.0],
			[-16.0, -122.0, 10.0, 1, 5.0],
			[34.0, -118.0, 10.0, 0, 5.0],
			[80.0, -96.0, 9.5, 3, 5.0],
			[116.0, -58.0, 9.5, 1, 5.0],
			[132.0, -12.0, 9.0, 0, 5.0],
			[130.0, 36.0, 9.0, 4, 5.0],
			[122.0, 78.0, 8.5, 1, 5.0],
			[108.0, 106.0, 7.8, 0, 5.0],
			[92.0, 122.0, 7.0, 2, 5.0],
			[74.0, 128.0, 6.5, 1, 5.0],
			[56.0, 124.0, 6.0, 0, 5.0],
			[44.0, 114.0, 5.8, 3, 5.0],
			[58.0, 106.0, 5.6, 4, 5.0],
			[76.0, 110.0, 5.5, 1, 5.2],
		]

	var pts: Array[Vector3] = []
	var sizes: Array = []
	var shapes: Array = []
	var ground_ys: Array = []
	for item in raw_coords:
		var x := float(item[0])
		var z := float(item[1])
		var agl := float(item[2])
		var shp := int(item[3])
		var sz := float(item[4])
		var gy := maxf(_ground_y_at(ground_fn, x, z, 0.0), water_floor)
		pts.append(Vector3(x, gy + agl, z))
		sizes.append(sz)
		shapes.append(shp)
		ground_ys.append(gy)
	return _build_specs_from_raw(pts, sizes, shapes, ground_ys, primary, accent)


static func airport_waypoints(_landmarks: Array, ground_fn: Callable) -> Array[Dictionary]:
	# Starts ahead of AirportLevel spawn (0, 62, 255 facing -Z) -> south apron dive -> Fuel Depot ->
	# Hangar apron -> Runway 09/27 fast low pass -> Cargo Container Yard -> Control Tower Ruins -> FINISH.
	var raw_coords := [
		[0.0, 200.0, 52.0, 0, 7.0],
		[38.0, 154.0, 36.0, 3, 6.8],
		[98.0, 132.0, 24.0, 0, 6.4],
		[168.0, 122.0, 18.0, 3, 6.2],
		[242.0, 114.0, 21.0, 2, 6.5],
		[312.0, 74.0, 22.0, 0, 6.5],
		[338.0, 10.0, 20.0, 3, 6.4],
		[334.0, -64.0, 20.0, 2, 6.4],
		[310.0, -138.0, 24.0, 4, 6.8],
		[272.0, -210.0, 23.0, 2, 6.8],
		[192.0, -264.0, 18.0, 0, 6.6],
		[96.0, -290.0, 17.0, 0, 6.4],
		[0.0, -270.0, 21.0, 3, 6.2],
		[0.0, -185.0, 23.0, 0, 6.0],
		[0.0, -95.0, 17.0, 2, 6.0],
		[-42.0, -20.0, 17.0, 3, 6.2],
		[-126.0, -64.0, 18.0, 0, 6.4],
		[-218.0, -104.0, 20.0, 3, 6.5],
		[-296.0, -138.0, 24.0, 4, 6.8],
		[-332.0, -56.0, 20.0, 2, 6.5],
		[-324.0, 38.0, 20.0, 0, 6.4],
		[-284.0, 128.0, 39.0, 2, 6.8],
		[-178.0, 198.0, 37.0, 3, 6.6],
		[-68.0, 224.0, 26.0, 0, 7.0],
	]
	var pts: Array[Vector3] = []
	var sizes: Array = []
	var shapes: Array = []
	var ground_ys: Array = []
	for item in raw_coords:
		var x := float(item[0])
		var z := float(item[1])
		var alt := float(item[2])
		var shp := int(item[3])
		var sz := float(item[4])
		var gy := _ground_y_at(ground_fn, x, z, 0.12)
		pts.append(Vector3(x, gy + alt, z))
		sizes.append(sz)
		shapes.append(shp)
		ground_ys.append(gy)
	return _build_specs_from_raw(pts, sizes, shapes, ground_ys,
			Color(0.12, 0.88, 1.0), Color(1.0, 0.54, 0.16))


static func loop_waypoints(positions: Array, ground_fn: Callable) -> Array[Dictionary]:
	if positions.is_empty():
		return []
	var is_uman_loop := (positions.size() == UMAN_WAYPOINTS.size()
			and positions[0] is Vector3
			and (positions[0] as Vector3).distance_squared_to(UMAN_WAYPOINTS[0]) < 0.05)
	var pts: Array[Vector3] = []
	var sizes: Array = []
	var shapes: Array = []
	var ground_ys: Array = []
	var shape_cycle := [1, 0, 2, 1, 3, 4]
	var aerial_cycle := [SHAPE_SQUARE, SHAPE_DIAMOND, SHAPE_HEXAGON]
	for i in range(positions.size()):
		var p: Vector3 = positions[i]
		var gy := _ground_y_at(ground_fn, p.x, p.z, 0.12 if is_uman_loop else 0.0)
		var min_y := maxf(gy + 3.8, 3.6 if is_uman_loop else gy + 4.2)
		var final_y := maxf(p.y, min_y)
		pts.append(Vector3(p.x, final_y, p.z))
		var sz := clampf(4.6 if is_uman_loop else 5.0, 3.8, 5.4)
		if i == 0 or i == positions.size() - 1:
			sz += 0.3
		sizes.append(sz)
		if is_uman_loop:
			shapes.append(SHAPE_ARCH if (final_y - gy) <= sz * ARCH_MAX_AGL_MULT else aerial_cycle[i % aerial_cycle.size()])
		else:
			shapes.append(shape_cycle[i % shape_cycle.size()])
		ground_ys.append(gy)
	var primary := Color(0.08, 0.92, 0.86) if is_uman_loop else Color(0.10, 0.90, 0.96)
	var accent := Color(0.24, 0.98, 0.56) if is_uman_loop else Color(1.0, 0.62, 0.22)
	return _build_specs_from_raw(pts, sizes, shapes, ground_ys, primary, accent)
