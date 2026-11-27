extends Control
class_name HUD

const CinematicOverlay := preload("res://scripts/util/cinematic_overlay.gd")


enum Component {CROSSHAIR, STATUS, HEADING, SPEED, ALTITUDE, LADDER, STICKS, RPM}

# HUD components
@onready var ladder := $VBoxContainer/HBoxLadder/HUDLadder
@onready var speed_scale := $VBoxContainer/HBoxLadder/HUDSpeedScale
@onready var altitude_scale := $VBoxContainer/HBoxLadder/HUDAltitudeScale
@onready var heading_scale := $VBoxContainer/HUDHeadingScale
@onready var stick_left := $VBoxContainer/HBoxInput/HUDStickLeft
@onready var stick_right := $VBoxContainer/HBoxInput/HUDStickRight
@onready var rpm_table := $HUDRPM
@onready var status := $HUDStatus

# Flight data
var hud_timer := 0.1
var hud_delta := 0.0
var hud_position := Vector3.ZERO
var hud_angles := Vector3.ZERO
var hud_velocity := Vector3.ZERO
var hud_left_stick := Vector2.ZERO
var hud_right_stick := Vector2.ZERO
var hud_rpm := [0, 0, 0, 0]
var is_first := false
var first_angles := Vector3.ZERO
var _cinematic_rect: ColorRect = null
var _cinematic_mat: ShaderMaterial = null
var _no_sharpen := false
var _last_s3d := -1.0
var _last_res := Vector2(-1.0, -1.0)


func _ready() -> void:
	if has_node("Crosshair"):
		$Crosshair.visible = false
	if stick_left != null:
		stick_left.visible = false
	if stick_right != null:
		stick_right.visible = false
	reset_data()
	update_data(hud_delta, hud_position, hud_angles, hud_velocity, hud_left_stick, hud_right_stick, hud_rpm)
	# Light cinematic grade behind the HUD widgets on MEDIUM/HIGH.  On LOW we keep
	# 0 full-screen post-processing passes (pure forward).
	_no_sharpen = (DisplayServer.get_name() == "headless" or OS.has_environment("DRONE_NO_SHARPEN"))
	_cinematic_rect = CinematicOverlay.attach(self, 0.14, 0.010, 0.002, 0.0, 0.09, 1.04, 1.06, 0.03)
	if _cinematic_rect != null:
		_cinematic_rect.add_to_group("cinematic_overlay")
		_cinematic_mat = _cinematic_rect.material as ShaderMaterial
		if _cinematic_mat != null:
			_cinematic_mat.set_shader_parameter("enable_rcas", not _no_sharpen)
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and gfx.has_signal("quality_changed") and not gfx.is_connected("quality_changed", Callable(self, "_sync_cinematic_for_quality")):
		gfx.connect("quality_changed", Callable(self, "_sync_cinematic_for_quality"))
	_sync_cinematic_for_quality(QualityManager.get_active_level())


func _exit_tree() -> void:
	var gfx := get_node_or_null("/root/Graphics")
	if gfx != null and gfx.has_signal("quality_changed") and gfx.is_connected("quality_changed", Callable(self, "_sync_cinematic_for_quality")):
		gfx.disconnect("quality_changed", Callable(self, "_sync_cinematic_for_quality"))


func _sync_cinematic_for_quality(lvl: int) -> void:
	if _cinematic_rect != null and is_instance_valid(_cinematic_rect):
		_cinematic_rect.visible = (lvl > QualityManager.Level.LOW)
		if _cinematic_rect.visible:
			_sync_cinematic_rcas()


func _sync_cinematic_rcas() -> void:
	if _cinematic_mat == null or _no_sharpen:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var s3d := clampf(vp.scaling_3d_scale, 0.25, 1.0)
	var res := vp.get_visible_rect().size
	if absf(s3d - _last_s3d) > 0.002:
		_last_s3d = s3d
		_cinematic_mat.set_shader_parameter("render_scale_3d", s3d)
	if res != _last_res:
		_last_res = res
		_cinematic_mat.set_shader_parameter("resolution", res)


func _process(_delta: float) -> void:
	if _cinematic_rect != null and _cinematic_rect.visible:
		_sync_cinematic_rcas()
	if hud_delta >= hud_timer:
		hud_position /= hud_delta
		hud_angles /= hud_delta
		hud_velocity /= hud_delta
		hud_left_stick /= hud_delta
		hud_right_stick /= hud_delta
		for i in range(hud_rpm.size()):
			hud_rpm[i] /= hud_delta
		update_display()
		reset_data()


func show_component(component: int, show: bool = true) -> void:
	var self_only := false
	var mod := Color(1, 1, 1, 1)
	if not show:
		mod = Color(1, 1, 1, 0)
	var hud_component := []
	match component:
		Component.CROSSHAIR:
			hud_component.append($Crosshair)
		Component.STATUS:
			hud_component.append(status)
			if has_node("MarginContainer"):
				hud_component.append($MarginContainer)
		Component.HEADING:
			hud_component.append(heading_scale)
		Component.SPEED:
			hud_component.append(speed_scale)
		Component.ALTITUDE:
			hud_component.append(altitude_scale)
		Component.LADDER:
			for marker in ladder.pitch_markers:
				hud_component.append(marker)
		Component.STICKS:
			hud_component.append(stick_left)
			hud_component.append(stick_right)
			# These begin hidden in _ready(); modulate alone cannot reveal them.
			if stick_left != null:
				stick_left.visible = show
			if stick_right != null:
				stick_right.visible = show
		Component.RPM:
			hud_component.append(rpm_table)
	for comp in hud_component:
		if self_only:
			comp.self_modulate = mod
		else:
			comp.modulate = mod


func update_display() -> void:
	ladder.update_ladder(hud_angles.x, hud_angles.z)
	speed_scale.update_speed(hud_velocity.length(), hud_delta)
	altitude_scale.update_altitude(hud_position.y, hud_delta)
	heading_scale.update_heading(hud_angles.y, hud_delta)
	# Stick crosshairs are driven every frame by update_realtime_sticks(); updating
	# them here with the throttled/averaged values made them jitter.
	rpm_table.update_rpm(hud_rpm[0], hud_rpm[1], hud_rpm[2], hud_rpm[3])


func update_realtime_sticks(left: Vector2, right: Vector2) -> void:
	if stick_left != null and stick_left.visible:
		stick_left.update_stick_input(left)
	if stick_right != null and stick_right.visible:
		stick_right.update_stick_input(right)


func update_data(dt: float, position: Vector3, angles: Vector3, velocity: Vector3,
		left_stick: Vector2, right_stick: Vector2, rpm: Array) -> void:
	hud_delta += dt
	hud_position += dt * position
	if is_first:
		first_angles = angles
		is_first = false
	# Adjust angles to prevent averaging issues
	hud_angles += dt * get_adjusted_angles(angles)
	hud_velocity += dt * velocity
	hud_left_stick += dt * left_stick
	hud_right_stick += dt * right_stick
	for i in range(hud_rpm.size()):
		hud_rpm[i] += dt * rpm[i]


func update_flight_mode(mode: int) -> void:
	$MarginContainer/FlightMode.text = FlightController.mode_name(mode)


func reset_data() -> void:
	is_first = true
	first_angles = Vector3.ZERO
	hud_delta = 0.0
	hud_position = Vector3.ZERO
	hud_angles = Vector3.ZERO
	hud_velocity = Vector3.ZERO
	hud_left_stick = Vector2.ZERO
	hud_right_stick = Vector2.ZERO
	hud_rpm = [0, 0, 0, 0]


func get_adjusted_angles(angles: Vector3) -> Vector3:
	var result = angles
	var correction = 0
	
	for i in range(3):
		# Check sign changes by difference with PI as arbitrary threshold
		if abs(angles[i] - first_angles[i]) > PI:
			if first_angles[i] > 0:
				correction = 1
			else:
				correction = -1
			result[i] = angles[i] + 2 * PI * correction
	
	return result
