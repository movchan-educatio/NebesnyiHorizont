## Tactical vector SVG icon loader & cache for HUD telemetry, menus and KillCam.
## Supports both imported Godot resources (iOS/export .pck) and raw .svg loading
## via Image.load_svg_from_string() so headless/editor runs work with zero .import setup.
class_name FpvIcons
extends RefCounted

const ICON_DIR := "res://Assets/icons/"

const ICON_IDS := [
	"icon_crosshair",
	"icon_drone_topdown",
	"icon_warhead_drop",
	"icon_battery_pack",
	"icon_signal_link",
	"icon_wind_sock",
	"icon_compass_rose",
	"icon_altitude_ladder",
	"icon_joystick_gimbal",
	"icon_target_tank",
	"icon_explosion_star",
	"icon_wing_emblem",
]

const ALIASES := {
	"crosshair": "icon_crosshair",
	"hud-reticle": "icon_crosshair",
	"drone": "icon_drone_topdown",
	"drone_topdown": "icon_drone_topdown",
	"quadcopter-frame": "icon_drone_topdown",
	"warhead": "icon_warhead_drop",
	"warhead_drop": "icon_warhead_drop",
	"payload": "icon_warhead_drop",
	"arm-switch": "icon_warhead_drop",
	"battery": "icon_battery_pack",
	"battery_pack": "icon_battery_pack",
	"lipo-battery": "icon_battery_pack",
	"signal": "icon_signal_link",
	"signal_link": "icon_signal_link",
	"signal-wave-bar": "icon_signal_link",
	"wind": "icon_wind_sock",
	"wind_sock": "icon_wind_sock",
	"compass": "icon_compass_rose",
	"compass_rose": "icon_compass_rose",
	"altitude": "icon_altitude_ladder",
	"altitude_ladder": "icon_altitude_ladder",
	"tuning-sliders": "icon_altitude_ladder",
	"joystick": "icon_joystick_gimbal",
	"joystick_gimbal": "icon_joystick_gimbal",
	"radio-controller": "icon_joystick_gimbal",
	"target": "icon_target_tank",
	"target_tank": "icon_target_tank",
	"waypoint-lock": "icon_target_tank",
	"explosion": "icon_explosion_star",
	"explosion_star": "icon_explosion_star",
	"wing": "icon_wing_emblem",
	"wing_emblem": "icon_wing_emblem",
}

static var _base_textures: Dictionary = {}
static var _tinted_textures: Dictionary = {}
static var _cleanup_wired: bool = false


static func resolve_id(icon_id: String) -> String:
	var key := icon_id.strip_edges().to_lower()
	if key.ends_with(".svg"):
		key = key.substr(0, key.length() - 4)
	if key in ICON_IDS:
		return key
	if ALIASES.has(key):
		return String(ALIASES[key])
	return key


static func get_icon(icon_id: String, tint: Color = Color.WHITE) -> Texture2D:
	_ensure_cleanup_hook()
	var canonical := resolve_id(icon_id)
	var base_tex := _load_base_texture(canonical)
	if base_tex == null:
		return null
	if tint.is_equal_approx(Color.WHITE):
		return base_tex

	var cache_key := "%s|%s" % [canonical, tint.to_html(true)]
	var cached = _tinted_textures.get(cache_key)
	if cached is Texture2D:
		return cached as Texture2D

	var src_img := base_tex.get_image()
	if src_img == null or src_img.is_empty():
		return base_tex
	var img := src_img.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(h):
		for x in range(w):
			var px := img.get_pixel(x, y)
			if px.a > 0.001:
				img.set_pixel(x, y, Color(px.r * tint.r, px.g * tint.g, px.b * tint.b, px.a * tint.a))
	var out_tex := ImageTexture.create_from_image(img)
	_tinted_textures[cache_key] = out_tex
	return out_tex


static func _load_base_texture(canonical: String) -> Texture2D:
	var existing = _base_textures.get(canonical)
	if existing is Texture2D:
		return existing as Texture2D

	var res_path := ICON_DIR + canonical + ".svg"
	var tex: Texture2D = null

	# Prefer direct SVG rasterization from file if raw SVG exists (guarantees crisp
	# rendering even before .import files exist in headless / clean checkouts).
	if FileAccess.file_exists(res_path):
		var svg_text := FileAccess.get_file_as_string(res_path)
		if not svg_text.is_empty():
			var img := Image.new()
			if img.load_svg_from_string(svg_text, 2.0) == OK and not img.is_empty():
				tex = ImageTexture.create_from_image(img)

	# Fallback for exported .pck builds where .svg was converted into an imported resource.
	if tex == null and ResourceLoader.exists(res_path):
		var loaded := ResourceLoader.load(res_path)
		if loaded is Texture2D:
			tex = loaded as Texture2D

	if tex != null:
		_base_textures[canonical] = tex
	return tex


static func clear_cache() -> void:
	_base_textures.clear()
	_tinted_textures.clear()
	_cleanup_wired = false


static func _ensure_cleanup_hook() -> void:
	if _cleanup_wired:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null and not root.tree_exiting.is_connected(clear_cache):
			root.tree_exiting.connect(clear_cache, CONNECT_ONE_SHOT)
			_cleanup_wired = true
