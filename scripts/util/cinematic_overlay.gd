extends RefCounted

## Mobile-only cinematic screen grade.  Adds one full-screen ColorRect using
## shaders/cinematic_overlay.gdshader and moves it to the back of the parent so
## UI widgets are drawn on top of it.  No-op on desktop and in headless QA.

const SHADER := preload("res://shaders/cinematic_overlay.gdshader")


static func is_active() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


static func attach(parent: Control, vignette: float = 0.32,
		grain: float = 0.010, scanline: float = 0.010) -> ColorRect:
	if parent == null or not is_active():
		return null
	if DisplayServer.get_name() == "headless":
		return null
	var shader := SHADER as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("vignette_strength", vignette)
	mat.set_shader_parameter("grain_strength", grain)
	mat.set_shader_parameter("scanline_strength", scanline)
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
