extends Node

## ExpressLRS WiFi Joystick input ("Velocidrone Mobile" protocol) & Feel FPV controller mapping.
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
const STALE_MS := 3000
const CENTER := 16384.0

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
var action_channels: Dictionary = {
	"arm": 4,
	"toggle_arm": 4,
	"deploy_payload": 5,
	"activate_payload": 6,
	"cycle_flight_modes": 7,
	"mode_turtle": 8,
	"mode_angle": 9,
	"mode_horizon": 10,
	"cycle_video_mode": 11,
	"respawn": 12,
	"toggle_weather": 13,
	"pause_menu": 14,
	"altitude_hold": 15,
	"toggle_osd": -1,
	"toggle_fpv_effects": -1,
}

var _udp := PacketPeerUDP.new()
var _http: HTTPRequest = null
var _http_busy := false
var _pending_ip := ""
var _last_frame_ms := 0
var _last_activate_ms := 0
var _switch_state := {}
var _switch_ready := false
var _baseline_channels := PackedFloat32Array()
var _armed_level_state := false


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
		push_warning("[ELRS] UDP port 11000 bind failed: %d" % err)
		return
	_udp.set_broadcast_enabled(true)
	status_text = "ELRS: ПОШУК"
	# Common AP IPs for Radiomaster / ExpressLRS backpack modules
	_try_activate("10.0.0.1")
	_try_activate("192.168.4.1")


func _process(_delta: float) -> void:
	_poll_udp()
	var now := Time.get_ticks_msec()
	if valid and now - _last_frame_ms > STALE_MS:
		valid = false
		status_text = "ELRS: НЕМАЄ ДАНИХ"
		emit_signal("status_changed", status_text)
		channels.fill(CENTER)
	if not valid and now - _last_activate_ms >= int(ACTIVATE_INTERVAL * 1000.0):
		_try_activate(module_ip if not module_ip.is_empty() else "10.0.0.1")


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
	channels = fresh
	var was_valid := valid
	valid = true
	module_ip = ip
	_last_frame_ms = Time.get_ticks_msec()
	status_text = "ELRS: ПОТІК"
	if not was_valid:
		emit_signal("status_changed", status_text)
	_update_switches()


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
func pitch() -> float:
	var ch := int(channel_map.get("pitch", 1))
	var val := _axis(ch)
	return -val if invert_pitch else val


## Direct normalised throttle (0.0..1.0)
func throttle() -> float:
	if not valid or channels.size() < 4:
		return -1.0
	var ch := int(channel_map.get("throttle", 2))
	var raw_val := _raw(ch)
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
func detect_moved_channel(threshold: float = 3500.0) -> int:
	if _baseline_channels.is_empty() or channels.size() < 4:
		return -1
	var best_ch := -1
	var best_delta := 0.0
	var count := mini(channels.size(), _baseline_channels.size())
	for i in range(count):
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
			_dispatch_action_event("toggle_arm", is_on)
			if not is_on:
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
	else:
		Input.action_release(action)


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
	if channel < 0 or channel >= CHANNEL_COUNT:
		action_channels[action] = -1
		if action == "arm" or action == "toggle_arm":
			action_channels["arm"] = -1
			action_channels["toggle_arm"] = -1
			arm_channel = -1
	else:
		action_channels[action] = channel
		if action == "arm" or action == "toggle_arm":
			action_channels["arm"] = channel
			action_channels["toggle_arm"] = channel
			arm_channel = channel
		elif action == "cycle_flight_modes":
			mode_channel = channel
		elif action == "cycle_video_mode":
			video_channel = channel
	save_settings()


func get_action_channel(action: String) -> int:
	return int(action_channels.get(action, -1))


# --------------------------------------------------------------- Settings Persistence
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

	action_channels = {
		"arm": 4,
		"toggle_arm": 4,
		"deploy_payload": 5,
		"activate_payload": 6,
		"cycle_flight_modes": 7,
		"mode_turtle": 8,
		"mode_angle": 9,
		"mode_horizon": 10,
		"cycle_video_mode": 11,
		"respawn": 12,
		"toggle_weather": 13,
		"pause_menu": 14,
		"altitude_hold": 15,
		"toggle_osd": -1,
		"toggle_fpv_effects": -1,
	}
	var stored = cfg.get("elrs_action_channels", {})
	if stored is Dictionary:
		for k in (stored as Dictionary).keys():
			var act := String(k)
			var ch := int((stored as Dictionary)[k])
			if ch >= -1 and ch < CHANNEL_COUNT:
				action_channels[act] = ch

	arm_channel = int(action_channels.get("arm", 4))
	mode_channel = int(action_channels.get("cycle_flight_modes", 7))
	video_channel = int(action_channels.get("cycle_video_mode", 11))


func save_settings() -> void:
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
	_udp.close()
