extends Node3D

## QA suite for the ten-module Flight School.  It builds the real course in an
## empty scene and teleports the drone through each module's success condition,
## so every state transition is exercised without a human pilot.

const FlightSchool = preload("res://scripts/util/flight_school.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")

var school: FlightSchool = null
var drone: Drone = null
var _saved_records: Dictionary = {}
var _saved_language: int = LocScript.Language.UA


func _ready() -> void:
	OS.set_environment("DRONE_TUTORIAL_SKIP_BRIEF", "1")
	_saved_records = Global.campaign_records.duplicate(true)
	_saved_language = LocScript.get_language()
	LocScript.set_language(LocScript.Language.UA, false)
	print("=== FLIGHT SCHOOL 10-MODULE QA ===")
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.drone_preset = 0
	Global.set_tutorial_completed(false)

	var scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(scene != null)
	drone = scene.instantiate() as Drone
	add_child(drone)
	drone.freeze = true
	drone.global_position = Vector3(0.0, 1.0, 0.0)

	var hud_root := Control.new()
	hud_root.custom_minimum_size = Vector2(1280, 720)
	add_child(hud_root)

	school = FlightSchool.new()
	add_child(school)
	school.initialize(self, drone, 0.0)
	school.setup_hud(hud_root)
	await get_tree().process_frame
	await get_tree().physics_frame

	assert(school.current_step == FlightSchool.Step.ARMING)
	assert(school.hover_beacon != null)
	assert(not school.gate_forward.is_empty())
	assert(not school.gate_window.is_empty())
	assert(school.brake_node != null)
	assert(school.landing_node != null)
	assert(school._dots.size() == FlightSchool.TOTAL_MODULES)
	print("[OK] course built: 10 progress dots, all gates present")

	# --- 1. ARM -> DISARM -> ARM -------------------------------------------
	assert(school.current_step == FlightSchool.Step.ARMING)
	drone.flight_controller.set_armed(true)
	school.update_flight_school(0.05)
	assert(school.current_step == FlightSchool.Step.ARMING, "one arm is not enough")
	drone.flight_controller.set_armed(false)
	school.update_flight_school(0.05)
	assert(school.current_step == FlightSchool.Step.ARMING, "must arm again")
	drone.flight_controller.set_armed(true)
	school.update_flight_school(0.05)
	assert(school.current_step == FlightSchool.Step.HOVER)
	print("[OK] arm / disarm / arm")

	# --- 2. HOVER ----------------------------------------------------------
	var hov := school.hover_pos
	drone.global_position = Vector3(hov.x, hov.y, hov.z)
	drone.linear_velocity = Vector3.ZERO
	for i in range(15):
		school.update_flight_school(0.3)
	assert(school.current_step == FlightSchool.Step.STICK_BASICS)
	print("[OK] hover 2-4 m hold")

	# --- 3. RIGHT STICK: pitch -> centre -> roll -> centre ------------------
	drone.global_position = Vector3(hov.x, 3.0, hov.z)
	drone.rotation = Vector3(0.22, 0.0, 0.0)
	school.update_flight_school(0.05)
	drone.rotation = Vector3.ZERO
	for i in range(4):
		school.update_flight_school(0.25)
	drone.rotation = Vector3(0.0, 0.0, 0.22)
	school.update_flight_school(0.05)
	drone.rotation = Vector3.ZERO
	for i in range(4):
		school.update_flight_school(0.25)
	assert(school.current_step == FlightSchool.Step.YAW_CONTROL)
	print("[OK] pitch/roll excursions + return to centre")

	# --- 4. YAW 70 degrees and back ----------------------------------------
	drone.rotation = Vector3(0.0, deg_to_rad(80.0), 0.0)
	school.update_flight_school(0.05)
	drone.rotation = Vector3.ZERO
	for i in range(4):
		school.update_flight_school(0.3)
	assert(school.current_step == FlightSchool.Step.FORWARD_GATE)
	print("[OK] yaw turn and return")

	_cross(school.gate_forward)
	assert(school.current_step == FlightSchool.Step.SLALOM)
	print("[OK] forward gate")

	_cross(school.gate_slalom_a)
	_cross(school.gate_slalom_b)
	assert(school.current_step == FlightSchool.Step.ALTITUDE_GATES)
	print("[OK] slalom A/B")

	_cross(school.gate_low)
	_cross(school.gate_high)
	assert(school.current_step == FlightSchool.Step.WINDOW_PASS)
	print("[OK] low/high altitude gates")

	_cross(school.gate_window)
	assert(school.current_step == FlightSchool.Step.BRAKE_STOP)
	print("[OK] window pass")

	# --- 9. BRAKE ----------------------------------------------------------
	drone.global_position = school.brake_pos + Vector3(1.0, 2.0, 1.0)
	drone.linear_velocity = Vector3(0.4, 0.0, 0.2)
	for i in range(7):
		school.update_flight_school(0.3)
	assert(school.current_step == FlightSchool.Step.LANDING)
	print("[OK] brake zone")

	# --- 10. LAND + DISARM -------------------------------------------------
	drone.global_position = school.landing_pos + Vector3(0.4, 0.35, 0.4)
	drone.linear_velocity = Vector3.ZERO
	drone.flight_controller.set_armed(false)
	school.update_flight_school(0.05)
	assert(school.current_step == FlightSchool.Step.COMPLETED)
	assert(Global.is_tutorial_completed())
	print("[OK] landing, disarm and graduation")

	# --- Error assistant ---------------------------------------------------
	school._error_cooldown = 0.0
	drone.flight_controller.set_armed(true)
	drone.global_position = Vector3(0.0, 20.0, 0.0)
	drone.linear_velocity = Vector3(0.0, 8.0, 0.0)
	drone.rotation = Vector3.ZERO
	school._step_alt = 20.0
	school._check_pilot_errors(0.05)
	print("  toast1=", school._toast_lbl.text)
	assert(school._toast_lbl.text.contains("ПЕРЕГАЗОВКА"), school._toast_lbl.text)

	school._error_cooldown = 0.0
	drone.global_position = Vector3(0.0, 10.0, 0.0)
	drone.linear_velocity = Vector3(0.0, -3.0, 0.0)
	drone.rotation = Vector3(0.0, 0.0, PI)
	school._step_alt = 10.0
	school._check_pilot_errors(0.05)
	print("  toast2=", school._toast_lbl.text)
	assert(school._toast_lbl.text.contains("ГОРИЗОНТ"), school._toast_lbl.text)

	school._error_cooldown = 0.0
	drone.rotation = Vector3.ZERO
	drone.linear_velocity = Vector3(0.2, -6.5, 0.1)
	school._step_alt = 15.0
	school._check_pilot_errors(0.05)
	print("  toast3=", school._toast_lbl.text)
	assert(school._toast_lbl.text.contains("КІЛЬЦЕ"), school._toast_lbl.text)

	school._error_cooldown = 0.0
	drone.linear_velocity = Vector3(7.0, 0.0, 0.0)
	school._step_alt = 8.0
	school._check_pilot_errors(0.05)
	print("  toast4=", school._toast_lbl.text)
	assert(school._toast_lbl.text.contains("ЗНОС"), school._toast_lbl.text)
	print("[OK] pilot error assistant")

	print("=== RESULT: FLIGHT SCHOOL 10-MODULE QA PASS ===")
	Global.campaign_records = _saved_records
	Global.save_campaign_records()
	LocScript.set_language(_saved_language, false)
	get_tree().quit(0)


func _cross(gate: Dictionary) -> void:
	var p: Vector3 = gate["pos"]
	drone.global_position = Vector3(p.x, p.y, p.z + 3.0)
	drone.linear_velocity = Vector3(0.0, 0.0, -6.0)
	school.update_flight_school(0.05)
	drone.global_position = Vector3(p.x, p.y, p.z - 3.0)
	school.update_flight_school(0.05)
