extends Node

## Packet-range regression tests; these do not replace testing a real TX.
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOBILE_ELRS] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	OS.set_environment("MOBILE_UI", "1")
	var elrs := get_node("/root/ElrsWifiInput")
	var old_channels: PackedFloat32Array = elrs.channels.duplicate()
	var old_valid: bool = elrs.valid
	var old_format: int = elrs._mobile_channel_format
	var old_map: Dictionary = elrs.channel_map.duplicate(true)
	var old_invert: bool = elrs.invert_throttle
	var old_ip: String = elrs.module_ip
	var old_last_frame: int = elrs._last_frame_ms
	var old_switch_ready: bool = elrs._switch_ready
	var old_switches: Dictionary = elrs._switch_state.duplicate(true)
	var old_arm_state: bool = elrs._armed_level_state
	var old_status: String = elrs.status_text
	elrs.channel_map = {"roll": 0, "pitch": 1, "throttle": 2, "yaw": 3}
	elrs.valid = true
	elrs.invert_throttle = false

	# A realistic 15-bit frame keeps roll, pitch and yaw centered while the
	# throttle crosses the old (and erroneous) 2048 format boundary.
	elrs._mobile_channel_format = elrs.MOBILE_FORMAT_UNKNOWN
	var fifteen := PackedFloat32Array()
	fifteen.resize(16)
	fifteen.fill(16384.0)
	var values: Array[float] = []
	for sample in [0.0, 1000.0, 2048.0, 2049.0, 3000.0, 16384.0, 32767.0]:
		fifteen[2] = sample
		elrs.channels = elrs._canonical_mobile_frame(fifteen)
		values.append(elrs.throttle())
	var monotonic := true
	for i in range(1, values.size()):
		monotonic = monotonic and values[i] >= values[i - 1]
	_check(monotonic and absf(values[3] - values[2]) < 0.001,
			"15-bit throttle remains continuous around 2048/2049")
	_check(elrs._mobile_channel_format == elrs.MOBILE_FORMAT_15BIT,
			"centred 15-bit frame is detected from all primary channels")
	_check(values[0] == 0.0 and values[-1] > 0.999,
			"15-bit throttle preserves its full travel")

	# Native CRSF samples are normalized as one frame, including AUX channels.
	elrs._mobile_channel_format = elrs.MOBILE_FORMAT_UNKNOWN
	var native := PackedFloat32Array()
	native.resize(16)
	native.fill(992.0)
	native[2] = 172.0
	native[4] = 172.0
	elrs.channels = elrs._canonical_mobile_frame(native)
	_check(elrs._mobile_channel_format == elrs.MOBILE_FORMAT_CRSF,
			"native CRSF frame is detected with centred axes")
	_check(absf(elrs._axis(0)) < 0.01 and elrs.throttle() == 0.0,
			"native centred roll and low throttle map correctly")
	_check(elrs.channels[4] < 14000.0, "native low AUX maps below switch threshold")
	native[0] = 172.0
	native[1] = 1811.0
	native[2] = 1811.0
	native[3] = 1811.0
	native[4] = 1811.0
	elrs.channels = elrs._canonical_mobile_frame(native)
	_check(elrs._axis(0) < -0.999 and elrs._axis(1) > 0.999
			and elrs._axis(3) > 0.999 and elrs.throttle() > 0.999,
			"native roll/pitch/yaw/throttle endpoints map correctly")
	_check(elrs.channels[4] > 18000.0, "native high AUX maps above switch threshold")

	# A first frame that looked native can later reveal a 15-bit source. Do not
	# keep clamping all subsequent 15-bit channel values to native full scale.
	fifteen[2] = 2049.0
	elrs.channels = elrs._canonical_mobile_frame(fifteen)
	_check(elrs._mobile_channel_format == elrs.MOBILE_FORMAT_15BIT
			and elrs.throttle() < 0.1, "unambiguous later frame corrects ambiguous initial format")

	# Exercise the real UDP payload parser once, without a network or a flight
	# controller; the initial packet only establishes the AUX baseline.
	elrs.valid = false
	elrs._switch_ready = false
	var packet := PackedByteArray()
	packet.resize(2 + 16 * 2)
	packet[0] = 1
	packet[1] = 16
	for i in range(16):
		packet[2 + 2 * i] = 172
		packet[3 + 2 * i] = 0
	elrs._parse_channels(packet, "127.0.0.1")
	_check(not elrs.valid and not elrs._switch_ready,
			"ambiguous initial frame waits safely without arming")
	for i in range(16):
		var value := 172 if i == 2 or i == 4 else 992
		packet[2 + 2 * i] = value & 0xff
		packet[3 + 2 * i] = value >> 8
	elrs._parse_channels(packet, "127.0.0.1")
	_check(elrs.valid and elrs._mobile_channel_format == elrs.MOBILE_FORMAT_CRSF
			and absf(elrs._axis(0)) < 0.01 and elrs.throttle() == 0.0,
			"real packet parser canonicalizes a native frame")
	_check(not elrs._armed_level_state, "first native packet initializes low ARM without arming")
	elrs.module_ip = ""
	elrs._last_frame_ms = Time.get_ticks_msec() - elrs.STALE_MS - 1
	elrs._process(0.0)
	_check(not elrs.valid and not elrs._switch_ready
			and elrs._mobile_channel_format == elrs.MOBILE_FORMAT_UNKNOWN,
			"stale connection resets format and switch baseline before reconnect")

	elrs.channels = old_channels
	elrs.valid = old_valid
	elrs._mobile_channel_format = old_format
	elrs.channel_map = old_map
	elrs.invert_throttle = old_invert
	elrs.module_ip = old_ip
	elrs._last_frame_ms = old_last_frame
	elrs._switch_ready = old_switch_ready
	elrs._switch_state = old_switches
	elrs._armed_level_state = old_arm_state
	elrs.status_text = old_status
	print("[MOBILE_ELRS] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
