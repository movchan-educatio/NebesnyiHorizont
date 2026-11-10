extends Node3D
class_name FlightController


enum Controller {YAW, ROLL, PITCH, YAW_SPEED, ROLL_SPEED, PITCH_SPEED,
		ALTITUDE, POS_X, POS_Z, VERTICAL_SPEED, FORWARD_SPEED, LATERAL_SPEED,
		LAUNCH}
enum FlightMode {RATE, LEVEL, SPEED, TRACK, LAUNCH, TURTLE, AUTO, HORIZON}
enum ArmFail {THROTTLE_HIGH, CRASH_RECOVERY_MODE}


signal armed(mode)
signal disarmed
signal arm_failed(reason)
signal flight_mode_changed(mode)


var time := 0.0
var dt := 0.0
var pos := Vector3(0, 0, 0)
var pos_prev := pos
var angles := Vector3(0, 0, 0)
var angles_prev := angles
var lin_vel := Vector3(0, 0, 0)
var local_vel := Vector3(0, 0, 0)
var ang_vel := Vector3(0, 0, 0)
var attitude := Basis()
var basis_prev := attitude
var basis_flat := attitude

var motors := []
var hover_thrust := 0.0
var input := [0, 0, 0, 0]

## In propeller-physics mode, stick position is a thrust request, not a linear
## motor-speed command. The drone supplies its current maximum TWR (including
## battery sag) so the curve can map requested thrust back to normalized RPM.
var throttle_curve_enabled := false
var throttle_max_twr := 8.5
var throttle_hover_point := 0.45

var control_profile = null

var state_armed := false: set = set_armed

var pid_controllers := []

var flight_mode: int = FlightMode.RATE

@export var pid_roll_p := 75.0 # (float, 0.0, 1000.0)
@export var pid_roll_i := 30.0 # (float, 0.0, 1000.0)
@export var pid_roll_d := 45.0 # (float, 0.0, 1000.0)
@export var pid_pitch_p := 75.0 # (float, 0.0, 1000.0)
@export var pid_pitch_i := 30.0 # (float, 0.0, 1000.0)
@export var pid_pitch_d := 45.0 # (float, 0.0, 1000.0)
@export var pid_yaw_p := 70.0 # (float, 0.0, 1000.0)
@export var pid_yaw_i := 90.0 # (float, 0.0, 1000.0)
@export var pid_yaw_d := 40.0 # (float, 0.0, 1000.0)
var pid_scale_p := 0.001
var pid_scale_i := 0.0005
var pid_scale_d := 0.0002

# --- Betaflight 4.5 rate-loop extras ---------------------------------------
## TPA starts cutting P/D above this throttle (Betaflight default 65%).
@export var tpa_breakpoint := 0.65
## Fraction of P/D removed at full throttle.
@export var tpa_rate := 0.55
## D at rest is this fraction of the full D term (D-Min).
@export var d_min_ratio := 0.40
## Setpoint acceleration (deg/s^2) that brings D-Min to full D.
@export var d_min_boost_range := 30000.0
## Anti-Gravity multiplies I by up to (1 + this) on a throttle punch.
@export var anti_gravity_gain := 2.0
## Feedforward gain per deg/s of setpoint change.
@export var ff_gain := 0.005
@export var ff_limit := 0.15

# --- HORIZON mode ------------------------------------------------------------
## Stick position beyond this value switches the axis from angle-hold to pure
## rate (acro) mode, allowing flips while keeping self-level near centre.
@export var horizon_threshold := 0.70 # (float, 0.5, 1.0)
## Maximum bank angle used by the angle-hold part of HORIZON.
@export var horizon_bank_deg := 45.0 # (float, 5.0, 90.0)

var _bf_base_kp: Array[float] = []
var _bf_base_ki: Array[float] = []
var _bf_base_kd: Array[float] = []
var _bf_prev_setpoint: Array[float] = []
var _bf_prev_throttle := 0.0
## Slow attitude trim for LEVEL/HORIZON.  Heavy combat airframes carry the
## battery/warhead below the frame, so their centre of mass is a few cm behind
## the geometric centre.  Collective thrust then produces a constant nose-down
## torque; a pure P/rate angle loop settles at a few degrees of forward tilt,
## which reads as "throttle makes the drone fly forward".  This integrator
## learns only while the pitch stick is centred, so a deliberate dive/climb is
## not cancelled, and removes the steady CG bias over ~1-2 s.
var _level_pitch_trim := 0.0
## Set by Drone each physics frame.  The trim integrator is disabled on the
## ground so a slope/landing-gear tilt cannot wind up a permanent offset.
var on_ground := false
const LEVEL_TRIM_GAIN := 1.5
const LEVEL_TRIM_LIMIT := 0.16
const LEVEL_TRIM_STICK_GATE := 0.08

var telemetry_file: FileAccess = null
@export var b_telemetry := false

@onready var debug_geom := get_tree().root.get_node_or_null("Level/DebugGeometry")


func _ready() -> void:
	for _i in range(Controller.size()):
		pid_controllers.append(PID.new())
		add_child(pid_controllers[-1])
	
	pid_controllers[Controller.ALTITUDE].set_coefficients(300 * pid_scale_p, 300 * pid_scale_i, 800 * pid_scale_d)
	pid_controllers[Controller.ALTITUDE].set_clamp_limits(0.3, 0.7)
	pid_controllers[Controller.VERTICAL_SPEED].set_coefficients(200 * pid_scale_p, 600 * pid_scale_i, 200 * pid_scale_d)
	pid_controllers[Controller.VERTICAL_SPEED].set_clamp_limits(0.1, 1)
	pid_controllers[Controller.ROLL].set_coefficients(50 * pid_scale_p, 30 * pid_scale_i, 120 * pid_scale_d)
	pid_controllers[Controller.ROLL].set_clamp_limits(-0.025, 0.025)
	pid_controllers[Controller.PITCH].set_coefficients(50 * pid_scale_p, 30 * pid_scale_i, 120 * pid_scale_d)
	pid_controllers[Controller.PITCH].set_clamp_limits(-0.025, 0.025)
	
	# Clamp limits for speed controllers are equal to the maximum pitch/roll angle
	var max_angle = deg_to_rad(35)
	pid_controllers[Controller.FORWARD_SPEED].set_coefficients(50 * pid_scale_p, 50 * pid_scale_i, 1 * pid_scale_d)
	pid_controllers[Controller.FORWARD_SPEED].set_clamp_limits(-max_angle, max_angle)
	pid_controllers[Controller.LATERAL_SPEED].set_coefficients(50 * pid_scale_p, 50 * pid_scale_i, 1 * pid_scale_d)
	pid_controllers[Controller.LATERAL_SPEED].set_clamp_limits(-max_angle, max_angle)
	
	pid_controllers[Controller.YAW_SPEED].set_coefficients(pid_scale_p * pid_yaw_p, pid_scale_i * pid_yaw_i, pid_scale_d * pid_yaw_d)
	pid_controllers[Controller.YAW_SPEED].set_clamp_limits(-0.6, 0.6)
	pid_controllers[Controller.ROLL_SPEED].set_coefficients(pid_scale_p * pid_roll_p, pid_scale_i * pid_roll_i, pid_scale_d * pid_roll_d)
	pid_controllers[Controller.ROLL_SPEED].set_clamp_limits(-0.6, 0.6)
	pid_controllers[Controller.PITCH_SPEED].set_coefficients(pid_scale_p * pid_pitch_p, pid_scale_i * pid_pitch_i, pid_scale_d * pid_pitch_d)
	pid_controllers[Controller.PITCH_SPEED].set_clamp_limits(-0.6, 0.6)
	
	pid_controllers[Controller.POS_X].set_coefficients(0.5, 0.05, 0.3)
	pid_controllers[Controller.POS_X].set_clamp_limits(-0.5, 0.5)
	pid_controllers[Controller.POS_Z].set_coefficients(0.5, 0.05, 0.3)
	pid_controllers[Controller.POS_Z].set_clamp_limits(-0.5, 0.5)
	pid_controllers[Controller.YAW].set_coefficients(50 * pid_scale_p, 20 * pid_scale_i, 100 * pid_scale_d)
	pid_controllers[Controller.YAW].set_clamp_limits(-0.5, 0.5)
	
	pid_controllers[Controller.LAUNCH].set_coefficients(700 * pid_scale_p, 300 * pid_scale_i, 700 * pid_scale_d)
	pid_controllers[Controller.LAUNCH].set_clamp_limits(-0.5, 0)
	
	_capture_bf_base()
	var _discard = connect("flight_mode_changed", Callable(get_parent(), "_on_flight_mode_changed"))
	# Default to ANGLE/LEVEL: self-levelling and a gentle bank limit are what
	# makes the first flight feel like a consumer camera drone instead of a
	# twitchy racing quad.  Acro remains one M-key press away.  If the player
	# disabled Angle in settings, start in the other enabled mode instead.
	change_flight_mode(resolve_flight_mode(FlightMode.LEVEL))
	
	if b_telemetry:
		if FileAccess.file_exists("user://telemetry.csv"):
			DirAccess.remove_absolute("user://telemetry.csv")


func _physics_process(_delta: float) -> void:
	if (flight_mode == FlightMode.LEVEL or flight_mode == FlightMode.SPEED \
			or flight_mode == FlightMode.TRACK) and not is_flight_safe():
		change_flight_mode(FlightMode.AUTO)
	elif flight_mode == FlightMode.LAUNCH and (angles.x < deg_to_rad(-80) or angles.x > deg_to_rad(10)):
		_on_disarm_input()

	if flight_mode == FlightMode.TRACK:
		if debug_geom:
			debug_geom.draw_debug_cube(0.02, get_tracking_target(), Vector3(0.2, 0.2, 0.2))

	if b_telemetry:
		write_telemetry()


func set_control_profile(profile: ControlProfile) -> void:
	control_profile = profile


func configure_throttle_curve(enabled: bool, max_twr: float,
		hover_point: float = 0.45) -> void:
	throttle_curve_enabled = enabled
	throttle_max_twr = maxf(max_twr, 1.0)
	throttle_hover_point = clampf(hover_point, 0.1, 0.9)


## Convert a pilot throttle request into motor PWM. Propeller thrust is roughly
## proportional to RPM squared, so an inverse square-root curve makes the
## configured hover point produce 1 g instead of an uncontrolled climb.
func throttle_to_motor_pwm(throttle: float) -> float:
	var stick := clampf(throttle, 0.0, 1.0)
	if not throttle_curve_enabled:
		return stick

	var requested_twr: float
	if stick <= throttle_hover_point:
		requested_twr = stick / throttle_hover_point
	else:
		var climb_fraction := (stick - throttle_hover_point) / (1.0 - throttle_hover_point)
		requested_twr = lerpf(1.0, throttle_max_twr, clampf(climb_fraction, 0.0, 1.0))
	return sqrt(clampf(requested_twr / throttle_max_twr, 0.0, 1.0))


## Scale PID controller parameters according to drone mass and inertia.
## Heavier / higher-inertia drones (e.g. 4 kg combat bomber) need
## disproportionately stronger P and D to achieve the same rate response.
func update_pid_for_inertia(drone_inertia: Vector3, drone_mass: float) -> void:
	# Mass-driven scaling: heavier drones get stronger gains. Exponent 0.65
	# grows faster than sqrt, so a 4 kg drone gets ~3.5× instead of 2.5×.
	var mass_scale := clampf(pow(drone_mass / 0.60, 0.65), 0.8, 4.0)
	# Inertia-driven scaling: high yaw/pitch inertia needs extra D to damp
	# the pendulum effect of a combat payload hanging below the frame.
	var inertia_sum := drone_inertia.x + drone_inertia.y + drone_inertia.z
	var inertia_scale := clampf(pow(inertia_sum / 0.02, 0.33), 1.0, 1.6)
	var scale_factor := clampf(mass_scale * inertia_scale, 0.8, 5.0)
	# A heavy payload slung under the frame gives the drone a permanent
	# pitch/roll trim torque.  P alone leaves a steady rate error, so the quad
	# slowly noses over with centred sticks.  Scale I much harder with mass so
	# the trim is learned in a fraction of a second instead of many seconds.
	var i_boost := clampf(pow(drone_mass / 0.60, 1.5), 1.0, 16.0)
	var kp_scaled := pid_scale_p * pid_roll_p * scale_factor
	var ki_scaled := pid_scale_i * pid_roll_i * scale_factor * i_boost
	var kd_scaled := pid_scale_d * pid_roll_d * scale_factor
	
	if pid_controllers.size() > Controller.PITCH_SPEED:
		pid_controllers[Controller.ROLL_SPEED].set_coefficients(kp_scaled, ki_scaled, kd_scaled)
		pid_controllers[Controller.PITCH_SPEED].set_coefficients(kp_scaled, ki_scaled, kd_scaled)
		pid_controllers[Controller.YAW_SPEED].set_coefficients(kp_scaled * 1.3, ki_scaled * 1.5, kd_scaled * 0.8)
	_capture_bf_base()


## Store the current PID gains as the "full" Betaflight values.  D-Min and
## TPA scale these per iteration without destroying the tuned base.
func _capture_bf_base() -> void:
	_bf_base_kp.resize(pid_controllers.size())
	_bf_base_ki.resize(pid_controllers.size())
	_bf_base_kd.resize(pid_controllers.size())
	_bf_prev_setpoint.resize(pid_controllers.size())
	for i in range(pid_controllers.size()):
		_bf_base_kp[i] = pid_controllers[i].kp
		_bf_base_ki[i] = pid_controllers[i].ki
		_bf_base_kd[i] = pid_controllers[i].kd


func _reset_bf_state() -> void:
	for i in range(_bf_prev_setpoint.size()):
		_bf_prev_setpoint[i] = 0.0
	_bf_prev_throttle = 0.0


## Betaflight rate curve with a fallback to the original expo curve.
func _rate_for_axis(axis: int, stick: float) -> float:
	if control_profile != null and control_profile.has_method("get_axis_rate"):
		return deg_to_rad(control_profile.get_axis_rate(axis, stick))
	var s := clampf(stick, -1.0, 1.0)
	var rate := 667.0
	var expo := 0.2
	return deg_to_rad(((1.0 - expo) * s + expo * s * s * s) * rate)


## One Betaflight PID iteration: TPA + D-Min + Anti-Gravity + Feedforward.
## `ag` is computed once per control tick so all axes see the same throttle
## punch (otherwise the first axis would consume the delta).
func _betaflight_pid(index: int, setpoint: float, measurement: float,
		delta: float, throttle: float, ag: float) -> float:
	if index >= pid_controllers.size() or index >= _bf_base_kp.size():
		return 0.0
	var pid: PID = pid_controllers[index]
	var base_kp: float = _bf_base_kp[index]
	var base_ki: float = _bf_base_ki[index]
	var base_kd: float = _bf_base_kd[index]
	var sp_prev: float = _bf_prev_setpoint[index]
	var sp_delta: float = setpoint - sp_prev
	_bf_prev_setpoint[index] = setpoint
	var sp_accel: float = absf(sp_delta) / maxf(delta, 0.00001)

	# TPA: P and D fade above 65% throttle to stop high-frequency chatter.
	var tpa := 1.0
	if throttle > tpa_breakpoint:
		var t := clampf((throttle - tpa_breakpoint) / maxf(1.0 - tpa_breakpoint, 0.001), 0.0, 1.0)
		tpa = 1.0 - tpa_rate * t

	# D-Min: low D when sticks are still, full D on a sharp flip.
	var boost := clampf(sp_accel / maxf(d_min_boost_range, 1.0), 0.0, 1.0)
	var kd := lerpf(base_kd * d_min_ratio, base_kd, boost) * tpa

	pid.kp = base_kp * tpa
	pid.ki = base_ki * ag
	pid.kd = kd
	# The PID loop must track the commanded angular rate while the stick is
	# held.  Without this assignment, only feedforward reacts to stick changes
	# and the drone stops responding as soon as the stick settles.
	pid.set_target(setpoint)
	var out := pid.get_output(measurement, delta, false)

	# Feedforward reacts to the stick before the integral winds up.
	out += clampf(sp_delta * ff_gain, -ff_limit, ff_limit)
	return clampf(out, pid.clamp_low, pid.clamp_high)


func _can_arm() -> bool:
	if state_armed:
		return false
	if input.size() > 0 and input[0] > 0.15:
		return false
	return true


func request_arm(force: bool = false) -> bool:
	if state_armed:
		return true
	if not force and not _can_arm():
		if input.size() > 0 and input[0] > 0.15:
			emit_signal("arm_failed", ArmFail.THROTTLE_HIGH)
		else:
			emit_signal("arm_failed", ArmFail.CRASH_RECOVERY_MODE)
		return false
	if flight_mode == FlightMode.AUTO:
		select_flight_mode(FlightMode.RATE)
	# Mobile only: arming must not change the flight mode.  The old code
	# switched to TURTLE/LAUNCH whenever either action happened to be held (for
	# example a radio AUX switch or a synthetic touch event), so pressing ARM
	# appeared to flip the mode and the drone fell over in TURTLE.  The desktop
	# build keeps its existing arm-in-turtle/launch behaviour.
	if not MenuUI.is_mobile_ui():
		if Input.is_action_pressed("mode_turtle"):
			change_flight_mode(FlightMode.TURTLE)
		elif Input.is_action_pressed("mode_launch"):
			change_flight_mode(FlightMode.LAUNCH)
	set_armed(true)
	for controller in pid_controllers:
		controller.set_disabled(false)
	return true


func request_disarm() -> void:
	set_armed(false)
	_level_pitch_trim = 0.0
	if flight_mode == FlightMode.TURTLE or flight_mode == FlightMode.LAUNCH:
		select_flight_mode(FlightMode.RATE)
	for controller in pid_controllers:
		controller.set_disabled(true)
		controller.reset()
	_reset_bf_state()


func _on_arm_input() -> void:
	request_arm()


func _on_disarm_input() -> void:
	request_disarm()


func set_armed(arm: bool) -> void:
	state_armed = arm
	for motor in motors:
		motor.powered = state_armed
	if state_armed:
		emit_signal("armed", flight_mode)
	else:
		emit_signal("disarmed")


func integrate_loop(delta: float, drone_pos: Vector3, drone_basis: Basis, world_lin_vel: Vector3 = Vector3.ZERO, world_ang_vel: Vector3 = Vector3.ZERO) -> void:
	dt = delta
	time += dt
	
	pos_prev = pos
	pos = drone_pos
	
	basis_prev = attitude
	attitude = drone_basis
	basis_flat = Basis(Vector3(attitude.x.x, 0, attitude.x.z), Vector3.UP, Vector3(attitude.z.x, 0, attitude.z.z)).orthonormalized()
	
	angles_prev = angles
	angles = attitude.get_euler()
	
	if world_ang_vel != Vector3.ZERO or world_lin_vel != Vector3.ZERO:
		lin_vel = world_lin_vel
		local_vel = (lin_vel) * attitude
		# Measure true body rates directly from rigid body gyroscope
		ang_vel = attitude.inverse() * world_ang_vel
	else:
		update_velocity()
	
	if state_armed:
		update_control(dt)


func update_position() -> void:
	pos_prev = pos
	pos = global_transform.origin
	
	basis_prev = attitude
	attitude = global_transform.basis
	
	angles_prev = angles
	angles = attitude.get_euler()


func update_velocity() -> void:
	if dt <= 0.0:
		return
	lin_vel = (pos - pos_prev) / dt
	local_vel = (lin_vel) * attitude
	
	var ref1 := Vector3(1, 0, 0)
	var orb1 := ((pos + attitude * (ref1) - (pos_prev + basis_prev * ref1)) / dt - lin_vel) * attitude
	var omegax := (ref1.cross(orb1) / ref1.length_squared()).cross(ref1)
	var ref2 := Vector3(0, 1, 0)
	var orb2 := ((pos + attitude * (ref2) - (pos_prev + basis_prev * ref2)) / dt - lin_vel) * attitude
	var omegay := (ref2.cross(orb2) / ref2.length_squared()).cross(ref2)
	var ref3 := Vector3(0, 0, 1)
	var orb3 := ((pos + attitude * (ref3) - (pos_prev + basis_prev * ref3)) / dt - lin_vel) * attitude
	var omegaz := (ref3.cross(orb3) / ref3.length_squared()).cross(ref3)
	ang_vel = Vector3(omegay.z, omegaz.x, omegax.y)


func init_telemetry() -> void:
	telemetry_file = FileAccess.open("user://telemetry.csv", FileAccess.WRITE)
	if telemetry_file == null:
		return
	telemetry_file.store_csv_line(["t", "input.power", "input.yaw", "input.roll", "input.pitch",
			"x", "y", "z", "vx", "vy", "vz", "vx_loc", "vy_loc", "vz_loc",
			"yaw", "roll", "pitch", "yaw_speed", "roll_speed", "pitch_speed",
			"delta_posx", "delta_posy", "delta_posz",
			"rpm1", "rpm2", "rpm3", "rpm4",
			"thrust1", "thrust2", "thrust3", "thrust4",
			"pid.alt.tgt", "pid.alt.err", "pid.alt.out", "pid.alt.clamp",
			"pid.pitch.tgt", "pid.pitch.err", "pid.pitch.out", "pid.pitch.clamp",
			"pid.roll.tgt", "pid.roll.err", "pid.roll.out", "pid.roll.clamp",
			"pid.yaw.tgt", "pid.yaw.err", "pid.yaw.out", "pid.yaw.clamp",
			"pid.yawspeed.tgt", "pid.yawspeed.err", "pid.yawspeed.out", "pid.yawspeed.clamp",
			"pid.pitchspeed.tgt", "pid.pitchspeed.err", "pid.pitchspeed.out", "pid.pitchspeed.clamp",
			"pid.rollspeed.tgt", "pid.rollspeed.err", "pid.rollspeed.out", "pid.rollspeed.clamp",
			"pid.fwdspeed.tgt", "pid.fwdspeed.err", "pid.fwdspeed.out", "pid.fwdspeed.clamp",
			"pid.latspeed.tgt", "pid.latspeed.err", "pid.latspeed.out", "pid.latspeed.clamp",
			"pid.vrtspeed.tgt", "pid.vrtspeed.err", "pid.vrtspeed.out", "pid.vrtspeed.clamp",
			"pid.posx.tgt", "pid.posx.err", "pid.posx.out", "pid.posx.clamp",
			"pid.posz.tgt", "pid.posz.err", "pid.posz.out", "pid.posz.clamp",
			"pid.launch.tgt", "pid.launch.err", "pid.launch.out", "pid.launch.clamp"])
	telemetry_file.close()


func write_telemetry() -> void:
	if !FileAccess.file_exists("user://telemetry.csv"):
		init_telemetry()
	
	telemetry_file = FileAccess.open("user://telemetry.csv", FileAccess.READ_WRITE)
	if telemetry_file == null:
		return
	telemetry_file.seek_end()
	var delta_pos := (get_tracking_target() - pos).rotated(Vector3.UP, -angles.y)
	var data := PackedStringArray([time, input[0], input[1], input[2], input[3],
			pos.x, pos.y, pos.z, lin_vel.x, lin_vel.y, lin_vel.z, local_vel.x, local_vel.y, local_vel.z,
			angles.y, angles.z, angles.x, ang_vel.y, ang_vel.z, ang_vel.x,
			delta_pos.x, delta_pos.y, delta_pos.z,
			motors[0].get_rpm(), motors[1].get_rpm(), motors[2].get_rpm(), motors[3].get_rpm(),
			motors[0].propeller.forces[0].length(), motors[1].propeller.forces[0].length(), motors[2].propeller.forces[0].length(), motors[3].propeller.forces[0].length(),
			pid_controllers[Controller.ALTITUDE].target, pid_controllers[Controller.ALTITUDE].err, pid_controllers[Controller.ALTITUDE].output, pid_controllers[Controller.ALTITUDE].clamped_output,
			pid_controllers[Controller.PITCH].target, pid_controllers[Controller.PITCH].err, pid_controllers[Controller.PITCH].output, pid_controllers[Controller.PITCH].clamped_output,
			pid_controllers[Controller.ROLL].target, pid_controllers[Controller.ROLL].err, pid_controllers[Controller.ROLL].output, pid_controllers[Controller.ROLL].clamped_output,
			pid_controllers[Controller.YAW].target, pid_controllers[Controller.YAW].err, pid_controllers[Controller.YAW].output, pid_controllers[Controller.YAW].clamped_output,
			pid_controllers[Controller.YAW_SPEED].target, pid_controllers[Controller.YAW_SPEED].err, pid_controllers[Controller.YAW_SPEED].output, pid_controllers[Controller.YAW_SPEED].clamped_output,
			pid_controllers[Controller.PITCH_SPEED].target, pid_controllers[Controller.PITCH_SPEED].err, pid_controllers[Controller.PITCH_SPEED].output, pid_controllers[Controller.PITCH_SPEED].clamped_output,
			pid_controllers[Controller.ROLL_SPEED].target, pid_controllers[Controller.ROLL_SPEED].err, pid_controllers[Controller.ROLL_SPEED].output, pid_controllers[Controller.ROLL_SPEED].clamped_output,
			pid_controllers[Controller.FORWARD_SPEED].target, pid_controllers[Controller.FORWARD_SPEED].err, pid_controllers[Controller.FORWARD_SPEED].output, pid_controllers[Controller.FORWARD_SPEED].clamped_output,
			pid_controllers[Controller.LATERAL_SPEED].target, pid_controllers[Controller.LATERAL_SPEED].err, pid_controllers[Controller.LATERAL_SPEED].output, pid_controllers[Controller.LATERAL_SPEED].clamped_output,
			pid_controllers[Controller.VERTICAL_SPEED].target, pid_controllers[Controller.VERTICAL_SPEED].err, pid_controllers[Controller.VERTICAL_SPEED].output, pid_controllers[Controller.VERTICAL_SPEED].clamped_output,
			pid_controllers[Controller.POS_X].target, pid_controllers[Controller.POS_X].err, pid_controllers[Controller.POS_X].output, pid_controllers[Controller.POS_X].clamped_output,
			pid_controllers[Controller.POS_Z].target, pid_controllers[Controller.POS_Z].err, pid_controllers[Controller.POS_Z].output, pid_controllers[Controller.POS_Z].clamped_output,
			pid_controllers[Controller.LAUNCH].target, pid_controllers[Controller.LAUNCH].err, pid_controllers[Controller.LAUNCH].output, pid_controllers[Controller.LAUNCH].clamped_output])
	telemetry_file.store_csv_line(data)
	telemetry_file.close()


func change_flight_mode(mode: int) -> void:
	flight_mode = mode
	emit_signal("flight_mode_changed", flight_mode)
	print("Mode: %s" % [flight_mode])


## Short label shared by the HUD and the big-level telemetry overlay.
static func mode_name(mode: int) -> String:
	match mode:
		FlightMode.RATE:
			return "ACRO"
		FlightMode.LEVEL:
			return "ANGLE"
		FlightMode.HORIZON:
			return "HORIZON"
		FlightMode.SPEED:
			return "SPEED"
		FlightMode.TRACK:
			return "POSITION"
		FlightMode.LAUNCH:
			return "LAUNCH"
		FlightMode.TURTLE:
			return "TURTLE"
		FlightMode.AUTO:
			return "AUTO"
		_:
			return "---"


## Angle (LEVEL) and Acro (RATE) can be disabled in Other settings.  Every
## switch path funnels through here so the aircraft never enters a mode the
## pilot has turned off; HORIZON is the always-available safe fallback.
func is_mode_available(mode: int) -> bool:
	match mode:
		FlightMode.RATE:
			return _setting_enabled("acro_mode", true)
		FlightMode.LEVEL:
			return _setting_enabled("angle_mode", true)
		_:
			return true


func _setting_enabled(key: String, default_value: bool) -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return default_value
	var config = settings.get("hud_config")
	if config is Dictionary:
		return bool((config as Dictionary).get(key, default_value))
	return default_value


func resolve_flight_mode(mode: int) -> int:
	if mode != FlightMode.RATE and mode != FlightMode.LEVEL:
		return mode
	if is_mode_available(mode):
		return mode
	if is_mode_available(FlightMode.RATE):
		return FlightMode.RATE
	if is_mode_available(FlightMode.LEVEL):
		return FlightMode.LEVEL
	return FlightMode.HORIZON


## User-selected mode switches need the same initial setpoints as the mode
## cycle. In particular, TRACK must start from the drone's current position.
func select_flight_mode(mode: int) -> void:
	mode = resolve_flight_mode(mode)
	change_flight_mode(mode)
	if mode == FlightMode.LEVEL:
		pid_controllers[Controller.ALTITUDE].set_target(pos.y)
	elif mode == FlightMode.TRACK:
		set_tracking_target(pos)
		pid_controllers[Controller.YAW].set_target(angles.y)


func _on_cycle_flight_modes() -> void:
	if flight_mode == FlightMode.TURTLE or flight_mode == FlightMode.LAUNCH:
		return
	# HORIZON is always available, so disabling both Angle and Acro leaves a
	# single safe mode instead of an empty cycle.
	var cycle: Array[int] = []
	if is_mode_available(FlightMode.RATE):
		cycle.append(FlightMode.RATE)
	if is_mode_available(FlightMode.LEVEL):
		cycle.append(FlightMode.LEVEL)
	cycle.append(FlightMode.HORIZON)
	var index := cycle.find(flight_mode)
	if index < 0:
		select_flight_mode(cycle[0])
		return
	var next_mode: int = cycle[(index + 1) % cycle.size()]
	if next_mode != flight_mode:
		select_flight_mode(next_mode)


func get_angles_from_basis() -> void:
	angles = global_transform.basis.get_euler()


func is_flight_safe() -> bool:
	var max_angle := deg_to_rad(50)
	var safe := true
	if abs(angles.x) > max_angle or abs(angles.z) > max_angle:
		safe = false
	return safe


func set_motors(motor_array: Array) -> void:
	motors = motor_array
	for motor in motors:
		var _discard = connect("armed", Callable(motor, "_on_armed"))


func set_hover_thrust(t: float) -> void:
	hover_thrust = t


func set_tracking_target(target: Vector3) -> void:
	pid_controllers[Controller.POS_X].set_target(target.x)
	pid_controllers[Controller.ALTITUDE].set_target(target.y)
	pid_controllers[Controller.POS_Z].set_target(target.z)


func get_tracking_target() -> Vector3:
	var target := Vector3(pid_controllers[Controller.POS_X].target, pid_controllers[Controller.ALTITUDE].target,
			pid_controllers[Controller.POS_Z].target)
	return target


func update_control(delta: float) -> void:
	dt = delta
	var motor_control := update_command()
#	print("%8.3f %8.3f %8.3f %8.3f" % [power, yaw, roll, pitch])
	
	var power: float = motor_control[0]
	var yaw: float = motor_control[1]
	var roll: float = motor_control[2]
	var pitch: float = motor_control[3]
	var motor_pwm := [power + yaw + roll + pitch,
			power - yaw - roll + pitch,
			power + yaw - roll - pitch,
			power - yaw + roll - pitch]
	
	# Air Mode
	var pwm_min: float = motor_pwm.min()
	var pwm_max: float = motor_pwm.max()
	var idle_pwm: float = motors[0].MIN_POWER / 100.0
	# Scale PWM to range [idle, 1] as needed
	if pwm_max - pwm_min > 1 - idle_pwm:
		var pwm_mid := (pwm_min + pwm_max) / 2.0
		for i in range(4):
			motor_pwm[i] = pwm_mid + (motor_pwm[i] - pwm_mid) * (1 - idle_pwm) / (pwm_max - pwm_min)
	pwm_min = motor_pwm.min()
	pwm_max = motor_pwm.max()
	var offset := 0.0
	if pwm_min < idle_pwm:
		offset = idle_pwm - pwm_min
	if pwm_max > 1:
		offset = 1 - pwm_max
	for i in range(4):
		motor_pwm[i] += offset
	
	if flight_mode == FlightMode.TURTLE:
		motor_pwm = [0, 0, 0, 0]
		if abs(roll) > abs(pitch):
			if abs(roll) > 0.2:
				if roll > 0:
					motor_pwm[1] = -roll
					motor_pwm[2] = -roll
				else:
					motor_pwm[0] = roll
					motor_pwm[3] = roll
		else:
			if abs(pitch) > 0.2:
				if pitch > 0:
					motor_pwm[2] = -pitch
					motor_pwm[3] = -pitch
				else:
					motor_pwm[0] = pitch
					motor_pwm[1] = pitch
	
	elif flight_mode == FlightMode.LAUNCH:
		motor_pwm = [idle_pwm, idle_pwm, idle_pwm, idle_pwm]
		motor_pwm[2] = clamp(-pitch, idle_pwm, 1)
		motor_pwm[3] = clamp(-pitch, idle_pwm, 1)
		if input[0] > 0.2:
			motor_pwm = [-pitch, -pitch, -pitch, -pitch]
			select_flight_mode(FlightMode.RATE)
	
	motors[0].set_pwm(motor_pwm[0])
	motors[1].set_pwm(motor_pwm[1])
	motors[2].set_pwm(motor_pwm[2])
	motors[3].set_pwm(motor_pwm[3])


func update_command() -> Array:
	var motor_control := [0, 0, 0, 0]
	
	var pwr: float = input[0]
	var y: float = input[1]
	var r: float = input[2]
	var p: float = input[3]
	
	var expo_y: float = control_profile.expo_yaw
	var rate_y: float = control_profile.rate_yaw
	var expo_r: float = control_profile.expo_roll
	var rate_r: float = control_profile.rate_roll
	var expo_p: float = control_profile.expo_pitch
	var rate_p: float = control_profile.rate_pitch
	
	if flight_mode == FlightMode.RATE:
		motor_control[0] = throttle_to_motor_pwm(pwr)

		# Anti-Gravity: one shared throttle-punch factor for all three axes.
		var d_thr: float = pwr - _bf_prev_throttle
		var ag := 1.0 + anti_gravity_gain * clampf(
				absf(d_thr) / maxf(dt, 0.00001) / 30.0, 0.0, 1.0)
		_bf_prev_throttle = pwr

		var yaw_input := _rate_for_axis(2, -y)
		motor_control[1] = _betaflight_pid(Controller.YAW_SPEED, yaw_input, ang_vel.y, dt, pwr, ag)

		var roll_input := _rate_for_axis(0, r)
		motor_control[2] = _betaflight_pid(Controller.ROLL_SPEED, roll_input, -ang_vel.z, dt, pwr, ag)

		var pitch_input := _rate_for_axis(1, p)
		motor_control[3] = _betaflight_pid(Controller.PITCH_SPEED, pitch_input, ang_vel.x, dt, pwr, ag)
	
	elif flight_mode == FlightMode.LEVEL:
		var bank_limit := deg_to_rad(control_profile.level_bank_deg)
		# Direct throttle: LEVEL keeps the self-levelling attitude hold but the
		# stick is real thrust, so the drone lifts off reliably.
		motor_control[0] = throttle_to_motor_pwm(pwr)
		
		pid_controllers[Controller.YAW_SPEED].set_target((-(1 - expo_y) * y - expo_y * pow(y, 3)) * PI)
		motor_control[1] = pid_controllers[Controller.YAW_SPEED].get_output(ang_vel.y, dt, false)
		
		# Cascaded attitude hold. The old code fed the angle PID straight into
		# the motors; its output saturated at 0.025 and the drone rocked back and
		# forth ("seesaw"). Now the angle error produces a limited turn-rate
		# request and a rate-feedback gain damps the rotation before the motors.
		var roll_target := ((1 - expo_r) * r + expo_r * pow(r, 3)) * bank_limit
		var roll_rate_target := clampf((roll_target - (-angles.z))
				* control_profile.level_angle_gain,
				-control_profile.level_rate_limit, control_profile.level_rate_limit)
		motor_control[2] = clampf((roll_rate_target - (-ang_vel.z))
				* control_profile.level_rate_gain, -0.25, 0.25)
		
		var pitch_target := ((1 - expo_p) * p + expo_p * pow(p, 3)) * bank_limit
		var pitch_error := pitch_target - angles.x
		# Learn the airframe's CG trim only while the pilot is not asking for a
		# deliberate pitch change.  The clamp keeps a bad frame/crash from
		# winding up a large permanent offset.
		if not on_ground and absf(p) < LEVEL_TRIM_STICK_GATE and absf(angles.x) < 0.35:
			_level_pitch_trim = clampf(
					_level_pitch_trim + pitch_error * LEVEL_TRIM_GAIN * dt,
					-LEVEL_TRIM_LIMIT, LEVEL_TRIM_LIMIT)
		elif absf(p) > 0.25:
			_level_pitch_trim = move_toward(_level_pitch_trim, 0.0, 0.10 * dt)
		var pitch_rate_target := clampf(pitch_error
				* control_profile.level_angle_gain,
				-control_profile.level_rate_limit, control_profile.level_rate_limit)
		motor_control[3] = clampf((pitch_rate_target - ang_vel.x)
				* control_profile.level_rate_gain + _level_pitch_trim, -0.25, 0.25)
	
	elif flight_mode == FlightMode.HORIZON:
		# HORIZON:self-leveling (Angle) near stick centre, pure rate (Acro)
		# when the stick is pushed past horizon_threshold.  This gives a soft
		# centre for precise aiming and progressive snap at the edges for flips.
		motor_control[0] = throttle_to_motor_pwm(pwr)

		# Anti-Gravity: shared throttle-punch factor across all axes.
		var d_thr: float = pwr - _bf_prev_throttle
		var ag := 1.0 + anti_gravity_gain * clampf(
				absf(d_thr) / maxf(dt, 0.00001) / 30.0, 0.0, 1.0)
		_bf_prev_throttle = pwr

		# Yaw is always rate mode in HORIZON.
		var yaw_input := _rate_for_axis(2, -y)
		motor_control[1] = _betaflight_pid(Controller.YAW_SPEED, yaw_input, ang_vel.y, dt, pwr, ag)

		var bank_limit := deg_to_rad(horizon_bank_deg)

		# --- Roll -----------------------------------------------------------
		var r_abs := absf(r)
		if r_abs < horizon_threshold:
			# Angle region: self-level to commanded bank angle.
			var roll_target := ((1 - expo_r) * r + expo_r * pow(r, 3)) * bank_limit
			var roll_rate_target := clampf((roll_target - (-angles.z))
					* control_profile.level_angle_gain,
					-control_profile.level_rate_limit, control_profile.level_rate_limit)
			motor_control[2] = clampf((roll_rate_target - (-ang_vel.z))
					* control_profile.level_rate_gain, -0.25, 0.25)
		else:
			# Rate region: acro, no self-leveling, permits flips.
			var roll_input := _rate_for_axis(0, r)
			motor_control[2] = _betaflight_pid(Controller.ROLL_SPEED, roll_input, -ang_vel.z, dt, pwr, ag)

		# --- Pitch ----------------------------------------------------------
		var p_abs := absf(p)
		if p_abs < horizon_threshold:
			var pitch_target := ((1 - expo_p) * p + expo_p * pow(p, 3)) * bank_limit
			var pitch_error := pitch_target - angles.x
			if not on_ground and absf(p) < LEVEL_TRIM_STICK_GATE and absf(angles.x) < 0.35:
				_level_pitch_trim = clampf(
						_level_pitch_trim + pitch_error * LEVEL_TRIM_GAIN * dt,
						-LEVEL_TRIM_LIMIT, LEVEL_TRIM_LIMIT)
			elif absf(p) > 0.25:
				_level_pitch_trim = move_toward(_level_pitch_trim, 0.0, 0.10 * dt)
			var pitch_rate_target := clampf(pitch_error
					* control_profile.level_angle_gain,
					-control_profile.level_rate_limit, control_profile.level_rate_limit)
			motor_control[3] = clampf((pitch_rate_target - ang_vel.x)
					* control_profile.level_rate_gain + _level_pitch_trim, -0.25, 0.25)
		else:
			var pitch_input := _rate_for_axis(1, p)
			motor_control[3] = _betaflight_pid(Controller.PITCH_SPEED, pitch_input, ang_vel.x, dt, pwr, ag)
	
	elif flight_mode == FlightMode.SPEED:
		var bank_limit := deg_to_rad(35)
		var flat_vel := (lin_vel) * basis_flat
		pid_controllers[Controller.VERTICAL_SPEED].set_target((pwr - 0.5) * 10.0)
		motor_control[0] = pid_controllers[Controller.VERTICAL_SPEED].get_output(lin_vel.y, dt, false)
		
		pid_controllers[Controller.YAW_SPEED].set_target(((1 - expo_y) * y + expo_y * pow(y, 3)) * 2)
		motor_control[1] = pid_controllers[Controller.YAW_SPEED].get_output(ang_vel.y, dt, false)
		
		pid_controllers[Controller.LATERAL_SPEED].set_target(((1 - expo_r) * r + expo_r * pow(r, 3)) * 10.0)
		var roll_change: float = pid_controllers[Controller.LATERAL_SPEED].get_output(flat_vel.x, dt, false)
		pid_controllers[Controller.ROLL].set_target(clamp(roll_change, -bank_limit, bank_limit))
		motor_control[2] = pid_controllers[Controller.ROLL].get_output(-angles.z, dt, false)
		
		pid_controllers[Controller.FORWARD_SPEED].set_target(((1 - expo_p) * p + expo_p * pow(p, 3)) * 10.0)
		var pitch_change: float = pid_controllers[Controller.FORWARD_SPEED].get_output(flat_vel.z, dt, false)
		pid_controllers[Controller.PITCH].set_target(clamp(pitch_change, -bank_limit, bank_limit))
		motor_control[3] = pid_controllers[Controller.PITCH].get_output(angles.x, dt, false)
	
	elif flight_mode == FlightMode.TRACK:
		var target := get_tracking_target()
		var target_prev := target
		target.x = target.x + ((1 - expo_r) * r + expo_r * pow(r, 3)) * 5.0 * dt
		target.y = target.y + (pwr - 0.5) * 5.0 * dt
		target.z = target.z + ((1 - expo_p) * p + expo_p * pow(p, 3)) * 5.0 * dt
		set_tracking_target(target)
		
		motor_control[0] = pid_controllers[Controller.ALTITUDE].get_output(pos.y, dt, false)
		
		var target_angle: float = pid_controllers[Controller.YAW].target \
				- ((1 - expo_y) * y + expo_y * pow(y, 3)) * PI / 2.0 * dt
		while target_angle > PI:
			target_angle -= 2 * PI
		while target_angle < -PI:
			target_angle += 2 * PI
		pid_controllers[Controller.YAW].set_target(target_angle)
		var hdg_delta := 0.0
		if abs(target_angle - angles.y) > PI:
			hdg_delta = 2 * PI
			if target_angle < 0:
				hdg_delta = -hdg_delta
		var measurement := angles.y + hdg_delta
		# Manually correct previous PID measurement to remove discontinuity
		if abs(pid_controllers[Controller.YAW].mv_prev - measurement) > PI:
			pid_controllers[Controller.YAW].mv_prev += hdg_delta
		motor_control[1] = pid_controllers[Controller.YAW].get_output(measurement, dt, false)
		
		var xform := Transform3D(attitude, pos)
		target = get_tracking_target()
		var delta_pos: Vector3 = xform * target
		var target_vel := (target - target_prev) / dt
		
		var bank_limit := deg_to_rad(35)
		if lin_vel.length() > 2.8 or target_vel.length() > 2.8 or delta_pos.length() > 3.0:
			pid_controllers[Controller.LATERAL_SPEED].set_target(target_vel.dot(attitude.x) + 2 * delta_pos.x)
			var roll_change: float = pid_controllers[Controller.LATERAL_SPEED].get_output(local_vel.x, dt, false)
			pid_controllers[Controller.ROLL].set_target(clamp(roll_change, -bank_limit, bank_limit))
			motor_control[2] = pid_controllers[Controller.ROLL].get_output(-angles.z, dt, false)
			
			pid_controllers[Controller.FORWARD_SPEED].set_target(target_vel.dot(attitude.z) + 2 * delta_pos.z)
			var pitch_change: float = pid_controllers[Controller.FORWARD_SPEED].get_output(local_vel.z, dt, false)
			pid_controllers[Controller.PITCH].set_target(clamp(pitch_change, -bank_limit, bank_limit))
			motor_control[3] = pid_controllers[Controller.PITCH].get_output(angles.x, dt, false)
			
		else:
			var roll_target: float = pid_controllers[Controller.POS_X].get_output(target.x - delta_pos.x, dt)
			pid_controllers[Controller.ROLL].set_target(clamp(roll_target,-bank_limit, bank_limit))
			motor_control[2] = pid_controllers[Controller.ROLL].get_output(-angles.z, dt)
	
			var pitch_target: float = pid_controllers[Controller.POS_Z].get_output(target.z - delta_pos.z, dt)
			pid_controllers[Controller.PITCH].set_target(clamp(pitch_target,-bank_limit, bank_limit))
			motor_control[3] = pid_controllers[Controller.PITCH].get_output(angles.x, dt)
	
	elif flight_mode == FlightMode.TURTLE:
		motor_control[0] = 0
		motor_control[1] = 0
		if abs(p) > abs(r):
			motor_control[2] = 0
			motor_control[3] = p
		else:
			motor_control[2] = r
			motor_control[3] = 0
	
	elif flight_mode == FlightMode.LAUNCH:
		motor_control[0] = throttle_to_motor_pwm(pwr)
		
		var pitch_input: float = pid_controllers[Controller.LAUNCH].target + ((1 - expo_p) * p + expo_p * pow(p, 3)) * dt
		pid_controllers[Controller.LAUNCH].set_target(pitch_input)
		motor_control[3] = pid_controllers[Controller.LAUNCH].get_output(angles.x, dt, false)
	
	elif flight_mode == FlightMode.AUTO:
		pid_controllers[Controller.YAW_SPEED].set_target(0)
		motor_control[1] = pid_controllers[Controller.YAW_SPEED].get_output(ang_vel.y, dt, false)
		
		var bank_limit := deg_to_rad(20)
		if is_flight_safe():
			var target_speed := -5.0
			if pos.y < 1:
				_on_disarm_input()
			pid_controllers[Controller.VERTICAL_SPEED].set_target(target_speed)
			motor_control[0] = pid_controllers[Controller.VERTICAL_SPEED].get_output(lin_vel.y, dt, false)
			
			pid_controllers[Controller.LATERAL_SPEED].set_target(0)
			var roll_change: float = pid_controllers[Controller.LATERAL_SPEED].get_output(local_vel.x, dt, false)
			pid_controllers[Controller.ROLL].set_target(clamp(roll_change, -bank_limit, bank_limit))
			motor_control[2] = pid_controllers[Controller.ROLL].get_output(-angles.z, dt, false)
			
			pid_controllers[Controller.FORWARD_SPEED].set_target(0)
			var pitch_change: float = pid_controllers[Controller.FORWARD_SPEED].get_output(local_vel.z, dt, false)
			pid_controllers[Controller.PITCH].set_target(clamp(pitch_change, -bank_limit, bank_limit))
			motor_control[3] = pid_controllers[Controller.PITCH].get_output(angles.x, dt, false)
		
		else:
			if ang_vel.length_squared() <= deg_to_rad(360):
				pid_controllers[Controller.ROLL].set_target(0)
				motor_control[2] = pid_controllers[Controller.ROLL].get_output(-angles.z, dt, false)
				pid_controllers[Controller.PITCH].set_target(0)
				motor_control[3] = pid_controllers[Controller.PITCH].get_output(angles.x, dt, false)
			else:
				pid_controllers[Controller.ROLL_SPEED].set_target(0)
				motor_control[2] = pid_controllers[Controller.ROLL_SPEED].get_output(-ang_vel.z, dt, false)
				pid_controllers[Controller.PITCH_SPEED].set_target(0)
				motor_control[3] = pid_controllers[Controller.PITCH_SPEED].get_output(ang_vel.x, dt, false)
	
	# Low-throttle attitude authority.  With the props near idle the mixer has
	# almost no thrust to work with; the full PID output only spun the motors up
	# and down and made the airframe buzz during a free fall.  Clamp the
	# differential command instead of removing it: the clamped PID still damps
	# rotation, but the motors stay near idle.
	if flight_mode in [FlightMode.RATE, FlightMode.LEVEL, FlightMode.HORIZON]:
		var authority := clampf(pwr / 0.18, 0.0, 1.0)
		var limit := lerpf(0.06, 0.25, authority)
		motor_control[1] = clampf(motor_control[1], -limit, limit)
		motor_control[2] = clampf(motor_control[2], -limit, limit)
		motor_control[3] = clampf(motor_control[3], -limit, limit)
	
	return motor_control


func reset() -> void:
	set_armed(false)
	_level_pitch_trim = 0.0
	if flight_mode == FlightMode.AUTO or flight_mode == FlightMode.TURTLE or flight_mode == FlightMode.LAUNCH:
		select_flight_mode(FlightMode.RATE)
	
	# Update position twice to ensure pos_prev == pos
	for _i in range(2):
		update_position()
	update_velocity()
	
	for controller in pid_controllers:
		controller.reset()
	pid_controllers[Controller.ALTITUDE].target = pos.y
	pid_controllers[Controller.POS_X].target = pos.x
	pid_controllers[Controller.POS_Z].target = pos.z
	_reset_bf_state()
	
	for motor in motors:
		motor.set_rpm(0)
