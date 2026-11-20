extends RefCounted
class_name FreestyleCourse

## Shared neon checkpoint course for every freestyle (TRAINING) map.
##
## The old freestyle gates were either the teal BigLevel torus rings, the GLB
## Gate_* decorations or Uman's purely decorative neon frames.  None of them
## were real checkpoints, so there was no timer, no gate count and no personal
## ghost.  This helper builds 24 *real* Area3D checkpoints with the Uman neon
## look and places them in the genuinely flyable openings of each map:
## hall windows / doors (industrial, village, steppe, wetlands), the ruined
## hangar arches and landmark facades (airport) and a tight weaving loop over
## the authored scenery (Uman / valley).

const RING_COUNT := 24

## Uman loop reused from UmanLevel.COURSE_WAYPOINTS, plus one extra bend.
const UMAN_WAYPOINTS := [
	Vector3(122, 5, 118), Vector3(96, 5, 84), Vector3(60, 6, 70),
	Vector3(20, 5, 52), Vector3(-24, 4, 34), Vector3(-62, 5, -18),
	Vector3(-108, 6, 32), Vector3(-128, 5, 76), Vector3(-80, 5, 104),
	Vector3(-20, 6, 112), Vector3(40, 5, 118), Vector3(96, 4, 96),
	Vector3(140, 5, 48), Vector3(120, 6, -8), Vector3(72, 5, -48),
	Vector3(16, 5, -70), Vector3(-52, 6, -56), Vector3(-118, 5, -28),
	Vector3(-142, 6, 18), Vector3(-96, 5, 60), Vector3(-30, 5, 88),
	Vector3(38, 6, 86), Vector3(108, 5, 108), Vector3(126, 5, 112),
]


static func is_mobile() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


# ---------------------------------------------------------------- materials --
static func _neon_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.06, 0.02, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.08, 0.02)
	mat.emission_energy = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _glow_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.03, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.10, 0.02)
	mat.emission_energy = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


static func _dark_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.035, 0.04, 1.0)
	mat.roughness = 0.85
	mat.metallic = 0.35
	return mat


static func _beam(parent: Node, a: Vector3, b: Vector3, radius: float,
		mat: Material) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = len
	cyl.radial_segments = 6 if is_mobile() else 10
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh)
	var mid: Vector3 = (a + b) * 0.5
	mesh.position = mid
	var up := Vector3.UP
	if d.normalized().abs().dot(up) > 0.95:
		up = Vector3.FORWARD
	if parent is Node3D:
		var parent3d := parent as Node3D
		mesh.look_at_from_position(parent3d.to_global(mid),
				parent3d.to_global(b), up)
	else:
		mesh.look_at_from_position(mid, b, up)
	mesh.rotate_object_local(Vector3.RIGHT, PI * 0.5)


static func _shape_points(shape: int, size: float) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	match shape:
		0:  # circle
			var n := 12 if is_mobile() else 18
			for i in range(n):
				var a := TAU * float(i) / float(n)
				pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
		1:  # arch
			var n := 9 if is_mobile() else 13
			for i in range(n):
				var a := PI * float(i) / float(n - 1)
				pts.append(Vector3(-cos(a) * size, sin(a) * size * 1.2, 0.0))
			pts.append(Vector3(size, 0.0, 0.0))
		2:  # hexagon
			for i in range(6):
				var a := TAU * float(i) / 6.0 + PI / 6.0
				pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
		3:  # triangle
			for i in range(3):
				var a := TAU * float(i) / 3.0 + PI * 0.5
				pts.append(Vector3(cos(a) * size, sin(a) * size, 0.0))
		_:  # wide rectangle - reads like a door / window frame
			var w := size * 1.18
			var h := size * 0.88
			pts.append(Vector3(-w, -h, 0.0))
			pts.append(Vector3(w, -h, 0.0))
			pts.append(Vector3(w, h, 0.0))
			pts.append(Vector3(-w, h, 0.0))
	return pts


static func _add_gate_visual(area: Area3D, shape: int, size: float) -> Dictionary:
	var mats := {
		"neon": _neon_material(),
		"glow": _glow_material(),
		"dark": _dark_material(),
	}
	var pts := _shape_points(shape, size)
	for i in range(pts.size()):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		if is_mobile():
			# No additive halo on the Mobile renderer: make the neon tube the
			# widest layer, otherwise the dark frame hides it at FPV distance.
			_beam(area, a, b, 0.16, mats["dark"])
			_beam(area, a, b, 0.30, mats["neon"])
		else:
			_beam(area, a, b, 0.30, mats["dark"])
			_beam(area, a, b, 0.22, mats["neon"])
			_beam(area, a, b, 0.42, mats["glow"])
	# Feet only on the frames that stand on the ground.
	if shape == 1 or shape == 4:
		for s in [-1.0, 1.0]:
			var foot := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.55, 0.30, 0.55)
			foot.mesh = box
			foot.material_override = mats["dark"]
			foot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			area.add_child(foot)
			foot.position = Vector3(s * size * 0.92, -size * 0.88, 0.0)
	return mats


static func make_checkpoint(parent: Node, spec: Dictionary, index: int) -> Area3D:
	var area := Area3D.new()
	area.name = "NeonGate%d" % index
	var pos: Vector3 = spec.get("pos", Vector3.ZERO)
	area.position = pos
	area.rotation.y = float(spec.get("yaw", 0.0))
	area.collision_layer = 0
	area.collision_mask = 1
	var size := float(spec.get("size", 3.0))
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	# Deliberately tight: a window gate must be flown through, not brushed.
	sphere.radius = maxf(1.35, size * 0.70 + 0.55)
	col.shape = sphere
	area.add_child(col)
	# Add to the tree before building the beams: _beam uses look_at(), which
	# needs a world transform and errors on nodes that are still orphaned.
	parent.add_child(area)
	var mats := _add_gate_visual(area, int(spec.get("shape", 0)), size)
	area.set_meta("ring_material", mats["neon"])
	area.set_meta("ring_radius", size)
	area.set_meta("ring_shape", int(spec.get("shape", 0)))
	# Readable START / number / FINISH marker - the old decorative course had
	# no indication where to begin, which way to fly or which gate was last.
	var label := Label3D.new()
	label.name = "GateNumber"
	label.text = "START 1/%d" % RING_COUNT if index == 0 else (
			"FINISH %d/%d" % [RING_COUNT, RING_COUNT]
			if index == RING_COUNT - 1 else "%d/%d" % [index + 1, RING_COUNT])
	label.font_size = 64
	label.billboard = 1  # BILLBOARD_ENABLED (Label3D has no enum constant here)
	label.position = Vector3(0.0, size * 1.35 + 0.3, 0.0)
	label.modulate = Color(1.0, 0.94, 0.62, 1.0)
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	area.add_child(label)
	# Ground pads make Start / Finish unmistakable even from FPV height.
	if index == 0 or index == RING_COUNT - 1:
		var pad := MeshInstance3D.new()
		pad.name = "StartFinishPad"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 3.2
		cyl.bottom_radius = 3.2
		cyl.height = 0.06
		cyl.radial_segments = 24
		pad.mesh = cyl
		var pad_mat := StandardMaterial3D.new()
		pad_mat.albedo_color = Color(0.06, 0.35, 0.10) if index == 0 \
				else Color(0.45, 0.30, 0.04)
		pad_mat.emission_enabled = true
		pad_mat.emission = Color(0.20, 1.0, 0.35) if index == 0 \
				else Color(1.0, 0.72, 0.15)
		pad_mat.emission_energy_multiplier = 1.2
		pad.material_override = pad_mat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		area.add_child(pad)
		pad.position = Vector3(0.0, 0.2 - pos.y, 0.0)
	return area


# -------------------------------------------------------------- waypoints --
static func hall_waypoints(map_id: String, ground_fn: Callable) -> Array[Dictionary]:
	var terrain_script = load("res://scripts/util/frontline_terrain.gd")
	var site: Dictionary = terrain_script.HALL_SITES.get(map_id, {})
	var specs: Array[Dictionary] = []
	if site.is_empty():
		return specs
	var c: Vector2 = site["center"]
	var half: Vector2 = site["half"]
	var h := float(site.get("roof_height", 18.0))
	var w := half.x * 2.0
	var d := half.y * 2.0
	var win_bottom := clampf(h * 0.34, 3.4, 5.0)
	var win_h := minf(clampf(h * 0.16, 2.0, 2.4),
			maxf(1.2, h - win_bottom - 0.6))
	var win_y := win_bottom + win_h * 0.5
	var door_y = minf(h * 0.30, 3.6) * 0.5
	# Long facades: 4 fly-through windows + 2 doors on each side.
	for side_v in [-1.0, 1.0]:
		var side: float = float(side_v)
		var z: float = c.y + side * (half.y + 0.7)
		var yaw: float = 0.0 if side > 0.0 else PI
		for k in range(4):
			specs.append({"pos": Vector3(c.x + (-0.42 + 0.28 * float(k)) * w, win_y, z),
					"yaw": yaw, "shape": 4, "size": 1.85})
		for sx_v in [-1.0, 1.0]:
			var sx: float = float(sx_v)
			specs.append({"pos": Vector3(c.x + sx * 0.27 * w, door_y, z),
					"yaw": yaw, "shape": 1, "size": 1.55})
	# Short facades: 2 windows + 1 door on each gable.
	for sx_v in [-1.0, 1.0]:
		var sx: float = float(sx_v)
		var x: float = c.x + sx * (half.x + 0.7)
		var yaw: float = PI * 0.5 if sx > 0.0 else -PI * 0.5
		for k in range(2):
			specs.append({"pos": Vector3(x, win_y, c.y + (-0.25 + 0.5 * float(k)) * d),
					"yaw": yaw, "shape": 4, "size": 1.85})
		specs.append({"pos": Vector3(x, door_y, c.y),
				"yaw": yaw, "shape": 1, "size": 1.55})
	# Exterior arches force a steep dive/climb between the hall openings.
	var outer := [Vector2(-42, 128), Vector2(26, -104), Vector2(-108, -30),
			Vector2(118, 64), Vector2(-126, -92), Vector2(52, 136)]
	for i in range(outer.size()):
		var p: Vector2 = outer[i]
		var nxt: Vector2 = outer[(i + 1) % outer.size()]
		var yaw := atan2(nxt.x - p.x, nxt.y - p.y)
		var gy: float = float(ground_fn.call(p.x, p.y)) if ground_fn.is_valid() else 0.0
		specs.append({"pos": Vector3(p.x, gy + 5.5 + float(i % 3) * 2.0, p.y),
				"yaw": yaw, "shape": 1, "size": 3.6 + float(i % 2) * 0.5})
	return specs


static func airport_waypoints(landmarks: Array, ground_fn: Callable) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var hangar: Vector3 = Vector3(285.0, 0.0, -145.0)
	for p in landmarks:
		if p is Vector3:
			var v: Vector3 = p
			if absf(v.x - 285.0) < 60.0 and absf(v.z + 145.0) < 60.0:
				hangar = v
	# Ruined hangar: four open arches, flown through along Z.
	for z_v in [-12.0, -4.0, 4.0, 12.0]:
		var z: float = float(z_v)
		specs.append({"pos": hangar + Vector3(0.0, 5.6, z),
				"yaw": 0.0, "shape": 4, "size": 4.4})
	# Tight facade gates on the other landmark structures.
	var facade_sources := landmarks.duplicate()
	for i in range(mini(8, facade_sources.size())):
		var p: Vector3 = facade_sources[i]
		if not (p is Vector3):
			continue
		var ang := TAU * float(i) / 8.0
		specs.append({"pos": p + Vector3(cos(ang) * 9.0, 3.4, sin(ang) * 9.0),
				"yaw": ang + PI * 0.5, "shape": 4 if i % 2 == 0 else 1,
				"size": 2.1 + float(i % 3) * 0.2})
	# Weaving outer loop keeps the last gates away from the landmarks.
	var count := RING_COUNT - specs.size()
	for i in range(count):
		var a := TAU * float(i) / float(count)
		var r := 186.0 + 26.0 * sin(a * 3.0)
		var x := cos(a) * r
		var z := sin(a) * r * 0.92
		var yaw := atan2(-sin(a), cos(a))
		var gy: float = float(ground_fn.call(x, z)) if ground_fn.is_valid() else 0.0
		specs.append({"pos": Vector3(x, gy + 8.0 + float(i % 4) * 2.6, z),
				"yaw": yaw, "shape": i % 5, "size": 2.5 + float(i % 3) * 0.35})
	return specs


static func loop_waypoints(positions: Array, ground_fn: Callable) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	if positions.is_empty():
		return specs
	for i in range(RING_COUNT):
		var wp: Vector3 = positions[i % positions.size()]
		var nxt: Vector3 = positions[(i + 1) % positions.size()]
		var dx := nxt.x - wp.x
		var dz := nxt.z - wp.z
		var yaw := atan2(dx, dz)
		var gy: float = float(ground_fn.call(wp.x, wp.z)) if ground_fn.is_valid() else 0.0
		# Uman/valley are the freestyle maps: the pilot expects red ARCHES,
		# not a mix of random polygons.  Hall/airport keep varied frames.
		# Smaller openings and a wider altitude band make the course a real
		# precision run instead of a straight-line sprint.  Start (0) and
		# Finish (23) sit next to the spawn/landing pad.
		specs.append({"pos": Vector3(wp.x, gy + 2.8 + float(i % 5) * 1.25, wp.z),
				"yaw": yaw + 0.65 * (1.0 if i % 2 == 0 else -1.0),
				"shape": 1, "size": 2.0 + float(i % 3) * 0.25})
	return specs
