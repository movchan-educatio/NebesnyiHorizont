## Russian battlefield markings for enemy vehicles and infantry: a small
## white-blue-red flag and a chalk "Z" drawn with rough white strokes.
## Vehicles get one rear flag + one Z; infantry gets only a small shoulder
## flag (no Z), matching the final art direction.
##
## Textures are generated once and shared; every marking is a double-sided quad
## so it reads from the chase/FPV angles without extra geometry.
class_name EnemyMarkings
extends RefCounted

static var _flag_tex: ImageTexture = null
static var _z_tex: ImageTexture = null


static func is_russian_vehicle(vehicle: Node) -> bool:
	if vehicle == null:
		return false
	var ai_vs_ai := bool(vehicle.get("ai_vs_ai"))
	if ai_vs_ai:
		return int(vehicle.get("ai_team")) == 1
	return bool(vehicle.get("hostile"))


static func mark_vehicle(vehicle: Node3D, box: Vector3) -> void:
	if vehicle == null or box.length_squared() < 0.01:
		return
	var flag := flag_texture()
	var z := z_texture()
	var half_z := box.z * 0.5
	var y := box.y * 0.55
	# One flag and one chalk Z per vehicle, on the rear plate.  The old
	# side/rear duplication made the hull look cluttered.
	var flag_mi := _add_quad(vehicle, flag, Vector3(0.95, 0.55, 1.0),
			Vector3(0.0, y, half_z + 0.012), Vector3.ZERO)
	flag_mi.name = "RussianFlag"
	var z_mi := _add_quad(vehicle, z, Vector3(0.85, 0.85, 1.0),
			Vector3(0.0, y + 0.62, half_z + 0.014), Vector3.ZERO)
	z_mi.name = "ChalkZ"


static func mark_infantry(rig: Node3D) -> void:
	if rig == null:
		return
	# Russian flag patch on the chest armor vest (pressed flat against the vest plate)
	var flag_mi := _add_quad(rig, flag_texture(), Vector3(0.080, 0.048, 1.0),
			Vector3(0.02, 1.34, -0.088), Vector3(-6.0, 180.0, 0.0))
	flag_mi.name = "RussianFlag"


static func flag_texture() -> ImageTexture:
	if _flag_tex != null:
		return _flag_tex
	var img := Image.create(256, 160, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	img.fill_rect(Rect2i(0, 0, 256, 54), Color(0.93, 0.95, 0.95, 1.0))
	img.fill_rect(Rect2i(0, 54, 256, 53), Color(0.08, 0.22, 0.55, 1.0))
	img.fill_rect(Rect2i(0, 107, 256, 53), Color(0.62, 0.06, 0.08, 1.0))
	# A thin dark frame reads as fabric edging on the hull.
	img.fill_rect(Rect2i(0, 0, 256, 3), Color(0.08, 0.08, 0.08, 0.8))
	img.fill_rect(Rect2i(0, 157, 256, 3), Color(0.08, 0.08, 0.08, 0.8))
	_flag_tex = ImageTexture.create_from_image(img)
	return _flag_tex


static func z_texture() -> ImageTexture:
	if _z_tex != null:
		return _z_tex
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261106
	# Three rough chalk strokes.  Each is drawn as many short translucent
	# segments, which gives the broken, hand-written edge of chalk on armour.
	_chalk_line(img, Vector2(42, 52), Vector2(214, 52), 16.0, rng)
	_chalk_line(img, Vector2(214, 52), Vector2(42, 204), 16.0, rng)
	_chalk_line(img, Vector2(42, 204), Vector2(214, 204), 16.0, rng)
	# A few stray chalk specks.
	for _i in range(90):
		var p := Vector2i(rng.randi_range(20, 236), rng.randi_range(20, 236))
		img.set_pixel(p.x, p.y, Color(0.92, 0.92, 0.86, rng.randf_range(0.08, 0.30)))
	_z_tex = ImageTexture.create_from_image(img)
	return _z_tex


static func _chalk_line(img: Image, a: Vector2, b: Vector2, width: float,
		rng: RandomNumberGenerator) -> void:
	var steps := int(maxf(a.distance_to(b), 1.0) * 1.6)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var p := a.lerp(b, t)
		var radius := width * rng.randf_range(0.32, 0.62)
		var alpha := rng.randf_range(0.55, 0.95)
		# Chalk is not a clean line: add a second, offset dab.
		_dab(img, p + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)),
				radius, alpha)
		if rng.randf() < 0.22:
			_dab(img, p + Vector2(rng.randf_range(-7, 7), rng.randf_range(-5, 5)),
					radius * 0.55, alpha * 0.55)


static func _dab(img: Image, center: Vector2, radius: float, alpha: float) -> void:
	var r := int(ceil(radius))
	var cx := int(center.x)
	var cy := int(center.y)
	for y in range(cy - r, cy + r + 1):
		if y < 0 or y >= img.get_height():
			continue
		for x in range(cx - r, cx + r + 1):
			if x < 0 or x >= img.get_width():
				continue
			var d := Vector2(x - center.x, y - center.y).length()
			if d > radius:
				continue
			var falloff := 1.0 - d / maxf(radius, 0.001)
			var c := Color(0.94, 0.94, 0.88, alpha * falloff)
			var old := img.get_pixel(x, y)
			if old.a < c.a:
				img.set_pixel(x, y, c)


static func _add_quad(parent: Node3D, tex: Texture2D, size: Vector3,
		pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(size.x, size.y)
	var mi := MeshInstance3D.new()
	mi.name = "RussianMarking"
	mi.mesh = quad
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = mat
	parent.add_child(mi)
	return mi
