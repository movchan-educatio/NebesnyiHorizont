extends RigidBody3D
class_name Drone


signal respawned
signal transform_updated(transform)


var motors := []
@onready var flight_controller := $FlightController
var hud := preload("res://HUD/HUD.tscn").instantiate()

var control_profile := ControlProfile.new()
@export var rate_pitch := 667.0 # (float, 1.0, 1800.0)
@export var rate_roll := 667.0 # (float, 1.0, 1800.0)
@export var rate_yaw := 667.0 # (float, 1.0, 1800.0)
@export var expo_pitch := 0.2 # (float, 0.0, 1.0)
@export var expo_roll := 0.2 # (float, 0.0, 1.0)
@export var expo_yaw := 0.2 # (float, 0.0, 1.0)

signal crashed(reason: String)
## Emitted just before a hard-contact crash.  Armed strike airframes listen to
## this to initiate their integrated warhead; gentle touchdowns never reach it.
signal hard_impact(impact_speed: float)

var drone_transform := Transform3D.IDENTITY
var drone_pos := Vector3.ZERO
var drone_basis := Basis.IDENTITY
var wind_velocity := Vector3.ZERO
var _inverted_ground_timer := 0.0
var _landing_timer := 0.0
var _was_airborne := false
var _parked := false
var _prev_lin_vel := Vector3.ZERO
var _arm_diag_frames := 0
var sim_thrust_mode := true

func set_wind(wind: Vector3) -> void:
	wind_velocity = wind

@export var projected_area := Vector3(0.1, 0.1, 0.1)
@export var cd := Vector3(0.3, 1.3, 0.3)

## RigidBody mass & CoG distribution
var dry_mass: float = 0.42
var battery_mass: float = 0.18
var payload_mass: float = 0.0
var has_payload: bool = false
## Heavy bombers have a mission limit: ~40 km/h loaded and up to 80 km/h
## after release.  Four-rotor racers leave this at zero (no artificial cap).
var speed_limit_ms: float = 0.0
var base_cog_offset: Vector3 = Vector3.ZERO
var payload_cog_offset: Vector3 = Vector3.ZERO
var frame_dimensions: Vector3 = Vector3(0.22, 0.06, 0.22)
var current_preset_index: int = 0
var payload_count: int = 0
var max_payload_count: int = 0
var is_fixed_wing: bool = false
var is_pusher: bool = false
var is_jet: bool = false
var is_vtol_frame: bool = false
var _base_motor_origins: Array[Vector3] = []
var _yaw_torque_scale: float = 1.0
var _battery_cutoff: float = 1.0

## Battery Voltage Sag Simulation
var battery_cells: int = 6
var battery_cell_voltage_rest: float = 4.2
var battery_cell_voltage: float = 4.2
var battery_sag_factor: float = 1.0
var sustained_sag_accum: float = 0.0
## 0 = LiPo (low resistance, high burst), 1 = Li-ion 6S2P 21700 (huge sag).
var battery_chemistry: int = 0
var battery_internal_resistance: float = 0.020
var battery_max_current: float = 120.0
var battery_capacity_mah: float = 1300.0
var battery_used_mah: float = 0.0
var battery_current_draw: float = 0.0
var battery_voltage: float = 25.2
var low_voltage_warn: bool = false

## All airframes get a larger usable pack in this build.  Capacity is now part
## of the flight model (voltage falls as the pack is used), so this is a real
## endurance increase rather than a cosmetic number.
const BATTERY_CAPACITY_SCALE := 1.45

## Propwash phase accumulates inside the 960 Hz substep loop so the
## turbulence is continuous instead of being quantised to the 120 Hz frame.
var _propwash_phase: float = 0.0
var _prev_throttle_cmd: float = 0.0
## Flight-controller sub-iterations per physics tick.  8 at 120 Hz = 960 Hz
## control loop.  Weak-PC presets may lower this (QA: QA_FC_SUBSTEPS).
var _fc_substeps := 8

var target_max_twr: float = 8.5
## True static thrust-to-weight at full RPM on a fresh battery, measured from
## the blade-element model.  The throttle curve is normalised against this so
## the hover stick actually hovers; target_max_twr stays the design figure used
## by the HUD and the analytic (non-sim) thrust path.
var physical_max_twr: float = 0.0
var current_total_thrust: float = 0.0
var _debug_print_timer: float = 0.0

## Atmospheric Motor Audio Synthesis & Doppler
var _motor_audio: AudioStreamPlayer3D = null
var _motor_audio_pitch: float = 0.70
var _motor_audio_vol: float = -45.0
var _motor_audio_tick: float = 0.0
var _motor_audio_accum: float = 0.0

## Mass the propeller model was tuned for. Thrust is scaled by the actual mass
## divided by this, so heavy presets (combat bomber) can still hover and climb.
const THRUST_REFERENCE_MASS := 0.73
var thrust_scale := 1.0

## Per-airframe-class motor/airframe response.  RPM_ACCELERATION is multiplied
## by the motor torque to get the RPM/s spool rate, so a 5" racer with 1.3 Nm
## needs a much larger number than a 10" heavy-lift motor with 5.5 Nm.
## Target 0->90% spool: micro ~0.06 s, 5" ~0.08 s, 7" ~0.12 s,
## 8" ~0.15 s, 10" ~0.20 s.  The old single 16k value made the 5" slower
## than the 10" and was the main reason punch-outs felt like a bus.
const PHYSICS_PROFILES := {
	"micro": {"rpm_accel": 500000.0, "esc_brake": 2.2, "propwash": 0.85},
	"5inch": {"rpm_accel": 300000.0, "esc_brake": 2.0, "propwash": 1.00},
	"7inch": {"rpm_accel": 80000.0, "esc_brake": 1.9, "propwash": 1.12},
	"8inch": {"rpm_accel": 40000.0, "esc_brake": 1.7, "propwash": 1.22},
	"10inch": {"rpm_accel": 14000.0, "esc_brake": 1.5, "propwash": 1.30},
}
var physics_class := "5inch"
var propwash_gain := 1.0

## World-space force collected from outside the flight model (rotor wash,
## explosions). The custom integrator consumes and clears it every step, so
## regular RigidBody3D forces would have no effect here.
var external_force := Vector3.ZERO


## Queue a world-space force for the next physics step.
func apply_external_force(force: Vector3) -> void:
	external_force += force

var ray : RayCast3D

@onready var debug_geom := get_tree().root.get_node_or_null("Level/DebugGeometry")
var b_debug := false


func _ready() -> void:
	# QA/docs: let a benchmark isolate the flight-controller costs from the
	# rest of the world physics.
	var qa_substeps := OS.get_environment("QA_FC_SUBSTEPS")
	if not qa_substeps.is_empty():
		_fc_substeps = clampi(int(qa_substeps), 1, 8)
	# Never let the body fall asleep: a sleeping rigid body stops receiving
	# _integrate_forces, so the motors would compute no thrust and the drone
	# would ignore the sticks.
	can_sleep = false
	# Continuous collision detection against static scenery at high FPV speeds (120+ km/h)
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	
	# Tactical shock-absorption physics: zero bounce (restitution), high friction rubber skids
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.0
	pmat.friction = 0.95
	pmat.absorbent = true
	physics_material_override = pmat
	linear_damp = 0.25
	angular_damp = 0.50
	var frame := get_node_or_null("Frame")
	if frame != null and frame.has_method("update_collision_shapes"):
		for shape in frame.collision_shapes:
			frame.remove_child(shape)
			add_child(shape)
	motors = [$Motor1, $Motor2, $Motor3, $Motor4]
	# Hide legacy stock prototype visuals (Frame1 and Motor1 meshes)
	if frame != null:
		_hide_all_visuals(frame)
	for motor in motors:
		_hide_all_visuals(motor)
		if motor.get("propeller") != null:
			motor.propeller.suppressed = true
			_hide_all_visuals(motor.propeller)

	flight_controller.set_motors(motors)
#	var prop = motors[0].propeller
#	var hover_rpm = sqrt(mass / 4 * 9.81 * 1000 / prop.LIFT_RATIO / pow(PI / 30.0, 2) / pow(prop.radius, 2))
#	flight_controller.set_hover_rpm(hover_rpm)
	flight_controller.set_hover_thrust(mass / 4 * 9.81)
	
	# Ground effect parameters
	var rad: float = motors[0].propeller.diameter * 0.0254 * 0.5
	var d: float = min((motors[0].transform.origin - motors[1].transform.origin).length(),
			(motors[0].transform.origin - motors[3].transform.origin).length())
	var b: float = (motors[0].transform.origin - motors[2].transform.origin).length()
	for motor in motors:
		motor.propeller.set_ground_effect_parameters(rad, d, b, 1)
	
	add_child(hud)
	var _discard = flight_controller.connect("armed", Callable(hud.status, "_on_armed"))
	_discard = flight_controller.connect("disarmed", Callable(hud.status, "_on_disarmed"))
	_discard = flight_controller.connect("armed", _on_armed_signal)
	_discard = flight_controller.connect("disarmed", _on_disarmed_signal)
	_discard = flight_controller.connect("flight_mode_changed", Callable(hud.status, "_on_mode_changed"))
	_discard = flight_controller.connect("arm_failed", Callable(hud.status, "_on_arm_failed"))
	
	add_child(control_profile)
	control_profile.set_rates(rate_pitch, rate_roll, rate_yaw)
	control_profile.set_expo(expo_pitch, expo_roll, expo_yaw)
	flight_controller.set_control_profile(control_profile)
	
	QuadSettings.load_quad_settings()
	if not QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		QuadSettings.connect("settings_updated", Callable(self, "_on_quad_settings_updated"))
	_on_quad_settings_updated()
	if Global.should_use_gentle_angle_assist() and flight_controller != null:
		flight_controller.select_flight_mode(FlightController.FlightMode.LEVEL)
	# FlightController defaults to LEVEL before the drone connects to its HUD
	# signal; push the current mode once so the on-screen badge matches.
	_on_flight_mode_changed(flight_controller.flight_mode)
	
	if not GameSettings.hud_config_updated.is_connected(_on_hud_config_updated):
		GameSettings.connect("hud_config_updated", Callable(self, "_on_hud_config_updated"))
	_on_hud_config_updated()
	
	# Add anti-checkpoint ghosting raycast
	ray = RayCast3D.new()
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	for motor in motors:
		for child in motor.get_children():
			if child is Area3D:
				ray.add_exception(child)
			else:
				for great_child in child.get_children():
					if great_child is Area3D:
						ray.add_exception(great_child)
	add_child(ray)
	ray.enabled = true
	_setup_motor_audio()
	


func _process(delta: float) -> void:
	update_hud_data(delta)
	
	# Animate the authentic 3D drone model propellers
	var model_node := get_node_or_null("DroneModel") as Node3D
	if model_node != null and is_instance_valid(model_node):
		var rpms := []
		for motor in motors:
			rpms.append(float(motor.rpm))
		DroneCatalog.animate_propellers(model_node, delta, rpms)
	
	if b_debug and debug_geom:
		for motor in motors:
			var prop = motor.propeller
			var vec_force: Vector3 = prop.global_transform.basis.y * prop.get_thrust()
			var vec_pos: Vector3 = prop.global_transform.origin - global_transform.origin
			debug_geom.draw_debug_arrow(delta, global_transform.origin + vec_pos, vec_force, vec_force.length() / 50,
					Color(5, 1, 0))
		
		var global_xform := global_transform
		var global_basis := global_xform.basis
		debug_geom.draw_debug_grid(0.02, global_xform * (Vector3(0, 0, 0)), 1.5, 1.5, 1, 1,
				Vector3.UP, global_basis * (Vector3.RIGHT))
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3.UP),
				linear_velocity, linear_velocity.length() / 10)
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3.UP),
				Vector3.RIGHT, linear_velocity.x / 10, Color(10, 0, 0))
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3.UP),
				Vector3.UP, linear_velocity.y / 10, Color(0, 10, 0))
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3.UP),
				Vector3.BACK, linear_velocity.z / 10, Color(0, 0, 10))
		
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3(0.2, 0, 0.5)),
				global_basis * (Vector3.RIGHT), (linear_velocity) * global_basis.x / 10,
				Color(10, 0, 0))
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3(-0.2, 0, 0.5)),
				global_basis * (Vector3.UP), linear_velocity.y / 10,
				Color(0, 10, 0))
		debug_geom.draw_debug_arrow(0.02, global_xform * (Vector3(0.2, 0, 0.5)),
				global_basis * (Vector3.DOWN), (linear_velocity) * global_basis.z / 10,
				Color(0, 0, 10))


func _physics_process(delta: float) -> void:
	var throttle_input: float = 0.0
	if flight_controller != null and not flight_controller.input.is_empty():
		throttle_input = float(flight_controller.input[0])
	var total_thrust: float = current_total_thrust
	_debug_print_timer -= delta
	# Debug throttle print disabled for clean console output
	# if _debug_print_timer <= 0.0:
	# 	_debug_print_timer = 0.25
	# 	print("Вхід газу: ", snappedf(throttle_input, 0.01), " | Тяга: ", snappedf(total_thrust, 0.1))

	drone_transform = global_transform
	drone_pos = drone_transform.origin
	drone_basis = drone_transform.basis
	
	var replay_transform := "%s, %s, %s, %s" % [drone_basis.x, drone_basis.y, drone_basis.z, drone_pos]
	replay_transform = replay_transform.replace("(", "").replace(")", "").replace(" ", "")
	emit_signal("transform_updated", replay_transform)
	
	# Cast a ray 1 meter in the direction of the drone's velocity vector
	# This is used as a backup check for checkpoints at high speeds
	var cast_vector := (linear_velocity) * drone_transform.basis
	if cast_vector.length_squared() > 1:
		cast_vector = cast_vector.normalized()
	if is_instance_valid(ray):
		ray.target_position = cast_vector
		ray.force_raycast_update()
		if ray.is_colliding():
			var collider := ray.get_collider()
			if collider is Area3D and collider.has_method("_on_drone_raycast_hit"):
				collider.call("_on_drone_raycast_hit", self)
	
	if b_debug and debug_geom:
		var drag: Vector3 = get_drag(linear_velocity, angular_velocity, drone_basis)[0]
		debug_geom.draw_debug_arrow(0.01, drone_pos, drag.normalized(), drag.length() / 10)
	_update_motor_audio(delta)
	var motors_armed: bool = flight_controller != null and flight_controller.state_armed \
			and visible and not freeze
	var avg_rpm := 0.0
	var max_rpm := 1.0
	if not motors.is_empty():
		for m in motors:
			if m != null:
				avg_rpm += absf(float(m.rpm))
				max_rpm = maxf(max_rpm, float(m.MAX_RPM))
		avg_rpm /= float(motors.size())
	Haptics.update_motor_feedback(motors_armed, throttle_input, avg_rpm, max_rpm, delta)


func _setup_motor_audio() -> void:
	var listener := get_node_or_null("AudioListener3D") as AudioListener3D
	if listener == null:
		listener = AudioListener3D.new()
		listener.name = "AudioListener3D"
		add_child(listener)
	if DisplayServer.get_name() != "headless":
		listener.make_current()

	if _motor_audio == null:
		_motor_audio = AudioStreamPlayer3D.new()
		_motor_audio.name = "MotorAudio3D"
		_motor_audio.bus = "Engine"
		_motor_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		_motor_audio.unit_size = 14.0
		_motor_audio.max_distance = 350.0
		_motor_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(_motor_audio)
	refresh_motor_audio()


func refresh_motor_audio() -> void:
	if _motor_audio == null:
		return
	var preset := int(Global.drone_preset)
	var p := DroneCatalog.preset(preset)
	var kind := int(p.get("audio_kind", 1 if mass >= 1.5 else 0))
	_motor_audio.stream = CombatSfx.drone_motor_stream(kind)
	_motor_audio.volume_db = -45.0
	_motor_audio.pitch_scale = 0.70
	if flight_controller != null and flight_controller.state_armed and not _motor_audio.playing:
		_motor_audio.play()


func _update_motor_audio(delta: float) -> void:
	if _motor_audio == null:
		return
	_motor_audio_tick -= delta
	_motor_audio_accum += delta
	if _motor_audio_tick > 0.0:
		return
	_motor_audio_tick = 1.0 / 30.0
	delta = _motor_audio_accum
	_motor_audio_accum = 0.0
	var armed: bool = flight_controller != null and flight_controller.state_armed
	if not armed:
		_motor_audio_vol = lerpf(_motor_audio_vol, -65.0, delta * 14.0)
		_motor_audio.volume_db = _motor_audio_vol
		if _motor_audio_vol <= -60.0 and _motor_audio.playing:
			_motor_audio.stop()
		return

	if not _motor_audio.playing:
		if _motor_audio_vol < -22.0:
			_motor_audio_vol = -20.0
		_motor_audio.volume_db = _motor_audio_vol
		_motor_audio.play()

	var throttle: float = 0.0
	var stick_load: float = 0.0
	if flight_controller != null and not flight_controller.input.is_empty():
		throttle = clampf(float(flight_controller.input[0]), 0.0, 1.0)
		var r: float = absf(float(flight_controller.input[1])) if flight_controller.input.size() > 1 else 0.0
		var p: float = absf(float(flight_controller.input[2])) if flight_controller.input.size() > 2 else 0.0
		var y: float = absf(float(flight_controller.input[3])) if flight_controller.input.size() > 3 else 0.0
		stick_load = clampf((r + p + y) * 0.35, 0.0, 0.35)

	# RPM modulation: Idle pitch ~0.68, Full throttle ~2.20 + extra pitch bite on stick load
	var target_pitch: float = lerpf(0.68, 2.20, throttle) + stick_load
	var target_vol: float = lerpf(-22.0, -8.0, throttle) + (stick_load * 2.0)

	_motor_audio_pitch = lerpf(_motor_audio_pitch, target_pitch, delta * 15.0)
	_motor_audio_vol = lerpf(_motor_audio_vol, target_vol, delta * 12.0)

	_motor_audio.pitch_scale = clampf(_motor_audio_pitch, 0.45, 2.75)
	_motor_audio.volume_db = clampf(_motor_audio_vol, -45.0, -3.5)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	sleeping = false
	# 8 substeps at 120 Hz physics = 960 Hz flight-controller loop, inside the
	# 500-1000 Hz band used by Betaflight 4.4/4.5 on real FPV hardware.
	var steps := _fc_substeps
	if !flight_controller.state_armed:
		steps = 1
	var dt := state.step / (steps as float)
	
	var xform := state.transform.orthonormalized()
	var pos := xform.origin
	var basis := xform.basis
	var lin_vel := state.linear_velocity
	var ang_vel := state.angular_velocity
	
	var throttle_cmd: float = 0.0
	if flight_controller != null and not flight_controller.input.is_empty():
		throttle_cmd = float(flight_controller.input[0])
	var contact_count := state.get_contact_count()
	var on_ground := (contact_count > 0)
	# Landing assist: at low collective, look up to 5 m below the airframe and
	# cushion the final descent.  Five rays (centre + four corners) catch roof
	# edges and sloped surfaces, not just flat terrain, so a controlled
	# touchdown works on any collidable surface.  The crash threshold is
	# bypassed while this assist is active.
	var landing_assist := false
	var support_dist := 999.0
	if flight_controller.state_armed and throttle_cmd < 0.25:
		var space := get_world_3d().direct_space_state
		if space != null:
			var span := clampf(maxf(frame_dimensions.x, frame_dimensions.z),
					0.18, 1.2) + 0.35
			var offsets: Array[Vector3] = [
				Vector3.ZERO,
				Vector3(span, 0.0, 0.0), Vector3(-span, 0.0, 0.0),
				Vector3(0.0, 0.0, span), Vector3(0.0, 0.0, -span),
			]
			for off in offsets:
				var q := PhysicsRayQueryParameters3D.create(
						pos + off + Vector3.UP * 0.30,
						pos + off - Vector3.UP * 5.0)
				q.exclude = [get_rid()]
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					continue
				var n: Vector3 = hit["position"]
				var normal: Vector3 = hit["normal"]
				# 0.28 accepts pitched roofs, container tops and steep banks;
				# anything more vertical is a wall and must not attract the drone.
				if normal.y < 0.28:
					continue
				var dist := n.distance_to(pos + off)
				if dist < support_dist:
					support_dist = dist
				if basis.y.dot(Vector3.UP) > 0.20:
					landing_assist = true
			if landing_assist:
				lin_vel.y = maxf(lin_vel.y, -1.8)
				if support_dist < 1.6:
					lin_vel.x = move_toward(lin_vel.x, 0.0, 7.0 * state.step)
					lin_vel.z = move_toward(lin_vel.z, 0.0, 7.0 * state.step)
				ang_vel.x = move_toward(ang_vel.x, 0.0, 2.5 * state.step)
				ang_vel.z = move_toward(ang_vel.z, 0.0, 2.5 * state.step)
	if OS.has_environment("DRONE_AUTOTEST") and flight_controller.state_armed \
			and _arm_diag_frames < 8:
		_arm_diag_frames += 1
		print("[Drone] diag frame=", _arm_diag_frames, " pos=", pos,
			" up=", basis.y, " contacts=", contact_count,
			" vel=", lin_vel, " ang=", ang_vel,
			" rpm=", [motors[0].get_rpm_target(), motors[1].get_rpm_target(),
				motors[2].get_rpm_target(), motors[3].get_rpm_target()])
	
	# P1-8 Crash Detection & Auto-disarm
	if flight_controller.state_armed:
		if not on_ground:
			_was_airborne = true
		if on_ground:
			var impact_speed := (lin_vel - _prev_lin_vel).length()
			if OS.has_environment("DRONE_KAMIKAZE_TEST"):
				print("[KAMTEST][Drone] contact contacts=", contact_count,
						" impact=", roundf(impact_speed * 10.0) / 10.0,
						" lin=", lin_vel, " prev=", _prev_lin_vel,
						" airborne=", _was_airborne)
			# Strike airframes listen to this to initiate the warhead before
			# the generic 14 m/s crash threshold.  The landing assist and the
			# frozen spawn never reach the required speed, so a grass graze or
			# a normal touchdown cannot self-detonate.
			if _was_airborne and impact_speed > 5.0:
				hard_impact.emit(impact_speed)
			if not landing_assist and (impact_speed > 14.0 or _prev_lin_vel.y < -12.0):
				if OS.has_environment("DRONE_AUTOTEST"):
					print("[Drone] impact check: contacts=", contact_count,
						" lin=", lin_vel, " prev=", _prev_lin_vel,
						" speed=", impact_speed, " pos=", pos)
				_trigger_crash("HARD_IMPACT")
			elif basis.y.dot(Vector3.UP) < -0.2:
				_inverted_ground_timer += state.step
				if _inverted_ground_timer > 0.6:
					_trigger_crash("INVERTED_ON_GROUND")
			else:
				_inverted_ground_timer = 0.0
				var min_impact := 2.8 if landing_assist else 1.8
				if impact_speed > min_impact and visible and not freeze:
					Haptics.trigger_collision(impact_speed)
				# A gentle touchdown at idle becomes a stable parked state:
				# disarm, zero the airframe and freeze it so it cannot slide or
				# tip over on a roof, slope, container or vehicle.  Arming
				# unfreezes it again.
				if _was_airborne and throttle_cmd <= 0.10 \
						and lin_vel.length() < 2.4:
					_landing_timer += state.step
					if _landing_timer > 0.35:
						flight_controller.request_disarm()
						for motor in motors:
							if motor != null:
								motor.set_pwm(0.0)
						lin_vel = Vector3.ZERO
						ang_vel = Vector3.ZERO
						_landing_timer = 0.0
						_park_on_surface()
				else:
					_landing_timer = 0.0
		else:
			_inverted_ground_timer = 0.0
			_landing_timer = 0.0
	else:
		_was_airborne = false
		_landing_timer = 0.0
	
	var weight: float = mass * 9.81
	# On ground at idle throttle (<= 4%), eliminate idle lift so the drone rests completely stable on grass
	var idle_t: float = 0.0 if (on_ground and throttle_cmd <= 0.04) else (weight * 0.06)
	var max_t: float = weight * target_max_twr * (battery_sag_factor * battery_sag_factor)
	
	var demanded_thrust := 0.0
	if not flight_controller.state_armed:
		demanded_thrust = 0.0
	elif throttle_cmd <= 0.45:
		demanded_thrust = lerpf(idle_t, weight, clampf(throttle_cmd / 0.45, 0.0, 1.0))
	else:
		demanded_thrust = lerpf(weight, max_t, clampf((throttle_cmd - 0.45) / 0.55, 0.0, 1.0))
	
	current_total_thrust = demanded_thrust
	var arm_len: float = frame_dimensions.x * 0.5
	# Blade Element Theory already predicts forward-flight thrust loss; this
	# explicit high-speed term accounts for the extra tip compressibility and
	# fuselage blanking at 130+ km/h.
	var airspeed := (lin_vel - wind_velocity).length()
	var bet_high_speed_loss := 1.0
	if is_jet:
		bet_high_speed_loss = 1.0
	elif is_fixed_wing:
		bet_high_speed_loss = 1.0 - clampf(pow(airspeed / 65.0, 2.0) * 0.12, 0.0, 0.15)
	else:
		bet_high_speed_loss = 1.0 - clampf(pow(airspeed / 45.0, 2.0) * 0.22, 0.0, 0.30)
	# The throttle curve must be normalised against the propellers' real static
	# thrust, not the design "twr" figure, or the hover stick produces 2 g.
	var curve_twr: float = physical_max_twr if physical_max_twr > 0.01 else target_max_twr
	
	flight_controller.on_ground = on_ground
	for i in range(steps):
		if i == 0:
			update_voltage_sag(state.step)
		flight_controller.configure_throttle_curve(sim_thrust_mode,
				curve_twr * battery_sag_factor * battery_sag_factor)
		flight_controller.integrate_loop(dt, pos, basis, lin_vel, ang_vel)
		
		var vec_force := Vector3.ZERO
		var vec_torque := Vector3.ZERO
		
		# Ground anti-windup & rest stability: when touched down with zero/idle throttle,
		# disarmed, or inverted, suppress all Air Mode motor torques and heavy-damp
		# velocities so the drone rests completely flat without hopping or jittering.
		var ground_torque_scale: float = 1.0
		var resting_on_ground: bool = on_ground and (throttle_cmd <= 0.08 or not flight_controller.state_armed or basis.y.dot(Vector3.UP) < 0.25)
		if resting_on_ground:
			ground_torque_scale = 0.0
			ang_vel = ang_vel.move_toward(Vector3.ZERO, 35.0 * dt)
			lin_vel.x = move_toward(lin_vel.x, 0.0, 25.0 * dt)
			lin_vel.z = move_toward(lin_vel.z, 0.0, 25.0 * dt)
			if lin_vel.y < 0.0:
				lin_vel.y = 0.0
			if lin_vel.length() < 0.15 and ang_vel.length() < 0.15:
				lin_vel = Vector3.ZERO
				ang_vel = Vector3.ZERO
		elif on_ground and flight_controller.flight_mode == FlightController.FlightMode.LEVEL and throttle_cmd < 0.28:
			# In ANGLE mode, prevent right-stick ground deflections at sub-hover
			# throttle from digging a skid into the terrain and flipping over.
			ground_torque_scale = clampf((throttle_cmd - 0.08) / 0.20, 0.0, 1.0)
			ang_vel.x = move_toward(ang_vel.x, 0.0, 12.0 * dt * (1.0 - ground_torque_scale))
			ang_vel.z = move_toward(ang_vel.z, 0.0, 12.0 * dt * (1.0 - ground_torque_scale))
		
		if sim_thrust_mode:
			# P1-1 Realistic motor RPM & propeller aerodynamics
			for motor in motors:
				motor.update_thrust(dt)
				var prop = motor.propeller
				if prop != null:
					prop.set_velocity((lin_vel - wind_velocity) * basis)
					prop.update_forces()
					var m_thrust: float = maxf(prop.forces[0].y, 0.0) \
							* battery_sag_factor * battery_sag_factor * _battery_cutoff
					m_thrust *= bet_high_speed_loss
					if on_ground and throttle_cmd <= 0.05:
						m_thrust = 0.0
					var m_force: Vector3 = basis.y * m_thrust
					vec_force += m_force
					
					var r_motor: Vector3 = basis * (motor.transform.origin - center_of_mass)
					vec_torque += r_motor.cross(m_force) * ground_torque_scale
					
					vec_force += basis * prop.forces[1]
					vec_torque += basis * prop.forces[3] * 0.5
					vec_torque += basis * prop.forces[4] * 0.5
				
				vec_torque += motor.get_torque() * _yaw_torque_scale * basis.y * battery_sag_factor * ground_torque_scale * ground_torque_scale
		else:
			# 1. Primary collective lift applied cleanly through center of mass along body normal
			vec_force += basis.y * demanded_thrust
			
			# 2. Update motor RPM and collect motor reaction torques + blade drag
			for motor in motors:
				motor.update_thrust(dt)
				var prop = motor.propeller
				if prop != null:
					prop.set_velocity((lin_vel - wind_velocity) * basis)
					prop.update_forces()
					var prop_drag: Vector3 = basis * prop.forces[1]
					vec_force += prop_drag
				vec_torque += motor.get_torque() * basis.y * battery_sag_factor * ground_torque_scale
			
			# 3. Control torques from flight controller PID mixer around CoG (Air Mode)
			var pitch_roll_thrust_cap: float = max_t * 0.40 * battery_sag_factor * ground_torque_scale
			
			# Pitch: differential between front (0, 1) and rear (2, 3)
			var front_pwr: float = (float(motors[0].rpm_target) + float(motors[1].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var rear_pwr: float = (float(motors[2].rpm_target) + float(motors[3].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var diff_pitch: float = front_pwr - rear_pwr
			vec_torque += basis.x * (diff_pitch * pitch_roll_thrust_cap * arm_len)
			
			# Roll: differential between left (0, 3) and right (1, 2)
			var left_pwr: float = (float(motors[0].rpm_target) + float(motors[3].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var right_pwr: float = (float(motors[1].rpm_target) + float(motors[2].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var diff_roll: float = left_pwr - right_pwr
			vec_torque += basis.z * (-diff_roll * pitch_roll_thrust_cap * arm_len)
			
			# Yaw: differential between CW (0, 2) and CCW (1, 3) motors
			var cw_pwr: float = (float(motors[0].rpm_target) + float(motors[2].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var ccw_pwr: float = (float(motors[1].rpm_target) + float(motors[3].rpm_target)) * 0.5 / maxf(float(motors[0].MAX_RPM), 1.0)
			var diff_yaw: float = cw_pwr - ccw_pwr
			vec_torque += basis.y * (diff_yaw * max_t * 0.10 * arm_len * battery_sag_factor * ground_torque_scale)
		
		# 4. Aerodynamic quadratic drag and forward tilted body lift
		var drag := get_drag(lin_vel, ang_vel, basis)
		vec_force += drag[0]
		vec_force += external_force
		vec_torque += drag[1]

		# 4b. Fixed-wing / VTOL aerodynamic wing lift, weathervane stability and jet cruise
		if (is_fixed_wing or is_vtol_frame) and not on_ground:
			var local_v := basis.inverse() * (lin_vel - wind_velocity)
			var fwd_speed := maxf(-local_v.z, 0.0)
			var onset := 4.0 if is_fixed_wing else 9.0
			if fwd_speed > onset and basis.y.dot(Vector3.UP) > 0.15:
				var span_ref := 14.0 if is_fixed_wing else 18.0
				var wing_factor := clampf((fwd_speed - onset) / span_ref, 0.0, 1.0)
				var max_lift_frac := 0.80 if is_fixed_wing else 0.32
				# Counter gravity-aligned vertical loss when pitched into forward cruise.
				var lift_dir := (basis.y * 0.4 + Vector3.UP * 0.6).normalized()
				vec_force += lift_dir * (weight * max_lift_frac * wing_factor * _battery_cutoff)
				# Weathervane sideslip damping keeps turns coordinated instead of skidding sideways.
				vec_force += basis * Vector3(-local_v.x * fwd_speed * mass * (0.06 if is_fixed_wing else 0.025), 0.0, 0.0)
			if is_jet and flight_controller.state_armed and throttle_cmd > 0.20:
				var jet_push := weight * 1.15 * clampf((throttle_cmd - 0.20) / 0.80, 0.0, 1.0) * battery_sag_factor * _battery_cutoff
				vec_force += (-basis.z) * jet_push
			elif is_fixed_wing and is_pusher and flight_controller.state_armed and throttle_cmd > 0.25:
				var nose_dip := clampf((-(-basis.z).y - 0.03) / 0.25, 0.0, 1.0)
				var cruise_blend := maxf(nose_dip, clampf((fwd_speed - 2.0) / 8.0, 0.0, 1.0))
				if cruise_blend > 0.01:
					var pusher_push := weight * 0.52 * clampf((throttle_cmd - 0.25) / 0.75, 0.0, 1.0) * cruise_blend * battery_sag_factor * _battery_cutoff
					vec_force += (-basis.z) * pusher_push
		
		# 5. Propwash: descending into the drone's own wake or chopping the
		# throttle at speed.  The pilot has to damp the resulting wobble.
		_propwash_phase += dt
		var local_vel_pw: Vector3 = basis.inverse() * (lin_vel - wind_velocity)
		var descent := clampf((-local_vel_pw.y - 1.0) / 7.0, 0.0, 1.0)
		# Only a real chop towards idle counts. The old formula treated any
		# throttle reduction (even 100% -> hover) as full propwash and could
		# throw a 0.6 kg quad into a 2 rad/s tumble.
		var brake := clampf((_prev_throttle_cmd - throttle_cmd) * 4.0, 0.0, 1.0) \
				* clampf(airspeed / 10.0, 0.0, 1.0) \
				* clampf(1.0 - throttle_cmd / 0.5, 0.0, 1.0) \
				* clampf((5.0 - local_vel_pw.y) / 5.0, 0.0, 1.0)
		var propwash := maxf(descent * clampf(throttle_cmd / 0.25, 0.0, 1.0), brake)
		if propwash > 0.001:
			var osc := Vector3(
				sin(_propwash_phase * 53.0),
				sin(_propwash_phase * 37.0 + 1.7),
				sin(_propwash_phase * 61.0 + 0.4))
			vec_torque += basis * osc * propwash * propwash_gain * mass * 0.12
			vec_force += basis.y * sin(_propwash_phase * 43.0) * propwash * propwash_gain * weight * 0.04
		
		# Integrate forces and velocities
		var a := vec_force * state.inverse_mass + Vector3(0, -9.81, 0)
		lin_vel += a * dt
		pos += lin_vel * dt
		
		# Angular acceleration through principal axes of inertia
		var local_torque: Vector3 = basis.inverse() * vec_torque
		var local_ang_a: Vector3 = local_torque * state.inverse_inertia
		var ang_a: Vector3 = basis * local_ang_a
		ang_vel += ang_a * dt
		var delta_ang_vel := ang_vel * dt
		var d_len := delta_ang_vel.length()
		if d_len > 0.00001:
			basis = basis.rotated(delta_ang_vel / d_len, d_len).orthonormalized()
		
		xform = Transform3D(basis, pos)
	
	# Heavy-lift speed envelope.  This is a soft physical limiter rather than a
	# teleport: excess horizontal velocity is bled off by the airframe drag and
	# capped just above the documented cruise speed.
	if speed_limit_ms > 0.0:
		var hv := Vector3(lin_vel.x, 0.0, lin_vel.z)
		if hv.length() > speed_limit_ms:
			hv = hv.normalized() * speed_limit_ms
			lin_vel.x = hv.x
			lin_vel.z = hv.z
	state.linear_velocity = lin_vel
	state.angular_velocity = ang_vel
	# P1-2 Synchronize state.transform with custom integrator
	var resting_on_ground: bool = on_ground and (throttle_cmd <= 0.08 or not flight_controller.state_armed or basis.y.dot(Vector3.UP) < 0.25)
	if not resting_on_ground:
		state.transform = Transform3D(basis.orthonormalized(), pos)
	else:
		basis = state.transform.basis.orthonormalized()
		pos = state.transform.origin
	drone_transform = state.transform
	drone_pos = state.transform.origin
	drone_basis = state.transform.basis
	_prev_lin_vel = lin_vel
	_prev_throttle_cmd = throttle_cmd
	external_force = Vector3.ZERO


func update_hud_data(delta: float) -> void:
	if flight_controller == null or hud == null:
		return
	var mot: Array = flight_controller.motors
	var input: Array = flight_controller.input
	if mot.size() < 4 or input.size() < 4:
		return
	var angles: Vector3 = flight_controller.angles
	var velocity: Vector3 = flight_controller.lin_vel
	var position: Vector3 = flight_controller.pos
	var left_stick := Vector2(input[1], -2 * (input[0] - 0.5))
	var right_stick := Vector2(input[2], -input[3])
	var rpm := [mot[0].rpm, mot[1].rpm, mot[2].rpm, mot[3].rpm]
	hud.update_data(delta, position, angles, velocity, left_stick, right_stick, rpm)
	if hud.has_method("update_realtime_sticks"):
		hud.update_realtime_sticks(left_stick, right_stick)


func reset() -> void:
	_on_reset()


## Zero the motion history used by crash detection. Call after teleporting a
## frozen drone so the first physics frame cannot see the pre-teleport velocity
## as a hard impact.
func reset_motion_history() -> void:
	_prev_lin_vel = Vector3.ZERO
	_inverted_ground_timer = 0.0
	_arm_diag_frames = 0


func _on_reset() -> void:
	var respawn_point: Node3D = null
	if get_tree().current_scene != null:
		respawn_point = get_tree().current_scene.get_node_or_null("Respawn") as Node3D
	var respawn_transform := global_transform
	if respawn_point != null:
		respawn_transform = respawn_point.global_transform.translated(Vector3(0, 0.1, 0))
	
	if Global.game_mode == Global.GameMode.RACE and Global.active_track:
		var launch_area: LaunchArea = Global.active_track.get_random_launch_area()
		var launch_transform: Transform3D = launch_area.global_transform
		var offset: float = -motors[0].transform.origin.z + 0.02
		respawn_transform = launch_transform.translated(Vector3(0, 0.1, offset))
	
	await get_tree().physics_frame
	_parked = false
	freeze = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = respawn_transform
	reset_motion_history()
	flight_controller.reset()
	battery_used_mah = 0.0
	battery_cell_voltage = battery_cell_voltage_rest
	battery_voltage = battery_cell_voltage_rest * float(battery_cells)
	battery_sag_factor = 1.0
	_battery_cutoff = 1.0
	battery_current_draw = 0.0
	sustained_sag_accum = 0.0
	low_voltage_warn = false
	
	emit_signal("respawned")


func get_drag(lin_vel: Vector3, ang_vel: Vector3, orientation: Basis) -> Array:
	var rho := 1.225 # Air density kg/m^3
	var airspeed: Vector3 = lin_vel - wind_velocity
	var local_vel: Vector3 = orientation.inverse() * airspeed
	var local_ang: Vector3 = orientation.inverse() * ang_vel
	
	# Quadratic aerodynamic drag along each body axis: F = 0.5 * rho * Cd * A * v * |v|
	var drag_force_local := Vector3(
		-0.5 * rho * cd.x * projected_area.x * local_vel.x * absf(local_vel.x),
		-0.5 * rho * cd.y * projected_area.y * local_vel.y * absf(local_vel.y),
		-0.5 * rho * cd.z * projected_area.z * local_vel.z * absf(local_vel.z)
	)

	# Payload parasitic drag: a PG-7V / VOG hangs under the belly and acts as
	# an aerodynamic sail, especially in forward flight.
	if has_payload and payload_mass > 0.001:
		var pay_x: float = 0.006 + payload_mass * 0.002
		var pay_y: float = 0.008 + payload_mass * 0.004
		var pay_z: float = 0.012 + payload_mass * 0.006
		drag_force_local.x += -0.5 * rho * 1.05 * pay_x * local_vel.x * absf(local_vel.x)
		drag_force_local.y += -0.5 * rho * 1.10 * pay_y * local_vel.y * absf(local_vel.y)
		drag_force_local.z += -0.5 * rho * 1.25 * pay_z * local_vel.z * absf(local_vel.z)
	
	# Body aerodynamic lift from forward flight with pitch tilt
	# When tilted nose down (-Z is forward), forward motion creates positive Y lift on bottom plate
	if local_vel.z < -1.0: # Moving forward (negative Z is forward in Godot)
		var angle_of_attack: float = atan2(-local_vel.y, -local_vel.z)
		var lift_coeff: float = clampf(sin(2.0 * angle_of_attack) * 1.1, -1.0, 1.0)
		var dynamic_pressure: float = 0.5 * rho * (local_vel.y * local_vel.y + local_vel.z * local_vel.z)
		var body_lift: float = dynamic_pressure * projected_area.y * lift_coeff
		drag_force_local.y += body_lift
	
	# Angular aerodynamic damping (resists fast spinning)
	var drag_torque_local := Vector3(
		-0.5 * rho * cd.x * projected_area.x * 0.08 * local_ang.x * absf(local_ang.x) - 0.005 * local_ang.x,
		-0.5 * rho * cd.y * projected_area.y * 0.08 * local_ang.y * absf(local_ang.y) - 0.005 * local_ang.y,
		-0.5 * rho * cd.z * projected_area.z * 0.08 * local_ang.z * absf(local_ang.z) - 0.005 * local_ang.z
	)
	
	return [orientation * drag_force_local, orientation * drag_torque_local]


func _on_flight_mode_changed(flight_mode: int) -> void:
	var led := $LEDMode
	led.set_blink_pattern()
	if flight_mode == FlightController.FlightMode.RATE:
		led.change_color(Color(1, 0, 0))
	elif flight_mode == FlightController.FlightMode.LEVEL:
		led.change_color(Color(0.2, 0.2, 1))
	elif flight_mode == FlightController.FlightMode.SPEED:
		led.change_color(Color(1, 1, 0))
	elif flight_mode == FlightController.FlightMode.TRACK:
		led.change_color(Color(0, 1, 0))
	elif flight_mode == FlightController.FlightMode.AUTO:
		led.change_color(Color(1, 0, 0))
		led.set_blink_pattern([Vector2(0.25, 0.25)])
	elif flight_mode == FlightController.FlightMode.TURTLE:
		led.change_color(Color(1, 0, 0))
		led.set_blink_pattern([Vector2(0.1, 0.1), Vector2(0.1, 0.7)])
	elif flight_mode == FlightController.FlightMode.LAUNCH:
		led.change_color(Color(1, 0, 0))
		led.set_blink_pattern([Vector2(0.15, 0.15), Vector2(0.55, 0.15)])
	
	hud.update_flight_mode(flight_mode)


## Individual masses used for the honest inertia tensor.  Positions are in
## body space: the battery sits on the top deck, the payload hangs under the
## belly, so the CoG moves forward and down exactly like the real drone.
func _mass_parts() -> Array:
	var parts: Array = []
	var frame_mass: float = dry_mass * 0.45
	var electronics_mass: float = dry_mass * 0.11
	var motor_mass: float = dry_mass * 0.11
	parts.append([frame_mass, Vector3.ZERO])
	parts.append([electronics_mass, Vector3(0.0, 0.012, 0.0)])
	if motors.size() >= 4:
		for motor in motors:
			parts.append([motor_mass, motor.transform.origin])
	else:
		var arm: float = frame_dimensions.x * 0.5
		var z: float = frame_dimensions.z * 0.5
		parts.append([motor_mass, Vector3(-arm, 0.01, -z)])
		parts.append([motor_mass, Vector3(arm, 0.01, -z)])
		parts.append([motor_mass, Vector3(-arm, 0.01, z)])
		parts.append([motor_mass, Vector3(arm, 0.01, z)])
	# Keep the battery centred over the frame. A rearward battery offset used to
	# be harmless when lift acted through the CoM, but with per-motor thrust it
	# creates a permanent nose-up torque that the rate loop has to fight.
	parts.append([battery_mass, Vector3(0.0, 0.032, 0.0)])
	if has_payload and payload_mass > 0.001:
		parts.append([payload_mass, payload_cog_offset])
	return parts


func recalculate_mass_and_inertia() -> void:
	# Honest tensor: I = sum m_i (r_i^2 E - r_i (x) r_i), with every part
	# (frame, four motors, battery, payload) contributing its own mass and
	# coordinate.  Godot only accepts the principal diagonal, so the diagonal
	# terms are applied; the off-diagonal coupling is left out by design.
	var parts := _mass_parts()
	var total_mass := 0.0
	var cog := Vector3.ZERO
	for part in parts:
		var m: float = part[0]
		var r: Vector3 = part[1]
		total_mass += m
		cog += r * m
	if total_mass < 0.01:
		total_mass = 0.1
	cog /= total_mass
	mass = maxf(total_mass, 0.1)

	# Keep the vertical CG (it is what a slung battery/payload really changes),
	# but balance the horizontal offset.  A horizontal CG offset puts a pitching
	# torque on every throttle change, which the pilot sees as the nose dipping
	# forward when the throttle is raised.  The airframe is treated as balanced
	# in X/Z; the attitude PID only has to handle real disturbances.
	var balanced_cog := Vector3(0.0, cog.y, 0.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = balanced_cog

	var i_xx := 0.0
	var i_yy := 0.0
	var i_zz := 0.0
	for part in parts:
		var m: float = part[0]
		var r: Vector3 = part[1] - balanced_cog
		i_xx += m * (r.y * r.y + r.z * r.z)
		i_yy += m * (r.x * r.x + r.z * r.z)
		i_zz += m * (r.x * r.x + r.y * r.y)
	# The carbon plate's own box inertia keeps a point-mass model from making
	# the frame unrealistically twitchy around the diagonal.
	var w: float = maxf(frame_dimensions.x, 0.1)
	var h: float = maxf(frame_dimensions.y, 0.02)
	var l: float = maxf(frame_dimensions.z, 0.1)
	var plate_mass: float = dry_mass * 0.45
	i_xx += plate_mass * (h * h + l * l) / 12.0
	i_yy += plate_mass * (w * w + l * l) / 12.0
	i_zz += plate_mass * (w * w + h * h) / 12.0

	inertia = Vector3(maxf(i_xx, 1e-5), maxf(i_yy, 1e-5), maxf(i_zz, 1e-5))
	if flight_controller != null and flight_controller.has_method("update_pid_for_inertia"):
		flight_controller.update_pid_for_inertia(inertia, mass)


func update_voltage_sag(dt: float) -> void:
	if motors.is_empty():
		return
	# Training / accessibility option: keep the pack at rest voltage so long
	# sorties do not lose thrust to sag.  The HUD current and mAh also stay at 0.
	if bool(GameSettings.hud_config.get("infinite_battery", false)):
		var v_full: float = battery_cell_voltage_rest * float(battery_cells)
		battery_current_draw = 0.0
		battery_voltage = v_full
		battery_sag_factor = 1.0
		_battery_cutoff = 1.0
		battery_cell_voltage = battery_cell_voltage_rest
		battery_used_mah = 0.0
		sustained_sag_accum = 0.0
		low_voltage_warn = false
		return
	var total_load := 0.0
	for motor in motors:
		total_load += clampf(absf(motor.rpm) / maxf(motor.MAX_RPM, 1.0), 0.0, 1.0)
	var avg_load := total_load / float(motors.size())

	# LiPo: low internal resistance, high burst current.  Li-ion 6S2P 21700:
	# high capacity but roughly five times the resistance, so a full punch
	# drags 25.2 V down towards 19 V and the quad loses its pop.
	var current: float = avg_load * battery_max_current
	battery_current_draw = current
	var usable_mah := maxf(battery_capacity_mah, 1.0)
	battery_used_mah = minf(battery_used_mah + current * dt / 3.6, usable_mah)
	var soc := clampf(1.0 - battery_used_mah / usable_mah, 0.0, 1.0)

	var nominal_cell := battery_cell_voltage_rest
	var v_nominal: float = nominal_cell * float(battery_cells)
	# A LiPo/Li-ion pack is ~4.2 V full and ~3.3 V empty per cell.
	var rest_cell := lerpf(3.30, nominal_cell, soc)
	var v_rest: float = rest_cell * float(battery_cells)
	var sag: float = current * battery_internal_resistance

	# Sustained punch-out heat build-up.
	if avg_load > 0.75:
		sustained_sag_accum = minf(sustained_sag_accum + dt * 0.06, 0.08)
	else:
		sustained_sag_accum = maxf(sustained_sag_accum - dt * 0.04, 0.0)

	var v := v_rest - sag - sustained_sag_accum * v_nominal
	battery_voltage = clampf(v, v_nominal * 0.55, v_nominal)
	battery_sag_factor = clampf(battery_voltage / v_nominal, 0.55, 1.0)
	_battery_cutoff = clampf(soc / 0.02, 0.0, 1.0)
	battery_cell_voltage = battery_voltage / float(maxi(battery_cells, 1))
	low_voltage_warn = battery_cell_voltage < 3.3 or soc < 0.12


func drop_payload_action() -> float:
	if payload_mass <= 0.001 or not has_payload:
		return 0.0
	
	var dropped_weight: float = payload_mass / float(maxi(max_payload_count, 1))
	payload_count = maxi(payload_count - 1, 0)
	
	# Mechanical release separation upward jump impulse
	var jump_impulse: float = dropped_weight * 2.2
	linear_velocity += global_transform.basis.y * jump_impulse
	
	if payload_count <= 0:
		has_payload = false
		payload_mass = 0.0
	else:
		payload_mass -= dropped_weight
	
	recalculate_mass_and_inertia()
	var preset := DroneCatalog.preset(Global.drone_preset)
	speed_limit_ms = float(preset.get("max_speed_loaded" if has_payload \
			else "max_speed_empty", speed_limit_ms))
	thrust_scale = clampf(mass / THRUST_REFERENCE_MASS, 0.35, 4.5)
	if flight_controller != null:
		flight_controller.set_hover_thrust(mass / 4.0 * 9.81)
	return dropped_weight


func _physics_class_for_prop(prop_d: float) -> String:
	if prop_d <= 0.01:
		return "5inch"
	if prop_d <= 4.0:
		return "micro"
	if prop_d <= 6.0:
		return "5inch"
	if prop_d <= 7.5:
		return "7inch"
	if prop_d <= 9.0:
		return "8inch"
	return "10inch"


func apply_preset_physics(p: Dictionary) -> void:
	dry_mass = float(p.get("dry", 0.42))
	battery_mass = float(p.get("batt", 0.18))
	payload_mass = float(p.get("payload_mass", 0.0))
	payload_count = int(p.get("payload", 0))
	if payload_mass > 0.001 and payload_count == 0:
		payload_count = 1
	max_payload_count = maxi(payload_count, 1)
	has_payload = (payload_mass > 0.001)
	speed_limit_ms = float(p.get("max_speed_loaded" if has_payload \
			else "max_speed_empty", 0.0))
	base_cog_offset = Vector3.ZERO
	payload_cog_offset = p.get("cog_offset", Vector3.ZERO)
	frame_dimensions = p.get("dimensions", Vector3(0.22, 0.06, 0.22))
	is_fixed_wing = bool(p.get("fixed_wing", false))
	is_pusher = bool(p.get("pusher", false))
	is_jet = bool(p.get("is_jet", false))
	is_vtol_frame = (str(p.get("id", "")) == "pisun_vtol")
	if motors.size() >= 4:
		if _base_motor_origins.size() < 4:
			_base_motor_origins.clear()
			for idx_m in range(4):
				_base_motor_origins.append(motors[idx_m].transform.origin)
		var arm_x := clampf(frame_dimensions.x * 0.36, 0.08, 1.05)
		var arm_z := clampf(frame_dimensions.z * 0.36, 0.08, 1.05)
		var signs := [Vector2(-1.0, -1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0), Vector2(-1.0, 1.0)]
		for idx_m in range(4):
			if motors[idx_m] != null:
				var y_base := _base_motor_origins[idx_m].y
				motors[idx_m].transform.origin = Vector3(signs[idx_m].x * arm_x, y_base, signs[idx_m].y * arm_z)
	if p.has("drag_area"):
		projected_area = p["drag_area"]
	if p.has("twr"):
		target_max_twr = float(p["twr"])
	# Select the motor/airframe response class from the real prop diameter.
	physics_class = _physics_class_for_prop(float(p.get("prop_d", 5.0)))
	var profile: Dictionary = PHYSICS_PROFILES[physics_class]
	propwash_gain = float(profile["propwash"])
	var prop_d := float(p.get("prop_d", 5.0))
	if prop_d > 0.01 and motors.size() >= 4:
		# Ground-effect geometry depends on the installed propeller and motor
		# spacing.  Recompute it on every preset change; otherwise a 10" bomber
		# kept the ground-effect radius of the previous 5" racer.
		var rad: float = prop_d * 0.0254 * 0.5
		var span_d: float = minf(
				(motors[0].transform.origin - motors[1].transform.origin).length(),
				(motors[0].transform.origin - motors[3].transform.origin).length())
		var span_b: float = (motors[0].transform.origin - motors[2].transform.origin).length()
		for motor in motors:
			if motor != null and motor.propeller != null:
				motor.propeller.set_ground_effect_parameters(rad, span_d, span_b, 1.0)
	for motor in motors:
		if motor == null:
			continue
		motor.RPM_ACCELERATION = float(profile["rpm_accel"])
		motor.ESC_BRAKING = float(profile["esc_brake"])
		motor.max_rpm_change = motor.MAX_TORQUE * motor.RPM_ACCELERATION
	# Invalid until DroneCatalog has applied the actual motors and propellers.
	physical_max_twr = 0.0

	# Battery chemistry: LiPo (0) vs Li-ion 6S2P 21700 (1).  The preset may
	# override resistance/current/capacity for a specific pack.
	battery_chemistry = int(p.get("battery_chemistry", 0))
	battery_cells = int(p.get("battery_cells", 6))
	battery_cell_voltage_rest = float(p.get("battery_cell_rest", 4.2))
	battery_capacity_mah = float(p.get("battery_mah", 1300.0)) * BATTERY_CAPACITY_SCALE
	battery_used_mah = 0.0
	battery_max_current = float(p.get("battery_max_current",
			90.0 if battery_chemistry == 1 else 120.0))
	battery_internal_resistance = float(p.get("battery_resistance",
			0.065 if battery_chemistry == 1 else 0.018))

	battery_cell_voltage = battery_cell_voltage_rest
	battery_voltage = battery_cell_voltage_rest * float(battery_cells)
	battery_sag_factor = 1.0
	_battery_cutoff = 1.0
	battery_current_draw = 0.0
	low_voltage_warn = false
	sustained_sag_accum = 0.0

	recalculate_mass_and_inertia()
	thrust_scale = clampf(mass / THRUST_REFERENCE_MASS, 0.35, 4.5)
	if flight_controller != null:
		flight_controller.set("_is_fixed_wing", is_fixed_wing)
		flight_controller.set_hover_thrust(mass / 4.0 * 9.81)


## Measure the installed propeller set's static thrust at full RPM and keep it
## as a TWR.  DroneCatalog calls this after motors and propellers are applied,
## so the throttle curve's hover point matches the blade-element physics.
func recalibrate_static_twr() -> void:
	var total_thrust := 0.0
	var total_torque := 0.0
	for motor in motors:
		if motor == null:
			continue
		var prop: Propeller = motor.get("propeller")
		if prop != null:
			total_thrust += maxf(prop.static_thrust(float(motor.MAX_RPM)), 0.0)
		total_torque += absf(float(motor.MAX_TORQUE))
	var weight := maxf(mass * 9.81, 0.001)
	physical_max_twr = total_thrust / weight
	var desired_yaw_alpha := 48.0 if is_fixed_wing else 75.0
	var desired_total_tau := inertia.y * desired_yaw_alpha * 0.12
	_yaw_torque_scale = clampf(desired_total_tau / maxf(total_torque, 0.5), 1.0, 6.0)


func set_payload_attached(attached: bool) -> void:
	has_payload = attached
	recalculate_mass_and_inertia()
	thrust_scale = clampf(mass / THRUST_REFERENCE_MASS, 0.35, 4.5)
	if flight_controller != null:
		flight_controller.set_hover_thrust(mass / 4.0 * 9.81)


func _on_quad_settings_updated() -> void:
	dry_mass = QuadSettings.dry_weight
	battery_mass = QuadSettings.battery_weight
	payload_mass = QuadSettings.payload_weight
	has_payload = (payload_mass > 0.001)
	var pnow := DroneCatalog.preset(Global.drone_preset)
	speed_limit_ms = float(pnow.get("max_speed_loaded" if has_payload \
			else "max_speed_empty", 0.0))
	recalculate_mass_and_inertia()
	thrust_scale = clampf(mass / THRUST_REFERENCE_MASS, 0.35, 4.5)
	if flight_controller != null:
		flight_controller.set_hover_thrust(mass / 4.0 * 9.81)
	
	thrust_scale = clampf(mass / THRUST_REFERENCE_MASS, 0.35, 4.5)
	var fpv := get_node_or_null("FPVCamera") as Camera3D
	if fpv != null:
		var p := DroneCatalog.preset(Global.drone_preset)
		var cam_pos = p.get("fpv_cam_pos", null)
		if cam_pos is Vector3:
			fpv.position = cam_pos
		var cam_pitch: float = float(p.get("fpv_cam_pitch", QuadSettings.angle))
		fpv.transform.basis = Basis.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(cam_pitch))
		var parent_level := get_parent()
		if parent_level != null and parent_level.has_method("_sync_fpv_drone_model") \
				and fpv.has_meta("base_pos"):
			parent_level.call("_sync_fpv_drone_model", false, false, true)
	control_profile.set_rates(QuadSettings.rate_pitch, QuadSettings.rate_roll, QuadSettings.rate_yaw)
	control_profile.set_expo(QuadSettings.expo_pitch, QuadSettings.expo_roll, QuadSettings.expo_yaw)
	control_profile.set_level_control(QuadSettings.level_bank,
			QuadSettings.level_angle_gain, QuadSettings.level_rate_gain,
			QuadSettings.level_rate_limit)


func _on_armed_signal(_mode: int = 0) -> void:
	if _parked:
		_parked = false
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_landing_timer = 0.0
	_was_airborne = false
	Haptics.trigger_arm_toggle(true)


func _on_disarmed_signal() -> void:
	Haptics.trigger_arm_toggle(false)


func _park_on_surface() -> void:
	_parked = true
	# Setting freeze from inside _integrate_forces is illegal; defer to idle.
	# The guard makes an immediate re-arm win the race, so the player never
	# gets a drone frozen by a landing that happened on the previous frame.
	call_deferred("_apply_park_freeze")


func _apply_park_freeze() -> void:
	if _parked and flight_controller != null and not flight_controller.state_armed:
		freeze = true


func _trigger_crash(reason: String) -> void:
	if not flight_controller.state_armed:
		return
	Haptics.trigger_crash()
	emit_signal("crashed", reason)
	flight_controller.request_disarm()
	for motor in motors:
		if motor != null:
			motor.set_pwm(0.0)
			motor.set_rpm_target(0.0)
	print("[Drone] CRASH DETECTED: ", reason)


func _on_hud_config_updated() -> void:
	hud.hud_timer = 1.0 / GameSettings.hud_config["fps"]
	hud.show_component(HUD.Component.CROSSHAIR, false)
	hud.show_component(HUD.Component.STATUS, bool(GameSettings.hud_config.get("status", true)))
	hud.show_component(HUD.Component.LADDER, GameSettings.hud_config["ladder"])
	hud.show_component(HUD.Component.SPEED, GameSettings.hud_config["speed"])
	hud.show_component(HUD.Component.ALTITUDE, GameSettings.hud_config["altitude"])
	hud.show_component(HUD.Component.HEADING, GameSettings.hud_config["heading"])
	# Live axis monitor: useful with a real radio/keyboard.  It is hidden only
	# when the on-screen twin sticks already show the same input.
	var show_stick_monitor := MenuUI.is_mobile_ui() \
			and bool(GameSettings.hud_config.get("sticks", true))
	var touch_pad := get_node_or_null("/root/TouchControls")
	if touch_pad != null and bool(touch_pad.get("touch_mode")):
		show_stick_monitor = false
	hud.show_component(HUD.Component.STICKS, show_stick_monitor)
	hud.show_component(HUD.Component.RPM, GameSettings.hud_config["rpm"])
	sim_thrust_mode = bool(GameSettings.hud_config.get("sim_thrust", true))
	if flight_controller != null:
		var resolved: int = flight_controller.resolve_flight_mode(flight_controller.flight_mode)
		if resolved != flight_controller.flight_mode:
			flight_controller.select_flight_mode(resolved)


func _hide_all_visuals(node: Node) -> void:
	if node == null:
		return
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	for child in node.get_children():
		_hide_all_visuals(child)


func _exit_tree() -> void:
	if QuadSettings != null and QuadSettings.settings_updated.is_connected(_on_quad_settings_updated):
		QuadSettings.settings_updated.disconnect(_on_quad_settings_updated)
	if GameSettings != null and GameSettings.hud_config_updated.is_connected(_on_hud_config_updated):
		GameSettings.hud_config_updated.disconnect(_on_hud_config_updated)
