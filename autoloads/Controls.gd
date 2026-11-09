extends Node


var input_map_path := "%s/InputMap.cfg" % Global.config_dir
var active_controller_guid := ""
var default_controller_guid := ""
var active_device := -1

var action_list := []

## Current stick map, filled from InputMap / calibration:
## channel -> { "axis": int, "inverted": bool }
var stick_bindings := {"throttle": {}, "yaw": {}, "pitch": {}, "roll": {}}
## Human-readable duplicate-axis conflicts found while reading the InputMap.
## One physical axis must never drive two stick channels.
var stick_conflicts := []

## Per-channel calibration: raw axis value at the negative end, at the positive
## end, and at the stick's resting centre:
##   channel -> { "min": float, "max": float, "center": float }
## "min" is the raw value captured at throttle-down / yaw-left / pitch-away /
## roll-left, "max" at the opposite end.  Real radios rarely reach exactly
## -1/+1, so without this the last few percent of stick travel are lost and
## the HUD marker never reaches the edge of its grid.  Ranges are stored per
## controller (InputMap.cfg section), unlike the global tuning values.
var stick_ranges := {}

const STICK_TUNING_VERSION := 5
## Calibration data written before this version came from the old wizard
## (threshold-crossing endpoints and a centre sampled mid-return), so it is
## discarded once on upgrade instead of silently shifting the neutral point.
const STICK_CALIBRATION_VERSION := 4
## Light jitter filter.  It is time-based (independent of FPS) and deliberately
## short: quick deliberate stick movements pass almost unfiltered, while ADC
## noise around the centre is smoothed away.  0 = completely raw input.
const DEFAULT_STICK_SMOOTHING := 0.16

## Controller deadband applied to every stick channel (±0.02 default).
## Values inside this range are snapped to zero to kill jitter / drift.
const DEFAULT_STICK_DEADZONE := 0.02
@export var stick_deadzone := DEFAULT_STICK_DEADZONE: set = _set_deadzone
## Smoothing strength (0.0 = none / instant, 0.5 = strongest).  Internally it
## maps to a short time constant, not a per-frame alpha, so the feel is the
## same at 60, 120 or 240 FPS.
@export var stick_smoothing := DEFAULT_STICK_SMOOTHING: set = _set_smoothing
## Per-channel inversion overrides (merged with the binding's inverted flag).
var stick_invert := {"throttle": false, "yaw": false, "pitch": false, "roll": false}

## Last filtered value per channel, used by the smoothing filter.
var _stick_filtered := {"throttle": 0.0, "yaw": 0.0, "pitch": 0.0, "roll": 0.0}
## Physics frame in which each channel filter was last updated.  Several
## systems (flight input, HUD, menu preview) call channel_value() in the same
## frame; without this the same sample would be filtered two or three times
## and the resulting lag would depend on how many widgets are visible.
var _stick_filter_frame := {"throttle": -1, "yaw": -1, "pitch": -1, "roll": -1}

func _set_deadzone(value: float) -> void:
	stick_deadzone = clampf(value, 0.0, 0.25)

func _set_smoothing(value: float) -> void:
	stick_smoothing = clampf(value, 0.0, 0.5)

## Apply deadband + smoothing to a stick value. Returns [-1..1].
## `frame_dt` is only used by tests; in game the value is refreshed at most
## once per physics frame so all readers see exactly the same filtered input.
func apply_stick_filter(channel: String, raw: float, frame_dt: float = -1.0) -> float:
	var value := clampf(raw, -1.0, 1.0)
	# Throttle is unipolar: a deadband in the middle of its travel would create
	# a notch in the power curve, so only the self-centring axes get it.
	# Values just outside the deadband are rescaled instead of jumping to 0.02,
	# which keeps the centre-to-edge transition smooth.
	if channel != "throttle":
		if absf(value) < stick_deadzone:
			value = 0.0
		elif stick_deadzone > 0.0:
			value = signf(value) * (absf(value) - stick_deadzone) / (1.0 - stick_deadzone)
	var frame := Engine.get_physics_frames()
	if frame_dt < 0.0 and int(_stick_filter_frame.get(channel, -1)) == frame:
		return clampf(_stick_filtered[channel], -1.0, 1.0)
	_stick_filter_frame[channel] = frame
	var dt := frame_dt
	if dt < 0.0:
		dt = 1.0 / maxf(float(Engine.physics_ticks_per_second), 30.0)
	if stick_smoothing <= 0.0001 or dt <= 0.0:
		_stick_filtered[channel] = value
		return value
	# One-pole low-pass with a 0..75 ms time constant.  Large per-frame
	# movements (a deliberate flick) raise alpha towards 1, so the filter only
	# removes small jitter and never adds noticeable input lag.
	var tau: float = stick_smoothing * 0.15
	var alpha: float = 1.0 - exp(-dt / tau)
	var speed: float = absf(value - float(_stick_filtered[channel]))
	var fast: float = clampf((speed - 0.04) / 0.18, 0.0, 1.0)
	alpha = maxf(alpha, fast)
	_stick_filtered[channel] = _stick_filtered[channel] + alpha * (value - _stick_filtered[channel])
	return clampf(_stick_filtered[channel], -1.0, 1.0)

## Reset all stick filters (call when re-centering or recalibrating).
func reset_stick_filters() -> void:
	for ch in _stick_filtered.keys():
		_stick_filtered[ch] = 0.0
		_stick_filter_frame[ch] = -1


## Raw axis -> normalised -1..+1 using the calibrated endpoints.  The
## calibration records which physical end is negative, so a reversed radio
## axis needs no extra "inverted" guesswork.  If no range was captured, fall
## back to the binding's inverted flag, which is how quick presets work.
func normalize_stick_raw(channel: String, raw: float) -> float:
	var rng: Dictionary = stick_ranges.get(channel, {})
	var has_range: bool = rng.has("min") and rng.has("max") \
			and absf(float(rng["max"]) - float(rng["min"])) > 0.1
	if not has_range:
		return clampf(raw * _binding_direction(channel), -1.0, 1.0)
	var lo := float(rng["min"])
	var hi := float(rng["max"])
	if channel == "throttle":
		var val := clampf((raw - lo) / (hi - lo) * 2.0 - 1.0, -1.0, 1.0)
		# Deadzone at the idle end of throttle so resting at the bottom reads
		# -1 (0% power) instead of a few percent caused by residual raw offset.
		if absf(val + 1.0) <= stick_deadzone:
			return -1.0
		return val
	var center := float(rng.get("center", (lo + hi) * 0.5))
	# Deadzone around the calibrated centre: kills post-calibration drift so a
	# released stick reads exactly 0 even if the radio's physical rest point is
	# a few ADC counts off the stored centre.  The deadzone is configured in
	# normalised units, so convert it to raw axis units before comparing.
	var half_span := absf(hi - lo) * 0.5
	if half_span > 0.001 and absf(raw - center) <= stick_deadzone * half_span:
		return 0.0
	return normalize_range_value(raw, lo, hi, center)


func _binding_direction(channel: String) -> float:
	var binding: Dictionary = stick_bindings.get(channel, {})
	if binding.is_empty():
		return 1.0
	return 1.0 if bool(binding.get("inverted", false)) else -1.0


## Store one channel's calibrated raw endpoints.  `negative_end` is the value
## captured while the stick was at throttle-down / left / nose-away; the
## opposite end is `positive_end`.  `center` is the measured rest position for
## self-centring axes (ignored for throttle).
func set_stick_range(channel: String, negative_end: float, positive_end: float,
		center: float = NAN) -> void:
	if absf(positive_end - negative_end) < 0.05:
		stick_ranges.erase(channel)
		return
	var mid := (negative_end + positive_end) * 0.5
	if is_nan(center):
		center = mid
	# Keep the centre strictly between the endpoints, even with a sloppy radio.
	var low := minf(negative_end, positive_end)
	var high := maxf(negative_end, positive_end)
	stick_ranges[channel] = {
		"min": negative_end,
		"max": positive_end,
		"center": clampf(center, low + 0.01, high - 0.01),
	}


func clear_stick_range(channel: String) -> void:
	stick_ranges.erase(channel)


## Generic raw -> -1..+1 mapping for a calibrated axis.  `lo` is the value at
## the negative end, `hi` at the positive end (either may be the numerically
## larger one on a reversed radio), `center` the measured rest point.
func normalize_range_value(raw: float, lo: float, hi: float, center: float = NAN) -> float:
	if absf(hi - lo) < 0.05:
		return 0.0
	if is_nan(center):
		center = (lo + hi) * 0.5
	var pos_span: float = hi - center
	var neg_span: float = lo - center
	if absf(pos_span) < 0.001 or absf(neg_span) < 0.001:
		return clampf((raw - lo) / (hi - lo) * 2.0 - 1.0, -1.0, 1.0)
	var delta: float = raw - center
	if absf(delta) < 0.0001:
		return 0.0
	var value: float
	if (delta > 0.0) == (pos_span > 0.0):
		value = delta / pos_span
	else:
		value = -delta / neg_span
	return clampf(value, -1.0, 1.0)

const STICK_ACTIONS := {
	"throttle": ["throttle_up", "throttle_down"],
	"yaw": ["yaw_left", "yaw_right"],
	"pitch": ["pitch_up", "pitch_down"],
	"roll": ["roll_left", "roll_right"],
}

## The action that represents the positive direction of each channel:
## throttle up, nose up, yaw right and roll right. The other action in
## STICK_ACTIONS is the negative direction (down / left).
const STICK_POSITIVE := {
	"throttle": "throttle_up",
	"yaw": "yaw_right",
	"pitch": "pitch_up",
	"roll": "roll_right",
}


func _ready() -> void:
	create_action_list()
	refresh_stick_bindings()
	make_joypad_events_global()
	# Guarantee the default keyboard shortcuts (M / Space / Backspace / H) even
	# on a fresh install where InputMap.cfg does not exist yet.
	restore_keyboard_shortcuts()
	if OS.has_environment("DRONE_INPUT_SELFTEST"):
		call_deferred("_run_selftest")


## Godot 4 treats `device == -1` as "any device", while 0/1/... only match that
## exact index. Radios often enumerate as device 1 or 2, so make every joypad
## binding global or the radio looks dead in game.
func make_joypad_events_global() -> void:
	for action in InputMap.get_actions():
		var fix: Array = []
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				if event.device != -1:
					fix.append(event)
		for event in fix:
			InputMap.action_erase_event(action, event)
			var dup: InputEvent = event.duplicate()
			dup.device = -1
			InputMap.action_add_event(action, dup)


## True for real press edges only: keys, joypad buttons and synthetic
## InputEventAction presses. A raw InputEventJoypadMotion matches button-like
## actions while it stays inside the range, so using it directly would fire the
## action on every axis sample (arm toggling itself on and off).
func is_action_edge(event: InputEvent, action: String) -> bool:
	if event is InputEventJoypadMotion:
		return false
	return event.is_action_pressed(action)


## Remove only the radio/gamepad events of an action, keeping its keyboard
## shortcuts intact.
func erase_joypad_events(action: String) -> void:
	if not InputMap.has_action(action):
		return
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			InputMap.action_erase_event(action, event)


## Resolve the active joypad if it is missing or was unplugged. Returns the
## device index, or -1 when nothing is connected.
func ensure_active_joypad() -> int:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		active_device = -1
		return -1
	if active_device < 0 or not pads.has(active_device):
		var preferred := -1
		if not default_controller_guid.is_empty():
			for pad in pads:
				if Input.get_joy_guid(pad) == default_controller_guid:
					preferred = pad
					break
		if preferred < 0 and not active_controller_guid.is_empty():
			for pad in pads:
				if Input.get_joy_guid(pad) == active_controller_guid:
					preferred = pad
					break
		active_device = preferred if preferred >= 0 else pads[0]
		active_controller_guid = Input.get_joy_guid(active_device)
	refresh_stick_bindings()
	return active_device


## Raw signed value of a stick channel, or 0 when unbound / no device.
func raw_channel(channel: String) -> float:
	if active_device < 0:
		return 0.0
	var binding: Dictionary = stick_bindings.get(channel, {})
	if binding.is_empty():
		return 0.0
	return Input.get_joy_axis(active_device, int(binding["axis"]))


## Normalised stick value for a channel: +1 = full "up/right", -1 = opposite,
## using the direction stored in the bindings. Applies deadband + smoothing.
## Returns NAN when unbound so the caller can fall back to the keyboard/action path.
func channel_value(channel: String) -> float:
	if active_device < 0:
		return NAN
	var binding: Dictionary = stick_bindings.get(channel, {})
	if binding.is_empty():
		return NAN
	var raw := Input.get_joy_axis(active_device, int(binding["axis"]))
	var value := normalize_stick_raw(channel, raw)
	# Per-channel manual inversion on top of the calibrated direction.
	if bool(stick_invert.get(channel, false)):
		value = -value
	return apply_stick_filter(channel, value)


## The stick position as the pilot physically holds it: calibrated and filtered,
## but WITHOUT the manual per-channel inversion.  The on-screen stick monitor
## uses this so it always mirrors the pilot's hand, even when a channel is
## reversed for flight.
func physical_channel_value(channel: String) -> float:
	var value := channel_value(channel)
	if is_nan(value):
		return NAN
	if bool(stick_invert.get(channel, false)):
		value = -value
	return value


func has_stick_binding(channel: String) -> bool:
	return not stick_bindings.get(channel, {}).is_empty()


func update_active_device(device: int) -> int:
	active_device = device
	active_controller_guid = Input.get_joy_guid(device)
	var config := ConfigFile.new()
	var err := config.load(input_map_path)
	if err == OK or err == ERR_FILE_NOT_FOUND:
		config.set_value("controls", "active_controller_guid", active_controller_guid)
		config.set_value("controls", "active_controller_name", Input.get_joy_name(device))
		err = config.save(input_map_path)
		if err != OK:
			Global.log_error(err, "Error while updating active device in config file.")
	else:
		Global.log_error(err, "Error while updating active device in config file.")
	return err


func update_default_device(device: int) -> int:
	var config := ConfigFile.new()
	var err := config.load(input_map_path)
	if err == OK or err == ERR_FILE_NOT_FOUND:
		if device >= 0:
			default_controller_guid = Input.get_joy_guid(device)
		else:
			default_controller_guid = ""
		config.set_value("controls", "default_controller", default_controller_guid)
		err = config.save(input_map_path)
		if err != OK:
			Global.log_error(err, "Error while updating default device in config file.")
	else:
		Global.log_error(err, "Error while updating default device in config file.")
	return err


func load_input_map(update_controller: bool = false) -> String:
	var config := ConfigFile.new()
	var err := config.load(input_map_path)
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			Global.log_error(err, "Could not open controls configuration file.")
			return "Could not open config file.\nPlease check Controls settings."
		return ""

	# Stick tuning is global (not per device): deadband, smoothing and inversion.
	var tuning_version := int(config.get_value("controls", "stick_tuning_version", 0))
	stick_deadzone = clampf(float(config.get_value("controls", "stick_deadzone", stick_deadzone)), 0.0, 0.25)
	stick_smoothing = clampf(float(config.get_value("controls", "stick_smoothing", stick_smoothing)), 0.0, 0.5)
	if tuning_version < STICK_TUNING_VERSION:
		# Old builds defaulted to 0, which felt twitchy on cheap radios.  Only
		# replace the untouched default; an explicitly customised value stays.
		if is_zero_approx(stick_smoothing):
			stick_smoothing = DEFAULT_STICK_SMOOTHING
		# Very large deadbands were a workaround for a badly captured centre.
		# They turn into a dead spot of their own, so put the sane default back
		# once the new calibration is in place.
		if stick_deadzone > 0.10:
			stick_deadzone = DEFAULT_STICK_DEADZONE
		# Calibrations made by the old wizard have an unreliable centre: it
		# sampled the stick while it was still returning from the end stop.
		# Keep the captured end points (they define direction and scaling) but
		# drop the stored centre so normalisation falls back to the midpoint.
		# Idle throttle then stays at 0% and the neutral is centred until the
		# pilot runs the corrected wizard.
		if tuning_version < STICK_CALIBRATION_VERSION:
			for section in config.get_sections():
				if not section.begins_with("controls_"):
					continue
				for key in config.get_section_keys(section):
					if key.ends_with("_range_center"):
						config.erase_section_key(section, key)
		config.set_value("controls", "stick_deadzone", stick_deadzone)
		config.set_value("controls", "stick_smoothing", stick_smoothing)
		config.set_value("controls", "stick_tuning_version", STICK_TUNING_VERSION)
		var tuning_err := config.save(input_map_path)
		if tuning_err != OK:
			Global.log_error(tuning_err, "Could not migrate stick tuning settings.")
	for channel in stick_invert.keys():
		stick_invert[channel] = bool(config.get_value(
				"controls", "stick_invert_" + channel, stick_invert[channel]))
	# v5: the flight controller's yaw sign was corrected (positive channel now
	# yaws right, matching the HUD and the action names).  Radios that used the
	# old "invert yaw" workaround must drop it or their yaw doubles.
	if tuning_version < 5:
		stick_invert["yaw"] = false
		# Slightly softer default stick response for the "smoother flight"
		# request; a custom value set on the slider is preserved.
		if is_equal_approx(stick_smoothing, 0.10):
			stick_smoothing = DEFAULT_STICK_SMOOTHING
		config.set_value("controls", "stick_invert_yaw", false)
		config.set_value("controls", "stick_smoothing", stick_smoothing)
		config.set_value("controls", "stick_tuning_version", STICK_TUNING_VERSION)
		var yaw_fix_err := config.save(input_map_path)
		if yaw_fix_err != OK:
			Global.log_error(yaw_fix_err, "Could not save the yaw-sign migration.")
	reset_stick_filters()

	var pads := Input.get_connected_joypads()
	var saved_guid := str(config.get_value("controls", "active_controller_guid", ""))
	active_controller_guid = saved_guid
	var device_index := -1
	for pad in pads:
		if Input.get_joy_guid(pad) == active_controller_guid:
			device_index = pad
			break

	if update_controller:
		var default_device := -1
		if config.has_section_key("controls", "default_controller"):
			default_controller_guid = str(config.get_value("controls", "default_controller", ""))
			for pad in pads:
				if Input.get_joy_guid(pad) == default_controller_guid:
					default_device = pad
					break
		if default_device >= 0:
			device_index = default_device
			active_controller_guid = default_controller_guid
			var _discard = update_active_device(device_index)
		elif not pads.is_empty():
			device_index = pads[0]
			var _discard = update_active_device(device_index)

	# The saved GUID may be stale after a re-plug or a radio re-flash.  Fall
	# back to the first connected pad; its live GUID is adopted below.
	if device_index < 0 and not pads.is_empty():
		device_index = pads[0]
	active_device = device_index

	var live_guid := ""
	if device_index >= 0:
		live_guid = Input.get_joy_guid(device_index)

	# Prefer the connected device's own section.  Only fall back to the saved
	# GUID (or any section) when the live device has no mapping yet.
	var section_guid := live_guid if not live_guid.is_empty() else saved_guid
	if not config.has_section("controls_" + section_guid):
		if config.has_section("controls_" + saved_guid):
			section_guid = saved_guid
		elif not live_guid.is_empty() and config.has_section("controls_" + live_guid):
			section_guid = live_guid
		else:
			for section in config.get_sections():
				if section.begins_with("controls_"):
					section_guid = section.trim_prefix("controls_")
					break

	# Apply the saved mapping even when the radio is currently unplugged: the
	# keyboard must keep working, and the radio picks the mapping up on connect.
	_apply_saved_bindings(config, "controls_%s" % section_guid)

	# Migrate the mapping to the live GUID.  Without this the old section is
	# re-applied on every launch and newly saved bindings (written under the
	# live GUID) are ignored.
	if not live_guid.is_empty():
		active_controller_guid = live_guid
		var dirty := false
		if section_guid != live_guid:
			_copy_section(config, "controls_%s" % section_guid, "controls_%s" % live_guid)
			dirty = true
		if str(config.get_value("controls", "active_controller_guid", "")) != live_guid:
			config.set_value("controls", "active_controller_guid", live_guid)
			dirty = true
		var live_name := Input.get_joy_name(device_index)
		if str(config.get_value("controls", "active_controller_name", "")) != live_name:
			config.set_value("controls", "active_controller_name", live_name)
			dirty = true
		if dirty:
			var save_err := config.save(input_map_path)
			if save_err != OK:
				Global.log_error(save_err, "Could not migrate controller bindings.")
	else:
		active_controller_guid = saved_guid

	refresh_stick_bindings()
	restore_keyboard_shortcuts()
	make_joypad_events_global()
	# The saved controller section may not contain the core flight buttons at
	# all, and `_apply_saved_bindings` erases joypad events for missing keys.
	# Restore a coherent named default map once, then only fill gaps.
	_ensure_core_pad_defaults(config, "controls_%s" % section_guid)

	if device_index < 0:
		var active_name := str(config.get_value("controls", "active_controller_name", ""))
		if not active_name.is_empty():
			return """%s not found!
					Please check it is properly plugged in,
					or head to the Controls settings to update your controller.""" % [active_name]
	return ""


## Copy every key of a controller section into another section.  Used when a
## radio re-enumerates under a new GUID: the old mapping is preserved instead
## of being silently ignored.
func _copy_section(config: ConfigFile, from_section: String, to_section: String) -> void:
	if from_section == to_section or not config.has_section(from_section):
		return
	if not config.has_section(to_section):
		config.add_section(to_section)
	for key in config.get_section_keys(from_section):
		config.set_value(to_section, key, config.get_value(from_section, key))


## Apply one controller's saved sticks and action bindings to the InputMap.
## The on-disk format is the one written by CalibrationScreen/save_bindings:
##   <channel>_up / _left  -> axis name
##   <channel>_inverted    -> the up/left action sits on the positive axis end
##   <action>              -> ControllerAction.Type
func _apply_saved_bindings(config: ConfigFile, section: String) -> void:
	if not config.has_section(section):
		return

	# Ranges belong to the device section: never leak one radio's endpoints into
	# another radio's axes.
	stick_ranges.clear()

	# --- sticks ---
	for channel in STICK_ACTIONS.keys():
		var pair: Array = STICK_ACTIONS[channel]
		var positive: String = STICK_POSITIVE[channel]
		var negative: String = pair[1] if positive == pair[0] else pair[0]
		if not config.has_section_key(section, pair[0]):
			continue
		var axis := joy_axis_index_from_string(config.get_value(section, pair[0]))
		if axis < 0:
			continue
		var inverted := bool(config.get_value(section, channel + "_inverted", false))
		var first_value := 1.0 if inverted else -1.0
		_add_axis_event(positive, axis, first_value)
		_add_axis_event(negative, axis, -first_value)
		# The wizard saves the actual raw endpoints; older configs do not have
		# them, in which case normalize_stick_raw() falls back to the -1..+1
		# assumption and the inverted flag above.
		var range_min := float(config.get_value(section, channel + "_range_min", NAN))
		var range_max := float(config.get_value(section, channel + "_range_max", NAN))
		var range_center := float(config.get_value(section, channel + "_range_center", NAN))
		if not is_nan(range_min) and not is_nan(range_max):
			set_stick_range(channel, range_min, range_max, range_center)

	# --- buttons / switches ---
	for entry in action_list:
		var action_name: String = entry.action_name
		if not config.has_section_key(section, action_name):
			entry.unbind()
			erase_joypad_events(action_name)
			continue
		var binding_type := int(config.get_value(section, action_name, ControllerAction.Type.NULL))
		entry.unbind()
		entry.bound = binding_type != ControllerAction.Type.NULL
		entry.type = binding_type
		erase_joypad_events(action_name)
		if binding_type == ControllerAction.Type.BUTTON:
			var button := joy_button_index_from_string(config.get_value(section, action_name + "_button", ""))
			if button >= 0:
				entry.button = button
				var event := InputEventJoypadButton.new()
				event.device = -1
				event.button_index = button
				InputMap.action_add_event(action_name, event)
		elif binding_type == ControllerAction.Type.AXIS:
			var axis := joy_axis_index_from_string(config.get_value(section, action_name + "_axis", ""))
			var low := float(config.get_value(section, action_name + "_min", 0.5))
			var high := float(config.get_value(section, action_name + "_max", 1.0))
			entry.axis = axis
			entry.axis_min = low
			entry.axis_max = high
			# Axis switches are dispatched by RadioController as synthetic
			# InputEventAction press/release edges. Binding the raw motion here too
			# makes level handlers fire once for the raw event and again for the
			# synthetic edge (and some handlers do not filter axis repeats).


func create_action_list() -> void:
	var actions := [["arm", "Arm (hold)"],
			["toggle_arm", "Arm (toggle)"],
			["respawn", "Reset drone"],
			["cycle_flight_modes", "Cycle modes"],
			["mode_horizon", "Mode: Horizon"],
			["mode_angle", "Mode: Angle"],
			["mode_speed", "Mode: Speed"],
			["mode_position", "Mode: Position"],
			["mode_turtle", "Mode: Turtle"],
			["mode_launch", "Mode: Launch Control"],
			["altitude_hold", "Hover assist (centre throttle)"],
			["deploy_payload", "Скинути бомбу"],
			["activate_payload", "Активація БЧ / миттєва детонація"],
			["toggle_fpv_effects", "FPV-фільтр"],
			["tutorial_help", "Довідка школи"],
			["tutorial_retry", "Повторити модуль"],
			["pause_menu", "Пауза"]]
	for action in actions:
		action_list.append(ControllerAction.new())
		action_list[-1].init(action[0], action[1])


func get_joypad_guid_list() -> Array:
	var controller_list: Array = []
	for device in Input.get_connected_joypads():
		controller_list.append(Input.get_joy_guid(device))
	return controller_list


func joy_axis_index_from_string(value) -> int:
	var s := str(value).strip_edges().to_lower()
	match s:
		"left x", "left_x", "axis 0", "0", "лівий x", "лівий_x":
			return JOY_AXIS_LEFT_X
		"left y", "left_y", "axis 1", "1", "лівий y", "лівий_y":
			return JOY_AXIS_LEFT_Y
		"right x", "right_x", "axis 2", "2", "правий x", "правий_x":
			return JOY_AXIS_RIGHT_X
		"right y", "right_y", "axis 3", "3", "правий y", "правий_y":
			return JOY_AXIS_RIGHT_Y
		"trigger left", "trigger_left", "left trigger", "axis 4", "4", "лівий тригер", "лівий_тригер":
			return JOY_AXIS_TRIGGER_LEFT
		"trigger right", "trigger_right", "right trigger", "axis 5", "5", "правий тригер", "правий_тригер":
			return JOY_AXIS_TRIGGER_RIGHT
	if s.begins_with("axis "):
		s = s.substr(5)
	elif s.begins_with("вісь "):
		s = s.substr(5)
	if s.is_valid_int():
		return int(s)
	return -1


func joy_button_index_from_string(value) -> int:
	var s := str(value).strip_edges().to_lower()
	match s:
		"a", "button 0", "0":
			return JOY_BUTTON_A
		"b", "button 1", "1":
			return JOY_BUTTON_B
		"x", "button 2", "2":
			return JOY_BUTTON_X
		"y", "button 3", "3":
			return JOY_BUTTON_Y
		"back", "button 4", "4":
			return JOY_BUTTON_BACK
		"guide", "button 5", "5":
			return JOY_BUTTON_GUIDE
		"start", "button 6", "6":
			return JOY_BUTTON_START
		"left stick", "left_stick", "button 7", "7":
			return JOY_BUTTON_LEFT_STICK
		"right stick", "right_stick", "button 8", "8":
			return JOY_BUTTON_RIGHT_STICK
		"left shoulder", "left_shoulder", "button 9", "9":
			return JOY_BUTTON_LEFT_SHOULDER
		"right shoulder", "right_shoulder", "button 10", "10":
			return JOY_BUTTON_RIGHT_SHOULDER
		"d-pad up", "dpad up", "dpad_up", "button 11", "11":
			return JOY_BUTTON_DPAD_UP
		"d-pad down", "dpad down", "dpad_down", "button 12", "12":
			return JOY_BUTTON_DPAD_DOWN
		"d-pad left", "dpad left", "dpad_left", "button 13", "13":
			return JOY_BUTTON_DPAD_LEFT
		"d-pad right", "dpad right", "dpad_right", "button 14", "14":
			return JOY_BUTTON_DPAD_RIGHT
	if s.begins_with("button "):
		s = s.substr(7)
	if s.is_valid_int():
		return int(s)
	return -1


func joy_axis_string(axis: int) -> String:
	match axis:
		JOY_AXIS_LEFT_X:
			return "Лівий X"
		JOY_AXIS_LEFT_Y:
			return "Лівий Y"
		JOY_AXIS_RIGHT_X:
			return "Правий X"
		JOY_AXIS_RIGHT_Y:
			return "Правий Y"
		JOY_AXIS_TRIGGER_LEFT:
			return "Лівий тригер"
		JOY_AXIS_TRIGGER_RIGHT:
			return "Правий тригер"
	return "Вісь %d" % axis


## Stable, locale-independent axis identifier for InputMap.cfg.  The display
## name (`joy_axis_string`) is localized, so it must never be persisted.
func joy_axis_config_string(axis: int) -> String:
	return "axis %d" % axis


func joy_button_string(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_GUIDE:
			return "Guide"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_LEFT_STICK:
			return "Left Stick"
		JOY_BUTTON_RIGHT_STICK:
			return "Right Stick"
		JOY_BUTTON_LEFT_SHOULDER:
			return "Left Shoulder"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "Right Shoulder"
		JOY_BUTTON_DPAD_UP:
			return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Pad Right"
	return "Button %d" % button


func restore_keyboard_shortcuts() -> void:
	# A fresh event per action: InputMap stores the object by reference, so
	# reusing one and changing its keycode would overwrite the previous binding.
	_ensure_key_binding("cycle_flight_modes", KEY_M)
	_ensure_key_binding("toggle_arm", KEY_SPACE)
	_ensure_key_binding("respawn", KEY_BACKSPACE)
	_ensure_key_binding("mode_horizon", KEY_H)
	_ensure_key_binding("deploy_payload", KEY_G)
	_ensure_key_binding("activate_payload", KEY_F)
	_ensure_joypad_button("arm", JOY_BUTTON_RIGHT_STICK)
	_ensure_joypad_button("deploy_payload", JOY_BUTTON_X)
	_ensure_joypad_button("activate_payload", JOY_BUTTON_Y)
	# Camera was shipped on Y in the old project.godot, which now collides with
	# the kamikaze payload (Y).  Keep the right trigger/button, free Y for the
	# warhead and expose every remaining flight function on the pad.
	_ensure_joypad_button("mode_horizon", JOY_BUTTON_DPAD_UP)
	_ensure_joypad_button("mode_angle", JOY_BUTTON_DPAD_RIGHT)
	_ensure_joypad_button("mode_speed", JOY_BUTTON_DPAD_DOWN)
	_ensure_joypad_button("mode_position", JOY_BUTTON_DPAD_LEFT)
	_ensure_joypad_button("altitude_hold", JOY_BUTTON_LEFT_STICK)
	_ensure_joypad_button("toggle_fpv_effects", JOY_BUTTON_MISC1)
	_ensure_key_binding("tutorial_help", KEY_F2)
	_ensure_joypad_button("tutorial_help", JOY_BUTTON_START)
	_ensure_key_binding("tutorial_retry", KEY_T)
	_ensure_joypad_button("tutorial_retry", JOY_BUTTON_B)
	# Erasing a stick action's events also drops the keyboard keys (WASD/arrows)
	# that KeyboardControls added, so put them back.
	var kc := get_node_or_null("/root/KeyboardControls")
	if kc != null and kc.has_method("ensure_bindings"):
		kc.ensure_bindings()


func _ensure_key_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


## Adds a default gamepad button only when the action has no joypad button at
## all, so a radio/gamepad binding made in the Controls screen is never lost.
## One coherent default pad map for the whole simulator.  The old project
## stored raw SDL button numbers (arm on LB, respawn on Back, pause on Start),
## while the HUD and the help promised RS/LB/Back/Start.  Migrate once per
## controller section, then preserve the player's custom bindings.
func _ensure_core_pad_defaults(config: ConfigFile, section: String) -> void:
	var defaults := {
		"toggle_arm": JOY_BUTTON_RIGHT_STICK,
		"arm": JOY_BUTTON_RIGHT_STICK,
		"respawn": JOY_BUTTON_LEFT_SHOULDER,
		"pause_menu": JOY_BUTTON_BACK,
		"cycle_flight_modes": JOY_BUTTON_A,
		"deploy_payload": JOY_BUTTON_X,
		"activate_payload": JOY_BUTTON_Y,
		"altitude_hold": JOY_BUTTON_LEFT_STICK,
		"mode_horizon": JOY_BUTTON_DPAD_UP,
		"mode_angle": JOY_BUTTON_DPAD_RIGHT,
		"mode_speed": JOY_BUTTON_DPAD_DOWN,
		"mode_position": JOY_BUTTON_DPAD_LEFT,
		"tutorial_help": JOY_BUTTON_START,
		"tutorial_retry": JOY_BUTTON_B,
		"toggle_fpv_effects": JOY_BUTTON_MISC1,
	}
	var version := int(config.get_value(section, "pad_defaults_version", 0))
	if version < 3:
		for action in defaults:
			var button := int(defaults[action])
			# Update both the live InputMap and the saved controller section.
			# The old configs stored axes (radio switches) for arm/respawn/
			# camera, so merely adding a button was overwritten on the next
			# load when `_apply_saved_bindings` replayed the axis entry.
			apply_action_binding(action, ControllerAction.Type.BUTTON, button)
			config.set_value(section, action, ControllerAction.Type.BUTTON)
			config.set_value(section, action + "_button", joy_button_string(button))
			for suffix in ["_axis", "_min", "_max"]:
				if config.has_section_key(section, action + suffix):
					config.erase_section_key(section, action + suffix)
		config.set_value(section, "pad_defaults_version", 3)
		var err := config.save(input_map_path)
		if err != OK:
			Global.log_error(err, "Could not save the gamepad default map.")
	else:
		for action in defaults:
			_ensure_joypad_button(action, int(defaults[action]))
	make_joypad_events_global()


func _ensure_joypad_button(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = -1
	InputMap.action_add_event(action, event)


# ---------------------------------------------------------------- bindings API

func _find_action(action: String) -> ControllerAction:
	for entry in action_list:
		if entry.action_name == action:
			return entry
	return null


func refresh_stick_bindings() -> void:
	# Rebuild from scratch so a channel whose binding was cleared in the UI
	# cannot keep a stale axis from a previous calibration.
	for channel in STICK_ACTIONS.keys():
		stick_bindings[channel] = {}
	stick_conflicts.clear()
	var used_axes := {}
	for channel in STICK_ACTIONS.keys():
		var positive: String = STICK_POSITIVE[channel]
		for event in InputMap.action_get_events(positive):
			if event is InputEventJoypadMotion:
				if used_axes.has(event.axis):
					# An old InputMap.cfg may bind one axis to two channels.
					# Keep the first channel, erase the duplicate's joypad
					# events and leave it unbound; the Controls screen shows
					# the conflict and offers recalibration.
					stick_conflicts.append("%s/%s (axis %d)" % [
							used_axes[event.axis], channel, event.axis])
					var pair: Array = STICK_ACTIONS[channel]
					for action in pair:
						erase_joypad_events(action)
					break
				used_axes[event.axis] = channel
				stick_bindings[channel] = {
					"axis": event.axis,
					"inverted": event.axis_value > 0.0,
				}
				break
	# A channel without a live binding must not keep a stale calibration range:
	# the next assignment could be on a different physical axis.
	for channel in STICK_ACTIONS.keys():
		if stick_bindings[channel].is_empty():
			stick_ranges.erase(channel)


## Quick auto-detected stick binding. `observed_value` is the raw axis value
## captured while the user moved the stick in the **positive** direction
## (throttle up, nose up, yaw right, roll right).
func apply_stick(channel: String, axis: int, observed_value: float) -> void:
	if not STICK_ACTIONS.has(channel):
		return
	refresh_stick_bindings()
	# A quick preset/auto-detect has no measured endpoints.  Discard the old
	# calibration range only when the axis actually changes: re-binding the
	# same axis keeps the measured endpoints valid, so the pilot's calibration
	# is not silently destroyed and they do not have to recalibrate again.
	var current: Dictionary = stick_bindings.get(channel, {})
	if current.is_empty() or int(current.get("axis", -1)) != axis:
		stick_ranges.erase(channel)
	# One physical axis must not drive two channels.  If another channel is
	# already on this axis, unbind it first; otherwise a single stick would
	# move throttle and yaw (or pitch and roll) at the same time.
	for other in STICK_ACTIONS.keys():
		if other == channel:
			continue
		var other_binding: Dictionary = stick_bindings.get(other, {})
		if not other_binding.is_empty() and int(other_binding["axis"]) == axis:
			stick_bindings[other] = {}
			stick_ranges.erase(other)
			for other_action in STICK_ACTIONS[other]:
				erase_joypad_events(other_action)
			stick_conflicts.append("%s -> %s (axis %d)" % [other, channel, axis])
	var pair: Array = STICK_ACTIONS[channel]
	var positive: String = STICK_POSITIVE[channel]
	var negative: String = pair[1] if positive == pair[0] else pair[0]
	var first_value := 1.0 if observed_value > 0.0 else -1.0
	_add_axis_event(positive, axis, first_value)
	_add_axis_event(negative, axis, -first_value)
	restore_keyboard_shortcuts()
	make_joypad_events_global()
	refresh_stick_bindings()


## Authoritative stick calibration: `negative_end` / `positive_end` are the raw
## values captured at the channel's negative and positive extremes, `center`
## the measured rest point.  The inverted flag is derived from those raw values
## (never guessed from a preset), and any manual inversion from the old profile
## is cleared so a fresh calibration cannot remain flipped.
func apply_stick_calibrated(channel: String, axis: int, negative_end: float,
		positive_end: float, center: float = NAN) -> void:
	if not STICK_ACTIONS.has(channel):
		return
	if absf(positive_end - negative_end) < 0.1:
		return
	refresh_stick_bindings()
	# One physical axis must not drive two channels.  If another channel is
	# already on this axis, unbind it first.
	for other in STICK_ACTIONS.keys():
		if other == channel:
			continue
		var other_binding: Dictionary = stick_bindings.get(other, {})
		if not other_binding.is_empty() and int(other_binding["axis"]) == axis:
			stick_bindings[other] = {}
			stick_ranges.erase(other)
			for other_action in STICK_ACTIONS[other]:
				erase_joypad_events(other_action)
			stick_conflicts.append("%s -> %s (axis %d)" % [other, channel, axis])
	# Derive inversion from the raw endpoint ORDER, not from the sign of a
	# single captured extreme.  If the captured "negative" end lies numerically
	# above the "positive" end, the radio axis runs backwards for this channel
	# (e.g. throttle down reads +0.9 and throttle up reads −0.9).
	var inverted: bool = negative_end > positive_end
	var pair: Array = STICK_ACTIONS[channel]
	var positive: String = STICK_POSITIVE[channel]
	var negative: String = pair[1] if positive == pair[0] else pair[0]
	var first_value: float = -1.0 if inverted else 1.0
	_add_axis_event(positive, axis, first_value)
	_add_axis_event(negative, axis, -first_value)
	stick_bindings[channel] = {"axis": axis, "inverted": inverted}
	set_stick_range(channel, negative_end, positive_end, center)
	stick_invert[channel] = false
	reset_stick_filters()
	restore_keyboard_shortcuts()
	make_joypad_events_global()
	refresh_stick_bindings()


## Clear every channel's calibration range (used when switching to a keyboard
## profile or resetting the device).
func clear_stick_ranges() -> void:
	stick_ranges.clear()


## Flip the direction of an already-bound stick without re-detecting its axis.
## A calibrated range stores the true direction in its endpoints and ignores
## the InputMap action flag, so with a range the manual override is used
## instead of flipping events (which would have no effect in flight).
func invert_stick(channel: String) -> void:
	var binding: Dictionary = stick_bindings.get(channel, {})
	if binding.is_empty():
		return
	if stick_ranges.has(channel):
		stick_invert[channel] = not bool(stick_invert.get(channel, false))
		reset_stick_filters()
		return
	var positive: String = STICK_POSITIVE[channel]
	var pair: Array = STICK_ACTIONS[channel]
	var negative: String = pair[1] if positive == pair[0] else pair[0]
	var first_value := 1.0 if not bool(binding.get("inverted", false)) else -1.0
	_add_axis_event(positive, int(binding["axis"]), first_value)
	_add_axis_event(negative, int(binding["axis"]), -first_value)
	restore_keyboard_shortcuts()
	make_joypad_events_global()
	refresh_stick_bindings()


func apply_action_binding(action: String, type: int, index: int,
		axis_min: float = 0.5, axis_max: float = 1.0) -> void:
	var entry := _find_action(action)
	if entry == null:
		return
	entry.bound = true
	entry.type = type
	erase_joypad_events(action)
	if type == ControllerAction.Type.BUTTON:
		entry.button = index
		entry.axis = -1
		var event := InputEventJoypadButton.new()
		event.button_index = index
		event.device = -1
		InputMap.action_add_event(action, event)
	elif type == ControllerAction.Type.AXIS:
		entry.axis = index
		entry.button = -1
		entry.axis_min = axis_min
		entry.axis_max = axis_max
		# RadioController edge-detects axis switches and dispatches them through
		# Input.parse_input_event(); do not also bind the raw motion in InputMap.
	restore_keyboard_shortcuts()
	make_joypad_events_global()


func clear_action(action: String) -> void:
	var entry := _find_action(action)
	if entry != null:
		entry.unbind()
	erase_joypad_events(action)
	restore_keyboard_shortcuts()


func describe_stick(channel: String) -> String:
	var binding: Dictionary = stick_bindings.get(channel, {})
	if binding.is_empty():
		return "—"
	return "%s%s" % [joy_axis_string(binding["axis"]),
			" (інв.)" if binding["inverted"] else ""]


func describe_binding(action: String) -> String:
	var entry := _find_action(action)
	if entry != null and entry.bound:
		if entry.type == ControllerAction.Type.BUTTON:
			return joy_button_string(entry.button)
		if entry.type == ControllerAction.Type.AXIS:
			return joy_axis_string(entry.axis)
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return joy_button_string(event.button_index)
		if event is InputEventJoypadMotion:
			return joy_axis_string(event.axis)
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)
	return "—"


func _add_axis_event(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_set_deadzone(action, 0.02)
	InputMap.action_erase_events(action)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = -1
	InputMap.action_add_event(action, event)


## Persist the active device's sticks + action bindings into InputMap.cfg in
## the format `load_input_map()` understands.
func _erase_key(config: ConfigFile, section: String, key: String) -> void:
	if config.has_section_key(section, key):
		config.erase_section_key(section, key)


func save_bindings() -> void:
	if active_controller_guid.is_empty() and active_device >= 0:
		active_controller_guid = Input.get_joy_guid(active_device)
	var section := "controls_" + active_controller_guid
	var config := ConfigFile.new()
	config.load(input_map_path)
	config.set_value("controls", "active_controller_guid", active_controller_guid)
	if active_device >= 0:
		config.set_value("controls", "active_controller_name", Input.get_joy_name(active_device))
	# Global stick tuning: deadband, smoothing and per-channel inversion.
	config.set_value("controls", "stick_deadzone", stick_deadzone)
	config.set_value("controls", "stick_smoothing", stick_smoothing)
	config.set_value("controls", "stick_tuning_version", STICK_TUNING_VERSION)
	for channel in stick_invert.keys():
		config.set_value("controls", "stick_invert_" + channel, bool(stick_invert[channel]))
	for channel in STICK_ACTIONS.keys():
		var binding: Dictionary = stick_bindings.get(channel, {})
		var pair: Array = STICK_ACTIONS[channel]
		if binding.is_empty():
			_erase_key(config, section, pair[0])
			_erase_key(config, section, channel + "_inverted")
			_erase_key(config, section, channel + "_range_min")
			_erase_key(config, section, channel + "_range_max")
			_erase_key(config, section, channel + "_range_center")
			continue
		var axis: int = binding["axis"]
		var inverted: bool = binding["inverted"]
		match channel:
			"throttle":
				config.set_value(section, "throttle_up", joy_axis_config_string(axis))
				config.set_value(section, "throttle_inverted", inverted)
			"yaw":
				config.set_value(section, "yaw_left", joy_axis_config_string(axis))
				config.set_value(section, "yaw_inverted", inverted)
			"pitch":
				config.set_value(section, "pitch_up", joy_axis_config_string(axis))
				config.set_value(section, "pitch_inverted", inverted)
			"roll":
				config.set_value(section, "roll_left", joy_axis_config_string(axis))
				config.set_value(section, "roll_inverted", inverted)
		var rng: Dictionary = stick_ranges.get(channel, {})
		if rng.is_empty():
			_erase_key(config, section, channel + "_range_min")
			_erase_key(config, section, channel + "_range_max")
			_erase_key(config, section, channel + "_range_center")
		else:
			config.set_value(section, channel + "_range_min", float(rng["min"]))
			config.set_value(section, channel + "_range_max", float(rng["max"]))
			config.set_value(section, channel + "_range_center", float(rng["center"]))
	for entry in action_list:
		var action_name: String = entry.action_name
		for suffix in ["", "_button", "_axis", "_min", "_max"]:
			if config.has_section_key(section, action_name + suffix):
				config.erase_section_key(section, action_name + suffix)
		if entry.bound:
			config.set_value(section, action_name, entry.type)
			if entry.type == ControllerAction.Type.BUTTON:
				config.set_value(section, action_name + "_button", joy_button_string(entry.button))
			elif entry.type == ControllerAction.Type.AXIS:
				config.set_value(section, action_name + "_axis", joy_axis_config_string(entry.axis))
				config.set_value(section, action_name + "_min", entry.axis_min)
				config.set_value(section, action_name + "_max", entry.axis_max)
	var err := config.save(input_map_path)
	if err != OK:
		Global.log_error(err, "Error while saving input bindings.")


func _run_selftest() -> void:
	var original_path := input_map_path
	input_map_path = "user://config_G3/InputMap_selftest.cfg"
	active_controller_guid = "SELFTEST-GUID"
	apply_stick("throttle", 1, -0.9)
	apply_stick("yaw", 0, -0.8)
	apply_stick("pitch", 3, 0.85)
	apply_stick("roll", 2, -0.75)
	apply_action_binding("toggle_arm", ControllerAction.Type.BUTTON, 9)
	apply_action_binding("deploy_payload", ControllerAction.Type.BUTTON, 2)
	# Stick tuning: deadband must snap to zero, smoothing must stay monotonic,
	# and all three settings must survive a save/load round trip.
	stick_deadzone = 0.07
	stick_smoothing = 0.15
	stick_invert["yaw"] = true
	reset_stick_filters()
	var deadband_ok := absf(apply_stick_filter("roll", 0.03)) < 0.0001
	reset_stick_filters()
	var pass_ok := apply_stick_filter("roll", 0.5) > 0.3

	# Calibrated endpoints: full physical travel must map to exactly ±1, both
	# for a normal and for a reversed axis.  This is what puts the HUD marker in
	# the corner of its grid instead of stopping a few pixels short.
	stick_ranges.clear()
	set_stick_range("roll", -0.80, 0.75, 0.01)
	var range_left_ok := normalize_stick_raw("roll", -0.80) <= -0.999
	var range_right_ok := normalize_stick_raw("roll", 0.75) >= 0.999
	var range_center_ok := absf(normalize_stick_raw("roll", 0.01)) < 0.001
	set_stick_range("roll", 0.85, -0.80, 0.0)
	var reversed_left_ok := normalize_stick_raw("roll", 0.85) <= -0.999
	var reversed_right_ok := normalize_stick_raw("roll", -0.80) >= 0.999
	set_stick_range("throttle", 0.90, -0.90)
	var throttle_down_ok := normalize_stick_raw("throttle", 0.90) <= -0.999
	var throttle_up_ok := normalize_stick_raw("throttle", -0.90) >= 0.999
	# A fresh wizard calibration must also clear a stale "invert all" flag,
	# otherwise a correctly captured roll channel would still fly backwards.
	stick_invert["roll"] = true
	apply_stick_calibrated("roll", 2, -0.80, 0.75, 0.01)
	var calibrated_invert_cleared := not bool(stick_invert["roll"])
	var calibrated_range_ok := absf(normalize_stick_raw("roll", -0.80) + 1.0) < 0.001

	var arm_live := not InputMap.action_get_events("toggle_arm").is_empty()
	var drop_live := not InputMap.action_get_events("deploy_payload").is_empty()
	var horizon_key := false
	for event in InputMap.action_get_events("mode_horizon"):
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_H:
			horizon_key = true
	save_bindings()
	var config := ConfigFile.new()
	config.load(input_map_path)
	var section := "controls_SELFTEST-GUID"
	var stored := config.has_section_key(section, "throttle_up") \
			and config.has_section_key(section, "toggle_arm_button") \
			and config.has_section_key(section, "deploy_payload_button")
	var ranges_stored := config.has_section_key(section, "roll_range_min") \
			and config.has_section_key(section, "roll_range_max") \
			and config.has_section_key(section, "roll_range_center")
	var tuning_stored := is_equal_approx(float(config.get_value("controls", "stick_deadzone", -1.0)), 0.07) \
			and is_equal_approx(float(config.get_value("controls", "stick_smoothing", -1.0)), 0.15) \
			and bool(config.get_value("controls", "stick_invert_yaw", false)) \
			and int(config.get_value("controls", "stick_tuning_version", 0)) == STICK_TUNING_VERSION
	var ranges_ok := range_left_ok and range_right_ok and range_center_ok \
			and reversed_left_ok and reversed_right_ok \
			and throttle_down_ok and throttle_up_ok
	print("[INPUT-SELFTEST] live arm=", arm_live, " drop=", drop_live,
			" stored=", stored, " deadband=", deadband_ok, " pass=", pass_ok,
			" tuning_stored=", tuning_stored, " horizon_key=", horizon_key,
			" ranges=", ranges_ok, " ranges_stored=", ranges_stored,
			" calibrated=", calibrated_range_ok, "/", calibrated_invert_cleared)
	if arm_live and drop_live and stored and deadband_ok and pass_ok and tuning_stored \
			and horizon_key and ranges_ok and ranges_stored and calibrated_range_ok \
			and calibrated_invert_cleared:
		print("[INPUT-SELFTEST] PASS input bindings")
	else:
		print("[INPUT-SELFTEST] FAIL input bindings")
	stick_deadzone = 0.02
	stick_smoothing = DEFAULT_STICK_SMOOTHING
	stick_invert["yaw"] = false
	stick_ranges.clear()
	reset_stick_filters()
	input_map_path = original_path
	get_tree().quit()
