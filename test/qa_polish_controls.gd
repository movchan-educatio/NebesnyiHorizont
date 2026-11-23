extends Node

## QA for Phase 1 "polish controls":
##  - custom rate/expo + stick tuning survive a save/load round trip
##  - DroneCatalog.apply() must not clobber pilot rates when custom_rates is set
##  - stick deadzone / smoothing behave exactly as documented
##  - live rate/expo edits propagate to a flying drone in ACRO and ANGLE
##
## Real player configuration is never touched: both config paths are redirected
## to user://qa_polish_tmp/ and restored (with the temp files deleted) on exit.

const TAG := "[QA_POLISH_CONTROLS]"
const TMP_DIR := "user://qa_polish_tmp/"
const QUAD_FILE := "qa_polish_tmp_Quad.cfg"
const INPUT_FILE := "qa_polish_tmp_InputMap.cfg"

var _fail := 0
var _quad: Node = null
var _controls: Node = null
var _quad_path_real := ""
var _input_path_real := ""
var _saved: Dictionary = {}
var _drone: Drone = null
var _fc: FlightController = null
var _profile: ControlProfile = null
var _standalone: ControlProfile = null


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print(TAG, " ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_fail += 1


func _near(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func _ensure_tmp_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


func _delete_temp_files() -> void:
	for file_name in [QUAD_FILE, INPUT_FILE]:
		var path: String = TMP_DIR + str(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.remove_absolute(abs_dir)


## Drive one control tick directly (no physics frames needed).
func _step(power: float, yaw: float, roll: float, pitch: float) -> void:
	if _fc == null:
		return
	_fc.input = [power, yaw, roll, pitch]
	_fc.integrate_loop(0.016, _fc.global_position, _fc.global_transform.basis,
			Vector3.ZERO, Vector3.ZERO)


## Persist rate/expo values through the real QuadSettings signal path.
func _push_rates(p: float, r: float, y: float, ep: float, er: float, ey: float) -> void:
	_quad.set("rate_pitch", p)
	_quad.set("rate_roll", r)
	_quad.set("rate_yaw", y)
	_quad.set("expo_pitch", ep)
	_quad.set("expo_roll", er)
	_quad.set("expo_yaw", ey)
	_quad.set("rate_type", 0)
	_quad.set("custom_rates", true)
	_quad.call("save_quad_settings")


func _run() -> void:
	await get_tree().process_frame
	print(TAG, " START Phase 1 polish-controls verification")

	_quad = get_node_or_null("/root/QuadSettings")
	_controls = get_node_or_null("/root/Controls")
	if _quad == null or _controls == null:
		printerr(TAG, " FAIL missing QuadSettings/Controls autoload")
		_fail += 1
		_finish()
		return

	# --- backup + isolate persistence ---------------------------------------
	_quad_path_real = str(_quad.get("quad_settings_path"))
	_input_path_real = str(_controls.get("input_map_path"))
	_saved = {
		"rate_pitch": _quad.get("rate_pitch"),
		"rate_roll": _quad.get("rate_roll"),
		"rate_yaw": _quad.get("rate_yaw"),
		"expo_pitch": _quad.get("expo_pitch"),
		"expo_roll": _quad.get("expo_roll"),
		"expo_yaw": _quad.get("expo_yaw"),
		"rate_type": _quad.get("rate_type"),
		"custom_rates": _quad.get("custom_rates"),
		"flight_preset": _quad.get("flight_preset"),
		"stick_deadzone": _controls.get("stick_deadzone"),
		"stick_smoothing": _controls.get("stick_smoothing"),
	}
	_ensure_tmp_dir()
	_quad.set("quad_settings_path", TMP_DIR + QUAD_FILE)
	_controls.set("input_map_path", TMP_DIR + INPUT_FILE)
	_check(FileAccess.file_exists(_quad.get("quad_settings_path")) == false,
			"isolated config paths (no real profile loaded from temp)")

	# --- 1. custom values -> save -------------------------------------------
	_quad.set("rate_pitch", 920)
	_quad.set("rate_roll", 880)
	_quad.set("rate_yaw", 740)
	_quad.set("expo_pitch", 0.65)
	_quad.set("expo_roll", 0.55)
	_quad.set("expo_yaw", 0.40)
	_quad.set("rate_type", 0)
	_quad.set("custom_rates", true)
	_quad.set("flight_preset", "custom")
	_controls.set("stick_deadzone", 0.14)
	_controls.set("stick_smoothing", 0.35)
	_quad.call("save_quad_settings")
	_controls.call("save_bindings")
	_check(FileAccess.file_exists(TMP_DIR + QUAD_FILE), "quad settings saved to temp path")
	_check(FileAccess.file_exists(TMP_DIR + INPUT_FILE), "input map saved to temp path")

	# --- 2. drone change must preserve pilot rates --------------------------
	DroneCatalog.apply(2)
	_check(bool(_quad.get("custom_rates")) == true, "custom_rates survives DroneCatalog.apply(2)")
	_check(int(_quad.get("rate_pitch")) == 920, "rate_pitch not overwritten by preset")
	_check(int(_quad.get("rate_roll")) == 880, "rate_roll not overwritten by preset")
	_check(int(_quad.get("rate_yaw")) == 740, "rate_yaw not overwritten by preset")
	_check(_near(float(_quad.get("expo_pitch")), 0.65), "expo_pitch not overwritten by preset")
	_check(_near(float(_quad.get("expo_roll")), 0.55), "expo_roll not overwritten by preset")
	_check(_near(float(_quad.get("expo_yaw")), 0.40), "expo_yaw not overwritten by preset")

	# --- 3. wipe memory, reload, assert exact values ------------------------
	_quad.set("rate_pitch", 123)
	_quad.set("rate_roll", 123)
	_quad.set("rate_yaw", 123)
	_quad.set("expo_pitch", 0.99)
	_quad.set("expo_roll", 0.99)
	_quad.set("expo_yaw", 0.99)
	_quad.set("rate_type", 2)
	_quad.set("custom_rates", false)
	_controls.set("stick_deadzone", 0.0)
	_controls.set("stick_smoothing", 0.0)
	_quad.call("load_quad_settings")
	_controls.call("load_input_map")
	_check(int(_quad.get("rate_pitch")) == 920, "reload rate_pitch == 920")
	_check(int(_quad.get("rate_roll")) == 880, "reload rate_roll == 880")
	_check(int(_quad.get("rate_yaw")) == 740, "reload rate_yaw == 740")
	_check(_near(float(_quad.get("expo_pitch")), 0.65), "reload expo_pitch == 0.65")
	_check(_near(float(_quad.get("expo_roll")), 0.55), "reload expo_roll == 0.55")
	_check(_near(float(_quad.get("expo_yaw")), 0.40), "reload expo_yaw == 0.40")
	_check(int(_quad.get("rate_type")) == 0, "reload rate_type == 0")
	_check(bool(_quad.get("custom_rates")) == true, "reload custom_rates == true")
	_check(_near(float(_controls.get("stick_deadzone")), 0.14), "reload stick_deadzone == 0.14")
	_check(_near(float(_controls.get("stick_smoothing")), 0.35), "reload stick_smoothing == 0.35")

	# --- 4. live drone / control profile / flight controller ----------------
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	if drone_scene == null:
		printerr(TAG, " FAIL Drone1.tscn could not be loaded")
		_fail += 1
		_finish()
		return
	_drone = drone_scene.instantiate() as Drone
	if _drone == null:
		printerr(TAG, " FAIL Drone1.tscn did not instantiate as Drone")
		_fail += 1
		_finish()
		return
	add_child(_drone)
	_fc = _drone.flight_controller
	_profile = _drone.control_profile

	# Standalone ControlProfile, matching the Drone-owned one.
	var standalone := ControlProfile.new()
	standalone.name = "QaStandaloneControlProfile"
	add_child(standalone)
	standalone.set_rates(920, 880, 740)
	standalone.set_expo(0.65, 0.55, 0.40)
	_standalone = standalone
	_check(_fc != null, "FlightController present in Drone1")
	_check(_profile != null, "ControlProfile present in Drone1")
	_check(_profile != null and _fc != null and _fc.control_profile == _profile,
			"FlightController uses the live Drone ControlProfile")
	_check(_near(standalone.get_axis_rate(0, 1.0), 880.0, 0.5),
			"standalone ControlProfile peak rate == 880 deg/s")
	_check(_near(standalone.get_axis_rate(1, 0.5), _profile.get_axis_rate(1, 0.5), 0.5),
			"standalone and live ControlProfile agree at half stick")

	# -- stick deadzone ------------------------------------------------------
	_controls.set("stick_deadzone", 0.14)
	_controls.set("stick_smoothing", 0.0)
	_controls.call("reset_stick_filters")
	var v: float = float(_controls.call("apply_stick_filter", "roll", 0.10, 1.0 / 60.0))
	_check(is_zero_approx(v), "deadzone 0.14 clamps 0.10 input to exactly 0.0 (got %f)" % v)
	_controls.call("reset_stick_filters")
	for _i in range(4):
		v = float(_controls.call("apply_stick_filter", "roll", 0.50, 1.0 / 60.0))
	_check(v > 0.35, "0.50 input past deadzone settles above 0.35 (got %f)" % v)

	# -- smoothing, zero deadzone, full 0 -> 1 step in one 16 ms frame --------
	_controls.set("stick_deadzone", 0.0)
	_controls.set("stick_smoothing", 0.0)
	_controls.call("reset_stick_filters")
	_controls.call("apply_stick_filter", "roll", 0.0, 1.0 / 60.0)
	v = float(_controls.call("apply_stick_filter", "roll", 1.0, 1.0 / 60.0))
	_check(_near(v, 1.0, 0.0001), "no smoothing: single 16 ms frame reaches 1.0 (got %f)" % v)

	_controls.set("stick_smoothing", 0.40)
	_controls.call("reset_stick_filters")
	_controls.call("apply_stick_filter", "roll", 0.0, 1.0 / 60.0)
	v = float(_controls.call("apply_stick_filter", "roll", 1.0, 1.0 / 60.0))
	_check(v < 0.25 and v > 0.0,
			"smoothing 0.40: same flick stays below 0.25, no bypass (got %f)" % v)
	_controls.call("reset_stick_filters")

	# -- arm the live flight controller --------------------------------------
	_fc.input = [0.0, 0.0, 0.0, 0.0]
	_check(bool(_fc.call("request_arm", true)) and bool(_fc.get("state_armed")),
			"FlightController armed")

	# -- ACRO / RATE: live rate edits ----------------------------------------
	_fc.call("change_flight_mode", FlightController.FlightMode.RATE)
	_check(int(_fc.get("flight_mode")) == FlightController.FlightMode.RATE,
			"RATE (ACRO) mode selected")

	_push_rates(250, 250, 250, 0.2, 0.2, 0.2)
	_check(int(_profile.rate_pitch) == 250 and int(_profile.rate_roll) == 250,
			"live ControlProfile updated to 250 immediately (ACRO)")
	_step(0.5, 0.0, 1.0, 0.0)
	var low_target := float(_fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target)
	_step(0.5, 0.0, 0.0, 1.0)
	var low_pitch_target := float(_fc.pid_controllers[FlightController.Controller.PITCH_SPEED].target)

	_push_rates(950, 950, 950, 0.2, 0.2, 0.2)
	_check(int(_profile.rate_pitch) == 950 and int(_profile.rate_roll) == 950,
			"live ControlProfile updated to 950 immediately (ACRO)")
	_step(0.5, 0.0, 1.0, 0.0)
	var high_target := float(_fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target)
	_step(0.5, 0.0, 0.0, 1.0)
	var high_pitch_target := float(_fc.pid_controllers[FlightController.Controller.PITCH_SPEED].target)
	print(TAG, " ACRO rate targets: roll ", low_target, " -> ", high_target,
			" pitch ", low_pitch_target, " -> ", high_pitch_target)
	_check(low_target > 0.0 and high_target > 2.5 * low_target,
			"ACRO roll rate target >2.5x from 250 to 950 (got %.2fx)" %
			(high_target / maxf(low_target, 0.0001)))
	_check(low_pitch_target > 0.0 and high_pitch_target > 2.5 * low_pitch_target,
			"ACRO pitch rate target >2.5x from 250 to 950 (got %.2fx)" %
			(high_pitch_target / maxf(low_pitch_target, 0.0001)))

	# -- ANGLE / LEVEL: same live edits, larger tilt / rate response ----------
	_fc.call("change_flight_mode", FlightController.FlightMode.LEVEL)
	_check(int(_fc.get("flight_mode")) == FlightController.FlightMode.LEVEL,
			"LEVEL (ANGLE) mode selected")
	_push_rates(250, 250, 250, 0.2, 0.2, 0.2)
	_step(0.5, 0.0, 1.0, 0.0)
	var low_level_cmd := float(_fc.call("update_command")[2])
	_push_rates(950, 950, 950, 0.2, 0.2, 0.2)
	_step(0.5, 0.0, 1.0, 0.0)
	var high_level_cmd := float(_fc.call("update_command")[2])
	print(TAG, " LEVEL roll commands: ", low_level_cmd, " -> ", high_level_cmd)
	_check(low_level_cmd > 0.0 and high_level_cmd > 2.5 * low_level_cmd,
			"LEVEL tilt/rate command >2.5x from 250 to 950 (got %.2fx)" %
			(high_level_cmd / maxf(low_level_cmd, 0.0001)))

	# -- expo: half-stick softening, peak unchanged --------------------------
	_fc.call("change_flight_mode", FlightController.FlightMode.RATE)
	_push_rates(900, 900, 900, 0.0, 0.0, 0.0)
	var mid_linear := _profile.get_axis_rate(0, 0.5)
	var peak_linear := _profile.get_axis_rate(0, 1.0)
	_step(0.5, 0.0, 0.5, 0.0)
	var mid_linear_target := float(_fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target)
	_push_rates(900, 900, 900, 0.75, 0.75, 0.75)
	var mid_expo := _profile.get_axis_rate(0, 0.5)
	var peak_expo := _profile.get_axis_rate(0, 1.0)
	_step(0.5, 0.0, 0.5, 0.0)
	var mid_expo_target := float(_fc.pid_controllers[FlightController.Controller.ROLL_SPEED].target)
	print(TAG, " expo half-stick: ", mid_linear, " -> ", mid_expo,
			" peak: ", peak_linear, " -> ", peak_expo)
	_check(mid_expo < mid_linear * 0.60,
			"expo 0.75 cuts half-stick rate by >40%% (got %.1f%%)" %
			(100.0 * (mid_linear - mid_expo) / maxf(mid_linear, 0.0001)))
	_check(_near(peak_expo, peak_linear, 0.5) and _near(peak_linear, 900.0, 0.5),
			"expo preserves full-stick peak (900 deg/s)")
	_check(mid_expo_target < mid_linear_target * 0.60,
			"ACRO rate target shows the same expo reduction")

	_finish()


func _finish() -> void:
	# Release the test-only scene nodes before quitting.
	if _standalone != null and is_instance_valid(_standalone):
		_standalone.free()
	if _drone != null and is_instance_valid(_drone):
		_drone.free()
	# Restore the original persistence paths and the original in-memory values.
	if _quad != null:
		_quad.set("quad_settings_path", _quad_path_real)
		for key in ["rate_pitch", "rate_roll", "rate_yaw", "expo_pitch", "expo_roll",
				"expo_yaw", "rate_type", "custom_rates", "flight_preset"]:
			if _saved.has(key):
				_quad.set(key, _saved[key])
	if _controls != null:
		_controls.set("input_map_path", _input_path_real)
		if _saved.has("stick_deadzone"):
			_controls.set("stick_deadzone", _saved["stick_deadzone"])
		if _saved.has("stick_smoothing"):
			_controls.set("stick_smoothing", _saved["stick_smoothing"])
	# Reload the real player profile, then remove the isolated temp config.
	if _quad != null:
		_quad.call("load_quad_settings")
	if _controls != null:
		_controls.call("load_input_map")
	_delete_temp_files()

	print(TAG, " RESULT ", "PASS" if _fail == 0 else "FAIL", " failures=", _fail)
	print(TAG, " PASS" if _fail == 0 else TAG + " FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
