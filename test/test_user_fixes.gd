extends Node

const HUDStatusScript = preload("res://HUD/HUDStatus.gd")
const LevelScript = preload("res://sceneries/Level.gd")
const ControlsScreenScript = preload("res://GUI/ControlsScreen.gd")

func _ready() -> void:
	print("==================================================")
	print("=== RUNNING USER FIXES VERIFICATION TEST SUITE ===")
	print("==================================================")
	
	# Test 1: Yaw direction
	var fc := FlightController.new()
	fc.control_profile = ControlProfile.new()
	fc.control_profile.set_rates(667.0, 667.0, 667.0)
	fc.control_profile.set_expo(0.2, 0.2, 0.2)
	add_child(fc)
	
	var rate_val := fc._rate_for_axis(2, 1.0)
	assert(rate_val > 0.0, "Expected positive yaw rate for positive stick")
	print("[PASS] 1. Yaw rate calculation is positive for right stick: ", rate_val)
	
	# Test 2: Arm failure signal and HUD message
	var hud_status: Label = HUDStatusScript.new()
	add_child(hud_status)
	
	# Test both enum ArmFail.THROTTLE_HIGH and string "THROTTLE_NOT_LOW"
	hud_status.call("_on_arm_failed", FlightController.ArmFail.THROTTLE_HIGH)
	assert(hud_status.text.contains("ГАЗ НЕ В НУЛІ"), "HUDStatus must show throttle warning")
	print("[PASS] 2a. HUDStatus correctly formats ArmFail enum: ", hud_status.text)
	
	hud_status.call("_on_arm_failed", "THROTTLE_NOT_LOW")
	assert(hud_status.text.contains("ГАЗ НЕ В НУЛІ"), "HUDStatus must accept string throttle warning")
	print("[PASS] 2b. HUDStatus correctly formats string fallback: ", hud_status.text)
	
	# Test 3: AudioListener3D creation on Drone
	var drone_packed := load("res://drone/drones/Drone1.tscn") as PackedScene
	var drone := drone_packed.instantiate() as Drone
	add_child(drone)
	await get_tree().physics_frame
	
	var listener := drone.get_node_or_null("AudioListener3D")
	assert(listener != null, "Drone must have AudioListener3D for audible motor sound")
	print("[PASS] 3. AudioListener3D exists on Drone: ", listener != null)
	
	# Test 4: Drone Preset Selection & Replacement («КВАД-5», index 3)
	Global.drone_preset = 3
	DroneCatalog.apply_to_drone(drone, 3)
	await get_tree().physics_frame
	var p3 := DroneCatalog.preset(3)
	assert(drone.mass < 0.90, "Quad-5 mass should be ~0.83 kg (%s)" % p3.get("name"))
	var model := drone.get_node_or_null("DroneModel")
	assert(model != null, "DroneModel must not be null after attach_model")
	assert(model.name == "DroneModel", "DroneModel node name must remain exact")
	print("[PASS] 4. Applied «КВАД-5»: mass=", drone.mass, " model=", model.name)
	
	# Test 5: Propeller Visual Cleanup in FPV mode
	var level: Node = LevelScript.new()
	level.set("drone", drone)
	add_child(level)
	level.call("_configure_drone_visuals_for_camera", true)
	
	# Check that propeller nodes inside DroneModel are hidden in FPV
	var props_visible := false
	var check_props_fn = func(n: Node, rec: Callable) -> void:
		if n.is_in_group("drone_prop_pivot") or String(n.name).to_lower().contains("propeller"):
			if n is Node3D and (n as Node3D).visible:
				props_visible = true
		for ch in n.get_children():
			rec.call(ch, rec)
	check_props_fn.call(model, check_props_fn)
	assert(not props_visible, "Propellers must be hidden in FPV camera")
	print("[PASS] 5. Propellers cleanly hidden in FPV camera")
	
	# Test 6: ControlsScreen Auto-Detect baseline delta logic
	var cs: Node = ControlsScreenScript.new()
	add_child(cs)
	cs.call("_start_detect", "stick", "roll")
	# Simulate throttle resting at -1.0
	cs.get("_detect_initial_axes")[1] = -1.0 # throttle axis initial
	cs.get("_detect_initial_axes")[2] = 0.0  # roll axis initial
	
	# A packet from throttle comes in at -0.99 (drift)
	var ev_throttle := InputEventJoypadMotion.new()
	ev_throttle.axis = 1
	ev_throttle.axis_value = -0.99
	cs._input(ev_throttle)
	
	# Verify roll is NOT bound to axis 1
	var roll_binding = Controls.stick_bindings.get("roll", {})
	assert(roll_binding.is_empty() or int(roll_binding.get("axis", -1)) != 1,
			"Auto-detect must NOT bind roll to resting throttle axis!")
	print("[PASS] 6a. Resting throttle (-1.0) correctly ignored during Roll auto-detection")
	
	# Now pilot intentionally deflects roll axis to +0.8
	var ev_roll := InputEventJoypadMotion.new()
	ev_roll.axis = 2
	ev_roll.axis_value = 0.8
	cs._input(ev_roll)
	roll_binding = Controls.stick_bindings.get("roll", {})
	assert(not roll_binding.is_empty() and int(roll_binding.get("axis", -1)) == 2,
			"Roll must be bound to axis 2 after intentional deflection")
	print("[PASS] 6b. Intentional roll stick deflection properly captured: axis=", roll_binding.get("axis"))
	
	print("==================================================")
	print("=== ALL USER FIXES VERIFIED SUCCESSFULLY! PASS ===")
	print("==================================================")
	get_tree().quit(0)
