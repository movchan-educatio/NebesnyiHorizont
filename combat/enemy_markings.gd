## Neutral tactical OPFOR markings for enemy vehicles and infantry.
## Replaces state flags and real-world invasion symbols with a dark olive-slate
## tactical identification plate so App Store review and visual identity stay clean.
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


static func mark_vehicle(_vehicle: Node3D, _box: Vector3) -> void:
	# State flags and chalk Z markings are intentionally disabled; enemy vehicles
	# use their cohesive dark olive-slate tactical camouflage instead.
	return


static func mark_infantry(_rig: Node3D) -> void:
	# State flag patches on infantry vests are intentionally disabled.
	return


static func flag_texture() -> ImageTexture:
	if _flag_tex != null:
		return _flag_tex
	var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.16, 0.20, 0.14, 1.0))
	_flag_tex = ImageTexture.create_from_image(img)
	return _flag_tex


static func z_texture() -> ImageTexture:
	if _z_tex != null:
		return _z_tex
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
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
