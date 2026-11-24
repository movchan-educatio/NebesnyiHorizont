class_name MenuIcons
extends RefCounted

## Procedural anti-aliased tactical icon generator for Nebesnyi Horizont FPV Simulator.
## Generates crisp SDF RGBA8 ImageTextures that render cleanly on iOS, macOS, Windows, and Android
## without relying on emoji fonts or missing TTF glyphs.

static var _cache: Dictionary = {}


static func _new_img(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _blend_px(img: Image, x: int, y: int, color: Color, cov: float) -> void:
	if cov <= 0.001 or x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	var a := clampf(color.a * clampf(cov, 0.0, 1.0), 0.0, 1.0)
	var cur := img.get_pixel(x, y)
	if a > cur.a:
		img.set_pixel(x, y, Color(color.r, color.g, color.b, a))


static func _aa_circle(img: Image, center: Vector2, radius: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := maxi(0, int(floor(center.x - radius - 1.5)))
	var max_x := mini(w - 1, int(ceil(center.x + radius + 1.5)))
	var min_y := maxi(0, int(floor(center.y - radius - 1.5)))
	var max_y := mini(h - 1, int(ceil(center.y + radius + 1.5)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			_blend_px(img, x, y, color, radius + 0.65 - d)


static func _aa_ring(img: Image, center: Vector2, radius: float, thickness: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var half_t := maxf(0.5, thickness * 0.5)
	var outer := radius + half_t + 1.5
	var min_x := maxi(0, int(floor(center.x - outer)))
	var max_x := mini(w - 1, int(ceil(center.x + outer)))
	var min_y := maxi(0, int(floor(center.y - outer)))
	var max_y := mini(h - 1, int(ceil(center.y + outer)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var d := absf(Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) - radius)
			_blend_px(img, x, y, color, half_t + 0.65 - d)


static func _aa_line(img: Image, a: Vector2, b: Vector2, thickness: float, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var half_t := maxf(0.5, thickness * 0.5)
	var pad := half_t + 1.5
	var min_x := maxi(0, int(floor(minf(a.x, b.x) - pad)))
	var max_x := mini(w - 1, int(ceil(maxf(a.x, b.x) + pad)))
	var min_y := maxi(0, int(floor(minf(a.y, b.y) - pad)))
	var max_y := mini(h - 1, int(ceil(maxf(a.y, b.y) + pad)))
	var ab := b - a
	var len_sq := ab.length_squared()
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0) if len_sq > 0.0001 else 0.0
			var d := p.distance_to(a + ab * t)
			_blend_px(img, x, y, color, half_t + 0.65 - d)


static func _aa_rect(img: Image, rect: Rect2, color: Color, filled: bool = true, thickness: float = 2.0) -> void:
	if not filled:
		var tl := rect.position
		var tr := Vector2(rect.end.x, rect.position.y)
		var br := rect.end
		var bl := Vector2(rect.position.x, rect.end.y)
		_aa_line(img, tl, tr, thickness, color)
		_aa_line(img, tr, br, thickness, color)
		_aa_line(img, br, bl, thickness, color)
		_aa_line(img, bl, tl, thickness, color)
		return
	var w := img.get_width()
	var h := img.get_height()
	var half := rect.size * 0.5
	var ctr := rect.position + half
	var min_x := maxi(0, int(floor(rect.position.x - 1.0)))
	var max_x := mini(w - 1, int(ceil(rect.end.x + 1.0)))
	var min_y := maxi(0, int(floor(rect.position.y - 1.0)))
	var max_y := mini(h - 1, int(ceil(rect.end.y + 1.0)))
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var q := Vector2(absf(float(x) + 0.5 - ctr.x) - half.x, absf(float(y) + 0.5 - ctr.y) - half.y)
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			_blend_px(img, x, y, color, 0.65 - d)


static func _aa_triangle(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var min_x := maxi(0, int(floor(minf(p0.x, minf(p1.x, p2.x)) - 1.5)))
	var max_x := mini(w - 1, int(ceil(maxf(p0.x, maxf(p1.x, p2.x)) + 1.5)))
	var min_y := maxi(0, int(floor(minf(p0.y, minf(p1.y, p2.y)) - 1.5)))
	var max_y := mini(h - 1, int(ceil(maxf(p0.y, maxf(p1.y, p2.y)) + 1.5)))
	var e0 := p1 - p0
	var e1 := p2 - p1
	var e2 := p0 - p2
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var s0 := e0.x * (p.y - p0.y) - e0.y * (p.x - p0.x)
			var s1 := e1.x * (p.y - p1.y) - e1.y * (p.x - p1.x)
			var s2 := e2.x * (p.y - p2.y) - e2.y * (p.x - p2.x)
			var inside := (s0 >= 0.0 and s1 >= 0.0 and s2 >= 0.0) or (s0 <= 0.0 and s1 <= 0.0 and s2 <= 0.0)
			var d0 := p.distance_to(p0 + e0 * clampf((p - p0).dot(e0) / maxf(e0.length_squared(), 0.0001), 0.0, 1.0))
			var d1 := p.distance_to(p1 + e1 * clampf((p - p1).dot(e1) / maxf(e1.length_squared(), 0.0001), 0.0, 1.0))
			var d2 := p.distance_to(p2 + e2 * clampf((p - p2).dot(e2) / maxf(e2.length_squared(), 0.0001), 0.0, 1.0))
			var min_d := minf(d0, minf(d1, d2))
			var sd := -min_d if inside else min_d
			_blend_px(img, x, y, color, 0.65 - sd)


static func _aa_arc(img: Image, center: Vector2, radius: float, a0: float, a1: float,
		thickness: float, color: Color, steps: int = 24) -> void:
	var prev := center + Vector2(cos(a0), sin(a0)) * radius
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var ang := lerpf(a0, a1, t)
		var nxt := center + Vector2(cos(ang), sin(ang)) * radius
		_aa_line(img, prev, nxt, thickness, color)
		prev = nxt


static func _finish(key: String, img: Image) -> ImageTexture:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func icon_play(color: Color = Color(0.1, 0.15, 0.1, 1.0), size: int = 32) -> ImageTexture:
	var key := "play_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	_aa_triangle(img, Vector2(s * 0.28, s * 0.20), Vector2(s * 0.80, s * 0.50), Vector2(s * 0.28, s * 0.80), color)
	return _finish(key, img)


static func icon_radio(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "radio_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.6, s * 0.068)
	# Antenna + tip pip
	_aa_line(img, Vector2(s * 0.50, s * 0.12), Vector2(s * 0.50, s * 0.34), t, color)
	_aa_circle(img, Vector2(s * 0.50, s * 0.12), maxf(1.4, s * 0.048), color)
	# Chassis frame
	_aa_rect(img, Rect2(s * 0.16, s * 0.34, s * 0.68, s * 0.52), color, false, t)
	# Gimbals + Telemetry Screen
	_aa_ring(img, Vector2(s * 0.33, s * 0.54), s * 0.095, t * 0.85, color)
	_aa_ring(img, Vector2(s * 0.67, s * 0.54), s * 0.095, t * 0.85, color)
	_aa_rect(img, Rect2(s * 0.38, s * 0.70, s * 0.24, s * 0.10), color, true)
	return _finish(key, img)


static func icon_rates(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "rates_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.6, s * 0.068)
	# Axes + S-curve response
	_aa_line(img, Vector2(s * 0.18, s * 0.80), Vector2(s * 0.84, s * 0.80), t * 0.85, Color(color.r, color.g, color.b, color.a * 0.55))
	_aa_line(img, Vector2(s * 0.18, s * 0.18), Vector2(s * 0.18, s * 0.80), t * 0.85, Color(color.r, color.g, color.b, color.a * 0.55))
	var prev := Vector2(s * 0.18, s * 0.80)
	for i in range(1, 13):
		var u := float(i) / 12.0
		var v := u * 0.32 + pow(u, 3.0) * 0.68
		var pt := Vector2(lerpf(s * 0.18, s * 0.84, u), lerpf(s * 0.80, s * 0.20, v))
		_aa_line(img, prev, pt, t, color)
		prev = pt
	_aa_circle(img, Vector2(s * 0.82, s * 0.22), maxf(1.8, s * 0.065), color)
	return _finish(key, img)


static func icon_hangar(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "hangar_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.064)
	# Cross arms
	_aa_line(img, Vector2(s * 0.24, s * 0.24), Vector2(s * 0.76, s * 0.76), t, color)
	_aa_line(img, Vector2(s * 0.24, s * 0.76), Vector2(s * 0.76, s * 0.24), t, color)
	# Rotor rings
	for pos in [
		Vector2(s * 0.23, s * 0.23),
		Vector2(s * 0.77, s * 0.23),
		Vector2(s * 0.23, s * 0.77),
		Vector2(s * 0.77, s * 0.77),
	]:
		_aa_ring(img, pos, s * 0.115, t * 0.9, color)
	# Center pod
	_aa_rect(img, Rect2(s * 0.42, s * 0.37, s * 0.16, s * 0.26), color, true)
	return _finish(key, img)


static func icon_settings(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "settings_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.5)
	var t := maxf(1.6, s * 0.072)
	_aa_ring(img, ctr, s * 0.23, t, color)
	_aa_circle(img, ctr, s * 0.085, color)
	for i in range(8):
		var a := float(i) * TAU / 8.0
		var dir := Vector2(cos(a), sin(a))
		_aa_line(img, ctr + dir * (s * 0.27), ctr + dir * (s * 0.38), t * 1.15, color)
	return _finish(key, img)


static func icon_back(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "back_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.8, s * 0.078)
	_aa_line(img, Vector2(s * 0.68, s * 0.22), Vector2(s * 0.32, s * 0.50), t, color)
	_aa_line(img, Vector2(s * 0.32, s * 0.50), Vector2(s * 0.68, s * 0.78), t, color)
	return _finish(key, img)


static func icon_close(color: Color = Color(0.95, 0.4, 0.4, 1.0), size: int = 32) -> ImageTexture:
	var key := "close_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.8, s * 0.078)
	_aa_line(img, Vector2(s * 0.25, s * 0.25), Vector2(s * 0.75, s * 0.75), t, color)
	_aa_line(img, Vector2(s * 0.75, s * 0.25), Vector2(s * 0.25, s * 0.75), t, color)
	return _finish(key, img)


static func icon_check(color: Color = Color(0.55, 0.95, 0.65, 1.0), size: int = 32) -> ImageTexture:
	var key := "check_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.9, s * 0.082)
	_aa_line(img, Vector2(s * 0.22, s * 0.52), Vector2(s * 0.43, s * 0.74), t, color)
	_aa_line(img, Vector2(s * 0.43, s * 0.74), Vector2(s * 0.79, s * 0.28), t, color)
	return _finish(key, img)


static func icon_home(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "home_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.6, s * 0.068)
	_aa_line(img, Vector2(s * 0.18, s * 0.48), Vector2(s * 0.50, s * 0.19), t, color)
	_aa_line(img, Vector2(s * 0.50, s * 0.19), Vector2(s * 0.82, s * 0.48), t, color)
	_aa_line(img, Vector2(s * 0.26, s * 0.44), Vector2(s * 0.26, s * 0.82), t, color)
	_aa_line(img, Vector2(s * 0.74, s * 0.44), Vector2(s * 0.74, s * 0.82), t, color)
	_aa_line(img, Vector2(s * 0.26, s * 0.82), Vector2(s * 0.74, s * 0.82), t, color)
	_aa_rect(img, Rect2(s * 0.43, s * 0.58, s * 0.14, s * 0.24), color, false, t * 0.9)
	return _finish(key, img)


static func icon_trophy(color: Color = Color(0.95, 0.78, 0.25, 1.0), size: int = 32) -> ImageTexture:
	var key := "trophy_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.066)
	_aa_line(img, Vector2(s * 0.30, s * 0.18), Vector2(s * 0.70, s * 0.18), t, color)
	_aa_line(img, Vector2(s * 0.30, s * 0.18), Vector2(s * 0.36, s * 0.48), t, color)
	_aa_line(img, Vector2(s * 0.70, s * 0.18), Vector2(s * 0.64, s * 0.48), t, color)
	_aa_line(img, Vector2(s * 0.36, s * 0.48), Vector2(s * 0.64, s * 0.48), t, color)
	_aa_arc(img, Vector2(s * 0.30, s * 0.30), s * 0.10, PI * 0.5, PI * 1.5, t * 0.9, color, 12)
	_aa_arc(img, Vector2(s * 0.70, s * 0.30), s * 0.10, -PI * 0.5, PI * 0.5, t * 0.9, color, 12)
	_aa_line(img, Vector2(s * 0.50, s * 0.49), Vector2(s * 0.50, s * 0.76), t, color)
	_aa_line(img, Vector2(s * 0.32, s * 0.79), Vector2(s * 0.68, s * 0.79), t * 1.15, color)
	return _finish(key, img)


static func icon_more(color: Color = Color(0.90, 0.96, 0.91, 1.0), size: int = 32) -> ImageTexture:
	var key := "more_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var cy := s * 0.5
	var r := maxf(2.1, s * 0.095)
	for cx in [s * 0.24, s * 0.50, s * 0.76]:
		_aa_circle(img, Vector2(cx, cy), r, color)
	return _finish(key, img)


static func icon_lock(color: Color = Color(1.0, 0.882, 0.0, 1.0), size: int = 24) -> ImageTexture:
	var key := "lock_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.078)
	_aa_rect(img, Rect2(s * 0.24, s * 0.45, s * 0.52, s * 0.38), color, false, t)
	_aa_arc(img, Vector2(s * 0.50, s * 0.42), s * 0.17, PI, TAU, t, color, 14)
	_aa_circle(img, Vector2(s * 0.50, s * 0.63), maxf(1.4, s * 0.062), color)
	return _finish(key, img)


static func icon_coin(color: Color = Color(0.05, 0.05, 0.05, 1.0), size: int = 24) -> ImageTexture:
	var key := "coin_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.5)
	var t := maxf(1.4, s * 0.075)
	# Crisp tactical diamond-hex emblem
	var top := ctr + Vector2(0.0, -s * 0.34)
	var right := ctr + Vector2(s * 0.34, 0.0)
	var bottom := ctr + Vector2(0.0, s * 0.34)
	var left := ctr + Vector2(-s * 0.34, 0.0)
	_aa_line(img, top, right, t, color)
	_aa_line(img, right, bottom, t, color)
	_aa_line(img, bottom, left, t, color)
	_aa_line(img, left, top, t, color)
	_aa_circle(img, ctr, s * 0.11, color)
	return _finish(key, img)


static func icon_star(color: Color = Color(1.0, 0.882, 0.0, 1.0), size: int = 24) -> ImageTexture:
	var key := "star_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.52)
	var r_out := s * 0.38
	var r_in := s * 0.17
	var pts: Array[Vector2] = []
	for i in range(10):
		var a := -PI * 0.5 + float(i) * PI / 5.0
		var r := r_out if (i % 2 == 0) else r_in
		pts.append(ctr + Vector2(cos(a), sin(a)) * r)
	for i in range(0, 10, 2):
		var tip := pts[i]
		var left_v := pts[(i + 9) % 10]
		var right_v := pts[(i + 1) % 10]
		_aa_triangle(img, ctr, left_v, tip, color)
		_aa_triangle(img, ctr, tip, right_v, color)
	return _finish(key, img)


static func icon_chevron_left(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 24) -> ImageTexture:
	var key := "chevl_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.6, s * 0.088)
	_aa_line(img, Vector2(s * 0.62, s * 0.22), Vector2(s * 0.34, s * 0.50), t, color)
	_aa_line(img, Vector2(s * 0.34, s * 0.50), Vector2(s * 0.62, s * 0.78), t, color)
	return _finish(key, img)


static func icon_chevron_right(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 24) -> ImageTexture:
	var key := "chevr_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.6, s * 0.088)
	_aa_line(img, Vector2(s * 0.38, s * 0.22), Vector2(s * 0.66, s * 0.50), t, color)
	_aa_line(img, Vector2(s * 0.66, s * 0.50), Vector2(s * 0.38, s * 0.78), t, color)
	return _finish(key, img)


static func icon_target(color: Color = Color(1.0, 0.882, 0.0, 1.0), size: int = 32) -> ImageTexture:
	var key := "target_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.5)
	var t := maxf(1.5, s * 0.068)
	_aa_ring(img, ctr, s * 0.30, t, color)
	_aa_circle(img, ctr, s * 0.08, color)
	_aa_line(img, Vector2(s * 0.50, s * 0.09), Vector2(s * 0.50, s * 0.24), t, color)
	_aa_line(img, Vector2(s * 0.50, s * 0.76), Vector2(s * 0.50, s * 0.91), t, color)
	_aa_line(img, Vector2(s * 0.09, s * 0.50), Vector2(s * 0.24, s * 0.50), t, color)
	_aa_line(img, Vector2(s * 0.76, s * 0.50), Vector2(s * 0.91, s * 0.50), t, color)
	return _finish(key, img)


static func icon_school(color: Color = Color(1.0, 0.882, 0.0, 1.0), size: int = 32) -> ImageTexture:
	var key := "school_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.068)
	# Precision wing / compass chevron emblem
	_aa_line(img, Vector2(s * 0.50, s * 0.16), Vector2(s * 0.84, s * 0.44), t, color)
	_aa_line(img, Vector2(s * 0.84, s * 0.44), Vector2(s * 0.50, s * 0.62), t, color)
	_aa_line(img, Vector2(s * 0.50, s * 0.62), Vector2(s * 0.16, s * 0.44), t, color)
	_aa_line(img, Vector2(s * 0.16, s * 0.44), Vector2(s * 0.50, s * 0.16), t, color)
	_aa_line(img, Vector2(s * 0.28, s * 0.55), Vector2(s * 0.28, s * 0.76), t, color)
	_aa_line(img, Vector2(s * 0.72, s * 0.55), Vector2(s * 0.72, s * 0.76), t, color)
	_aa_arc(img, Vector2(s * 0.50, s * 0.72), s * 0.22, 0.15, PI - 0.15, t, color, 16)
	return _finish(key, img)


static func icon_sortie(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "sortie_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.068)
	# Waypoint / sortie trajectory diamond
	_aa_line(img, Vector2(s * 0.18, s * 0.76), Vector2(s * 0.48, s * 0.52), t, color)
	_aa_line(img, Vector2(s * 0.48, s * 0.52), Vector2(s * 0.78, s * 0.24), t, color)
	_aa_line(img, Vector2(s * 0.60, s * 0.22), Vector2(s * 0.80, s * 0.22), t, color)
	_aa_line(img, Vector2(s * 0.80, s * 0.22), Vector2(s * 0.80, s * 0.42), t, color)
	_aa_circle(img, Vector2(s * 0.18, s * 0.76), s * 0.08, color)
	_aa_ring(img, Vector2(s * 0.48, s * 0.52), s * 0.085, t * 0.85, color)
	return _finish(key, img)


static func icon_briefing(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "briefing_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.066)
	_aa_rect(img, Rect2(s * 0.20, s * 0.16, s * 0.60, s * 0.68), color, false, t)
	_aa_line(img, Vector2(s * 0.32, s * 0.34), Vector2(s * 0.68, s * 0.34), t, color)
	_aa_line(img, Vector2(s * 0.32, s * 0.50), Vector2(s * 0.68, s * 0.50), t, color)
	_aa_line(img, Vector2(s * 0.32, s * 0.66), Vector2(s * 0.55, s * 0.66), t, color)
	return _finish(key, img)


static func icon_wifi(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "wifi_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.74)
	var t := maxf(1.5, s * 0.068)
	_aa_circle(img, ctr, s * 0.075, color)
	_aa_arc(img, ctr, s * 0.22, -PI * 0.78, -PI * 0.22, t, color, 14)
	_aa_arc(img, ctr, s * 0.39, -PI * 0.78, -PI * 0.22, t, color, 18)
	_aa_arc(img, ctr, s * 0.56, -PI * 0.78, -PI * 0.22, t, color, 20)
	return _finish(key, img)


static func icon_rotate(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "rotate_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var ctr := Vector2(s * 0.5, s * 0.5)
	var t := maxf(1.5, s * 0.068)
	var r := s * 0.32
	_aa_arc(img, ctr, r, -PI * 0.85, PI * 0.55, t, color, 22)
	var head := ctr + Vector2(cos(PI * 0.55), sin(PI * 0.55)) * r
	_aa_line(img, head, head + Vector2(-s * 0.10, -s * 0.14), t, color)
	_aa_line(img, head, head + Vector2(s * 0.14, -s * 0.06), t, color)
	return _finish(key, img)


static func icon_pause(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "pause_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	_aa_rect(img, Rect2(s * 0.28, s * 0.22, s * 0.14, s * 0.56), color, true)
	_aa_rect(img, Rect2(s * 0.58, s * 0.22, s * 0.14, s * 0.56), color, true)
	return _finish(key, img)


static func icon_sliders(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "sliders_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.066)
	var ys := [s * 0.26, s * 0.50, s * 0.74]
	var kx := [s * 0.36, s * 0.66, s * 0.44]
	for i in range(3):
		_aa_line(img, Vector2(s * 0.16, ys[i]), Vector2(s * 0.84, ys[i]), t * 0.8, Color(color.r, color.g, color.b, color.a * 0.65))
		_aa_circle(img, Vector2(kx[i], ys[i]), s * 0.095, color)
	return _finish(key, img)


static func icon_bolt(color: Color = Color(1.0, 0.882, 0.0, 1.0), size: int = 32) -> ImageTexture:
	var key := "bolt_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	_aa_triangle(img, Vector2(s * 0.56, s * 0.14), Vector2(s * 0.26, s * 0.54), Vector2(s * 0.54, s * 0.54), color)
	_aa_triangle(img, Vector2(s * 0.46, s * 0.46), Vector2(s * 0.74, s * 0.46), Vector2(s * 0.44, s * 0.86), color)
	return _finish(key, img)


static func icon_flag(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "flag_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.068)
	_aa_line(img, Vector2(s * 0.26, s * 0.18), Vector2(s * 0.26, s * 0.84), t, color)
	_aa_rect(img, Rect2(s * 0.26, s * 0.20, s * 0.50, s * 0.34), color, false, t)
	_aa_rect(img, Rect2(s * 0.26, s * 0.20, s * 0.25, s * 0.17), color, true)
	_aa_rect(img, Rect2(s * 0.51, s * 0.37, s * 0.25, s * 0.17), color, true)
	return _finish(key, img)


static func icon_camera(color: Color = Color(0.95, 0.94, 0.92, 1.0), size: int = 32) -> ImageTexture:
	var key := "camera_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(size)
	var s := float(size)
	var t := maxf(1.5, s * 0.068)
	_aa_rect(img, Rect2(s * 0.14, s * 0.30, s * 0.52, s * 0.40), color, false, t)
	_aa_ring(img, Vector2(s * 0.40, s * 0.50), s * 0.10, t * 0.85, color)
	_aa_triangle(img, Vector2(s * 0.68, s * 0.50), Vector2(s * 0.86, s * 0.34), Vector2(s * 0.86, s * 0.66), color)
	return _finish(key, img)
