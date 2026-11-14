extends Node
class_name RadioController

const ASSIST_HOVER_THROTTLE := 0.45
const FLIGHT_MODE_SWITCHES := [
	"mode_turtle", "mode_launch", "mode_position", "mode_speed",
	"mode_angle", "mode_horizon",
]

signal reset_requested
signal mode_changed
signal arm_input
signal disarm_input


@export var target_path: NodePath
var target: Node3D = null

var input := [0.0, 0.0, 0.0, 0.0]
var hover_assist := false
## Optional REB/link model (combat/reb_system.gd).  When set, it injects
## stick jitter, input latency and a failsafe cut.
var link_provider: Node = null
var input_latency_frames := 0
var _input_history: Array = []
## Test hook: when >= 0, forces throttle power (used by DRONE_AUTOTEST).
var test_throttle := -1.0
## Test hook: when set, overrides yaw stick (used by DRONE_AUTOTEST_PAN).
var test_yaw := 2.0
## Test hook: when set, overrides pitch stick (used by gate fly-through test).
var test_pitch := 2.0
## Test hook: when set, overrides roll stick (used by the LEVEL stability test).
var test_roll := 2.0

var axis_bindings := []
## Last in-range state per axis-bound action, so a switch or trigger produces
## one press and one release instead of firing on every axis sample.
var _axis_action_state := {}

## Active joypad and throttle calibration for radios whose throttle stick rests
## at an extreme (not centred like a gamepad).
var _device := -1
var _throttle_axis := 1
var _throttle_rest := 0.0
var _throttle_sign := 1.0
## True for self-centering throttles (gamepads and spring-centred radios):
## centre is idle and only the upward half of the axis adds power.  A real
## radio throttle rests at an extreme, so the full -1..+1 travel is used.
var _throttle_centered := false
var _was_armed := false
var _since_arm := 0.0
## Throttle low-pass + slew limiter.  Raw radio ADC noise and keyboard steps
## were fed straight to the mixer and produced visible vertical jitter.
var _throttle_filtered := 0.0
var _throttle_filter_ready := false
## Roll/pitch/yaw low-pass.  Keyboard sticks are digital (0 or ±1) and the
## radio ADC is noisy; feeding either straight to the rate loop makes the
## drone twitch.  A short 60 ms filter with a 7/s slew limit keeps the response
## immediate while removing the on/off edge.
var _stick_filtered := Vector3.ZERO
var _stick_filter_ready := false
const STICK_FILTER_TAU := 0.06
const STICK_SLEW := 7.0
## The phone build gets a snappier filter; PC keeps the original feel.
const MOBILE_STICK_FILTER_TAU := 0.045
const MOBILE_STICK_SLEW := 9.0


func _ready() -> void:
	target = get_node_or_null(target_path)
	if target == null and get_tree().current_scene != null:
		target = get_tree().current_scene.get_node_or_null("Drone")
	
	var action_list := Controls.action_list
	for controller_action in action_list:
		if controller_action.type == ControllerAction.Type.AXIS:
			axis_bindings.append(controller_action)
	
	_connect_target()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	call_deferred("_setup_radio")


func _on_joy_connection_changed(_device_id: int, _connected: bool) -> void:
	_setup_radio()
	refresh_bindings()


func _connect_target() -> void:
	if target == null:
		return
	if target.has_method("_on_reset") and not is_connected("reset_requested", Callable(target, "_on_reset")):
		connect("reset_requested", Callable(target, "_on_reset"))
	var fc = target.get("flight_controller")
	if fc != null:
		if fc.has_method("_on_cycle_flight_modes") and not is_connected("mode_changed", Callable(fc, "_on_cycle_flight_modes")):
			connect("mode_changed", Callable(fc, "_on_cycle_flight_modes"))
		if fc.has_method("_on_arm_input") and not is_connected("arm_input", Callable(fc, "_on_arm_input")):
			connect("arm_input", Callable(fc, "_on_arm_input"))
		if fc.has_method("_on_disarm_input") and not is_connected("disarm_input", Callable(fc, "_on_disarm_input")):
			connect("disarm_input", Callable(fc, "_on_disarm_input"))


func _setup_radio() -> void:
	_device = Controls.ensure_active_joypad()
	refresh_bindings()
	if _device < 0:
		return
	# Let the sticks settle, then log where the throttle rests. The throttle
	# curve itself is absolute (down end = 0, up end = 1), so the mapping does
	# not depend on the rest point - this is only a diagnostic.
	await get_tree().create_timer(0.4).timeout
	# The saved map may have been loaded after this node's _ready; re-read it
	# before sampling the throttle so the switch bindings are live.
	refresh_bindings()
	if _device < 0 or not Input.get_connected_joypads().has(_device):
		_device = Controls.ensure_active_joypad()
		if _device < 0:
			return
	var sample := Input.get_joy_axis(_device, _throttle_axis)
	_throttle_rest = sample
	var joy_name := Input.get_joy_name(_device).to_lower()
	var is_gamepad := joy_name.contains("xbox") or joy_name.contains("playstation") \
			or joy_name.contains("dualshock") or joy_name.contains("dualsense") \
			or joy_name.contains("gamepad") or (joy_name.contains("controller") and not joy_name.contains("radio"))
	_throttle_centered = is_gamepad or absf(_throttle_rest) < 0.35
	var direction := _throttle_direction()
	_throttle_sign = direction
	if absf(_throttle_rest) > 0.6:
		print("[RadioController] device=", _device, " name=", Input.get_joy_name(_device),
				" throttle_axis=", _throttle_axis, " rest=", _throttle_rest,
				" dir=", _throttle_sign)
	else:
		print("[RadioController] device=", _device, " name=", Input.get_joy_name(_device),
				" throttle_axis=", _throttle_axis, " rest=", _throttle_rest,
				" dir=", _throttle_sign, " (centred)")


## Re-read the saved stick/action map. BigLevel calls this after
## Controls.load_input_map(); without it the radio's switches stay unbound
## until the level is restarted.
func refresh_bindings() -> void:
	axis_bindings.clear()
	_axis_action_state.clear()
	for controller_action in Controls.action_list:
		if controller_action.type == ControllerAction.Type.AXIS:
			axis_bindings.append(controller_action)
	var binding: Dictionary = Controls.stick_bindings.get("throttle", {})
	if not binding.is_empty():
		_throttle_axis = int(binding["axis"])


## +1 when a positive raw axis value means "throttle up".
func _throttle_direction() -> float:
	var binding: Dictionary = Controls.stick_bindings.get("throttle", {})
	if binding.is_empty():
		return -1.0
	return 1.0 if bool(binding.get("inverted", false)) else -1.0


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if _device >= 0 and motion.device != _device:
			return
		for i in range(axis_bindings.size()):
			if motion.axis != axis_bindings[i].axis:
				continue
			var controller_action = axis_bindings[i]
			var action: String = controller_action.action_name
			var in_range: bool = motion.axis_value >= controller_action.axis_min \
					and motion.axis_value <= controller_action.axis_max
			var state_key := "%d_%s" % [motion.device, action]
			if in_range == bool(_axis_action_state.get(state_key, false)):
				continue
			_axis_action_state[state_key] = in_range
			# `Input.action_press()` updates polling state but does not send an
			# InputEvent through the scene tree. Parse a synthetic action event so
			# level handlers receive every axis-bound switch (arm, camera, payload,
			# pause, and flight mode), including the release edge.
			var action_event := InputEventAction.new()
			action_event.action = action
			action_event.pressed = in_range
			action_event.strength = 1.0 if in_range else 0.0
			if in_range:
				Input.action_press(action)
			else:
				Input.action_release(action)
			Input.parse_input_event(action_event)
	elif Controls.is_action_edge(event, "cycle_flight_modes"):
		emit_signal("mode_changed")
	elif _is_flight_mode_switch_event(event):
		_sync_flight_mode_switches()
	elif event.is_action("altitude_hold") and not event.is_echo():
		hover_assist = event.is_action_pressed("altitude_hold")


func _is_flight_mode_switch_event(event: InputEvent) -> bool:
	if event.is_echo():
		return false
	for action in FLIGHT_MODE_SWITCHES:
		if event.is_action(action):
			return true
	return false


func _sync_flight_mode_switches() -> void:
	if target == null or not is_instance_valid(target):
		return
	var fc := target.get("flight_controller") as FlightController
	if fc == null:
		return

	var desired_mode := FlightController.FlightMode.RATE
	if Input.is_action_pressed("mode_turtle"):
		desired_mode = FlightController.FlightMode.TURTLE
	elif Input.is_action_pressed("mode_launch"):
		desired_mode = FlightController.FlightMode.LAUNCH
	elif Input.is_action_pressed("mode_position"):
		desired_mode = FlightController.FlightMode.TRACK
	elif Input.is_action_pressed("mode_speed"):
		desired_mode = FlightController.FlightMode.SPEED
	elif Input.is_action_pressed("mode_angle"):
		desired_mode = FlightController.FlightMode.LEVEL
	elif Input.is_action_pressed("mode_horizon"):
		desired_mode = FlightController.FlightMode.HORIZON

	if fc.flight_mode != desired_mode:
		fc.select_flight_mode(desired_mode)


func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		target = get_tree().current_scene.get_node_or_null("Drone") if get_tree().current_scene != null else null
		_connect_target()
	read_input()
	
	if target is Drone:
		target.flight_controller.input = input


## The calibration wizard can store an ELRS/touch trim in MobileInput.  The
## default is an empty table, so this is a no-op until the pilot calibrates.
func _calibrated_stick(mobile: Node, source: String, channel: String, value: float) -> float:
	if mobile == null:
		return value
	return float(mobile.call("calibrate", source, channel, value))


func _calibrated_power(mobile: Node, source: String, value: float) -> float:
	if mobile == null:
		return value
	var normalised := value * 2.0 - 1.0
	normalised = float(mobile.call("calibrate", source, "throttle", normalised))
	return clampf((normalised + 1.0) * 0.5, 0.0, 1.0)


func read_input() -> void:
	# Keyboard sticks: W/S throttle, A/D yaw, arrows pitch/roll.
	var kb_yaw: float = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) \
			- (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	var kb_roll: float = (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0) \
			- (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0)
	var kb_pitch: float = (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0) \
			- (1.0 if Input.is_key_pressed(KEY_UP) else 0.0)

	# Radio/gamepad sticks come from the saved per-channel bindings, not from
	# the InputMap actions.  This keeps one physical axis from driving two
	# channels when an old config has duplicate bindings.  On a phone the
	# on-screen twin sticks are a deliberate mode switch and take precedence;
	# otherwise a live WiFi ELRS stream overrides the physical gamepad.
	var wifi := get_node_or_null("/root/ElrsWifiInput")
	var touch := get_node_or_null("/root/TouchControls")
	var mobile := get_node_or_null("/root/MobileInput")
	var touch_active: bool = touch != null and bool(touch.get("enabled")) \
			and bool(touch.get("touch_mode"))
	var wifi_active: bool = wifi != null and bool(wifi.get("valid"))
	var elrs_roll_sign := -1.0 if wifi != null and bool(wifi.get("invert_roll")) else 1.0
	var pad_yaw := 0.0
	var pad_roll := 0.0
	var pad_pitch := 0.0
	if touch_active:
		# TouchControls._apply_axis_curve already applies the user deadband, expo
		# and sensitivity once; avoid double-filtering through Controls here.
		pad_yaw = _calibrated_stick(mobile, "touch", "yaw", float(touch.get("yaw")))
		pad_roll = _calibrated_stick(mobile, "touch", "roll", float(touch.get("roll")))
		pad_pitch = _calibrated_stick(mobile, "touch", "pitch", float(touch.get("pitch")))
	elif wifi_active:
		pad_yaw = Controls.apply_stick_filter("yaw", _calibrated_stick(mobile, "elrs", "yaw", float(wifi.yaw())))
		pad_roll = Controls.apply_stick_filter("roll", _calibrated_stick(mobile, "elrs", "roll", float(wifi.roll())))
		pad_pitch = Controls.apply_stick_filter("pitch", _calibrated_stick(mobile, "elrs", "pitch", float(wifi.pitch())))
	else:
		pad_yaw = Controls.channel_value("yaw")
		pad_roll = Controls.channel_value("roll")
		pad_pitch = Controls.channel_value("pitch")
	var yaw := kb_yaw if absf(kb_yaw) > 0.01 else (0.0 if is_nan(pad_yaw) else pad_yaw)
	var roll := kb_roll if absf(kb_roll) > 0.01 else (0.0 if is_nan(pad_roll) else pad_roll)
	var pitch := kb_pitch if absf(kb_pitch) > 0.01 else (0.0 if is_nan(pad_pitch) else pad_pitch)

	# Dynamic deadband (0.05) around stick centre: kills jitter and prevents
	# the drone from drifting when the sticks are released.
	# Filtered through Controls.channel_value (deadband + smoothing).

	if test_yaw <= 1.0:
		yaw = test_yaw
	if test_pitch <= 1.0:
		pitch = test_pitch
	if test_roll <= 1.0:
		roll = test_roll
	if test_throttle >= 0.0:
		input = [test_throttle, yaw, roll, pitch]
		return

	# Keyboard throttle is W/S only.  Up/Down are pitch and must never change
	# throttle: with a radio connected, pressing an arrow used to slam the
	# throttle to 0 or 1 and made the drone unflyable.
	var key_up: bool = Input.is_key_pressed(KEY_W)
	var key_down: bool = Input.is_key_pressed(KEY_S)

	if _device < 0 or not Input.get_connected_joypads().has(_device):
		_device = Controls.ensure_active_joypad()
	var pad_power := -1.0
	if touch_active:
		pad_power = _calibrated_power(mobile, "touch", float(touch.get("throttle")))
	elif wifi_active:
		pad_power = _calibrated_power(mobile, "elrs", float(wifi.throttle()))
	else:
		pad_power = _radio_throttle()

	var power := 0.0
	if key_up:
		power = 1.0
	elif key_down:
		power = 0.0
	elif pad_power >= 0.0:
		power = pad_power
	elif hover_assist:
		power = ASSIST_HOVER_THROTTLE

	# A short "soft start" caps the throttle at the calibrated hover point if
	# "arm" is pressed with the stick high. This avoids a launch without forcing
	# the drone below hover while the controller comes online.
	var armed: bool = target is Drone and (target as Drone).flight_controller.state_armed
	if not armed:
		_was_armed = false
		_since_arm = 0.0
	else:
		if not _was_armed:
			_was_armed = true
			_since_arm = 0.0
		_since_arm += get_physics_process_delta_time()
		if _since_arm < 0.6:
			power = minf(power, ASSIST_HOVER_THROTTLE)
	# Throttle smoothing: radio ADC noise and keyboard steps both produce
	# visible vertical jitter when the raw value is fed to the mixer.  A 90 ms
	# low-pass plus a slew limit keeps the climb smooth without adding
	# perceptible lag to throttle punches.
	var dt := maxf(get_physics_process_delta_time(), 0.0001)
	var mobile_feel := MenuUI.is_mobile_ui()
	var throttle_tau := 0.09 if mobile_feel else 0.12
	if mobile_feel:
		throttle_tau = 0.025 + float(Controls.get("stick_smoothing")) * 0.65
	var throttle_slew_up := 3.2 if mobile_feel else 2.4
	var throttle_slew_down := 7.0 if mobile_feel else 6.0
	if not _throttle_filter_ready or not armed:
		_throttle_filtered = power
		_throttle_filter_ready = true
	else:
		_throttle_filtered = lerpf(_throttle_filtered, power,
				1.0 - exp(-dt / throttle_tau))
		# Climb changes are slewed gently; throttle cuts stay quick so the
		# pilot can still drop power immediately.
		var slew := throttle_slew_up if power > _throttle_filtered \
				else throttle_slew_down
		_throttle_filtered = move_toward(_throttle_filtered, power, slew * dt)

	# Roll/pitch/yaw smoothing.  The test hooks and the first armed frame must
	# pass through untouched, otherwise the scripted QA probes see a ramp.
	var test_sticks := test_yaw <= 1.0 or test_pitch <= 1.0 or test_roll <= 1.0
	var target_sticks := Vector3(yaw, roll, pitch)
	if test_sticks or not _stick_filter_ready or not armed:
		_stick_filtered = target_sticks
		_stick_filter_ready = true
	else:
		var filter_tau := MOBILE_STICK_FILTER_TAU if mobile_feel \
				else STICK_FILTER_TAU
		var slew_cap := MOBILE_STICK_SLEW if mobile_feel else STICK_SLEW
		var blend := 1.0 - exp(-dt / filter_tau)
		_stick_filtered = _stick_filtered.lerp(target_sticks, blend)
		var max_step := slew_cap * dt
		_stick_filtered.x = move_toward(_stick_filtered.x, target_sticks.x, max_step)
		_stick_filtered.y = move_toward(_stick_filtered.y, target_sticks.y, max_step)
		_stick_filtered.z = move_toward(_stick_filtered.z, target_sticks.z, max_step)
	input = [_throttle_filtered, _stick_filtered.x, _stick_filtered.y,
			_stick_filtered.z]
	_apply_link_effects()


## REB effects: noisy sticks, a short control delay and the failsafe cut.
func _apply_link_effects() -> void:
	if link_provider == null or not is_instance_valid(link_provider):
		link_provider = null
		return
	var jitter = link_provider.get("stick_jitter")
	if jitter is Vector2:
		input[1] = clampf(float(input[1]) + jitter.x, -1.0, 1.0)
		input[2] = clampf(float(input[2]) + jitter.y * 0.6, -1.0, 1.0)
		input[3] = clampf(float(input[3]) + jitter.y, -1.0, 1.0)

	# Control latency: replay a short history ring (0 frames = no delay).
	if input_latency_frames > 0:
		_input_history.append(input.duplicate())
		if _input_history.size() > input_latency_frames:
			input = _input_history.pop_front()
		else:
			input = _input_history[0].duplicate()
	elif not _input_history.is_empty():
		_input_history.clear()

	if bool(link_provider.get("failsafe")):
		input = [0.0, 0.0, 0.0, 0.0]


## Throttle from the calibrated radio axis, or -1 when there is no radio
## throttle. The stick's down end is zero and its up end is full power, so the
## result never depends on where the stick happened to rest at start-up.
func _radio_throttle() -> float:
	if _device < 0:
		return -1.0
	var binding: Dictionary = Controls.stick_bindings.get("throttle", {})
	if binding.is_empty():
		return -1.0
	var axis := int(binding["axis"])
	if axis != _throttle_axis:
		_throttle_axis = axis
		_throttle_rest = Input.get_joy_axis(_device, axis)
		_throttle_centered = absf(_throttle_rest) < 0.25
	var value := Controls.channel_value("throttle")
	if is_nan(value):
		return -1.0
	# Channel value already includes calibrated endpoint normalisation, the
	# deadband/smoothing filter and the manual throttle inversion.  Mapping it
	# to 0..1 here means full physical down is exactly 0 and full up exactly 1,
	# so the HUD marker and the motor curve agree on what "full travel" means.
	var target_drone = target as Drone
	var is_armed: bool = target_drone != null and target_drone.flight_controller != null and target_drone.flight_controller.state_armed
	if _throttle_centered:
		var power := centered_throttle_power(value, is_armed)
		# Centred stick = altitude hold, not just a fixed hover throttle.  A
		# small vertical-speed trim compensates for battery sag and preset mass
		# differences, so releasing the stick settles instead of slowly
		# climbing or sinking.  The correction is capped at ±5% throttle.
		if is_armed and absf(value) < 0.06 and target_drone != null:
			power = clampf(power - target_drone.linear_velocity.y * 0.008,
					0.40, 0.50)
		return power
	# Real radio throttle: down end is zero, up end is full power.
	return clampf((value + 1.0) * 0.5, 0.0, 1.0)


## Map a self-centering throttle axis to motor power.  Unarmed (and before
## take-off) centre is idle.  Once armed, centre is HOVER: releasing the left
## stick after a climb settles into a hover instead of cutting the motors and
## dropping the drone.  The lower half descends, the upper half climbs.
static func centered_throttle_power(value: float, armed: bool) -> float:
	if not armed:
		return clampf(value, 0.0, 1.0)
	if absf(value) < 0.06:
		value = 0.0
	if value < 0.0:
		return clampf((value + 1.0) * ASSIST_HOVER_THROTTLE, 0.0,
				ASSIST_HOVER_THROTTLE)
	return clampf(ASSIST_HOVER_THROTTLE + value * (1.0 - ASSIST_HOVER_THROTTLE),
			ASSIST_HOVER_THROTTLE, 1.0)


func simulate_action_event(action_name: String, action_pressed: bool) -> InputEventAction:
	var event = InputEventAction.new()
	event.action = action_name
	event.pressed = action_pressed
	return event
