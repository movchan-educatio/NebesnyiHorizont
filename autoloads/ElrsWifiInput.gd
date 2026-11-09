extends Node

## ExpressLRS WiFi Joystick input ("Velocidrone Mobile" protocol).
##
## The ELRS TX module (3.4+) exposes a Wi-Fi access point / joins the local
## network.  This node discovers its UDP beacon on port 11000, activates the
## stream with an HTTP POST to /udpcontrol, and parses the 15-bit channel
## frames.  It is the iOS-friendly replacement for Apple-blocked USB/BT RC
## controllers and works on Windows/Android too.
##
## Protocol:
##   beacon:  UDP 11000, payload "ELRS" (or "VELOCIDRONE" for TBS)
##   start:   POST http://<ip>/udpcontrol
##            action=joystick_begin&interval=4000&channels=16
##   frames:  UDP 11000: [1, channel_count, uint16 LE channels...]
##   values:  0..32767, 0xF26A (62058) means "no data"
##   stop:    POST action=joystick_end (so the module can be rediscovered)

signal status_changed(text: String)

const UDP_PORT := 11000
const CHANNEL_COUNT := 16
const NO_DATA := 62058
const ACTIVATE_INTERVAL := 5.0
const STALE_MS := 3000
const CENTER := 16384.0

var enabled := false
var valid := false
var module_ip := ""
var status_text := "ELRS: ВИМК."
var channels := PackedFloat32Array()
## ELRS setup (also editable from the on-screen SETUP panel).
## Arm/modes/video are 0-based channel indices: 4 = CH5, 5 = CH6, 6 = CH7.
var invert_roll := true
var arm_channel := 4
var mode_channel := 5
var video_channel := 6
## Any InputMap action -> 0-based ELRS channel.  The old Controls screen uses
## this to bind drop, payload, respawn, flight modes and every other action to
## a Pocket switch, not just arm/modes/video.
var action_channels: Dictionary = {}

var _udp := PacketPeerUDP.new()
var _http: HTTPRequest = null
var _http_busy := false
var _pending_ip := ""
var _last_frame_ms := 0
var _last_activate_ms := 0
var _switch_state := {}
var _switch_ready := false


func _ready() -> void:
	# Keep polling while the setup panel pauses the tree: the live CH1-16
	# readout is how the pilot discovers which switch is which.
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = OS.get_name() == "iOS" or OS.has_environment("ELRS_WIFI")
	channels.resize(CHANNEL_COUNT)
	channels.fill(CENTER)
	_load_settings()
	_http = HTTPRequest.new()
	_http.timeout = 4.0
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)
	set_process(enabled)
	if enabled:
		_start()


func _start() -> void:
	var err := _udp.bind(UDP_PORT, "0.0.0.0")
	if err != OK:
		status_text = "ELRS: UDP %d зайнятий" % err
		push_warning("[ELRS] UDP port 11000 bind failed: %d" % err)
		return
	_udp.set_broadcast_enabled(true)
	status_text = "ELRS: ПОШУК"
	# If the phone is on the module's own AP, 10.0.0.1 is always the module.
	_try_activate("10.0.0.1")


func _process(_delta: float) -> void:
	if not enabled:
		return
	_poll_udp()
	var now := Time.get_ticks_msec()
	if valid and now - _last_frame_ms > STALE_MS:
		valid = false
		status_text = "ELRS: НЕМАЄ ДАНИХ"
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
	valid = true
	module_ip = ip
	_last_frame_ms = Time.get_ticks_msec()
	status_text = "ELRS: ПОТІК"
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


func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	_http_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 \
			and response_code < 300:
		module_ip = _pending_ip
		status_text = "ELRS: ПІДКЛЮЧЕНО " + module_ip
	else:
		status_text = "ELRS: НЕМАЄ МОДУЛЯ"


func _send_release() -> void:
	if module_ip.is_empty():
		return
	if not is_inside_tree() or _http == null or not _http.is_inside_tree():
		return
	if _http_busy:
		return
	_http_busy = true
	_http.request("http://%s/udpcontrol" % module_ip,
			["Content-Type: application/x-www-form-urlencoded"],
			HTTPClient.METHOD_POST, "action=joystick_end")


# --------------------------------------------------------------- channels
func _raw(index: int) -> float:
	if index < 0 or index >= channels.size():
		return CENTER
	return channels[index]


func _axis(index: int) -> float:
	var value := (_raw(index) - CENTER) / CENTER
	if absf(value) < 0.03:
		return 0.0
	return clampf(value, -1.0, 1.0)


func roll() -> float:
	return _axis(0)


func pitch() -> float:
	return _axis(1)


func throttle() -> float:
	if not valid or channels.size() < 3:
		return -1.0
	return clampf(_raw(2) / 32767.0, 0.0, 1.0)


func yaw() -> float:
	return _axis(3)


func _load_settings() -> void:
	var cfg: Dictionary = GameSettings.hud_config
	invert_roll = bool(cfg.get("elrs_invert_roll", true))
	var legacy_arm := clampi(int(cfg.get("elrs_arm_channel", 4)), 0, CHANNEL_COUNT - 1)
	var legacy_mode := clampi(int(cfg.get("elrs_mode_channel", 5)), 0, CHANNEL_COUNT - 1)
	var legacy_video := clampi(int(cfg.get("elrs_video_channel", 6)), 0, CHANNEL_COUNT - 1)
	action_channels.clear()
	var stored = cfg.get("elrs_action_channels", {})
	if stored is Dictionary:
		for key in (stored as Dictionary).keys():
			var action := String(key)
			var channel := int((stored as Dictionary)[key])
			if action.is_empty():
				continue
			if channel >= 0 and channel < CHANNEL_COUNT:
				action_channels[action] = channel
	# Old settings files only had the three core channels.
	if not action_channels.has("toggle_arm"):
		action_channels["toggle_arm"] = legacy_arm
	if not action_channels.has("cycle_flight_modes"):
		action_channels["cycle_flight_modes"] = legacy_mode
	if not action_channels.has("cycle_video_mode"):
		action_channels["cycle_video_mode"] = legacy_video
	_ensure_core_actions()
	_sync_legacy_channels()


## Core actions must always exist and must never share a channel.  If the
## pilot assigns «скид» to CH5, ARM moves to the next free channel instead of
## silently stealing the same switch.
func _ensure_core_actions() -> void:
	for core in ["toggle_arm", "cycle_flight_modes", "cycle_video_mode"]:
		var channel := int(action_channels.get(core, -1))
		var conflict := channel < 0 or channel >= CHANNEL_COUNT
		if not conflict:
			for other in action_channels.keys():
				if String(other) != core and int(action_channels[other]) == channel:
					conflict = true
					break
		if conflict:
			action_channels[core] = _first_free_channel()


func _first_free_channel() -> int:
	var used := {}
	for action in action_channels.keys():
		used[int(action_channels[action])] = true
	for index in range(4, CHANNEL_COUNT):
		if not used.has(index):
			return index
	for index in range(0, 4):
		if not used.has(index):
			return index
	return 4


func _sync_legacy_channels() -> void:
	arm_channel = int(action_channels.get("toggle_arm", 4))
	mode_channel = int(action_channels.get("cycle_flight_modes", 5))
	video_channel = int(action_channels.get("cycle_video_mode", 6))


func save_settings() -> void:
	# The SETUP panel edits the three legacy properties directly, so they are
	# the authoritative source for the core actions here.  A custom action that
	# occupied the same channel is removed; two core actions on one channel are
	# resolved by _ensure_core_actions().
	var requested := {
		"toggle_arm": arm_channel,
		"cycle_flight_modes": mode_channel,
		"cycle_video_mode": video_channel,
	}
	for core in requested.keys():
		var channel := int(requested[core])
		for other in action_channels.keys():
			if String(other) != core and not requested.has(String(other)) \
					and int(action_channels[other]) == channel:
				action_channels.erase(other)
		action_channels[core] = channel
	_ensure_core_actions()
	_sync_legacy_channels()
	var cfg: Dictionary = GameSettings.hud_config
	cfg["elrs_invert_roll"] = invert_roll
	cfg["elrs_arm_channel"] = arm_channel
	cfg["elrs_mode_channel"] = mode_channel
	cfg["elrs_video_channel"] = video_channel
	cfg["elrs_action_channels"] = action_channels.duplicate(true)
	GameSettings.save_hud_config()
	# Re-baseline the switch edges so changing a channel assignment cannot
	# trigger an immediate arm/mode change on the next frame.
	_switch_ready = false
	_switch_state.clear()


## Assign any InputMap action to an ELRS channel (0-based).  Used by the old
## Controls screen so drop, payload, respawn and the rest are bindable on a
## phone.  Pass -1 to clear a non-core action.
func set_action_channel(action: String, channel: int) -> void:
	if action.is_empty():
		return
	if channel < 0 or channel >= CHANNEL_COUNT:
		if action in ["toggle_arm", "cycle_flight_modes", "cycle_video_mode"]:
			# The SETUP panel always shows a channel for these three; keep a
			# valid default instead of leaving a dead entry there.
			channel = {"toggle_arm": 4, "cycle_flight_modes": 5,
					"cycle_video_mode": 6}[action]
		else:
			action_channels.erase(action)
			_ensure_core_actions()
			_sync_legacy_channels()
			save_settings()
			return
	for other in action_channels.keys():
		if String(other) != action and int(action_channels[other]) == channel:
			action_channels.erase(other)
	action_channels[action] = channel
	_ensure_core_actions()
	_sync_legacy_channels()
	save_settings()


func get_action_channel(action: String) -> int:
	return int(action_channels.get(action, -1))


func _channel_action(index: int) -> String:
	for action in action_channels.keys():
		if int(action_channels[action]) == index:
			return String(action)
	return ""


func _update_switches() -> void:
	var first := not _switch_ready
	var indices := {}
	for action in action_channels.keys():
		var index := int(action_channels[action])
		if index >= 0 and index < CHANNEL_COUNT:
			indices[index] = true
	for index in indices.keys():
		var on := _raw(int(index)) > CENTER
		if not first and bool(_switch_state.get(index, on)) != on:
			_dispatch_switch(int(index), on)
		_switch_state[index] = on
	_switch_ready = true


func _dispatch_switch(index: int, on: bool) -> void:
	var action := _channel_action(index)
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


func _exit_tree() -> void:
	_send_release()
	_udp.close()
