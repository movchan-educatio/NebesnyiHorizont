## Mobile input bridge.
##
## The old PC «Керування» and «Калібрування» screens enumerate USB joypads
## through Input.get_connected_joypads().  On iPhone there is no joypad at all:
## the pilot either uses the on-screen sticks or a Radiomaster Pocket streamed
## over ELRS WiFi.  This autoload exposes those two sources through the same
## four AETR axes, so the existing wizard/binding UI keeps working unchanged.
##
## Axis order matches Controls and EdgeTX Mode 2:
##   0 = roll, 1 = pitch, 2 = throttle, 3 = yaw
## Values are normalised to -1..+1 (touch throttle 0..1 is converted to -1..+1).
extends Node

const DEVICE_ID := -2
const SOURCE_TOUCH := "touch"
const SOURCE_ELRS := "elrs"
const AXIS_CHANNELS := ["roll", "pitch", "throttle", "yaw"]
const AXIS_NAMES := {
	"roll": ["КРЕН", "ROLL"],
	"pitch": ["ТАНГАЖ", "PITCH"],
	"throttle": ["ГАЗ", "THROTTLE"],
	"yaw": ["РИСКАННЯ", "YAW"],
}
const SOURCE_NAMES := {
	"elrs": ["ELRS WiFi", "ELRS WiFi"],
	"touch": ["Сенсорні стіки", "Touch sticks"],
}

## Empty = automatic (ELRS first, then touch).  The setup screens set this
## explicitly when the pilot switches the source there.
var source_override := ""

## source -> channel -> { "min": float, "max": float, "center": float }
## Only ELRS is calibrated; the touch sticks are generated from a fixed radius
## and are already exact, so saving a range for them would only reduce travel.
var calibration := {}


func _ready() -> void:
	_load_calibration()


func elrs() -> Node:
	return get_node_or_null("/root/ElrsWifiInput")


func touch() -> Node:
	return get_node_or_null("/root/TouchControls")


func touch_available() -> bool:
	return OS.get_name() == "iOS" or OS.has_environment("TOUCH_CONTROLS") \
			or DisplayServer.is_touchscreen_available()


func elrs_available() -> bool:
	var wifi := elrs()
	return wifi != null and bool(wifi.get("valid"))


func available_sources() -> Array:
	var out: Array = []
	if elrs_available():
		out.append(SOURCE_ELRS)
	if touch_available():
		out.append(SOURCE_TOUCH)
	return out


func available() -> bool:
	return not available_sources().is_empty()


func default_source() -> String:
	if elrs_available():
		return SOURCE_ELRS
	if touch_available():
		return SOURCE_TOUCH
	return ""


func source() -> String:
	if source_override == SOURCE_ELRS and elrs_available():
		return SOURCE_ELRS
	if source_override == SOURCE_TOUCH and touch_available():
		return SOURCE_TOUCH
	return default_source()


func set_source(value: String) -> void:
	source_override = value


func clear_source_override() -> void:
	source_override = ""


func source_name() -> String:
	return _source_name(source())


func display_name(value: String) -> String:
	return _source_name(value)


func short_source_name(value: String = "") -> String:
	var s := source() if value.is_empty() else value
	match s:
		SOURCE_ELRS:
			return "ELRS"
		SOURCE_TOUCH:
			return "СЕНСОР" if not is_english() else "TOUCH"
	return "—"


func _source_name(value: String) -> String:
	if value.is_empty():
		return "Немає джерела"
	var names: Array = SOURCE_NAMES.get(value, [value, value])
	return String(names[0]) if not is_english() else String(names[1])


func is_english() -> bool:
	return MenuUI.is_english()


## Normalised -1..+1 value for an AETR axis index.
func axis(index: int) -> float:
	match source():
		SOURCE_ELRS:
			return _elrs_axis(index)
		SOURCE_TOUCH:
			return _touch_axis(index)
	return 0.0


func _elrs_axis(index: int) -> float:
	var wifi := elrs()
	if wifi == null or not bool(wifi.get("valid")):
		return 0.0
	var channels: PackedFloat32Array = wifi.get("channels")
	if channels.size() < 4:
		return 0.0
	var value := 0.0
	match index:
		0:
			value = _normalize_center(channels[0])
			value = calibrate(SOURCE_ELRS, "roll", value)
			if bool(wifi.get("invert_roll")):
				value = -value
		1:
			value = calibrate(SOURCE_ELRS, "pitch", _normalize_center(channels[1]))
		2:
			value = calibrate(SOURCE_ELRS, "throttle",
					clampf(channels[2] / 32767.0, 0.0, 1.0) * 2.0 - 1.0)
		3:
			value = calibrate(SOURCE_ELRS, "yaw", _normalize_center(channels[3]))
	return clampf(value, -1.0, 1.0)


func _touch_axis(index: int) -> float:
	var pad := touch()
	if pad == null:
		return 0.0
	var value := 0.0
	match index:
		0:
			value = float(pad.get("roll"))
		1:
			value = float(pad.get("pitch"))
		2:
			value = float(pad.get("throttle")) * 2.0 - 1.0
		3:
			value = float(pad.get("yaw"))
	return clampf(value, -1.0, 1.0)


func _normalize_center(raw: float) -> float:
	return clampf((raw - 16383.5) / 16383.5, -1.0, 1.0)


## Apply the saved range of one source/channel to a normalised value.  The
## calibration wizard stores values in the same -1..+1 space.
func calibrate(source_name_value: String, channel: String, value: float) -> float:
	var by_channel: Dictionary = calibration.get(source_name_value, {})
	var range_value: Dictionary = by_channel.get(channel, {})
	if range_value.is_empty():
		return value
	var lo := float(range_value.get("min", -1.0))
	var hi := float(range_value.get("max", 1.0))
	var center := float(range_value.get("center", NAN))
	return Controls.normalize_range_value(value, lo, hi, center)


func set_calibration(source_name_value: String, channel: String,
		negative_end: float, positive_end: float, center: float = NAN) -> void:
	if absf(positive_end - negative_end) < 0.25:
		return
	var by_channel: Dictionary = calibration.get(source_name_value, {})
	var mid := (negative_end + positive_end) * 0.5
	if is_nan(center):
		center = mid
	var low := minf(negative_end, positive_end)
	var high := maxf(negative_end, positive_end)
	by_channel[channel] = {
		"min": negative_end,
		"max": positive_end,
		"center": clampf(center, low + 0.01, high - 0.01),
	}
	calibration[source_name_value] = by_channel


func clear_calibration(source_name_value: String) -> void:
	calibration.erase(source_name_value)


func save_calibration() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	var hud: Dictionary = settings.get("hud_config")
	hud["mobile_input_calibration"] = calibration.duplicate(true)
	settings.call("save_hud_config")


func _load_calibration() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	var hud: Dictionary = settings.get("hud_config")
	var stored = hud.get("mobile_input_calibration", {})
	if stored is Dictionary:
		calibration = (stored as Dictionary).duplicate(true)


## The PC screens are too wide for an iPhone in landscape.  Both entries use
## this helper to pick their compact layout.
func is_mobile_screen() -> bool:
	if OS.get_name() == "iOS" or DisplayServer.is_touchscreen_available():
		return true
	# Windows QA: the same compact layout must be testable without an iPhone.
	if OS.has_environment("MOBILE_UI_TEST") or OS.has_environment("TOUCH_CONTROLS"):
		return true
	# A desktop window shorter than a phone in landscape.  Do not use the
	# viewport rect here: canvas_items stretching keeps the logical height at
	# 1080 even on a tiny window, so the row count tells us nothing.
	var window_size := DisplayServer.window_get_size()
	return window_size.y > 0 and window_size.y < 560
