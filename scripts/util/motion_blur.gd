class_name MotionBlur
extends CanvasLayer

## Screen-space motion blur driven by the FPV camera velocity.
##
## This is deliberately a canvas pass instead of a 3D post-process: it runs
## before the FPV analogue overlay and HUD, so the video grain, OSD and sticks
## stay perfectly sharp.  The ColorRect hides itself when the drone is still.

var _rect: ColorRect
var _material: ShaderMaterial
var _camera: Camera3D
var _prev_position := Vector3.ZERO
var _prev_forward := Vector3.FORWARD
var _smooth := 0.0
var _has_prev := false


func _ready() -> void:
	layer = 2
	_rect = ColorRect.new()
	_rect.name = "MotionBlurQuad"
	_rect.color = Color.WHITE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	var shader := load("res://shaders/motion_blur.gdshader") as Shader
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_rect.material = _material
	add_child(_rect)


func _process(delta: float) -> void:
	if _material == null:
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		_has_prev = false
		if _camera == null:
			return
	var pos := _camera.global_position
	var forward := -_camera.global_basis.z
	if not _has_prev:
		_prev_position = pos
		_prev_forward = forward
		_has_prev = true
		return
	var dt := maxf(delta, 0.0001)
	var velocity := (pos - _prev_position) / dt
	_prev_position = pos
	var rate := forward.angle_to(_prev_forward) / dt
	_prev_forward = forward

	var local_v := _camera.global_basis.inverse() * velocity
	var forward_speed := maxf(-local_v.z, 0.0)
	var lateral := Vector2(local_v.x, -local_v.y)
	var lateral_speed := lateral.length()
	var quality := float(QualityManager.get_value("motion_blur", 1.0))
	var target := clampf(forward_speed / 52.0, 0.0, 1.0) * 0.82
	target += clampf(lateral_speed / 24.0, 0.0, 1.0) * 0.30
	target += clampf(rate / 2.8, 0.0, 1.0) * 0.34
	target = clampf(target * quality, 0.0, 1.0)
	_smooth = lerpf(_smooth, target, 1.0 - exp(-7.0 * dt))
	_rect.visible = _smooth > 0.012
	if not _rect.visible:
		return
	var direction := Vector2.ZERO
	if lateral_speed > 0.4:
		direction = lateral.normalized() * clampf(lateral_speed / 18.0, 0.0, 1.0)
	_material.set_shader_parameter("strength", _smooth)
	_material.set_shader_parameter("screen_dir", direction)
	_material.set_shader_parameter("radial_amount", 0.55)
