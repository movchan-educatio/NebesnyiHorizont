## Recon UAV Kill-Cam Director (ported from ReconKillCamDirector.ts & KillCamViewport.tsx).
## Activates on key/final combat target destruction: positions an orbital recon drone
## camera at 85-115 m altitude / 120-150 m stand-off with physical speed-of-sound
## shockwave delay, optical zoom, RF scanlines, bilingual telemetry & 1-tap skip.
class_name ReconKillCamDirector
extends Node

const FpvIconsScript = preload("res://scripts/util/fpv_icons.gd")

signal kill_cam_finished()

const SPEED_OF_SOUND := 343.0
const SIGNAL_LOSS_SEC := 0.15
const RADIO_CONFIRM_SEC := 0.35
const AUTO_CLOSE_SEC := 3.8
const ORBIT_RAD_PER_SEC := 0.072
const FOV_START := 32.0
const FOV_END := 15.0

static var _rf_shader: Shader = null
static var _signal_loss_shader: Shader = null


static func _get_rf_shader() -> Shader:
	if _rf_shader != null:
		return _rf_shader
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float time_sec = 0.0;
uniform float jolt = 0.0;
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
void fragment() {
	vec2 uv = UV;
	float scan = sin(uv.y * 540.0 + time_sec * 18.0) * 0.5 + 0.5;
	float noise = hash21(floor(uv * vec2(260.0, 140.0)) + fract(time_sec * 17.3));
	vec2 d = uv - vec2(0.5);
	float vig = smoothstep(0.32, 0.78, dot(d, d) * 1.45);
	float band = smoothstep(0.92, 1.0, sin(uv.y * 14.0 - time_sec * 4.5));
	float alpha = vig * 0.42 + scan * 0.06 + (noise - 0.5) * (0.08 + jolt * 0.14) + band * (0.04 + jolt * 0.08);
	vec3 col = mix(vec3(0.05, 0.11, 0.10), vec3(0.70, 0.92, 0.85), clamp(noise * 0.45 + band, 0.0, 1.0));
	COLOR = vec4(col, clamp(alpha, 0.0, 0.65));
}
"""
	_rf_shader = sh
	return _rf_shader


static func _get_signal_loss_shader() -> Shader:
	if _signal_loss_shader != null:
		return _signal_loss_shader
	var static_sh := Shader.new()
	static_sh.code = """
shader_type canvas_item;
uniform float time_sec = 0.0;
float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}
void fragment() {
	vec2 grid = floor(UV * vec2(220.0, 128.0));
	float n = hash21(grid + fract(time_sec * 47.0));
	float bar = smoothstep(0.65, 1.0, sin(UV.y * 42.0 + time_sec * 65.0));
	float v = clamp(n * 0.85 + bar * 0.25, 0.06, 0.96);
	COLOR = vec4(v * 0.92, v, v * 0.94, 1.0);
}
"""
	_signal_loss_shader = static_sh
	return _signal_loss_shader


static func prewarm() -> void:
	_get_rf_shader()
	_get_signal_loss_shader()

var _active: bool = false
var _elapsed: float = 0.0
var _shockwave_delay: float = 0.42
var _shockwave_fired: bool = false
var _static_active: bool = false
var _radio_confirm_fired: bool = false
var _jolt_age: float = -1.0

var _impact_pos: Vector3 = Vector3.ZERO
var _orbit_radius: float = 135.0
var _altitude_offset: float = 98.0
var _orbit_angle: float = 0.0

var _level_root: Node3D = null
var _prev_cam: Camera3D = null
var _cam: Camera3D = null
var _env: Environment = null
var _orig_exposure: float = 1.0
var _on_finished: Callable = Callable()

var _hud_layer: CanvasLayer = null
var _flash_rect: ColorRect = null
var _rf_rect: ColorRect = null
var _rf_mat: ShaderMaterial = null
var _signal_loss_box: Control = null
var _signal_loss_rect: ColorRect = null
var _signal_loss_mat: ShaderMaterial = null
var _telemetry_lbl: Label = null
var _status_lbl: Label = null
var _acoustic_lbl: Label = null
var _skip_btn: Button = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_active() -> bool:
	return _active


func trigger(level_root: Node3D, impact_pos: Vector3, drone_pos: Vector3 = Vector3.ZERO,
		prev_cam: Camera3D = null, on_finished: Callable = Callable()) -> bool:
	if _active:
		cancel()
	if level_root == null or not is_instance_valid(level_root):
		return false

	_level_root = level_root
	_impact_pos = impact_pos
	_on_finished = on_finished
	_prev_cam = prev_cam if (prev_cam != null and is_instance_valid(prev_cam)) else get_viewport().get_camera_3d()

	_orbit_radius = randf_range(120.0, 150.0)
	_altitude_offset = randf_range(85.0, 115.0)
	var base_dir := Vector2(drone_pos.x - impact_pos.x, drone_pos.z - impact_pos.z)
	if base_dir.length_squared() < 1.0:
		base_dir = Vector2(0.4, 0.9)
	_orbit_angle = _pick_unobstructed_azimuth(atan2(base_dir.y, base_dir.x))

	_cam = Camera3D.new()
	_cam.name = "ReconKillCam"
	_cam.fov = FOV_START
	_cam.near = 1.0
	_cam.far = 1600.0
	_level_root.add_child(_cam)
	_update_camera_pose(0.0)
	if DisplayServer.get_name() != "headless":
		_cam.current = true

	var slant := _cam.global_position.distance_to(_impact_pos)
	_shockwave_delay = clampf(slant / SPEED_OF_SOUND, 0.25, 0.72)
	_shockwave_fired = false
	_static_active = true
	_radio_confirm_fired = false
	_jolt_age = -1.0
	_elapsed = 0.0
	_active = true

	# Temporary optical impact flash exposure boost on WorldEnvironment
	var world_env := _level_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		_env = world_env.environment
		_orig_exposure = _env.tonemap_exposure
		_env.tonemap_exposure = _orig_exposure

	if DisplayServer.get_name() != "headless":
		_build_hud()
		var audio := get_node_or_null("/root/Audio")
		if audio != null and audio.has_method("play_signal_loss_static"):
			audio.call("play_signal_loss_static", 0.16, -5.0)
	return true


func _pick_unobstructed_azimuth(preferred: float) -> float:
	if _level_root == null or not _level_root.is_inside_tree():
		return preferred
	var space := _level_root.get_world_3d().direct_space_state if _level_root.get_world_3d() != null else null
	if space == null:
		return preferred
	var target := _impact_pos + Vector3.UP * 2.0
	for step in range(6):
		var ang := preferred + float(step) * (TAU / 6.0)
		var cand := Vector3(
			_impact_pos.x + cos(ang) * _orbit_radius,
			_impact_pos.y + _altitude_offset,
			_impact_pos.z + sin(ang) * _orbit_radius
		)
		var query := PhysicsRayQueryParameters3D.create(cand, target)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return ang
	return preferred


func _build_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "ReconKillCamHUD"
	_hud_layer.layer = 96
	_hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud_layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if _elapsed < 0.20:
			return
		if (ev is InputEventMouseButton and ev.pressed) or (ev is InputEventScreenTouch and ev.pressed):
			cancel()
	)
	_hud_layer.add_child(root)

	# Lightweight tactical RF static + scanlines + vignette shader
	_rf_rect = ColorRect.new()
	_rf_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rf_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rf_mat = ShaderMaterial.new()
	_rf_mat.shader = _get_rf_shader()
	_rf_rect.material = _rf_mat
	root.add_child(_rf_rect)

	# Optical impact flash overlay
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(1.0, 0.94, 0.80, 0.36)
	root.add_child(_flash_rect)

	var safe_pad := _safe_margins()
	var is_en := Loc.get_language() == Loc.Language.EN

	# Top banner & coordinates telemetry
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = safe_pad.x + 24.0
	top_bar.offset_right = -(safe_pad.z + 24.0)
	top_bar.offset_top = safe_pad.y + 18.0
	top_bar.offset_bottom = safe_pad.y + 84.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_bar)

	_status_lbl = Label.new()
	_status_lbl.text = "● REC  UAV-RECON // OPTICAL FEED" if is_en else "● ЗАПИС  БПЛА РОЗВІДКИ // КАМЕРА"
	_status_lbl.add_theme_font_size_override("font_size", 18)
	_status_lbl.add_theme_color_override("font_color", Color(0.98, 0.35, 0.30, 0.96))
	_status_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_status_lbl.add_theme_constant_override("outline_size", 4)
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_status_lbl)

	_telemetry_lbl = Label.new()
	_telemetry_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_telemetry_lbl.add_theme_font_size_override("font_size", 16)
	_telemetry_lbl.add_theme_color_override("font_color", Color(0.84, 0.97, 0.90, 0.96))
	_telemetry_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_telemetry_lbl.add_theme_constant_override("outline_size", 4)
	top_bar.add_child(_telemetry_lbl)

	# Center reticle overlay (FpvIcons crosshair SVG + corner brackets)
	var center_box := CenterContainer.new()
	center_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_box)

	var reticle_tex := FpvIconsScript.get_icon("icon_crosshair", Color(0.75, 0.98, 0.86, 0.85))
	if reticle_tex != null:
		var reticle := TextureRect.new()
		reticle.texture = reticle_tex
		reticle.custom_minimum_size = Vector2(96, 96)
		reticle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center_box.add_child(reticle)

	# Bottom telemetry + prominent skip button
	var bottom_vb := VBoxContainer.new()
	bottom_vb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_vb.offset_left = safe_pad.x + 24.0
	bottom_vb.offset_right = -(safe_pad.z + 24.0)
	bottom_vb.offset_top = -(safe_pad.w + 132.0)
	bottom_vb.offset_bottom = -(safe_pad.w + 22.0)
	bottom_vb.alignment = BoxContainer.ALIGNMENT_END
	bottom_vb.add_theme_constant_override("separation", 10)
	bottom_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_vb)

	_acoustic_lbl = Label.new()
	_acoustic_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_acoustic_lbl.text = "ACOUSTIC WAVE: INBOUND..." if is_en else "УДАРНА ХВИЛЯ: НАБЛИЖЕННЯ..."
	_acoustic_lbl.add_theme_font_size_override("font_size", 16)
	_acoustic_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35, 0.96))
	_acoustic_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_acoustic_lbl.add_theme_constant_override("outline_size", 4)
	bottom_vb.add_child(_acoustic_lbl)

	var btn_center := CenterContainer.new()
	btn_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_vb.add_child(btn_center)

	_skip_btn = Button.new()
	_skip_btn.text = "SKIP [ SPACE / TAP ]" if is_en else "ПРОПУСТИТИ [ ПРОБІЛ / ТАП ]"
	_skip_btn.custom_minimum_size = Vector2(290, 48)
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.add_theme_font_size_override("font_size", 17)
	_skip_btn.add_theme_color_override("font_color", Color(0.96, 0.98, 0.95))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.12, 0.10, 0.86)
	sb.border_color = Color(0.95, 0.72, 0.22, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_skip_btn.add_theme_stylebox_override("normal", sb)
	_skip_btn.add_theme_stylebox_override("hover", sb)
	_skip_btn.add_theme_stylebox_override("pressed", sb)
	_skip_btn.pressed.connect(cancel)
	btn_center.add_child(_skip_btn)

	# 150 ms white-noise RF signal-loss freeze frame before orbital recon snap.
	_signal_loss_box = Control.new()
	_signal_loss_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_signal_loss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_signal_loss_box)

	_signal_loss_rect = ColorRect.new()
	_signal_loss_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_signal_loss_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signal_loss_mat = ShaderMaterial.new()
	_signal_loss_mat.shader = _get_signal_loss_shader()
	_signal_loss_rect.material = _signal_loss_mat
	_signal_loss_box.add_child(_signal_loss_rect)

	var loss_center := CenterContainer.new()
	loss_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loss_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_signal_loss_box.add_child(loss_center)

	var loss_panel := PanelContainer.new()
	loss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.03, 0.04, 0.05, 0.88)
	lsb.border_color = Color(0.95, 0.28, 0.22, 0.95)
	lsb.set_border_width_all(2)
	lsb.set_corner_radius_all(6)
	lsb.content_margin_left = 26
	lsb.content_margin_right = 26
	lsb.content_margin_top = 12
	lsb.content_margin_bottom = 12
	loss_panel.add_theme_stylebox_override("panel", lsb)
	loss_center.add_child(loss_panel)

	var loss_lbl := Label.new()
	loss_lbl.text = "VIDEO SIGNAL LOST" if is_en else "ВТРАТА ВІДЕОСИГНАЛУ"
	loss_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loss_lbl.add_theme_font_size_override("font_size", 24)
	loss_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.92))
	loss_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	loss_lbl.add_theme_constant_override("outline_size", 5)
	loss_panel.add_child(loss_lbl)

	_refresh_telemetry_label()


func _safe_margins() -> Vector4:
	# Returns Vector4(left, top, right, bottom) inset margins from DisplayServer safe area.
	var vs := Vector2(1280, 720)
	if get_viewport() != null:
		vs = get_viewport().get_visible_rect().size
	var win_size := Vector2(DisplayServer.window_get_size())
	if win_size.x < 2.0 or win_size.y < 2.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var sx := vs.x / win_size.x
	var sy := vs.y / win_size.y
	return Vector4(
		maxf(0.0, float(safe.position.x) * sx),
		maxf(0.0, float(safe.position.y) * sy),
		maxf(0.0, (win_size.x - float(safe.end.x)) * sx),
		maxf(0.0, (win_size.y - float(safe.end.y)) * sy)
	)


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	if _elapsed >= AUTO_CLOSE_SEC:
		cancel()
		return

	if _elapsed < SIGNAL_LOSS_SEC:
		if _signal_loss_mat != null:
			_signal_loss_mat.set_shader_parameter("time_sec", _elapsed)
		if _flash_rect != null:
			_flash_rect.color.a = 0.0
		return

	if _static_active:
		_static_active = false
		if _signal_loss_box != null and is_instance_valid(_signal_loss_box):
			_signal_loss_box.visible = false
		if _flash_rect != null:
			_flash_rect.color.a = 0.36
		if _env != null and is_instance_valid(_env):
			_env.tonemap_exposure = _orig_exposure + 0.42

	var optical_age := maxf(_elapsed - SIGNAL_LOSS_SEC, 0.0)
	_update_camera_pose(delta)

	if not _radio_confirm_fired and _elapsed >= RADIO_CONFIRM_SEC:
		_radio_confirm_fired = true
		var audio_node := get_node_or_null("/root/Audio")
		if audio_node != null and audio_node.has_method("play_radio_confirm_beep"):
			audio_node.call("play_radio_confirm_beep", -7.0)

	if not _shockwave_fired and _elapsed >= SIGNAL_LOSS_SEC + _shockwave_delay:
		_shockwave_fired = true
		_jolt_age = 0.0
		var audio := get_node_or_null("/root/Audio")
		if audio != null and audio.has_method("play_recon_shockwave"):
			audio.call("play_recon_shockwave", -3.5)
		if _acoustic_lbl != null:
			var is_en := Loc.get_language() == Loc.Language.EN
			_acoustic_lbl.text = ("SHOCKWAVE IMPACT (+%.2fs)" % _shockwave_delay) if is_en else ("ЗВУК ВИБУХУ (+%.2f с)" % _shockwave_delay)
			_acoustic_lbl.add_theme_color_override("font_color", Color(0.55, 0.96, 0.65, 0.96))

	if _jolt_age >= 0.0:
		_jolt_age += delta

	if _env != null and is_instance_valid(_env):
		var flash_decay := exp(-optical_age * 4.5)
		_env.tonemap_exposure = _orig_exposure + 0.42 * flash_decay

	if _flash_rect != null:
		_flash_rect.color.a = 0.36 * exp(-optical_age * 5.2)

	if _rf_mat != null:
		_rf_mat.set_shader_parameter("time_sec", _elapsed)
		var jolt_amt := exp(-_jolt_age * 5.0) if (_jolt_age >= 0.0 and _jolt_age < 0.7) else 0.0
		_rf_mat.set_shader_parameter("jolt", jolt_amt)

	_refresh_telemetry_label()


func _update_camera_pose(delta: float) -> void:
	if _cam == null or not is_instance_valid(_cam):
		return
	_orbit_angle += ORBIT_RAD_PER_SEC * delta
	var drift_y := sin(_elapsed * 1.1) * 1.4
	var pos := Vector3(
		_impact_pos.x + cos(_orbit_angle) * _orbit_radius,
		_impact_pos.y + _altitude_offset + drift_y,
		_impact_pos.z + sin(_orbit_angle) * _orbit_radius
	)
	_cam.global_position = pos
	var aim := _impact_pos + Vector3.UP * 1.4
	_cam.look_at(aim, Vector3.UP)

	# Smooth optical zoom: 32 deg -> 15 deg
	var zt := clampf(_elapsed / 2.4, 0.0, 1.0)
	var ease_z := 1.0 - pow(1.0 - zt, 2.2)
	_cam.fov = lerpf(FOV_START, FOV_END, ease_z)

	# Subtle gimbal jitter + damped acoustic shockwave tremor
	var gx := sin(_elapsed * 7.3) * 0.0022 + cos(_elapsed * 11.7) * 0.0014
	var gy := cos(_elapsed * 6.1) * 0.0025 + sin(_elapsed * 13.1) * 0.0012
	if _jolt_age >= 0.0 and _jolt_age < 0.75:
		var tremor := exp(-_jolt_age * 5.8) * sin(_jolt_age * 38.0)
		gx += tremor * 0.022
		gy += exp(-_jolt_age * 6.4) * cos(_jolt_age * 31.0) * 0.016
	_cam.rotate_object_local(Vector3.RIGHT, gx)
	_cam.rotate_object_local(Vector3.UP, gy)


func _refresh_telemetry_label() -> void:
	if _telemetry_lbl == null or _cam == null:
		return
	var slant := _cam.global_position.distance_to(_impact_pos)
	var zoom_x := FOV_START / maxf(_cam.fov, 1.0)
	var alt := maxf(_cam.global_position.y - _impact_pos.y, 0.0)
	var lat := 48.5012 + _impact_pos.z * 0.00001
	var lon := 37.9844 + _impact_pos.x * 0.000014
	var is_en := Loc.get_language() == Loc.Language.EN
	if is_en:
		_telemetry_lbl.text = "COORD %.4fN %.4fE\nALT %dm  DIST %dm  ZOOM %.1fx" % [
			lat, lon, int(round(alt)), int(round(slant)), zoom_x
		]
	else:
		_telemetry_lbl.text = "КООРД %.4fN %.4fE\nВИС %dм  ВІДСТ %dм  ЗУМ %.1fx" % [
			lat, lon, int(round(alt)), int(round(slant)), zoom_x
		]


func _input(event: InputEvent) -> void:
	if not _active or _elapsed < 0.18:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if kc == KEY_SPACE or kc == KEY_ENTER or kc == KEY_KP_ENTER or kc == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancel()


func cancel() -> void:
	if not _active:
		return
	_active = false
	_cleanup_resources()
	var cb := _on_finished
	_on_finished = Callable()
	kill_cam_finished.emit()
	if cb.is_valid():
		cb.call()


func _cleanup_resources() -> void:
	if _env != null and is_instance_valid(_env):
		_env.tonemap_exposure = _orig_exposure
	_env = null

	if _prev_cam != null and is_instance_valid(_prev_cam) and DisplayServer.get_name() != "headless":
		_prev_cam.current = true
	_prev_cam = null

	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null

	if _hud_layer != null and is_instance_valid(_hud_layer):
		_hud_layer.queue_free()
	_hud_layer = null
	_rf_rect = null
	_rf_mat = null
	_signal_loss_box = null
	_signal_loss_rect = null
	_signal_loss_mat = null
	_flash_rect = null
	_telemetry_lbl = null
	_status_lbl = null
	_acoustic_lbl = null
	_skip_btn = null


func _exit_tree() -> void:
	_active = false
	_on_finished = Callable()
	_cleanup_resources()
