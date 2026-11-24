class_name VoltTheme
extends RefCounted

## 03 · VOLT MONOLITH design system for the mobile tactical UI.
## Palette: Obsidian Black + Volt Yellow (#FFE100) + Warm Stone White (#EAE7DF).

const BG := Color("080808")
const SURFACE := Color(0.067, 0.067, 0.071, 0.88)
const SURFACE_SOLID := Color("131315")
const SURFACE_2 := Color(0.118, 0.120, 0.128, 0.92)
const SURFACE_HOVER := Color(0.168, 0.172, 0.184, 0.96)
const YELLOW := Color("ffe100")
const YELLOW_HOVER := Color("ffec40")
const YELLOW_PRESSED := Color("d6bc00")
const YELLOW_SOFT := Color(1.0, 0.882, 0.0, 0.16)
const YELLOW_BORDER := Color(1.0, 0.882, 0.0, 0.68)
const STONE := Color("eae7df")
const STONE_DIM := Color("949087")
const TEXT := Color("f4f2ec")
const TEXT_DARK := Color("080808")
const MUTED := Color("7d7a73")
const BORDER := Color(0.918, 0.906, 0.875, 0.15)
const BORDER_STRONG := Color(0.918, 0.906, 0.875, 0.30)
const GOOD := Color("4cd98a")
const DANGER := Color("f05d5e")

const PATH_DISPLAY := "res://GUI/mobile/fonts/Unbounded-Bold.ttf"
const PATH_UI := "res://GUI/mobile/fonts/Manrope-Variable.ttf"
const PATH_MONO := "res://GUI/mobile/fonts/JetBrainsMono-Bold.ttf"
const PATH_FALLBACK_SANS := "res://GUI/NotoSans-Regular.ttf"
const PATH_FALLBACK_MONO := "res://HUD/B612Mono-Regular.ttf"

static var _font_cache: Dictionary = {}
static var _knob_cache: Dictionary = {}


static func _load_font_file(path: String) -> Font:
	var key := "raw:" + path
	if _font_cache.has(key):
		return _font_cache[key] as Font
	var font: Font = null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Font:
			font = res as Font
	if font == null:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(abs_path) == OK:
				font = ff
	if font is FontFile and path != PATH_FALLBACK_SANS:
		var fb := _load_raw_fallback()
		if fb != null and not (font as FontFile).fallbacks.has(fb):
			(font as FontFile).fallbacks.append(fb)
	_font_cache[key] = font
	return font


static func _load_raw_fallback() -> Font:
	var key := "raw_fb"
	if _font_cache.has(key):
		return _font_cache[key] as Font
	var fb: Font = null
	if ResourceLoader.exists(PATH_FALLBACK_SANS):
		var res := load(PATH_FALLBACK_SANS)
		if res is Font:
			fb = res as Font
	if fb == null:
		var abs_path := ProjectSettings.globalize_path(PATH_FALLBACK_SANS)
		if FileAccess.file_exists(abs_path):
			var ff := FontFile.new()
			if ff.load_dynamic_font(abs_path) == OK:
				fb = ff
	_font_cache[key] = fb
	return fb


static func _weighted_var(base: Font, wght: float, key: String, embolden_fallback: float = 0.0) -> Font:
	if _font_cache.has(key) and _font_cache[key] != null:
		return _font_cache[key] as Font
	if base != null:
		var fv := FontVariation.new()
		fv.base_font = base
		var vars := base.get_supported_variation_list()
		if vars.has(0x77676874) or vars.has("wght"):
			fv.variation_opentype = {0x77676874: wght}
		elif embolden_fallback != 0.0:
			fv.variation_embolden = embolden_fallback
		_font_cache[key] = fv
		return fv
	var fb := _load_raw_fallback()
	if fb != null and embolden_fallback != 0.0:
		var ffv := FontVariation.new()
		ffv.base_font = fb
		ffv.variation_embolden = embolden_fallback
		_font_cache[key] = ffv
		return ffv
	_font_cache[key] = fb
	return fb


static func font_display() -> Font:
	var key := "display"
	if _font_cache.has(key) and _font_cache[key] != null:
		return _font_cache[key] as Font
	var f := _load_font_file(PATH_DISPLAY)
	if f != null:
		_font_cache[key] = f
		return f
	return _weighted_var(_load_raw_fallback(), 800.0, key, 0.35)


static func font_ui() -> Font:
	return _weighted_var(_load_font_file(PATH_UI), 650.0, "ui_semibold", 0.14)


static func font_ui_bold() -> Font:
	return _weighted_var(_load_font_file(PATH_UI), 800.0, "ui_extrabold", 0.28)


static func font_mono() -> Font:
	var key := "mono"
	if _font_cache.has(key) and _font_cache[key] != null:
		return _font_cache[key] as Font
	var f := _load_font_file(PATH_MONO)
	if f != null:
		_font_cache[key] = f
		return f
	var fb_mono := _load_font_file(PATH_FALLBACK_MONO)
	if fb_mono != null:
		_font_cache[key] = fb_mono
		return fb_mono
	return _load_raw_fallback()


static func panel_box(bg: Color = SURFACE, border: Color = BORDER, border_w: int = 1,
		radius: int = 14, pad_h: int = 14, pad_v: int = 10, shadow_sz: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	if shadow_sz > 0:
		sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
		sb.shadow_size = shadow_sz
		sb.shadow_offset = Vector2(0, 4)
	return sb


static func button_box(bg: Color = SURFACE_2, border: Color = BORDER, border_w: int = 1,
		radius: int = 10, pad_h: int = 14, pad_v: int = 8, shadow_col: Color = Color(0.0, 0.0, 0.0, 0.42),
		shadow_sz: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	if shadow_sz > 0:
		sb.shadow_color = shadow_col
		sb.shadow_size = shadow_sz
		sb.shadow_offset = Vector2(0, 3)
	return sb


static func primary_button_box(radius: int = 10, pad_h: int = 16, pad_v: int = 8) -> StyleBoxFlat:
	return button_box(YELLOW, YELLOW, 1, radius, pad_h, pad_v, Color(1.0, 0.882, 0.0, 0.24), 10)


static func stone_button_box(radius: int = 10, pad_h: int = 14, pad_v: int = 8) -> StyleBoxFlat:
	return button_box(STONE, STONE, 1, radius, pad_h, pad_v, Color(0.0, 0.0, 0.0, 0.45), 6)


static func ghost_button_box(radius: int = 10, pad_h: int = 12, pad_v: int = 6) -> StyleBoxFlat:
	return button_box(Color(1.0, 1.0, 1.0, 0.045), BORDER, 1, radius, pad_h, pad_v, Color(0, 0, 0, 0), 0)


static func danger_button_box(radius: int = 10, pad_h: int = 14, pad_v: int = 8) -> StyleBoxFlat:
	return button_box(Color(0.941, 0.365, 0.369, 0.14), Color(0.941, 0.365, 0.369, 0.55), 1, radius, pad_h, pad_v)


static func pill_box(bg: Color = SURFACE, border: Color = BORDER, pad_h: int = 10, pad_v: int = 4) -> StyleBoxFlat:
	return button_box(bg, border, 1, 999, pad_h, pad_v, Color(0, 0, 0, 0.32), 4)


static func capsule_box() -> StyleBoxFlat:
	return panel_box(Color(0.067, 0.067, 0.075, 0.90), BORDER_STRONG, 1, 999, 8, 10, 14)


static func segment_box() -> StyleBoxFlat:
	return panel_box(Color(1.0, 1.0, 1.0, 0.04), BORDER, 1, 10, 3, 3, 0)


static func slider_track() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	sb.set_corner_radius_all(99)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func slider_fill(highlighted: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = YELLOW_HOVER if highlighted else YELLOW
	sb.set_corner_radius_all(99)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func apply_button_variant(btn: Button, variant: String = "secondary", radius: int = 10,
		pad_h: int = 14, pad_v: int = 6) -> void:
	if btn == null:
		return
	var norm: StyleBoxFlat
	var hov: StyleBoxFlat
	var prs: StyleBoxFlat
	var fg := TEXT
	var fg_hov := TEXT
	var fg_prs := TEXT
	match variant:
		"primary":
			norm = primary_button_box(radius, pad_h, pad_v)
			hov = button_box(YELLOW_HOVER, Color(1.0, 0.96, 0.65), 1, radius, pad_h, pad_v, Color(1.0, 0.882, 0.0, 0.32), 12)
			prs = button_box(YELLOW_PRESSED, YELLOW, 1, radius, pad_h, pad_v, Color(0, 0, 0, 0.4), 4)
			fg = TEXT_DARK
			fg_hov = TEXT_DARK
			fg_prs = TEXT_DARK
			btn.add_theme_font_override("font", font_ui_bold())
		"stone":
			norm = stone_button_box(radius, pad_h, pad_v)
			hov = button_box(Color("f5f3ed"), STONE, 1, radius, pad_h, pad_v)
			prs = button_box(STONE_DIM, STONE, 1, radius, pad_h, pad_v)
			fg = TEXT_DARK
			fg_hov = TEXT_DARK
			fg_prs = TEXT_DARK
			btn.add_theme_font_override("font", font_ui_bold())
		"ghost":
			norm = ghost_button_box(radius, pad_h, pad_v)
			hov = button_box(Color(1.0, 1.0, 1.0, 0.09), BORDER_STRONG, 1, radius, pad_h, pad_v, Color(0, 0, 0, 0), 0)
			prs = button_box(YELLOW_SOFT, YELLOW_BORDER, 1, radius, pad_h, pad_v, Color(0, 0, 0, 0), 0)
			fg = STONE
			fg_hov = TEXT
			fg_prs = YELLOW
			btn.add_theme_font_override("font", font_ui())
		"active_soft":
			norm = button_box(YELLOW_SOFT, YELLOW_BORDER, 2, radius, pad_h, pad_v, Color(1.0, 0.882, 0.0, 0.16), 6)
			hov = button_box(Color(1.0, 0.882, 0.0, 0.24), YELLOW, 2, radius, pad_h, pad_v, Color(1.0, 0.882, 0.0, 0.22), 8)
			prs = button_box(YELLOW, YELLOW, 2, radius, pad_h, pad_v)
			fg = YELLOW
			fg_hov = YELLOW_HOVER
			fg_prs = TEXT_DARK
			btn.add_theme_font_override("font", font_ui_bold())
		"danger":
			norm = danger_button_box(radius, pad_h, pad_v)
			hov = button_box(Color(0.941, 0.365, 0.369, 0.24), DANGER, 1, radius, pad_h, pad_v)
			prs = button_box(DANGER, DANGER, 1, radius, pad_h, pad_v)
			fg = Color("ff9c9d")
			fg_hov = Color("ffd5d6")
			fg_prs = TEXT_DARK
			btn.add_theme_font_override("font", font_ui_bold())
		_:
			norm = button_box(SURFACE_2, BORDER, 1, radius, pad_h, pad_v)
			hov = button_box(SURFACE_HOVER, BORDER_STRONG, 1, radius, pad_h, pad_v)
			prs = button_box(YELLOW_SOFT, YELLOW_BORDER, 1, radius, pad_h, pad_v)
			fg = TEXT
			fg_hov = TEXT
			fg_prs = YELLOW
			btn.add_theme_font_override("font", font_ui())
	btn.add_theme_stylebox_override("normal", norm)
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("focus", hov)
	btn.add_theme_stylebox_override("pressed", prs)
	btn.add_theme_stylebox_override("disabled", button_box(Color(0.05, 0.05, 0.055, 0.6), Color(1, 1, 1, 0.08), 1, radius, pad_h, pad_v, Color(0, 0, 0, 0), 0))
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg_hov)
	btn.add_theme_color_override("font_focus_color", fg_hov)
	btn.add_theme_color_override("font_pressed_color", fg_prs)
	btn.add_theme_color_override("font_disabled_color", MUTED)


static func animate_pop_in(ctrl: Control, duration: float = 0.20) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	if DisplayServer.get_name() == "headless":
		ctrl.modulate.a = 1.0
		ctrl.scale = Vector2.ONE
		return
	if not ctrl.is_inside_tree():
		return
	ctrl.pivot_offset = ctrl.size * 0.5
	ctrl.modulate.a = 0.0
	ctrl.scale = Vector2(0.975, 0.975)
	var tw := ctrl.create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "modulate:a", 1.0, duration)
	tw.tween_property(ctrl, "scale", Vector2.ONE, duration)


static func make_volt_knob_texture(size: int = 24) -> ImageTexture:
	if _knob_cache.has(size):
		return _knob_cache[size] as ImageTexture
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(float(size - 1) * 0.5, float(size - 1) * 0.5)
	var r_outer := float(size) * 0.42
	var r_inner := float(size) * 0.21
	for y in range(size):
		for x in range(size):
			var d := Vector2(float(x), float(y)).distance_to(center)
			if d <= r_outer + 0.8:
				var aa := clampf(r_outer + 0.8 - d, 0.0, 1.0)
				var col := Color(YELLOW.r, YELLOW.g, YELLOW.b, aa)
				if d <= r_inner + 0.6 and d >= r_inner - 1.4:
					var ring_t := clampf(1.0 - absf(d - (r_inner - 0.3)), 0.0, 1.0)
					col = col.lerp(Color(TEXT_DARK.r, TEXT_DARK.g, TEXT_DARK.b, aa), ring_t * 0.85)
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_knob_cache[size] = tex
	return tex
