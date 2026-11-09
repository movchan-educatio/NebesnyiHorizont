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
var status_text := "ELRS: OFF"
var channels := PackedFloat32Array()

var _udp := PacketPeerUDP.new()
var _http: HTTPRequest = null
var _http_busy := false
var _pending_ip := ""
var _last_frame_ms := 0
var _last_activate_ms := 0
var _switch_state := {}
var _switch_ready := false


func _ready() -> void:
	enabled = OS.get_name() == "iOS" or OS.has_environment("ELRS_WIFI")
	channels.resize(CHANNEL_COUNT)
	channels.fill(CENTER)
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
		status_text = "ELRS: UDP %d busy" % err
		push_warning("[ELRS] UDP port 11000 bind failed: %d" % err)
		return
	_udp.set_broadcast_enabled(true)
	status_text = "ELRS: SEARCHING"
	# If the phone is on the module's own AP, 10.0.0.1 is always the module.
	_try_activate("10.0.0.1")


func _process(_delta: float) -> void:
	if not enabled:
		return
	_poll_udp()
	var now := Time.get_ticks_msec()
	if valid and now - _last_frame_ms > STALE_MS:
		valid = false
		status_text = "ELRS: NO DATA"
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
			status_text = "ELRS: FOUND " + ip
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
	status_text = "ELRS: STREAMING"
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
		status_text = "ELRS: CONNECTED " + module_ip
	else:
		status_text = "ELRS: NO MODULE"


func _send_release() -> void:
	if module_ip.is_empty():
		return
	if not is_inside_tree() or _http == null:
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


func _update_switches() -> void:
	var first := not _switch_ready
	for index in [4, 5, 6]:
		var on := _raw(index) > CENTER
		if not first and bool(_switch_state.get(index, on)) != on:
			_dispatch_switch(index, on)
		_switch_state[index] = on
	_switch_ready = true


func _dispatch_switch(index: int, on: bool) -> void:
	var action := ""
	match index:
		4:
			action = "toggle_arm"
		5:
			action = "cycle_flight_modes"
		6:
			action = "cycle_video_mode"
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
