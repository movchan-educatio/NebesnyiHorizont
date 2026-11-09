extends Node
class_name ControlProfile


enum RateType {ACTUAL, BETAFLIGHT, QUICK}

var rate_pitch := 667.0
var rate_roll := 667.0
var rate_yaw := 667.0

var expo_pitch := 0.2
var expo_roll := 0.2
var expo_yaw := 0.2

## Betaflight 4.4/4.5 style rates.  ACTUAL uses center sensitivity and max
## rate; BETAFLIGHT uses RC rate + super rate; QUICK is the simple cubic curve.
## All three honour expo and are selected in the drone setup screen.
var rate_type: int = RateType.BETAFLIGHT
var center_sensitivity_roll := 200.0
var center_sensitivity_pitch := 200.0
var center_sensitivity_yaw := 180.0
var betaflight_rc_rate := 1.0
var betaflight_super_rate := 0.70

## LEVEL mode: maximum lean, how strongly a lean error asks for a turn rate,
## and the rate feedback gain that cancels the old attitude-hold oscillation.
var level_bank_deg := 35.0
var level_angle_gain := 3.0
var level_rate_gain := 0.16
var level_rate_limit := 5.0


func _ready() -> void:
	set_rates(rate_pitch, rate_roll, rate_yaw)
	set_expo(expo_pitch, expo_roll, expo_yaw)


## Betaflight 4.5 rate curve.  `axis` is 0=roll, 1=pitch, 2=yaw and `stick`
## is the raw -1..1 stick position.  Returns degrees per second.
func get_axis_rate(axis: int, stick: float) -> float:
	var s := clampf(stick, -1.0, 1.0)
	var a := absf(s)
	var max_rate: float
	var center: float
	var expo: float
	match axis:
		1:
			max_rate = rate_pitch
			center = center_sensitivity_pitch
			expo = expo_pitch
		2:
			max_rate = rate_yaw
			center = center_sensitivity_yaw
			expo = expo_yaw
		_:
			max_rate = rate_roll
			center = center_sensitivity_roll
			expo = expo_roll
	var expo_factor := 1.0 + expo * (a - 1.0)
	match rate_type:
		RateType.BETAFLIGHT:
			var rc := 200.0 * betaflight_rc_rate * s
			var super_factor := 1.0 / clampf(1.0 - a * betaflight_super_rate, 0.01, 1.0)
			return rc * expo_factor * super_factor
		RateType.QUICK:
			return max_rate * s * a * a * expo_factor
		_:
			# Actual Rates: linear centre + cubic towards max rate.
			var r := center * s + (max_rate - center) * s * a * a
			return r * expo_factor


func set_rate_type(t: int) -> void:
	rate_type = clampi(t, RateType.ACTUAL, RateType.QUICK)


func set_actual_rates(center_roll: float, center_pitch: float, center_yaw: float) -> void:
	center_sensitivity_roll = clampf(center_roll, 10.0, 800.0)
	center_sensitivity_pitch = clampf(center_pitch, 10.0, 800.0)
	center_sensitivity_yaw = clampf(center_yaw, 10.0, 800.0)


func set_betaflight_rates(rc_rate: float, super_rate: float) -> void:
	betaflight_rc_rate = clampf(rc_rate, 0.1, 2.5)
	betaflight_super_rate = clampf(super_rate, 0.0, 0.95)


func set_level_control(bank_deg: float, angle_gain: float, rate_gain: float,
		rate_limit: float) -> void:
	level_bank_deg = clampf(bank_deg, 5.0, 60.0)
	level_angle_gain = clampf(angle_gain, 0.5, 12.0)
	level_rate_gain = clampf(rate_gain, 0.01, 0.3)
	level_rate_limit = clampf(rate_limit, 1.0, 12.0)


func get_rates() -> Array:
	var rates := [rate_pitch, rate_roll, rate_yaw]
	return rates


func set_rates(p : float, r : float, y : float) -> void:
	rate_pitch = p
	rate_roll = r
	rate_yaw = y


func get_expo() -> Array:
	var expo = [expo_pitch, expo_roll, expo_yaw]
	return expo


## The menu value is the real expo weight used by the stick curve: 0 is linear,
## 1 is fully cubic. (The old cube-root conversion made 0.2 behave like 0.58.)
func set_expo(p : float, r : float, y : float) -> void:
	expo_pitch = clampf(p, 0.0, 1.0)
	expo_roll = clampf(r, 0.0, 1.0)
	expo_yaw = clampf(y, 0.0, 1.0)
