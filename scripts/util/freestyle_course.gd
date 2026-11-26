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
	var frame := Node3D.new()
	frame.name = "FrameVisual"
	root.add_child(frame)
	var glow := Node3D.new()
	glow.name = "InnerGlow"
	root.add_child(glow)
	var tube := clampf(size * 0.068, 0.16, 0.34)
	if shape == SHAPE_ARCH:
		var is_grounded := (not is_nan(left_ground_off)) and (not is_nan(right_ground_off))
		var lf := (-size * 0.72 if not is_grounded else (left_ground_off - 0.35))
		var rf := (-size * 0.72 if not is_grounded else (right_ground_off - 0.35))
		var pts := _shape_points(shape, size, lf, rf)
		var crown_y := -size * 0.05
		var inner_pts: Array[Vector3] = []
		for k in range(pts.size()):
			var p: Vector3 = pts[k]
			if is_grounded and (k == 0 or k == pts.size() - 1):
				var g_off := left_ground_off if k == 0 else right_ground_off
				inner_pts.append(Vector3(p.x * 0.91, g_off + 0.10, 0.0))
			elif not is_grounded:
				inner_pts.append(p * 0.90)
			else:
				inner_pts.append(Vector3(p.x * 0.91, crown_y + (p.y - crown_y) * 0.91, 0.0))
		var seg_count := pts.size() - 1
		for i in range(seg_count):
			frame.add_child(_beam(pts[i], pts[i + 1], tube, frame_mat))
			glow.add_child(_beam(inner_pts[i], inner_pts[i + 1], tube * 0.42, glow_mat))
		if is_grounded:
			var dark_mat := _dark_material()
			var foot_x := size * 0.92
			var feet := [
				["FootLeft", -foot_x, left_ground_off],
				["FootRight", foot_x, right_ground_off],
			]
			for f in feet:
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
				foot.position = Vector3(float(f[1]), float(f[2]) + 0.12, 0.0)
				root.add_child(foot)
		return
	var pts := _shape_points(shape, size)
	var open_chain := (shape == SHAPE_UGATE)
	var seg_count := (pts.size() - 1) if open_chain else pts.size()
	for i in range(seg_count):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		frame.add_child(_beam(a, b, tube, frame_mat))
		glow.add_child(_beam(a * 0.90, b * 0.90, tube * 0.42, glow_mat))


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

	var frame_mat := _neon_material(col)
	var glow_mat := _glow_material(col.lightened(0.18))
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
	lbl.position = Vector3(0.0, size * 0.96 + 0.95, 0.0)
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
