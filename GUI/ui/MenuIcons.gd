class_name MenuIcons
extends RefCounted

## Procedural tactical icon generator for Nebesnyi Horizont FPV Simulator.
## Generates crisp RGBA8 ImageTextures that render flawlessly on iOS, macOS, Windows and Android
## without relying on missing TTF font glyphs or emoji fonts.

static var _cache: Dictionary = {}

static func icon_play(color: Color = Color(0.1, 0.15, 0.1, 1.0), size: int = 32) -> ImageTexture:
	var key := "play_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pad := float(size) * 0.18
	var h := float(size)
	for y in range(size):
		var fy := float(y)
		var rel_y := (fy - pad) / (h - 2.0 * pad)
		if rel_y >= 0.0 and rel_y <= 1.0:
			var max_x := (h - 2.0 * pad) * (1.0 - absf(rel_y - 0.5) * 2.0)
			for x in range(int(pad), int(pad + max_x)):
				if x < size:
					img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_radio(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "radio_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Antenna
	var mid: int = size / 2
	for y in range(int(size * 0.1), int(size * 0.35)):
		img.set_pixel(mid, y, color)
		img.set_pixel(mid - 1, y, color)
	# Body
	var bx0: int = int(size * 0.18)
	var bx1: int = int(size * 0.82)
	var by0: int = int(size * 0.35)
	var by1: int = int(size * 0.88)
	for y in range(by0, by1):
		for x in range(bx0, bx1):
			var is_border: bool = (x == bx0 or x == bx1 - 1 or y == by0 or y == by1 - 1)
			# Sticks dots
			var is_left_stick: bool = abs(x - int(size * 0.36)) <= 2 and abs(y - int(size * 0.55)) <= 2
			var is_right_stick: bool = abs(x - int(size * 0.64)) <= 2 and abs(y - int(size * 0.55)) <= 2
			var is_screen: bool = (x >= int(size * 0.38) and x <= int(size * 0.62) and y >= int(size * 0.70) and y <= int(size * 0.82))
			if is_border or is_left_stick or is_right_stick or is_screen:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_rates(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "rates_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# 3 vertical slider tracks with knobs
	var xs: Array[int] = [int(size * 0.25), int(size * 0.50), int(size * 0.75)]
	var knob_ys: Array[int] = [int(size * 0.65), int(size * 0.35), int(size * 0.50)]
	for i in range(3):
		var x: int = xs[i]
		var ky: int = knob_ys[i]
		for y in range(int(size * 0.18), int(size * 0.82)):
			img.set_pixel(x, y, color * Color(1, 1, 1, 0.6))
		for kx in range(x - 3, x + 4):
			for y in range(ky - 2, ky + 3):
				if kx >= 0 and kx < size and y >= 0 and y < size:
					img.set_pixel(kx, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_hangar(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "hangar_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := float(size) * 0.5
	# Quad cross arms
	var r := float(size) * 0.36
	for d in range(-int(r), int(r) + 1):
		var fd := float(d)
		var x1 := int(mid + fd)
		var y1 := int(mid + fd)
		var x2 := int(mid + fd)
		var y2 := int(mid - fd)
		if x1 >= 0 and x1 < size and y1 >= 0 and y1 < size:
			img.set_pixel(x1, y1, color)
		if x2 >= 0 and x2 < size and y2 >= 0 and y2 < size:
			img.set_pixel(x2, y2, color)
	# 4 motor pods
	var motors := [
		Vector2(mid - r, mid - r),
		Vector2(mid + r, mid - r),
		Vector2(mid - r, mid + r),
		Vector2(mid + r, mid + r)
	]
	for m in motors:
		for y in range(int(m.y - 3), int(m.y + 4)):
			for x in range(int(m.x - 3), int(m.x + 4)):
				if x >= 0 and x < size and y >= 0 and y < size:
					if Vector2(x, y).distance_to(m) <= 3.2:
						img.set_pixel(x, y, color)
	# Center drone pod
	for y in range(int(mid - 3), int(mid + 4)):
		for x in range(int(mid - 2), int(mid + 3)):
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_settings(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "settings_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid := Vector2(float(size) * 0.5, float(size) * 0.5)
	var r_outer := float(size) * 0.38
	var r_inner := float(size) * 0.22
	var r_hole := float(size) * 0.11
	for y in range(size):
		for x in range(size):
			var pos := Vector2(float(x), float(y))
			var d := pos.distance_to(mid)
			if d <= r_outer and d >= r_hole:
				var angle := (pos - mid).angle()
				var teeth := sin(angle * 6.0) # 6 gear teeth
				if d <= r_inner or teeth > 0.0:
					img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_back(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "back_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid_y := float(size) * 0.5
	var tip_x := float(size) * 0.25
	var base_x := float(size) * 0.72
	for y in range(size):
		var fy := float(y)
		var rel := absf(fy - mid_y)
		var target_x := tip_x + rel * 1.1
		for x in range(int(target_x), int(target_x + 3.0)):
			if x < int(base_x) and x >= 0 and x < size:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_close(color: Color = Color(0.95, 0.4, 0.4, 1.0), size: int = 32) -> ImageTexture:
	var key := "close_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pad := int(size * 0.22)
	for i in range(pad, size - pad):
		for w in range(-1, 2):
			var x1 := i
			var y1 := i + w
			var x2 := size - 1 - i
			var y2 := i + w
			if x1 >= 0 and x1 < size and y1 >= 0 and y1 < size:
				img.set_pixel(x1, y1, color)
			if x2 >= 0 and x2 < size and y2 >= 0 and y2 < size:
				img.set_pixel(x2, y2, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_check(color: Color = Color(0.55, 0.95, 0.65, 1.0), size: int = 32) -> ImageTexture:
	var key := "check_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Short stem
	for i in range(0, int(size * 0.28)):
		for w in range(-1, 2):
			var x := int(size * 0.22) + i
			var y := int(size * 0.50) + i + w
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, color)
	# Long stem
	for i in range(0, int(size * 0.45)):
		for w in range(-1, 2):
			var x := int(size * 0.48) + i
			var y := int(size * 0.76) - int(i * 1.3) + w
			if x >= 0 and x < size and y >= 0 and y < size:
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func icon_home(color: Color = Color(0.85, 0.95, 0.88, 1.0), size: int = 32) -> ImageTexture:
	var key := "home_%s_%d" % [color.to_html(), size]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var mid: int = size / 2
	# Roof
	for y in range(int(size * 0.18), int(size * 0.52)):
		var fy := float(y - int(size * 0.18))
		var w := int(fy * 1.2)
		for x in range(mid - w, mid + w + 1):
			if x >= 0 and x < size:
				if abs(x - (mid - w)) <= 1 or abs(x - (mid + w)) <= 1 or y == int(size * 0.51):
					img.set_pixel(x, y, color)
	# Walls
	for y in range(int(size * 0.52), int(size * 0.85)):
		for x in range(int(size * 0.28), int(size * 0.72)):
			var is_wall: bool = (x == int(size * 0.28) or x == int(size * 0.71) or y == int(size * 0.84))
			# Door
			var is_door: bool = (x >= int(size * 0.42) and x <= int(size * 0.58) and y >= int(size * 0.62))
			if is_wall or (is_door and (x == int(size * 0.42) or x == int(size * 0.58) or y == int(size * 0.62))):
				img.set_pixel(x, y, color)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
