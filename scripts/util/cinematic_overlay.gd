extends RefCounted

## Cinematic finishing grade for the whole game.
##
## Adds one full-screen ColorRect using shaders/cinematic_overlay.gdshader and
## moves it to the back of the parent so every UI widget is drawn on top and
## stays pixel-sharp. The shader costs one screen fetch plus ALU - no extra
## render target, no second scene pass, identical cost on mobile and desktop.
##
## Two ways to use it:
##   attach(control, ...)  - grade a Control subtree (HUD, menus). Caller's
##                           widgets render after the rect at child index 0.
##   attach_canvas(layer, ...) - grade a CanvasLayer (gallery / replay).

const SHADER := preload("res://shaders/cinematic_overlay.gdshader")


static func is_active() -> bool:
	# Headless QA must stay deterministic; every real platform gets the grade.
	return DisplayServer.get_name() != "headless"


static func _make_material(vignette: float, grain: float, scanline: float,
		letterbox: float, leak: float, contrast: float, saturation: float,
		halation: float) -> ShaderMaterial:
	var shader := SHADER as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("grain_strength", grain)
	mat.set_shader_parameter("scanline_strength", scanline)
	mat.set_shader_parameter("letterbox", letterbox)
	mat.set_shader_parameter("light_leak", leak)
	mat.set_shader_parameter("contrast", contrast)
	mat.set_shader_parameter("saturation", saturation)
	mat.set_shader_parameter("halation", halation)
	var vp := Engine.get_main_loop() as SceneTree
	if vp != null and vp.root != null:
		mat.set_shader_parameter("resolution", Vector2(vp.root.size))
	return mat


static func attach(parent: Control, vignette: float = 0.30,
		grain: float = 0.012, scanline: float = 0.004,
		letterbox: float = 0.0, leak: float = 0.22,
		contrast: float = 1.10, saturation: float = 1.08,
		halation: float = 0.05) -> ColorRect:
	if parent == null or not is_active():
		return null
	var mat := _make_material(vignette, grain, scanline, letterbox, leak,
			contrast, saturation, halation)
	if mat == null:
		return null
	var rect := ColorRect.new()
	rect.name = "CinematicOverlay"
	rect.material = mat
	rect.color = Color(1, 1, 1, 1)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.focus_mode = Control.FOCUS_NONE
	parent.add_child(rect)
	parent.move_child(rect, 0)
	return rect


static func attach_canvas(layer: CanvasLayer, vignette: float = 0.38,
		grain: float = 0.016, scanline: float = 0.0,
		letterbox: float = 0.045, leak: float = 0.35,
		contrast: float = 1.12, saturation: float = 1.10,
		halation: float = 0.06) -> ColorRect:
	if layer == null or not is_active():
		return null
	var mat := _make_material(vignette, grain, scanline, letterbox, leak,
			contrast, saturation, halation)
	if mat == null:
		return null
	var rect := ColorRect.new()
	rect.name = "CinematicOverlay"
	rect.material = mat
	rect.color = Color(1, 1, 1, 1)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return rect
