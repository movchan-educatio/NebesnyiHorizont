extends Node

## ExpressLRS WiFi Joystick input ("Velocidrone Mobile" protocol) & tactical FPV controller mapping.
##
## The ELRS TX module (3.4+) exposes a Wi-Fi access point / joins the local
## network. This node discovers its UDP beacon on port 11000, activates the
## stream with an HTTP POST to /udpcontrol, and parses the 15-bit channel
## frames. It is the iOS-friendly replacement for Apple-blocked USB/BT RC
## controllers and works on Windows/Android/macOS too.
##
## Protocol:
##   beacon:  UDP 11000, payload "ELRS" (or "VELOCIDRONE" for TBS)
##   start:   POST http://<ip>/udpcontrol
##            action=joystick_begin&interval=4000&channels=16
##   frames:  UDP 11000: [1, channel_count, uint16 LE channels...]
##   values:  0..32767, 0xF26A (62058) means "no data"
##   stop:    POST action=joystick_end (so the module can be rediscovered)

signal status_changed(text: String)
signal arm_state_changed(armed: bool)

const UDP_PORT := 11000
const CHANNEL_COUNT := 16
const NO_DATA := 62058
const ACTIVATE_INTERVAL := 4.0
const STALE_MS := 8000
const CENTER := 16384.0
const MOBILE_FORMAT_UNKNOWN := 0
const MOBILE_FORMAT_15BIT := 1
const MOBILE_FORMAT_CRSF := 2

## v2 moved every optional AUX action off the channel map.  The old defaults
## put pause, turtle, weather and respawn on CH13-CH16, which meant a normal
## EdgeTX/ELRS model (16 channels, switches above CH8) could pause the game or
## flip the flight mode while the pilot was only moving the sticks.
const AUX_DEFAULTS_VERSION := 2
const OLD_DEFAULT_ACTION_CHANNELS := {
	"arm": 4, "toggle_arm": 4, "deploy_payload": 5, "activate_payload": 6,
	"cycle_flight_modes": 7, "mode_turtle": 8, "mode_angle": 9,
	"mode_horizon": 10, "cycle_video_mode": 11, "respawn": 12,
	"toggle_weather": 13, "pause_menu": 14, "altitude_hold": 15,
	"toggle_osd": -1, "toggle_fpv_effects": -1,
}
const SAFE_DEFAULT_ACTION_CHANNELS := {
	"arm": 4, "toggle_arm": 4, "deploy_payload": -1, "activate_payload": -1,
	"cycle_flight_modes": -1, "mode_turtle": -1, "mode_angle": -1,
	"mode_horizon": -1, "cycle_video_mode": -1, "respawn": -1,
	"toggle_weather": -1, "pause_menu": -1, "altitude_hold": -1,
	"toggle_osd": -1, "toggle_fpv_effects": -1,
}

var enabled := false
var valid := false
var module_ip := ""
var status_text := "ELRS: ВИМК."
var channels := PackedFloat32Array()

## Configurable channel mapping for the 4 primary flight axes (0-based: 0 = CH1, 1 = CH2, etc.)
## Default order: AETR (Roll = 0, Pitch = 1, Throttle = 2, Yaw = 3)
var channel_map: Dictionary = {
	"roll": 0,
	"pitch": 1,
	"throttle": 2,
	"yaw": 3,
}

## Independent inversion flags for each stick
var invert_roll := false
var invert_pitch := false
var invert_yaw := false
var invert_throttle := false

## Legacy channel properties (for backwards compatibility)
var arm_channel := 4
var mode_channel := 5
var video_channel := 6

## Action bindings: Action name -> 0-based channel index (4 = CH5, 5 = CH6, etc., -1 = Disabled)
## Only ARM is mapped out of the box.  Optional actions are bound explicitly
## from the mobile controller-setup screen; a stray switch must never pause the
## mission or change the flight mode on its own.
var action_channels: Dictionary = OLD_DEFAULT_ACTION_CHANNELS.duplicate()

var _udp := PacketPeerUDP.new()
var _http: HTTPRequest = null
var _http_busy := false
var _pending_ip := ""
var _last_frame_ms := 0
var _last_valid_ms := 0
var _last_activate_ms := 0
var _switch_state := {}
var _switch_ready := false
var _baseline_channels := PackedFloat32Array()
var _armed_level_state := false
## Input packet range is detected once per connection from the complete primary
## channel frame, not from an individual throttle value. Gameplay always reads
## canonical 15-bit channels so axes, calibration and AUX share one scale.
var _mobile_channel_format := MOBILE_FORMAT_UNKNOWN


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Enabled by default on iOS, or if ELRS_WIFI is set, or if touch controls / mobile UI is active
	enabled = OS.get_name() == "iOS" or OS.has_environment("ELRS_WIFI") or MenuUI.is_mobile_ui() or DisplayServer.is_touchscreen_available()
	channels.resize(CHANNEL_COUNT)
	channels.fill(CENTER)
	_load_settings()
	_http = HTTPRequest.new()
	_http.timeout = 3.5
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	set_process(true)
	_start()


func _start() -> void:
	var err := _udp.bind(UDP_PORT, "0.0.0.0")
	if err != OK:
		status_text = "ELRS: UDP %d" % err
		print_verbose("[ELRS] UDP port %d busy or unavailable (%d)" % [UDP_PORT, err])
		return
	_udp.set_broadcast_enabled(true)
	status_text = "ELRS: ПОШУК"


func _process(delta: float) -> void:
	# Absorb main-thread hitches during scene/level loading so an active Wi-Fi TX
	# session is not falsely marked stale before UDP packets are polled again.
	if valid and delta > 0.35:
		_last_frame_ms += int(minf(delta - 0.05, 12.0) * 1000.0)
	_poll_udp()
	var now := Time.get_ticks_msec()
	if valid:
		_last_valid_ms = now
	if valid and now - _last_frame_ms > STALE_MS:
		valid = false
		if OS.get_name() == "iOS" or OS.has_feature("mobile") \
				or OS.has_environment("MOBILE_UI"):
			_mobile_channel_format = MOBILE_FORMAT_UNKNOWN
			sync_switches()
		status_text = "ELRS: НЕМАЄ ДАНИХ"
		emit_signal("status_changed", status_text)
		channels.fill(CENTER)
	# Only retry activation when an ELRS transmitter module has actually been discovered
	# to prevent continuous socket timeouts / micro-stutters on standard home Wi-Fi
	if not valid and not module_ip.is_empty() and now - _last_activate_ms >= int(ACTIVATE_INTERVAL * 1000.0):
		_try_activate(module_ip)


func was_recently_active(window_ms: int = 20000) -> bool:
	if valid:
		return true
	if _last_valid_ms <= 0:
		return false
	return (Time.get_ticks_msec() - _last_valid_ms) <= window_ms


func scan_now() -> void:
	if not valid:
		_try_activate("10.0.0.1")
		_try_activate("192.168.4.1")


func _poll_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var ip := _udp.get_packet_ip()
		var packet := _udp.get_packet()
		if packet.size() >= 2 and packet[0] == 1:
			_parse_channels(packet, ip)
			continue
		var text := packet.get_string_from_utf8()
		if text.find("ELRS") >= 0 or text.find("VELOCIDRONE") >= 0:
			module_ip = ip
			status_text = "ELRS: ЗНАЙДЕНО " + ip
			emit_signal("status_changed", status_text)
			_try_activate(ip)


func _parse_channels(packet: PackedByteArray, ip: String) -> void:
	var count := int(packet[1])
	if count < 4 or count > CHANNEL_COUNT:
		return
	if packet.size() < 2 + count * 2:
		return
	var fresh := PackedFloat32Array()
	fresh.resize(count)
	for i in range(count):
		var value := int(packet[2 + i * 2]) | (int(packet[3 + i * 2]) << 8)
		if value == NO_DATA:
			return
		fresh[i] = float(value)
	var was_valid := valid
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		if not was_valid:
			_mobile_channel_format = MOBILE_FORMAT_UNKNOWN
		fresh = _canonical_mobile_frame(fresh)
		if _mobile_channel_format == MOBILE_FORMAT_UNKNOWN:
			# An ambiguous frame must not be interpreted as full negative stick
			# input or as an armed switch. Wait for identifiable centered axes.
			module_ip = ip
			var waiting := "ELRS: ВИРІВНЯЙТЕ СТІКИ"
			if status_text != waiting:
				status_text = waiting
				emit_signal("status_changed", status_text)
			return
	channels = fresh
	valid = true
	module_ip = ip
	_last_frame_ms = Time.get_ticks_msec()
	status_text = "ELRS: ПОТІК"
	if not was_valid:
		emit_signal("status_changed", status_text)
	_update_switches()


## The documented ELRS WiFi protocol uses 15-bit samples. Some native CRSF
## sources use 172..1811 instead. Their numeric domains overlap, so a lone
## throttle sample cannot identify the format. Select CRSF only if the entire
## primary frame fits and at least two axes are near its centre; otherwise keep
## 15-bit readings until the frame supplies evidence. Reset on disconnect.
func _canonical_mobile_frame(raw: PackedFloat32Array) -> PackedFloat32Array:
	if raw.size() < 4:
		return raw
	var primary: Array[int] = []
	for key in ["roll", "pitch", "throttle", "yaw"]:
		var index := int(channel_map.get(key, -1))
		if index < 0 or index >= raw.size() or primary.has(index):
			return raw
		primary.append(index)
	var native_range := true
	var above_native := false
	var centred_axes := 0
	for index in primary:
		var value := float(raw[index])
		native_range = native_range and value >= 172.0 and value <= 1811.0
		above_native = above_native or value > 2048.0
		if value >= 792.0 and value <= 1192.0:
			centred_axes += 1
	if _mobile_channel_format == MOBILE_FORMAT_UNKNOWN:
		if above_native:
			_mobile_channel_format = MOBILE_FORMAT_15BIT
		elif native_range and centred_axes >= 2:
			_mobile_channel_format = MOBILE_FORMAT_CRSF
	elif _mobile_channel_format == MOBILE_FORMAT_CRSF and above_native:
		# An initially ambiguous low 15-bit frame can become unambiguous later.
		_mobile_channel_format = MOBILE_FORMAT_15BIT
	if _mobile_channel_format != MOBILE_FORMAT_CRSF:
		return raw
	var converted := raw.duplicate()
	for i in range(converted.size()):
		converted[i] = clampf((raw[i] - 172.0) / 1639.0, 0.0, 1.0) * 32767.0
	return converted


func _try_activate(ip: String) -> void:
	if _http_busy or ip.is_empty():
		return
	_http_busy = true
	_pending_ip = ip
	_last_activate_ms = Time.get_ticks_msec()
	var err := _http.request("http://%s/udpcontrol" % ip,
			["Content-Type: application/x-www-form-urlencoded"],
			HTTPClient.METHOD_POST,
			"action=joystick_begin&interval=4000&channels=16")
	if err != OK:
		_http_busy = false
		status_text = "ELRS: HTTP %d" % err
		emit_signal("status_changed", status_text)


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_http_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300:
		module_ip = _pending_ip
		status_text = "ELRS: ПІДКЛЮЧЕНО " + module_ip
		emit_signal("status_changed", status_text)
	else:
		if not valid:
			status_text = "ELRS: ОЧІКУВАННЯ"
			emit_signal("status_changed", status_text)


func _send_release() -> void:
	if module_ip.is_empty() or not is_inside_tree() or _http == null:
		return
	if _http_busy:
		return
	_http_busy = true
	_http.request("http://%s/udpcontrol" % module_ip,
			["Content-Type: application/x-www-form-urlencoded"],
			HTTPClient.METHOD_POST, "action=joystick_end")


# --------------------------------------------------------------- Channel Readings
func _raw(index: int) -> float:
	if index < 0 or index >= channels.size():
		return CENTER
	return channels[index]


## Returns normalised -1.0..+1.0 with a small deadband around stick centre.
func _axis(index: int) -> float:
	var value := (_raw(index) - CENTER) / CENTER
	if absf(value) < 0.025:
		return 0.0
	return clampf(value, -1.0, 1.0)


## Direct normalised roll (-1..+1)
func roll() -> float:
	var ch := int(channel_map.get("roll", 0))
	var val := _axis(ch)
	return -val if invert_roll else val


## Direct normalised pitch (-1..+1)
## Standard flight physics (RadioController, Controls.gd): stick forward/away = -1.0 (nose down).
func pitch() -> float:
	var ch := int(channel_map.get("pitch", 1))
	var val := _axis(ch)
	# Stick pushed UP yields val > 0; convert to -1.0 forward pitch by default.
	var standard := -val
	return -standard if invert_pitch else standard


## Direct normalised throttle (0.0..1.0)
func throttle() -> float:
	if not valid or channels.size() < 4:
		return -1.0
	var ch := int(channel_map.get("throttle", 2))
	var raw_val := _raw(ch)
	# Mobile native CRSF frames are canonicalized during packet parsing; never
	# select a range from this single value, whose domains overlap.
	var val := clampf(raw_val / 32767.0, 0.0, 1.0)
	if invert_throttle:
		val = 1.0 - val
	# Bottom deadband so resting at bottom reads exact 0.0% and never fails THROTTLE_HIGH
	if val < 0.035:
		return 0.0
	return (val - 0.035) / (1.0 - 0.035)


## Direct normalised yaw (-1..+1)
func yaw() -> float:
	var ch := int(channel_map.get("yaw", 3))
	var val := _axis(ch)
	return -val if invert_yaw else val


# --------------------------------------------------------------- Stick Configuration
func set_stick_channel(stick_name: String, ch_index: int) -> void:
	if not channel_map.has(stick_name):
		return
	channel_map[stick_name] = clampi(ch_index, 0, CHANNEL_COUNT - 1)
	save_settings()


func get_stick_channel(stick_name: String) -> int:
	return int(channel_map.get(stick_name, 0))


func set_stick_invert(stick_name: String, inverted: bool) -> void:
	match stick_name:
		"roll": invert_roll = inverted
		"pitch": invert_pitch = inverted
		"yaw": invert_yaw = inverted
		"throttle": invert_throttle = inverted
	save_settings()


func is_stick_inverted(stick_name: String) -> bool:
	match stick_name:
		"roll": return invert_roll
		"pitch": return invert_pitch
		"yaw": return invert_yaw
		"throttle": return invert_throttle
	return false


# --------------------------------------------------------------- Auto-Detect Helper
func capture_baseline() -> void:
	_baseline_channels = channels.duplicate()


## Returns channel index (0..15) that moved by more than threshold, or -1 if none.
## Set aux_only to true when assigning AUX switches so stick noise (ch 0..3) is ignored.
func detect_moved_channel(threshold: float = 3500.0, aux_only: bool = false) -> int:
	if _baseline_channels.is_empty() or channels.size() < 4:
		return -1
	var best_ch := -1
	var best_delta := 0.0
	var start_idx := 4 if aux_only else 0
	var count := mini(channels.size(), _baseline_channels.size())
	for i in range(start_idx, count):
		var d := absf(channels[i] - _baseline_channels[i])
		if d > best_delta and d >= threshold:
			best_delta = d
			best_ch = i
	return best_ch


# --------------------------------------------------------------- Switch Handling & Arming
func _update_switches() -> void:
	var first := not _switch_ready

	# Handle ARM level switch specifically
	var arm_idx := int(action_channels.get("arm", arm_channel))
	if arm_idx >= 0 and arm_idx < channels.size():
		var raw_arm := _raw(arm_idx)
		var is_on := _armed_level_state
		if raw_arm > 18000.0:
			is_on = true
		elif raw_arm < 14000.0:
			is_on = false
		if not first and _armed_level_state != is_on:
			_armed_level_state = is_on
			emit_signal("arm_state_changed", is_on)
			_dispatch_action_event("arm", is_on)
			if is_on:
				_trigger_arm()
			else:
				# Immediate safety disarm on active flight controller
				_trigger_safety_disarm()
		_armed_level_state = is_on

	# Handle all registered actions
	for action in action_channels.keys():
		if action == "arm" or action == "toggle_arm":
			continue
		var idx := int(action_channels[action])
		if idx < 0 or idx >= CHANNEL_COUNT:
			continue
		var raw_val := _raw(idx)
		var prev_on: bool = bool(_switch_state.get(action, false))
		var on := prev_on
		if raw_val > 18000.0:
			on = true
		elif raw_val < 14000.0:
			on = false
		if not first and prev_on != on:
			_dispatch_action_event(String(action), on)
		_switch_state[action] = on

	_switch_ready = true


func sync_switches() -> void:
	_switch_ready = false
	_switch_state.clear()


func _dispatch_action_event(action: String, on: bool) -> void:
	if action.is_empty() or not InputMap.has_action(action):
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = on
	event.strength = 1.0 if on else 0.0
	Input.parse_input_event(event)
	if on:
		Input.action_press(action)
		# For non-level switch actions, pulse release so next edge triggers cleanly
		if action != "arm":
			call_deferred("_release_action", action)
	else:
		Input.action_release(action)


func _release_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)


func _trigger_arm() -> void:
	var cur_scene := get_tree().current_scene
	if cur_scene == null:
		return
	var drone := cur_scene.get_node_or_null("Drone")
	if drone != null:
		var fc = drone.get("flight_controller")
		if fc != null and fc.has_method("request_arm"):
			fc.request_arm(true)


func _trigger_safety_disarm() -> void:
	var cur_scene := get_tree().current_scene
	if cur_scene == null:
		return
	var drone := cur_scene.get_node_or_null("Drone")
	if drone != null:
		var fc = drone.get("flight_controller")
		if fc != null and fc.has_method("request_disarm"):
			fc.request_disarm()


func set_action_channel(action: String, channel: int) -> void:
	if action.is_empty():
		return
	# CH1-CH4 are stick axes, not AUX switches.  Never bind an action there.
	if channel >= 0 and channel < 4:
		return
	if channel < 0 or channel >= CHANNEL_COUNT:
		action_channels[action] = -1
		if action == "arm" or action == "toggle_arm":
			action_channels["arm"] = -1
			action_channels["toggle_arm"] = -1
			arm_channel = -1
		elif action == "cycle_flight_modes":
			mode_channel = -1
		elif action == "cycle_video_mode":
			video_channel = -1
	else:
		if action == "arm" or action == "toggle_arm":
			# Binding ARM takes the switch over: no second action may fire on
			# the same AUX channel.
			for other in action_channels.keys():
				if other != "arm" and other != "toggle_arm" \
						and int(action_channels[other]) == channel:
					action_channels[other] = -1
			action_channels["arm"] = channel
			action_channels["toggle_arm"] = channel
			arm_channel = channel
		else:
			# A normal action taking a switch releases whatever used to be
			# there.  If that switch was ARM, move ARM to the first free AUX
			# channel instead of silently leaving two actions on one switch.
			var arm_was_here := int(action_channels.get("arm", -1)) == channel
			for other in action_channels.keys():
				if other == "arm" or other == "toggle_arm":
					continue
				if other != action and int(action_channels[other]) == channel:
					action_channels[other] = -1
			action_channels[action] = channel
			if arm_was_here:
				var free := _first_free_aux()
				action_channels["arm"] = free
				action_channels["toggle_arm"] = free
				arm_channel = free
		if action == "cycle_flight_modes":
			mode_channel = channel
		elif action == "cycle_video_mode":
			video_channel = channel
	save_settings()


## First AUX index (CH6+) not used by a non-ARM action, or -1 when all are
## occupied.  Keeps ARM on a real switch when another action claims CH5.
func _first_free_aux() -> int:
	for ch in range(5, CHANNEL_COUNT):
		var used := false
		for other in action_channels.keys():
			if other == "arm" or other == "toggle_arm":
				continue
			if int(action_channels[other]) == ch:
				used = true
				break
		if not used:
			return ch
	return -1


func get_action_channel(action: String) -> int:
	return int(action_channels.get(action, -1))


# --------------------------------------------------------------- Settings Persistence
func _is_mobile_profile() -> bool:
	return OS.has_feature("mobile") or OS.get_name() == "iOS" \
			or MenuUI.is_mobile_ui() or DisplayServer.is_touchscreen_available()


func _load_settings() -> void:
	var cfg: Dictionary = GameSettings.hud_config
	invert_roll = bool(cfg.get("elrs_invert_roll", false))
	invert_pitch = bool(cfg.get("elrs_invert_pitch", false))
	invert_yaw = bool(cfg.get("elrs_invert_yaw", false))
	invert_throttle = bool(cfg.get("elrs_invert_throttle", false))

	if cfg.has("elrs_channel_map") and cfg["elrs_channel_map"] is Dictionary:
		channel_map = (cfg["elrs_channel_map"] as Dictionary).duplicate()
	else:
		channel_map = {"roll": 0, "pitch": 1, "throttle": 2, "yaw": 3}

	action_channels = (SAFE_DEFAULT_ACTION_CHANNELS if _is_mobile_profile()
			else OLD_DEFAULT_ACTION_CHANNELS).duplicate()
	var stored = cfg.get("elrs_action_channels", {})
	if stored is Dictionary:
		for k in (stored as Dictionary).keys():
			var act := String(k)
			var ch := int((stored as Dictionary)[k])
			if ch >= -1 and ch < CHANNEL_COUNT:
				action_channels[act] = ch

	# Migrate profiles written by the old build.  The previous release saved
	# every optional action onto CH6-CH16.  Only reset values that still match
	# those old auto-generated defaults; a genuinely custom binding is kept.
	var defaults_version := int(cfg.get("elrs_action_defaults_version", 1))
	var migrated := false
	if _is_mobile_profile() and defaults_version < AUX_DEFAULTS_VERSION:
		for act in action_channels.keys():
			var old_default := int(OLD_DEFAULT_ACTION_CHANNELS.get(act, -2))
			if old_default >= 0 and int(action_channels[act]) == old_default:
				action_channels[act] = int(SAFE_DEFAULT_ACTION_CHANNELS.get(act, -1))
		# Pause on an AUX switch is never a sensible default: a 16-channel
		# ELRS model would pause the game when that switch moved.
		action_channels["pause_menu"] = -1
		cfg["elrs_action_defaults_version"] = AUX_DEFAULTS_VERSION
		migrated = true

	if _sanitize_action_channels():
		migrated = true
	if migrated:
		save_settings()


## Keeps the persisted action table safe even when it came from an older build
## or a hand-edited config: ARM and toggle_arm are one switch, no action may sit
## on a stick channel (CH1-CH4), and two actions may not share an AUX channel.
## Returns true when anything had to be changed.
func _sanitize_action_channels() -> bool:
	var changed := false
	var arm_ch := int(action_channels.get("arm", -1))
	if arm_ch < 0:
		arm_ch = int(action_channels.get("toggle_arm", -1))
	if arm_ch >= 0 and arm_ch < 4:
		arm_ch = -1
		changed = true
	if int(action_channels.get("arm", -99)) != arm_ch \
			or int(action_channels.get("toggle_arm", -99)) != arm_ch:
		changed = true
	action_channels["arm"] = arm_ch
	action_channels["toggle_arm"] = arm_ch
	arm_channel = arm_ch

	# CH1-CH4 are the sticks.  Binding an action there makes it fire while the
	# pilot is only moving a stick, which is exactly the reported "menu opens
	# by itself" failure mode.
	for action in action_channels.keys():
		if action == "arm" or action == "toggle_arm":
			continue
		var ch := int(action_channels[action])
		if ch >= 0 and ch < 4:
			action_channels[action] = -1
			changed = true

	var used := {}
	for action in action_channels.keys():
		if action == "arm" or action == "toggle_arm":
			continue
		var ch := int(action_channels[action])
		if ch < 0:
			continue
		if ch == arm_ch or used.has(ch):
			action_channels[action] = -1
			changed = true
		else:
			used[ch] = action

	mode_channel = int(action_channels.get("cycle_flight_modes", -1))
	video_channel = int(action_channels.get("cycle_video_mode", -1))
	return changed


func save_settings() -> void:
	# The legacy in-flight setup panel writes arm_channel/mode_channel
	# directly, so fold those properties back into the generic table before
	# persisting; otherwise the new binding is silently ignored on reload.
	if arm_channel >= -1 and arm_channel < CHANNEL_COUNT:
		action_channels["arm"] = arm_channel
		action_channels["toggle_arm"] = arm_channel
	# mode_channel/video_channel are legacy mirrors.  The action table is the
	# authority: deriving them here prevents a stale mirror from re-enabling
	# an action that was just displaced by a conflict.
	mode_channel = int(action_channels.get("cycle_flight_modes", -1))
	video_channel = int(action_channels.get("cycle_video_mode", -1))
	var cfg: Dictionary = GameSettings.hud_config
	cfg["elrs_invert_roll"] = invert_roll
	cfg["elrs_invert_pitch"] = invert_pitch
	cfg["elrs_invert_yaw"] = invert_yaw
	cfg["elrs_invert_throttle"] = invert_throttle
	cfg["elrs_channel_map"] = channel_map.duplicate()
	cfg["elrs_arm_channel"] = arm_channel
	cfg["elrs_mode_channel"] = mode_channel
	cfg["elrs_video_channel"] = video_channel
	cfg["elrs_action_channels"] = action_channels.duplicate(true)
	GameSettings.save_hud_config()
	_switch_ready = false
	_switch_state.clear()


func _exit_tree() -> void:
	_send_release()
	if _http != null and is_instance_valid(_http):
		_http.cancel_request()
		_http.queue_free()
		_http = null
	_udp.close()
