## Tactical haptic & vibration controller tuned for iOS CoreHaptics / Taptic
## Engine and mobile Vibration API (`Input.vibrate_handheld`).
##
## Maps physical flight events (rotor spin/load, surface scrapes/collisions,
## crashes, kamikaze/ordnance blasts, arming toggles and HUD tactile taps) into
## bounded, debounced `duration_ms` + `amplitude` bursts while respecting the
## user's `Global.menu_settings["haptics_enabled"]` preference and pause state.
class_name Haptics
extends RefCounted

const COLLISION_MIN_SPEED := 1.8
const COLLISION_MAX_SPEED := 18.0
const COLLISION_COOLDOWN_MS := 110
const UI_COOLDOWN_MS := 35
const STRONG_OVERRIDE_MS := 140

static var _stats: Dictionary = {
	"total_pulses": 0,
	"by_tag": {},
	"last_tag": "",
	"last_duration_ms": 0,
	"last_amplitude": 0.0,
}
static var _last_event_ms: int = -100000
static var _last_collision_ms: int = -100000
static var _last_collision_amp: float = 0.0
static var _last_ui_ms: int = -100000
static var _last_strong_event_ms: int = -100000
static var _motor_timer_s: float = 0.0


static func is_enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var g := tree.root.get_node_or_null("Global")
		if g != null:
			var ms = g.get("menu_settings")
			if ms is Dictionary:
				return bool((ms as Dictionary).get("haptics_enabled", true))
	return true


static func reset_stats() -> void:
	_stats = {
		"total_pulses": 0,
		"by_tag": {},
		"last_tag": "",
		"last_duration_ms": 0,
		"last_amplitude": 0.0,
	}
	_last_event_ms = -100000
	_last_collision_ms = -100000
	_last_collision_amp = 0.0
	_last_ui_ms = -100000
	_last_strong_event_ms = -100000
	_motor_timer_s = 0.0


static func get_stats() -> Dictionary:
	return _stats.duplicate(true)


static func pulse(duration_ms: int, amplitude: float, tag: String = "") -> bool:
	if not is_enabled():
		return false
	var dur := clampi(duration_ms, 8, 500)
	var amp := clampf(amplitude, 0.0, 1.0)
	if amp <= 0.01:
		return false

	_stats["total_pulses"] = int(_stats.get("total_pulses", 0)) + 1
	var by_tag := _stats.get("by_tag", {}) as Dictionary
	if not tag.is_empty():
		by_tag[tag] = int(by_tag.get(tag, 0)) + 1
	_stats["by_tag"] = by_tag
	_stats["last_tag"] = tag
	_stats["last_duration_ms"] = dur
	_stats["last_amplitude"] = amp

	var now := Time.get_ticks_msec()
	_last_event_ms = now
	if tag != "motor" and tag != "ui" and not tag.is_empty():
		_last_strong_event_ms = now

	if DisplayServer.get_name() != "headless":
		Input.vibrate_handheld(dur, amp)
	return true


static func trigger_collision(impact_speed: float) -> bool:
	if not is_enabled() or impact_speed < COLLISION_MIN_SPEED:
		return false
	var t := clampf((impact_speed - COLLISION_MIN_SPEED)
			/ (COLLISION_MAX_SPEED - COLLISION_MIN_SPEED), 0.0, 1.0)
	var amp := lerpf(0.28, 1.0, t)
	var dur := int(round(lerpf(18.0, 95.0, t)))
	var now := Time.get_ticks_msec()
	if now - _last_collision_ms < COLLISION_COOLDOWN_MS and amp <= _last_collision_amp + 0.25:
		return false
	_last_collision_ms = now
	_last_collision_amp = amp
	return pulse(dur, amp, "collision")


static func trigger_crash() -> bool:
	_motor_timer_s = 0.0
	return pulse(140, 1.0, "crash")


static func trigger_explosion(intensity: float = 1.0) -> bool:
	_motor_timer_s = 0.0
	var k := clampf(intensity, 0.2, 1.35)
	var t := clampf((k - 0.2) / 1.15, 0.0, 1.0)
	var dur := int(round(lerpf(65.0, 180.0, t)))
	var amp := clampf(lerpf(0.55, 1.0, t), 0.2, 1.0)
	return pulse(dur, amp, "explosion")


static func trigger_arm_toggle(armed: bool) -> bool:
	if not armed:
		_motor_timer_s = 0.0
		return pulse(18, 0.42, "disarm")
	return pulse(32, 0.72, "arm")


static func trigger_ui_tap() -> bool:
	var now := Time.get_ticks_msec()
	if now - _last_ui_ms < UI_COOLDOWN_MS:
		return false
	_last_ui_ms = now
	return pulse(12, 0.35, "ui")


## Continuous cadence-modulated motor texture driven by actual rotor RPM &
## throttle load. Immediately stops when disarmed, frozen, or paused.
static func update_motor_feedback(armed: bool, throttle: float, avg_rpm: float,
		max_rpm: float, delta: float) -> bool:
	if not is_enabled() or not armed or max_rpm <= 1.0 or delta <= 0.0:
		_motor_timer_s = 0.0
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.paused:
		_motor_timer_s = 0.0
		return false
	var now := Time.get_ticks_msec()
	if now - _last_strong_event_ms < STRONG_OVERRIDE_MS:
		return false
	var rpm_ratio := clampf(avg_rpm / max_rpm, 0.0, 1.2)
	var thr := clampf(throttle, 0.0, 1.0)
	var load := clampf(maxf(thr * 0.9, rpm_ratio), 0.0, 1.0)
	if rpm_ratio < 0.05 and thr < 0.05:
		_motor_timer_s = 0.0
		return false
	var interval := lerpf(0.22, 0.085, load)
	_motor_timer_s += delta
	if _motor_timer_s < interval:
		return false
	_motor_timer_s = fmod(_motor_timer_s, interval)
	var amp := lerpf(0.08, 0.48, load)
	var dur := int(round(lerpf(12.0, 24.0, load)))
	return pulse(dur, amp, "motor")
