## Big procedural maps level.
##
## Loads one of three large Blender maps based on the menu mode and runs the
## full mission loop for it:
##   TRAINING - fly through 24 rings, no hostiles
##   COMBAT   - the combat layer (targets / AA / infantry) plus moving armour
##   SPEED    - timed 20-checkpoint circuit with moving traffic hazards
##
## Also spawns moving vehicles, upgrades the environment (fog, glow, SSAO,
## ACES tonemap) and shows a start banner / results screen with two buttons.
extends "res://sceneries/Level.gd"

const VEHICLE := preload("res://combat/vehicle.gd")
const DESTRUCTIBLE := preload("res://combat/destructible_building.gd")
const PayloadScript = preload("res://combat/payload.gd")
const BombBallisticsScript = preload("res://combat/ballistics.gd")
const EnemyRiflemanScript = preload("res://combat/enemy_infantry.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const StickOverlayScript = preload("res://HUD/StickOverlay.gd")
const AmbientBattleScript = preload("res://combat/ambient_battle.gd")
const FoliageSystemScript = preload("res://scripts/util/foliage_system.gd")
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")
const ValleySceneBuilderScript = preload("res://scripts/util/valley_scene_builder.gd")
const QualityManagerScript = preload("res://scripts/util/quality_manager.gd")
const FlightSchool = preload("res://scripts/util/flight_school.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")
const MAIN_MENU := "res://GUI/MainMenu.tscn"
const MOBILE_MENU := "res://GUI/mobile/MobileMenu.tscn"

var _map_root: Node3D = null
var _triggers: Node3D = null
var _hud: CanvasLayer = null
var _hud_label: Label = null
var _hud_message: Label = null
var _elrs_status_label: Label = null
var _touch_controls: Node = null
var _crosshair: Control = null
var _stick_overlay: Control = null
var _diag: Label = null
var _diag_on := false
var _test_frames := -1
var _test_y0 := 0.0
var _test_max := -1e9
var _results: Control = null
var _results_stats: Label = null
var _chain_brief: Control = null
var _chain_brief_start: Button = null
var _telem_left: Label = null
var _telem_right: Label = null
var _battery := 25.2
var _mah := 0.0
var _fps_ema := 120.0
var _scene_uptime := 0.0

var _speed_checkpoints: Array[Area3D] = []
var _speed_next := 0
var _speed_time := 0.0
var _rings_passed := 0
var _rings_total := 0
var _training_rings: Array[Area3D] = []
var _nav_marker: Label = null
var _vehicles: Array[Vehicle] = []
var _infantry_units: Array[Node3D] = []
var _kills := {}
var _mission_targets_total := 0
var _mission_targets_destroyed := 0
## Random per-load offset applied to the authored combat target positions, so
## infantry/armour never spawn in the exact same spot twice.
var _mission_offset := Vector3.ZERO
var _offset_targets := false
var _results_title: Label = null
var _next_mission_btn: Button = null

var _mission_started := false
var _mission_phase := 0
var _mission_phase_hold := 0.0
var _mission_phase_active := false
var _recon_point := Vector3.ZERO
var _extract_point := Vector3.ZERO
var _mission_finished := false
var _mission_failed := false
var _mission_time := 0.0
var _score := 0
var _ground_y := 0.0
## Sea surface used by the TAC-05 naval mission (deep basin, not the 0.35 m
## film that used to lie on top of the legacy valley floor).
var _sea_y := 0.0
var _ground_guard_timer := 0.0
var _hud_tick := 0.0
var _telemetry_tick := 0.0
var _telemetry_accum := 0.0
var _nav_tick := 0.0
var _audio_priority_tick := 0.0
var _osd_visible := true
var _fpv_rig: Node3D = null
var _reb: RebSystem = null
## Empty = the original valley maps.  Set by the frontline scenes
## (steppe / village / industrial / wetlands) to build the new terrain.
@export var frontline_map := ""
var _fpv_payload: Node3D = null
var _payload_rest := Transform3D.IDENTITY
var _payload_dropped := false
var _payload_enabled := false
var _payload_ammo_left := 0
var _heavy_bomber := false
var _bomb_nodes: Array[Node3D] = []
var _bomb_sight: BombSight = null
var _bomb_cooldown := 0.0
## Polled edges make payload switches work even when a radio maps an AUX
## toggle to a raw Joypad Axis instead of a Button/synthetic action.
var _payload_axis_drop_prev := false
var _payload_axis_trigger_prev := false
var _payload_axis_poll_ready := false
var _bomb_release_arm: Node3D = null
var _bomb_kind := "82mm"
var _model_root: Node3D = null
var _wind_player: AudioStreamPlayer = null
var _beeper_player: AudioStreamPlayer = null
var _alert_player: AudioStreamPlayer = null
var _ew_crackle_player: AudioStreamPlayer = null
var _beeper_timer := 0.0
var _wind_indicator: Label = null
var _jamming_announced := false
var _low_battery_announced := false
var _radio_subtitle: Label = null
var _radio_subtitle_timer := 0.0
var _radio_cooldown := 0.0
var _audio_duck_timer := 0.0
var _ew_was_active := false
var _lq_was_critical := false
var _lq_warn_timer := 0.0
var _threat_indicator: Label = null
var _threat_position := Vector3.ZERO
var _threat_kind := ""
var _threat_timer := 0.0
var _threat_scan_tick := 0.0
var _sam_warn_timer := 0.0
var _kamikaze_warn_timer := 0.0
var _special_index := 0
var _special_hold := 0.0
var _special_zones: Array[Dictionary] = []
var _special_beacons: Array[Node3D] = []
var _special_convoy: Vehicle = null
var _special_convoy_dest := Vector3.ZERO
var _special_convoy_start := Vector3.ZERO
var _special_convoy_far_timer := 0.0
var _special_convoy_warned := false
var _special_extract_active := false
var _special_extract_point := Vector3.ZERO
var _special_extract_hold := 0.0
var _special_extract_beacon: Node3D = null
var _special_pickup_prop: Node3D = null
var _combat_music: AudioStreamPlayer = null
var _audio_mix_tick := 0.0
var _rig_visible := true
var _weather := 0
enum VisionMode { NORMAL = 0, NVG = 1, FLIR_WHITE_HOT = 2, FLIR_BLACK_HOT = 3 }
var _vision_mode: VisionMode = VisionMode.NORMAL
var _vision_overlay: ColorRect = null
var _vision_material: ShaderMaterial = null
var _thunder_timer: float = 8.0
var _lightning_light: DirectionalLight3D = null
var _lightning_flash_timer: float = 0.0
var _sun_light_energy_default: float = 1.0
var _flight_school: FlightSchool = null
var _flash_token := 0
## QA: survives a scene reload so the retry test can detect its second run.
static var _retry_test_round := 0
var _rain: GPUParticles3D = null
var _dust: GPUParticles3D = null


func _ready() -> void:
	if Global.startup:
		Global.initialize()
	super._ready()

	# A retry/reload must always start unpaused and focused. Results menus set
	# the tree paused, and a stale paused state after a reload used to swallow
	# the first Space press (so the drone would not arm).
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		DisplayServer.window_move_to_foreground()
	
	# Explicitly re-init inputs on scene entry to fix Space/Radio not arming.
	Controls.load_input_map()
	Controls.ensure_active_joypad()
	var radio := get_node_or_null("RadioController")
	if radio != null and radio.has_method("refresh_bindings"):
		radio.refresh_bindings()

	# Input/radio setup is deferred so a problem here can never abort level
	# start-up (that was leaving an empty yellow scene with nothing in it).
	call_deferred("_setup_input")

	_upgrade_environment()
	if OS.has_environment("DRONE_WINDOW_DEMO") or OS.has_environment("DRONE_CRANE_DEMO") or OS.has_environment("DRONE_STATION_DEMO"):
		Global.play_mode = Global.PlayMode.TRAINING
		Global.special_mission = 0
	if OS.has_environment("DRONE_PRESET"):
		Global.drone_preset = int(OS.get_environment("DRONE_PRESET"))
	if OS.has_environment("DRONE_COMBAT_MISSION"):
		Global.play_mode = Global.PlayMode.COMBAT
		Global.combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 5)
		Global.special_mission = 0
	if OS.has_environment("DRONE_TUTORIAL") or (OS.has_environment("DRONE_PLAY_MODE") and OS.get_environment("DRONE_PLAY_MODE").to_lower() == "tutorial"):
		Global.play_mode = Global.PlayMode.TUTORIAL
		Global.special_mission = 0
	if OS.has_environment("DRONE_PLAY_MODE") and OS.get_environment("DRONE_PLAY_MODE").to_lower() == "chaos":
		Global.play_mode = Global.PlayMode.CHAOS
		frontline_map = "industrial"
		Global.special_mission = 0
	if OS.has_environment("DRONE_MAP"):
		frontline_map = OS.get_environment("DRONE_MAP")
	# Strict role enforcement: Only Magura-X for TAC-05, and Magura-X can ONLY play TAC-05!
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and Global.combat_mission == 5:
		if Global.drone_preset != 10:
			QuadSettings.custom_rates = false
			DroneCatalog.apply(10)
	elif Global.drone_preset == 10:
		QuadSettings.custom_rates = false
		DroneCatalog.apply(0)

	GameSettings.hud_config["crosshair"] = true
	GameSettings.hud_config["status"] = false
	GameSettings.hud_config["horizon"] = false
	GameSettings.hud_config["speed"] = false
	GameSettings.hud_config["altitude"] = false
	GameSettings.hud_config["heading"] = false
	GameSettings.hud_config["sticks"] = true
	GameSettings.hud_config["osd"] = true

	_map_root = get_node_or_null("MapRoot") as Node3D
	_triggers = get_node_or_null("Triggers") as Node3D
	_load_map()
	# Let the freshly instantiated map register its collision before probing it.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d._on_hud_config_updated()
		if not d.crashed.is_connected(_on_drone_crashed):
			d.crashed.connect(_on_drone_crashed)
		if d.has_signal("hard_impact") \
				and not d.hard_impact.is_connected(_on_drone_hard_impact):
			d.hard_impact.connect(_on_drone_hard_impact)
	# Combat targets get a fresh area offset every load.  The launch point is
	# computed from the same offset so the drone always starts far away.
	if Global.play_mode == Global.PlayMode.COMBAT and Global.combat_mission != 5:
		_mission_offset = Vector3(randf_range(-55.0, 55.0), 0.0,
				randf_range(-35.0, 35.0))
	_place_drone_over_ground()
	var is_boat: bool = bool(DroneCatalog.preset(Global.drone_preset).get("is_naval", false))
	if d != null and not is_boat:
		var g_cnt := int(QualityManagerScript.get_value("grass_count", 2200))
		var g_rad := float(QualityManagerScript.get_value("grass_range", 75.0))
		# NOTE: raw linear values passed as Vector3 uniforms, not sRGB colours.
		# They track the PBR ground: straw blades on the dry maps, darker reed
		# green in the marsh.
		var dry := frontline_map != "wetlands"
		var g_base := Color(0.085, 0.080, 0.035) if dry else Color(0.045, 0.070, 0.022)
		var g_tip := Color(0.240, 0.215, 0.095) if dry else Color(0.115, 0.165, 0.055)
		var g_center := Vector3(d.global_position.x, _ground_y, d.global_position.z)
		if _spawn_inside_hall:
			# The player spawns inside the hall, but the first exterior view must
			# still have the dense new grass.  Centre the carpet just outside the
			# east door instead of skipping it entirely.
			var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(
					frontline_map, {})
			if not site.is_empty():
				var c: Vector2 = site["center"]
				var half: Vector2 = site["half"]
				g_center = Vector3(c.x + half.x + 32.0, _ground_y, c.y)
				g_rad = minf(g_rad, 42.0)
		FoliageSystemScript.spawn_dense_grass(self, g_center, g_rad, g_cnt,
				g_base, g_tip, frontline_map,
				Vector3(d.global_position.x, 0.0, d.global_position.z), 9.0)
		if not frontline_map.is_empty():
			# Grass follows the active camera, so every part of every map gets
			# the same dense near-field blades, not only the spawn apron.
			var fg_script = load("res://scripts/util/follow_grass.gd")
			if fg_script != null:
				var fg = fg_script.new()
				fg.name = "FollowGrass"
				add_child(fg)
				fg.setup(frontline_map, QualityManagerScript.get_active_level())
				fg.set_spawn_clear(Vector3(d.global_position.x, 0.0,
						d.global_position.z), 9.0)
				fg.prime(Vector3(d.global_position.x, 0.0,
						d.global_position.z))
	_hide_drone_visuals(d)
	var preset_drone := get_node_or_null("Drone")
	if preset_drone != null:
		DroneCatalog.apply_to_drone(preset_drone, Global.drone_preset)
		_model_root = preset_drone.get_node_or_null("DroneModel") as Node3D
	_refresh_model_visibility()

	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		cam.cull_mask = 1
		cam.current = true
	_attach_fpv_rig()
	_setup_fpv_camera_for_preset()
	_setup_multi_cameras()
	_setup_warhead_sensor()
	# Apply the combat-FPV camera lift after the preset has placed the lens.
	_refresh_model_visibility()

	if frontline_map == "":
		_build_valley_props()
	else:
		_build_frontline_props()
		if Global.play_mode == Global.PlayMode.COMBAT \
				and not OS.has_environment("QA_NO_AMBIENT") \
				and QualityManager.get_active_level() != QualityManager.Level.LOW:
			var ambient = AmbientBattleScript.new()
			ambient.name = "AmbientBattle"
			ambient.map_name = frontline_map
			ambient.drone = get_node_or_null("Drone")
			if QualityManager.get_active_level() == QualityManager.Level.MEDIUM:
				ambient.rate_scale = 2.0
			add_child(ambient)
	# Valley closed scenic railway loop, moving train, and railway station
	if frontline_map == "":
		ValleySceneBuilderScript.build_railway_loop_and_train(self, _ground_y)
		ValleySceneBuilderScript.build_railway_station(self, Vector3(0.0, _ground_y, -228.0))
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and Global.combat_mission == 5:
		var NavalBuilder = load("res://scripts/util/naval_scene_builder.gd")
		NavalBuilder.build_sea_and_coast(self, _sea_y)
	QualityManagerScript.apply_to_scene(self)
	_tune_map_environment()
	_setup_hud()
	if Global.play_mode == Global.PlayMode.COMBAT:
		var markers_script = load("res://scripts/util/objective_markers.gd")
		if markers_script != null:
			var markers = markers_script.new()
			markers.name = "ObjectiveMarkers"
			_hud.add_child(markers)
			markers.setup(self)
	if _has_bomb_sight():
		call_deferred("_setup_bomber_systems")
	if Global.play_mode == Global.PlayMode.CHAOS:
		var ch := get_node_or_null("CombatHUD") as CanvasLayer
		if ch != null:
			ch.visible = false
	_setup_reb()
	_update_hud()
	_setup_weather()
	_setup_vision_overlay()
	_apply_osd_colors()
	call_deferred("_dismiss_global_loading_overlay")
	# Mission entry always shows the flight HUD.  A stale "OSD off" from an
	# earlier session used to hide every label after returning from the menu.
	_osd_visible = true
	GameSettings.hud_config["osd"] = true
	_apply_osd()
	if Global.play_mode == Global.PlayMode.COMBAT and Global.chain_briefing_pending:
		Global.chain_briefing_pending = false
		call_deferred("_show_chain_briefing")
	if OS.has_environment("DRONE_CLEAN_SHOT"):
		_osd_visible = false
		_apply_osd()
		for cname in ["Help", "FPVOverlay", "CombatHUD"]:
			var cnode := get_node_or_null(cname)
			if cnode is CanvasLayer:
				(cnode as CanvasLayer).visible = false
			elif cnode is CanvasItem:
				(cnode as CanvasItem).visible = false
	_setup_audio()
	call_deferred("_auto_hide_help")

	if OS.has_environment("DRONE_HYDRO_RAM_TEST"):
		call_deferred("_setup_hydro_ram_test")

	print("[BigLevel] ready complete mode=", Global.play_mode,
			" flytest=", OS.has_environment("DRONE_FLYTEST"))
	if OS.has_environment("DRONE_HIDE_NODE"):
		var hide_path := OS.get_environment("DRONE_HIDE_NODE")
		var hide_node := get_node_or_null(hide_path)
		if hide_node is Node3D:
			(hide_node as Node3D).visible = false
			print("[BigLevel] QA hid node ", hide_path)
	if OS.has_environment("DRONE_GFX_AUDIT"):
		call_deferred("_run_gfx_audit")
	if OS.has_environment("DRONE_BOMBER_TEST"):
		call_deferred("_bomber_qa_demo")
	if OS.has_environment("DRONE_DIAG"):
		_test_frames = 0
		_diag_on = true
	if OS.has_environment("DRONE_SHOW_DIAG"):
		_diag_on = true
	if OS.has_environment("DRONE_AUTOTEST"):
		_run_autotest()
	elif OS.has_environment("DRONE_MISSION_DEMO"):
		call_deferred("_mission_demo")
	elif OS.has_environment("DRONE_FULLTEST"):
		call_deferred("_full_test")
	elif OS.has_environment("DRONE_DROP_DEMO"):
		call_deferred("_drop_demo")
	elif OS.has_environment("DRONE_WINDOW_DEMO"):
		call_deferred("_window_demo")
	elif OS.has_environment("DRONE_CRANE_DEMO"):
		call_deferred("_crane_demo")
	elif OS.has_environment("DRONE_EXPLOSION_DEMO"):
		call_deferred("_explosion_demo")
	elif OS.has_environment("DRONE_STATION_DEMO"):
		call_deferred("_station_demo")
	elif OS.has_environment("DRONE_PAUSE_DEMO"):
		call_deferred("_pause_demo")
	elif OS.has_environment("DRONE_PAUSE_TEST"):
		call_deferred("_pause_test")
	elif OS.has_environment("DRONE_SHOT_TEST"):
		call_deferred("_shot_test")
	elif OS.has_environment("DRONE_FLYTEST"):
		call_deferred("_fly_test")
	elif OS.has_environment("DRONE_STABILITY_TEST"):
		call_deferred("_stability_test")
	elif OS.has_environment("DRONE_PAYLOAD_TEST"):
		call_deferred("_payload_test")
	elif OS.has_environment("DRONE_KAMIKAZE_TEST"):
		call_deferred("_kamikaze_contact_test")
	elif OS.has_environment("DRONE_DROP_TEST"):
		call_deferred("_payload_drop_qa_test")
	elif OS.has_environment("DRONE_RETRY_TEST"):
		call_deferred("_retry_test")


## QA: activates the warhead on a kamikaze preset and verifies the drone is
## taken out and respawned with a fresh payload.
func _payload_test() -> void:
	await get_tree().create_timer(2.5).timeout
	var d := get_node_or_null("Drone") as Drone
	var p := DroneCatalog.preset(Global.drone_preset)
	print("[PAYLOADTEST] preset=", Global.drone_preset, " enabled=", _payload_enabled,
			" has_drop=", bool(p.get("has_drop", false)),
			" payload=", int(p.get("payload", 0)))
	_activate_fpv_payload()
	await get_tree().process_frame
	print("[PAYLOADTEST] after activation dropped=", _payload_dropped,
			" visible=", d.visible if d != null else "null",
			" freeze=", d.freeze if d != null else "null")
	await get_tree().create_timer(3.8).timeout
	print("[PAYLOADTEST] after respawn dropped=", _payload_dropped,
			" visible=", d.visible if d != null else "null")
	get_tree().quit()


## QA: verifies a dropper's payload actually leaves the pylon, is a physical
## RigidBody3D, and consumes one round from the authoritative ammo counter.
func _payload_drop_qa_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		print("[DROPTEST] FAIL no drone")
		get_tree().quit(1)
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	var has_drop := bool(p.get("has_drop", false))
	var before := _ammo_count()
	print("[DROPTEST] preset=", Global.drone_preset,
			" has_drop=", has_drop, " ammo_before=", before)
	if not has_drop or before <= 0:
		print("[DROPTEST] FAIL not a dropper")
		get_tree().quit(1)
		return
	var ground := _spawn_ground_height(d.global_position.x, d.global_position.z)
	d.freeze = true
	d.global_position = Vector3(d.global_position.x, ground + 25.0,
			d.global_position.z)
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.flight_controller.request_arm(true)
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[DROPTEST] armed=", d.flight_controller.state_armed,
			" agl=", roundf((d.global_position.y - ground) * 10.0) / 10.0)
	# Exercise the polled-edge path used by a latching AUX switch.  No timer is
	# involved: the first physics tick after the action edge must release it.
	Input.action_press("deploy_payload")
	await get_tree().physics_frame
	Input.action_release("deploy_payload")
	await get_tree().create_timer(0.25).timeout
	var payloads := 0
	for child in get_children():
		if child is Payload:
			payloads += 1
	var after := _ammo_count()
	# Second release uses a real InputEventAction (key/button path) instead of
	# the polled edge, proving the two input paths do not double-drop.
	await get_tree().create_timer(1.1).timeout
	var mid := _ammo_count()
	var press := InputEventAction.new()
	press.action = "deploy_payload"
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().physics_frame
	var release := InputEventAction.new()
	release.action = "deploy_payload"
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().create_timer(0.25).timeout
	var after_event := _ammo_count()
	var ok := payloads > 0 and after == before - 1 \
			and after_event == mid - 1
	print("[DROPTEST] payload_nodes=", payloads, " ammo_after=", after,
			" poll_drop=", before - after,
			" event_drop=", mid - after_event,
			" result=", "PASS" if ok else "FAIL")
	print("[DROPTEST] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


## QA: verifies both halves of the strike-airframe rule:
##   1. a gentle touchdown with the landing assist does NOT detonate;
##   2. a hard 16 m/s body contact DOES initiate the integrated warhead.
func _kamikaze_contact_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		print("[KAMTEST] FAIL no drone")
		get_tree().quit(1)
		return
	print("[KAMTEST] preset=", Global.drone_preset,
			" payload_enabled=", _payload_enabled,
			" kamikaze=", bool(DroneCatalog.preset(Global.drone_preset).get(
					"kamikaze", false)))
	if not _payload_enabled:
		print("[KAMTEST] FAIL no armed airframe")
		get_tree().quit(1)
		return
	var ground := _spawn_ground_height(d.global_position.x, d.global_position.z)
	# Deterministic QA: the physical radio would overwrite the synthetic
	# throttle/attitude each frame.
	var radio := get_node_or_null("RadioController")
	if radio != null:
		radio.set_physics_process(false)
	d.freeze = false
	d.flight_controller.request_arm(true)
	await get_tree().physics_frame
	# Gentle touchdown: throttle 0 lets the landing assist cushion the fall.
	d.global_position = Vector3(d.global_position.x, ground + 5.0,
			d.global_position.z)
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.flight_controller.input = [0.0, 0.0, 0.0, 0.0]
	await get_tree().create_timer(1.8).timeout
	var gentle_ok := not _payload_dropped
	print("[KAMTEST] gentle_touchdown_detonated=", _payload_dropped,
			" result=", "PASS" if gentle_ok else "FAIL")
	# Hard contact: a 22 m/s lateral strike into a temporary concrete test
	# wall.  Using a wall instead of the ground avoids the rotor ground-effect
	# cushion, which can flare a real quad down to <1 m/s right above grass.
	if not d.flight_controller.state_armed:
		d.flight_controller.request_arm(true)
	d.freeze = false
	d.global_position = Vector3(d.global_position.x, ground + 18.0,
			d.global_position.z)
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.flight_controller.input = [0.30, 0.0, 0.0, 0.0]
	print("[KAMTEST] pre_strike pos=", d.global_position,
			" freeze=", d.freeze, " armed=", d.flight_controller.state_armed)
	var wall := StaticBody3D.new()
	wall.name = "QaKamikazeWall"
	wall.collision_layer = 1
	wall.collision_mask = 1
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10.0, 10.0, 1.0)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	var wall_mesh := MeshInstance3D.new()
	var wall_mesh_box := BoxMesh.new()
	wall_mesh_box.size = Vector3(10.0, 10.0, 1.0)
	wall_mesh.mesh = wall_mesh_box
	wall_mesh.material_override = FrontlineTerrainScript._pbr(
			"hall_concrete", Color(0.6, 0.6, 0.58), 0.2)
	wall.add_child(wall_mesh)
	wall.position = Vector3(d.global_position.x, d.global_position.y,
			d.global_position.z - 8.0)
	add_child(wall)
	await get_tree().physics_frame
	d.linear_velocity = Vector3(0.0, 0.0, -22.0)
	for _i in range(5):
		await get_tree().create_timer(0.1).timeout
		print("[KAMTEST] strike_sample y=",
				roundf(d.global_position.y * 10.0) / 10.0,
				" z=", roundf(d.global_position.z * 10.0) / 10.0,
				" vz=", roundf(d.linear_velocity.z * 10.0) / 10.0,
				" last_speed=", roundf(_drone_last_speed * 10.0) / 10.0,
				" armed=", d.flight_controller.state_armed,
				" airborne=", bool(d.get("_was_airborne")))
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(wall):
		wall.queue_free()
	var hard_ok := _payload_dropped and not d.visible
	print("[KAMTEST] hard_contact_detonated=", _payload_dropped,
			" drone_hidden=", not d.visible,
			" result=", "PASS" if hard_ok else "FAIL")
	print("[KAMTEST] RESULT ", "PASS" if gentle_ok and hard_ok else "FAIL")
	get_tree().quit(0 if gentle_ok and hard_ok else 1)


## QA: really arm and spin up the motors, then report how much the drone climbs.
## Uses a Timer (not awaits) so a freed coroutine cannot silently stop it.
func _fly_test() -> void:
	print("[FLYTEST] enter preset=", Global.drone_preset)
	var d := get_node_or_null("Drone") as Drone
	var radio := get_node_or_null("RadioController")
	if d == null:
		print("[FLYTEST] FAIL no drone")
		get_tree().quit()
		return
	_place_drone_over_ground()
	# Let the teleport settle in the physics server before unfreezing; arming in
	# the same frame as the transform assignment makes Bullet/Godot integrate
	# from a stale state and flings the body across the map.
	await get_tree().physics_frame
	await get_tree().physics_frame
	d.flight_controller.request_arm(true)
	if radio != null:
		# Heavy Li-ion bombers need far more than 65% just to hover.  Pick a
		# throttle that is ~10% above the preset's theoretical hover point.
		var twr := float(DroneCatalog.preset(Global.drone_preset).get("twr", 2.0))
		var hover_throttle := 0.45 + 0.55 * sqrt(1.0 / maxf(twr, 1.0))
		radio.test_throttle = clampf(hover_throttle + 0.10, 0.60, 0.95)
	var timer := Timer.new()
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	timer.wait_time = 0.5
	timer.timeout.connect(_fly_test_tick)
	timer.start()
	_fly_ticks = 0
	_fly_y0 = d.global_position.y
	print("[FLYTEST] preset=", Global.drone_preset, " name=",
			DroneCatalog.preset(Global.drone_preset)["name"], " mass=", d.mass,
			" armed=", d.flight_controller.state_armed, " y0=", roundf(_fly_y0 * 100.0) / 100.0)


var _fly_ticks := 0
var _fly_y0 := 0.0
var _fly_max := 0.0


func _fly_test_tick() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		print("[FLYTEST] drone gone")
		get_tree().quit()
		return
	_fly_ticks += 1
	_fly_max = maxf(_fly_max, d.global_position.y)
	print("[FLYTEST]  t=", 0.5 * _fly_ticks,
			" y=", roundf(d.global_position.y * 100.0) / 100.0,
			" vy=", roundf(d.linear_velocity.y * 10.0) / 10.0,
			" rpm=", roundf(d.motors[0].get_rpm()))
	if _fly_ticks >= 10:
		var rise := _fly_max - _fly_y0
		print("[FLYTEST] rise=", roundf(rise * 100.0) / 100.0, "m ",
				"PASS" if rise > 3.0 else "FAIL")
		get_tree().quit()


## QA: hold a roll stick, release it and measure whether LEVEL mode settles or
## keeps rocking (the old "seesaw"). Prints the envelope and a PASS/FAIL.
func _stability_test() -> void:
	var d := get_node_or_null("Drone") as Drone
	var radio := get_node_or_null("RadioController")
	if d == null or radio == null:
		print("[STABILITY] FAIL setup")
		get_tree().quit()
		return
	_place_drone_over_ground()
	await get_tree().physics_frame
	await get_tree().physics_frame
	d.flight_controller.request_arm(true)
	radio.test_throttle = 0.55
	await get_tree().create_timer(1.0).timeout
	var stick := 0.6
	if OS.has_environment("DRONE_STAB_STICK"):
		stick = clampf(float(OS.get_environment("DRONE_STAB_STICK")), 0.05, 1.0)
	var hold := 0.8
	if OS.has_environment("DRONE_STAB_HOLD"):
		hold = clampf(float(OS.get_environment("DRONE_STAB_HOLD")), 0.2, 4.0)
	radio.test_roll = stick
	await get_tree().create_timer(hold).timeout
	radio.test_roll = 0.0
	var release_roll := rad_to_deg(d.flight_controller.angles.z)
	print("[STABILITY] released at roll=", roundf(release_roll * 10.0) / 10.0)
	var prev_rate := 0.0
	var reversals := 0
	var samples: Array[float] = []
	for i in range(40):
		await get_tree().create_timer(0.1).timeout
		var roll := rad_to_deg(d.flight_controller.angles.z)
		var rate := rad_to_deg(d.flight_controller.ang_vel.z)
		samples.append(absf(roll))
		if i > 2 and signf(rate) != 0.0 and signf(prev_rate) != 0.0 \
				and signf(rate) != signf(prev_rate) and absf(rate) > 3.0:
			reversals += 1
		prev_rate = rate
		if i % 5 == 0:
			print("[STABILITY]  t=", (i + 1) * 0.1, " roll=",
					roundf(roll * 10.0) / 10.0, " rate=", roundf(rate * 10.0) / 10.0)
	var late_peak := 0.0
	for i in range(20, samples.size()):
		late_peak = maxf(late_peak, samples[i])
	var ok := late_peak < 12.0 and reversals <= 8
	print("[STABILITY] late_peak=", roundf(late_peak * 10.0) / 10.0,
			"deg reversals=", reversals, " ", "PASS" if ok else "FAIL")
	get_tree().quit()


## QA: finish a run, press retry (full scene reload), then arm with a fresh
## Space-equivalent. This is the exact path that used to leave the drone dead.
func _retry_test() -> void:
	if _retry_test_round == 0:
		_retry_test_round = 1
		await get_tree().create_timer(1.0).timeout
		_mission_started = true
		_finish_mission("RETRY TEST")
		await get_tree().create_timer(0.8).timeout
		print("[RETRYTEST] first run paused=", get_tree().paused,
				" results_visible=", _results != null and _results.visible)
		_on_retry_pressed()
		return
	# Second run after reload.
	await get_tree().create_timer(1.2).timeout
	var d := get_node_or_null("Drone") as Drone
	var paused_now := get_tree().paused
	var d0 := d
	if d != null:
		d.flight_controller.request_arm(true)
	await get_tree().create_timer(0.8).timeout
	var armed: bool = d0 != null and d0.flight_controller.state_armed
	var ok := not paused_now and armed and _mission_started
	print("[RETRYTEST] reloaded paused=", paused_now, " armed=", armed,
			" mission_started=", _mission_started, " ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _pause_test() -> void:
	var timer := Timer.new()
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.one_shot = true
	add_child(timer)
	timer.start(0.6)
	await timer.timeout
	get_tree().paused = true
	if pause_menu != null:
		if pause_menu.has_method("show_menu"):
			pause_menu.show_menu(true)
		else:
			pause_menu.visible = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	timer.start(0.4)
	await timer.timeout
	var ev := InputEventAction.new()
	ev.action = "pause_menu"
	ev.pressed = true
	Input.parse_input_event(ev)
	timer.start(0.4)
	await timer.timeout
	var visible_now: Variant = pause_menu.visible if pause_menu != null else false
	var ok := not get_tree().paused and not bool(visible_now)
	print("[PAUSETEST] paused_after_esc=", get_tree().paused, " menu_visible=", visible_now)
	print("[PAUSETEST] ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _pause_demo() -> void:
	await get_tree().create_timer(1.0).timeout
	if pause_menu != null:
		if OS.has_environment("DRONE_QUAD_DEMO"):
			pause_menu.call("_on_quad_pressed")
		else:
			pause_menu.visible = true


## The keyboard reference strip is useful on the first launch but becomes
## clutter immediately. Hide it after a few seconds; arming hides it too.
func _auto_hide_help() -> void:
	await get_tree().create_timer(9.0).timeout
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false


func _setup_input() -> void:
	Controls.load_input_map()
	Controls.ensure_active_joypad()
	Controls.make_joypad_events_global()
	# The radio controller may have finished _ready before the saved map was
	# loaded; refresh it so switches/axis buttons work immediately.
	var radio := get_node_or_null("RadioController")
	if radio != null and radio.has_method("refresh_bindings"):
		radio.call("refresh_bindings")
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	Controls.ensure_active_joypad()
	Controls.make_joypad_events_global()
	var radio := get_node_or_null("RadioController")
	if radio != null and radio.has_method("_setup_radio"):
		radio.call_deferred("_setup_radio")


func _drop_demo() -> void:
	await get_tree().create_timer(3.4).timeout
	_drop_fpv_payload()


func _mission_demo() -> void:
	await get_tree().create_timer(2.0).timeout
	_mission_started = true
	_mission_time = 83.42
	_score = 1850
	if Global.play_mode == Global.PlayMode.TRAINING:
		_rings_passed = _rings_total
	elif Global.play_mode == Global.PlayMode.SPEED:
		_speed_next = _speed_checkpoints.size()
	_finish_mission("ДЕМО")


func _window_demo() -> void:
	pass


func _crane_demo() -> void:
	pass


func _explosion_demo() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		d.freeze = true
		d.global_position = Vector3(0.0, _ground_y + 7.0, 11.5)
		d.rotation = Vector3(deg_to_rad(-24.0), 0.0, 0.0)

	var v_node := _add_vehicle(VEHICLE.Kind.TANK, [Vector3(0.0, _ground_y, 0.0)], 0.0, false, 320.0, 300)
	if v_node != null:
		v_node.global_position = Vector3(0.0, _ground_y, 0.0)

	await get_tree().create_timer(0.4).timeout
	var payload := PayloadScript.new()
	payload.damage = 500.0
	payload.blast_radius = 10.0
	add_child(payload)
	payload.global_position = Vector3(0.0, _ground_y + 5.5, 1.2)
	payload.linear_velocity = Vector3(0.0, -11.0, -2.0)


# ------------------------------------------------------------------ visuals
var _tint := Color(0.5, 0.45, 0.3)


func _biome() -> Dictionary:
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			return {"ground": Color(0.55, 0.75, 0.50),
					"built": Color(0.92, 0.92, 0.90),
					"rock": Color(0.62, 0.70, 0.58),
					"top": Color(0.16, 0.34, 0.62),
					"horizon": Color(0.72, 0.80, 0.86),
					"fog": Color(0.80, 0.86, 0.90)}
		Global.PlayMode.TRAINING:
			return {"ground": Color(0.55, 0.75, 0.50),
					"built": Color(0.92, 0.92, 0.90),
					"rock": Color(0.62, 0.70, 0.58),
					"top": Color(0.16, 0.34, 0.62),
					"horizon": Color(0.72, 0.80, 0.86),
					"fog": Color(0.80, 0.86, 0.90)}
		Global.PlayMode.SPEED:
			return {"ground": Color(0.85, 0.70, 0.46),
					"built": Color(0.92, 0.86, 0.78),
					"rock": Color(0.74, 0.58, 0.40),
					"top": Color(0.10, 0.18, 0.40),
					"horizon": Color(0.98, 0.66, 0.34),
					"fog": Color(0.92, 0.76, 0.54)}
		_:
			return {"ground": Color(0.58, 0.68, 0.40),
					"built": Color(0.90, 0.88, 0.82),
					"rock": Color(0.64, 0.66, 0.52),
					"top": Color(0.18, 0.28, 0.46),
					"horizon": Color(0.86, 0.84, 0.72),
					"fog": Color(0.84, 0.84, 0.74)}


func _upgrade_environment() -> void:
	VisualEnhancer.apply_to_scene(self)


## Per-map atmosphere: the same reference grade, tuned so the four maps do not
## look like the same weather.  Runs after QualityManager so the profile's
## volumetric/shadow settings stay authoritative.
func _tune_map_environment() -> void:
	if frontline_map.is_empty():
		return
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	match frontline_map:
		"industrial":
			env.fog_light_color = Color(0.62, 0.68, 0.74)
			env.fog_light_energy = 0.50
			env.fog_density = 0.00022
			env.fog_aerial_perspective = 0.28
			env.volumetric_fog_density = 0.0011
			env.ambient_light_energy = 0.28
			env.ambient_light_sky_contribution = 0.30
			env.tonemap_exposure = 0.98
			env.glow_intensity = 0.22
			if sun != null:
				sun.rotation_degrees = Vector3(-22.0, 68.0, 0.0)
				sun.light_energy = 2.6
				sun.light_color = Color(1.0, 0.79, 0.56)
				sun.light_volumetric_fog_energy = 3.4
		"village":
			env.fog_light_color = Color(0.78, 0.74, 0.64)
			env.fog_light_energy = 0.52
			env.fog_density = 0.00014
			env.volumetric_fog_density = 0.0010
			env.ambient_light_energy = 0.50
			env.ambient_light_sky_contribution = 0.40
			env.tonemap_exposure = 1.08
			if sun != null:
				sun.rotation_degrees = Vector3(-26.0, 42.0, 0.0)
				sun.light_energy = 3.1
				sun.light_color = Color(1.0, 0.85, 0.67)
				sun.light_volumetric_fog_energy = 3.2
		"steppe":
			env.fog_light_color = Color(0.84, 0.78, 0.64)
			env.fog_light_energy = 0.56
			env.fog_density = 0.00016
			env.volumetric_fog_density = 0.0011
			env.ambient_light_energy = 0.56
			env.ambient_light_sky_contribution = 0.42
			env.tonemap_exposure = 1.10
			if sun != null:
				sun.rotation_degrees = Vector3(-26.0, 45.0, 0.0)
				sun.light_energy = 3.2
				sun.light_color = Color(1.0, 0.86, 0.69)
				sun.light_volumetric_fog_energy = 3.5
		"wetlands":
			env.fog_light_color = Color(0.66, 0.74, 0.78)
			env.fog_light_energy = 0.60
			env.fog_density = 0.00035
			env.volumetric_fog_density = 0.0016
			env.ambient_light_energy = 0.34
			env.ambient_light_sky_contribution = 0.32
			env.tonemap_exposure = 1.02
			if sun != null:
				sun.rotation_degrees = Vector3(-20.0, 28.0, 0.0)
				sun.light_energy = 1.8
				sun.light_color = Color(0.92, 0.86, 0.72)
				sun.light_volumetric_fog_energy = 3.5
	# Unified grade for the new look: softer daylight, less haze, a touch more
	# contrast/saturation.  Absolute (not multiplicative) so repeated quality
	# switches cannot compound the values.
	env.tonemap_exposure = clampf(env.tonemap_exposure, 0.95, 1.0)
	env.tonemap_white = 1.6
	env.fog_density = minf(env.fog_density, 0.00028)
	env.ambient_light_energy = clampf(env.ambient_light_energy, 0.45, 0.75)
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.04
	env.adjustment_saturation = 1.04
	env.adjustment_brightness = 1.0
	if sun != null:
		sun.light_energy = minf(sun.light_energy, 2.2)
	# Soft cool fill from the opposite side.  One extra unshadowed directional
	# light gives shape to facades and the hall interior without SSAO/SSIL cost.
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		add_child(fill)
	fill.rotation_degrees = Vector3(-52.0, -140.0, 0.0)
	fill.light_color = Color(0.62, 0.72, 0.88)
	fill.light_energy = 0.32
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0


## Called by QualityManager after any preset change (including mid-flight):
## re-apply the map's atmosphere on top of the global profile.
func on_quality_applied() -> void:
	_tune_map_environment()


# --------------------------------------------------------------- prop builders
## Original valley content, unchanged.  Kept separate from _ready so the four
## frontline maps can swap in their own terrain without touching this code.
func _build_valley_props() -> void:
	# TAC-05 is fought in open water.  The normal valley mountains, factory,
	# fortifications and tree lines would sit inside the naval basin and hide
	# the sea behind a green hillside, so the mission gets a clean horizon:
	# only the sea, the quay, the hydroelectric dam and the corvette.
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and Global.combat_mission == 5:
		_spawn_special_or_campaign()
		return
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 235.0, 1350.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -28.0))
			_spawn_vegetation(500, 55.0, 850.0, 0.30)
			var d_inst := get_node_or_null("Drone") as Drone
			_flight_school = FlightSchool.new()
			add_child(_flight_school)
			_flight_school.initialize(self, d_inst, _ground_y)
		Global.PlayMode.TRAINING:
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 235.0, 1350.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -28.0))
			ValleySceneBuilderScript.build_construction_crane(self, Vector3(56.0, _ground_y, -24.0), deg_to_rad(35.0))
			ValleySceneBuilderScript.build_concrete_pipe_park(self, Vector3(-58.0, _ground_y, 16.0), deg_to_rad(15.0))
			ValleySceneBuilderScript.build_container_freestyle_park(self, Vector3(22.0, _ground_y, 42.0), deg_to_rad(-10.0))
			_spawn_training_rings()
			_spawn_vegetation(680, 55.0, 900.0, 0.32)
		Global.PlayMode.SPEED:
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 245.0, 1380.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -20.0))
			ValleySceneBuilderScript.build_construction_crane(self, Vector3(72.0, _ground_y, -28.0), deg_to_rad(20.0))
			ValleySceneBuilderScript.build_concrete_pipe_park(self, Vector3(-65.0, _ground_y, 10.0), deg_to_rad(10.0))
			_spawn_speed_course()
			_spawn_boost_pads()
			_spawn_vegetation(620, 65.0, 900.0, 0.34)
		_:
			if OS.has_environment("DRONE_COMBAT_MISSION"):
				Global.combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 5)
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 430.0, 1550.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -60.0))
			ValleySceneBuilderScript.build_combat_fortifications(self, Vector3(-42.0, _ground_y, -90.0), deg_to_rad(10.0))
			ValleySceneBuilderScript.build_construction_crane(self, Vector3(68.0, _ground_y, -110.0), deg_to_rad(45.0))
			ValleySceneBuilderScript.build_container_freestyle_park(self, Vector3(45.0, _ground_y, -65.0), deg_to_rad(25.0))
			_spawn_special_or_campaign()
			_spawn_vegetation(680, 65.0, 920.0, 0.35)
			if OS.has_environment("DRONE_RECON_VIEW"):
				call_deferred("_setup_recon_view")


## Ukrainian front-line maps.  The terrain module builds the ground, trenches,
## tree lines, craters and landmarks; this function only wires up the mission
## logic that BigLevel already owns.
func _build_frontline_props() -> void:
	var builder = load("res://scripts/util/frontline_terrain.gd")
	if builder == null:
		push_error("[BigLevel] frontline_terrain.gd missing")
		return
	builder.build(self, frontline_map, _ground_y)
	var d := get_node_or_null("Drone") as Drone
	match frontline_map:
		"steppe":
			_spawn_vegetation(720, 70.0, 1000.0, 0.30)
		"village":
			_spawn_vegetation(540, 60.0, 820.0, 0.38)
		"industrial":
			_spawn_vegetation(260, 80.0, 700.0, 0.18)
		"wetlands":
			_spawn_vegetation(380, 90.0, 760.0, 0.26)
	if Global.play_mode == Global.PlayMode.COMBAT:
		_spawn_special_or_campaign()
		_start_reinforcements()
		# The random destructible office blocks used to drop 5-storey concrete
		# towers into the middle of the handcrafted factory/village skyline.
		# The authored landmark pass now owns every building silhouette, so the
		# procedural blocks are no longer spawned on frontline maps.  They stay
		# available for the legacy test map only.
		if frontline_map == "" and not OS.has_environment("QA_NO_DESTRUCTIBLES"):
			_spawn_destructible_buildings(4, 130.0, 250.0)
	if Global.play_mode == Global.PlayMode.CHAOS:
		_spawn_chaos_battle()
	if Global.play_mode == Global.PlayMode.TRAINING:
		# The legacy valley range was the only place with the 24-ring course.
		# Keep free-flight/training on the four finished maps: the rings follow
		# the real terrain height instead of the flat test-strip height.
		# Free flight on the finished maps stays clear of the 24 race gates:
		# they cluttered the view and the "GATE 1/24" marker covered the OSD.
		_rings_total = 0
	if Global.play_mode == Global.PlayMode.SPEED:
		# The timed course also used to live only on the legacy valley.  Build
		# it on the selected frontline map with terrain-aware checkpoint/boost
		# heights.
		_spawn_speed_course()
		_spawn_boost_pads()
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		_flight_school = FlightSchool.new()
		add_child(_flight_school)
		_flight_school.initialize(self, d, _ground_y)
	if OS.has_environment("DRONE_RECON_VIEW"):
		call_deferred("_setup_recon_view")
	if OS.has_environment("DRONE_GROUND_AUDIT"):
		call_deferred("_run_ground_audit")
	if OS.has_environment("DRONE_FLOAT_AUDIT"):
		call_deferred("_run_float_audit")


## QA-only: scan every authored prop instance for a visible mesh whose lowest
## point floats above the rendered terrain.  Bridges/boats live over water by
## design and are excluded.
func _run_float_audit() -> void:
	await get_tree().create_timer(3.0).timeout
	if frontline_map.is_empty():
		print("[FLOAT] skipped: not a frontline map")
		return
	var terrain_root := get_node_or_null("FrontlineTerrain")
	if terrain_root != null and terrain_root.has_meta("qa_float_result"):
		var pre: Dictionary = terrain_root.get_meta("qa_float_result")
		print("[FLOAT] pre-batch map=", pre.get("map"),
				" checked=", int(pre.get("checked", 0)) + int(pre.get("multimesh_checked", 0)),
				" floating=", int(pre.get("floating", 0)) + int(pre.get("multimesh_floating", 0)))
		for item in pre.get("issues", []):
			print("[FLOAT] pre-batch issue ", item)
	var fassets = load("res://scripts/util/frontline_assets.gd")
	if fassets == null:
		return
	var issues := 0
	var checked := 0
	for node in get_tree().get_nodes_in_group("frontline_asset"):
		var n := node as Node3D
		if n == null or not is_instance_valid(n):
			continue
		var nm := String(n.name).to_lower()
		if nm.contains("bridge") or nm.contains("barge") or nm.contains("boat") \
				or nm.contains("water"):
			continue
		var bb: AABB = fassets.visual_aabb(n)
		if bb.size.y < 0.05:
			continue
		checked += 1
		var p := Vector2(n.global_position.x, n.global_position.z)
		var ground := FrontlineTerrainScript.footprint_surface_height(
				frontline_map, p, bb.size.x, bb.size.z, n.global_rotation.y)
		var gap := bb.position.y - ground
		if gap > 0.65:
			issues += 1
			if issues <= 20:
				print("[FLOAT] ", n.name, " at ", n.global_position,
						" bottom=", roundf(bb.position.y * 100.0) / 100.0,
						" ground=", roundf(ground * 100.0) / 100.0,
						" gap=", roundf(gap * 100.0) / 100.0)
	print("[FLOAT] map=", frontline_map, " checked=", checked,
			" floating=", issues)
	if OS.has_environment("DRONE_FLOAT_AUDIT_QUIT"):
		get_tree().quit(0 if issues == 0 else 1)


## QA-only: after the combat layer has spawned, compare every ground vehicle
## and infantryman with the analytic terrain height.  >1.2 m difference means
## the unit is standing on a roof or another prop.
func _run_ground_audit() -> void:
	await get_tree().create_timer(3.0).timeout
	if frontline_map.is_empty():
		print("[GROUND-AUDIT] skipped: not a frontline map")
		return
	var issues := 0
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		if v.kind == Vehicle.Kind.HELI or v.kind == Vehicle.Kind.SHAHED:
			continue
		var terrain := FrontlineTerrainScript.height_at(frontline_map,
				v.global_position.x, v.global_position.z)
		var diff := v.global_position.y - terrain
		var ok := absf(diff) < 1.2
		if not ok:
			issues += 1
		print("[GROUND-AUDIT] vehicle=%d pos=%s terrain=%.2f diff=%.2f ok=%s" % [
			v.kind, str(v.global_position), terrain, diff, str(ok)])
	for u in _infantry_units:
		if not is_instance_valid(u):
			continue
		var terrain := FrontlineTerrainScript.height_at(frontline_map,
				u.global_position.x, u.global_position.z)
		var diff := u.global_position.y - terrain
		var ok := absf(diff) < 1.2
		if not ok:
			issues += 1
		print("[GROUND-AUDIT] infantry pos=%s terrain=%.2f diff=%.2f ok=%s" % [
			str(u.global_position), terrain, diff, str(ok)])
	print("[GROUND-AUDIT] map=", frontline_map, " issues=", issues)


## QA-only graphics audit: confirms that the whole detail stack (terrain
## nature, follow-camera grass, world dressing, 100-object kit, material
## upgrade) really exists on the loaded combat map, rather than only in code.
func _run_gfx_audit() -> void:
	await get_tree().create_timer(2.0).timeout
	var ft := get_node_or_null("FrontlineTerrain")
	var mm_count := 0
	var mm_instances := 0
	var mesh_count := 0
	var pbr_meshes := 0
	var detail: Dictionary = {}
	if ft != null:
		for n in ft.find_children("*", "MultiMeshInstance3D", true, false):
			var mmi := n as MultiMeshInstance3D
			if mmi.multimesh == null:
				continue
			mm_count += 1
			mm_instances += mmi.multimesh.instance_count
			var nm := String(mmi.name).to_lower()
			for key in ["grass", "tuft", "stone", "flower", "scrub", "bush",
					"tree", "crop", "debris", "props"]:
				if nm.contains(key):
					detail[key] = int(detail.get(key, 0)) + mmi.multimesh.instance_count
					break
		for n in ft.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			mesh_count += 1
			for s in range(mi.mesh.get_surface_count()):
				var m = mi.get_surface_override_material(s)
				if m is StandardMaterial3D:
					var sm := m as StandardMaterial3D
					if sm.normal_enabled and sm.albedo_texture != null:
						pbr_meshes += 1
						break
	var fg := get_node_or_null("FollowGrass")
	var fg_count := int(fg.get("count")) if fg != null else 0
	var fg_radius := float(fg.get("radius")) if fg != null else 0.0
	var dg_near := get_node_or_null("DenseGrassFoliage") as MultiMeshInstance3D
	var dg_far := get_node_or_null("DenseGrassFar") as MultiMeshInstance3D
	var dg_near_n := dg_near.multimesh.instance_count \
			if dg_near != null and dg_near.multimesh != null else 0
	var dg_far_n := dg_far.multimesh.instance_count \
			if dg_far != null and dg_far.multimesh != null else 0
	var wd := ft != null and bool(ft.get_meta("gfx_world_detail", false))
	var wd_factor = ft.get_meta("gfx_world_detail_factor", 0.0) if ft != null else 0.0
	var kit := int(ft.get_meta("gfx_object_kit", 0)) if ft != null else 0
	var kit_cols := int(ft.get_meta("gfx_object_kit_colliders", 0)) \
			if ft != null else 0
	var upgrades := int(ft.get_meta("gfx_material_upgrades", 0)) \
			if ft != null else 0
	var crop_fields := ft.find_children("*CropField_*", "MeshInstance3D", true,
			false).size() if ft != null else 0
	var lvl := QualityManagerScript.get_active_level()
	print("[GFX-AUDIT] map=", frontline_map, " mode=", Global.play_mode,
			" quality=", QualityManagerScript.NAMES[lvl])
	print("[GFX-AUDIT] terrain: multimeshes=", mm_count,
			" instances=", mm_instances, " meshes=", mesh_count,
			" pbr_meshes=", pbr_meshes)
	print("[GFX-AUDIT] detail=", detail)
	print("[GFX-AUDIT] dressing: world_detail=", wd,
			" factor=", wd_factor, " object_kit=", kit,
			" colliders=", kit_cols, " material_upgrades=", upgrades,
			" crop_fields=", crop_fields)
	print("[GFX-AUDIT] follow_grass=", fg != null,
			" count=", fg_count, " radius=", fg_radius,
			" static_grass=", dg_near_n + dg_far_n,
			" (near=", dg_near_n, " far=", dg_far_n, ")")
	print("[GFX-AUDIT] combat: destructibles=",
			get_tree().get_nodes_in_group("destructible").size(),
			" vehicles=", get_tree().get_nodes_in_group("vehicle").size(),
			" infantry=", _infantry_units.size(), " chaos_soldiers=",
			get_tree().get_nodes_in_group("chaos_soldier").size())


# ------------------------------------------------------------------ map load
func _map_path() -> String:
	if frontline_map != "":
		return ""
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			return "res://Assets/maps/map_training.glb"
		Global.PlayMode.TRAINING:
			return "res://Assets/maps/map_training.glb"
		Global.PlayMode.SPEED:
			return "res://Assets/maps/map_training.glb"
		_:
			return "res://Assets/maps/map_combat.glb"


func _load_map() -> void:
	if _map_root == null:
		return
	var path := _map_path()
	if path == "":
		# Frontline maps build their own procedural clipmap terrain.  This has
		# to happen before _place_drone_over_ground() probes the surface.
		var builder = load("res://scripts/util/frontline_terrain.gd")
		if builder == null:
			push_error("[BigLevel] frontline_terrain.gd missing")
		else:
			builder.build_terrain(self, frontline_map, 0.0)
		_prepare_bedrock_floor()
		return
	if not ResourceLoader.exists(path):
		print("[BigLevel] map not found: ", path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("[BigLevel] map is not a scene: ", path)
		return
	var instance := packed.instantiate()
	_map_root.add_child(instance)
	_apply_map_materials(instance)
	# Legacy GLB maps (city / valley) get the same map-wide material upgrade
	# as the handmade frontline maps, so their flat placeholder materials pick
	# up PBR normals, roughness and close-range detail automatically.
	if not OS.has_environment("QA_NO_MATERIAL_UPGRADE"):
		var upgrader = load("res://scripts/util/material_upgrader.gd")
		if upgrader != null:
			upgrader.upgrade(instance, "legacy", QualityManagerScript.get_active_level())
	if not OS.has_environment("QA_NO_LEGACY_DETAIL"):
		call_deferred("_scatter_legacy_map", instance)
	_prepare_bedrock_floor()
	print("[BigLevel] loaded ", path, " (mode ", Global.play_mode, ")")


## Legacy maps do not have the procedural FrontlineTerrain height field, so
## their clutter is placed with physics raycasts once the world is live.
func _scatter_legacy_map(instance: Node3D) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_instance_valid(instance):
		return
	var ld = load("res://scripts/util/legacy_detail.gd")
	if ld != null:
		ld.scatter(self, instance, QualityManagerScript.get_active_level())


## Bedrock safety floor placed deep in the abyss (-50m) so it NEVER interferes
## with the real terrain surface or prevents landing on grass in lower valleys.
func _prepare_bedrock_floor() -> void:
	var ground_node := get_node_or_null("Ground") as StaticBody3D
	if ground_node == null:
		return
	ground_node.collision_layer = 1
	ground_node.collision_mask = 1
	ground_node.global_position = Vector3(0.0, -50.0, 0.0)
	var fallback_ground := ground_node.get_node_or_null("MeshInstance3D") as VisualInstance3D
	if fallback_ground != null:
		fallback_ground.visible = false
	var fallback_col := ground_node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if fallback_col != null:
		fallback_col.disabled = false
		fallback_col.position = Vector3.ZERO
		var box := BoxShape3D.new()
		box.size = Vector3(12000.0, 10.0, 12000.0)
		fallback_col.shape = box


func _make_tex_material(albedo_path: String, normal_path: String,
		uv_scale: float, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	if ResourceLoader.exists(albedo_path):
		material.albedo_texture = load(albedo_path)
	if ResourceLoader.exists(normal_path):
		material.normal_enabled = true
		material.normal_texture = load(normal_path)
	material.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	material.uv1_world_triplanar = true
	material.roughness = 0.95
	material.albedo_color = tint
	return material


func _apply_map_materials(node: Node) -> void:
	var biome := _biome()
	var ground_mat: Material = null
	if ResourceLoader.exists("res://Assets/GroundMaterial.tres"):
		ground_mat = load("res://Assets/GroundMaterial.tres") as Material
	if ground_mat == null:
		ground_mat = _make_tex_material("res://Assets/textures/1.png",
				"res://Assets/textures/NormalMap.png", 0.10, biome["ground"])
	var rock := _make_tex_material("res://Assets/textures/2.png",
			"res://Assets/textures/NormalMap-2.png", 0.18, biome["rock"])
	var built := _make_tex_material("res://Assets/textures/4.png",
			"res://Assets/textures/NormalMap-1.png", 0.30, biome["built"])
	_assign_materials(node, ground_mat, rock, built)


func _assign_materials(node: Node, ground_mat: Material, rock: StandardMaterial3D,
		built: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		var name_lower := String(mesh.name).to_lower()
		var is_ground := name_lower.contains("ground") or name_lower.contains("floor") \
				or name_lower.contains("field") or name_lower.contains("terrain") \
				or name_lower.contains("trench")
		if is_ground:
			mesh.material_override = ground_mat
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			# Remove old procedural placeholder cubes/dunes/watchtowers/pads from map_*.glb
			# so only the terrain surface and ValleySceneBuilder landmarks remain.
			mesh.visible = false
			_disable_collisions_recursive(mesh)
			mesh.queue_free()
			return
	for child in node.get_children():
		_assign_materials(child, ground_mat, rock, built)


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)


func _find_ground_y(x: float, z: float) -> float:
	# Inside a hero hall a downward ray hits the roof, which is correct for the
	# building but wrong for every gameplay object placed on its floor.  Use the
	# authored finished-floor height instead.
	var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
	if not site.is_empty():
		var c: Vector2 = site["center"]
		var half: Vector2 = site["half"]
		if absf(x - c.x) < half.x - 3.0 and absf(z - c.y) < half.y - 3.0:
			var sink := float(site.get("sink", 0.0))
			return FrontlineTerrainScript.height_at(frontline_map, x, z) + 0.02 - sink
	# On the procedural maps the terrain height field is authoritative.  A
	# high downward ray used to hit warehouse roofs, spawning targets,
	# vehicles and infantry on rooftops.  Only legacy maps need a physics
	# probe here.
	if not frontline_map.is_empty():
		return FrontlineTerrainScript.height_at(frontline_map, x, z) + 0.02
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, 400.0, z)
	var to := Vector3(x, -200.0, z)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	var drone := get_node_or_null("Drone")
	if drone is CollisionObject3D:
		query.exclude = [(drone as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 0.0
	return (hit["position"] as Vector3).y


## Water surface for the current frontline map (very low on non-frontline maps).
func _map_water_level() -> float:
	if frontline_map.is_empty():
		return -1000.0
	return float(FrontlineTerrainScript.water_level(frontline_map))


## TAC-05 sea level.  The legacy valley uses a flat ground plane at y=0, so a
## 0.35 m water film left the Magura hull scraping the floor and the mission
## ended with a self-detonation.  A 3 m basin keeps the whole route afloat.
func _naval_sea_level() -> float:
	if frontline_map.is_empty():
		return 3.0
	return maxf(_map_water_level() + 0.8, 1.5)


## Spiral outward from (x,z) until the analytic terrain is safely above water.
func _find_dry_spot(x: float, z: float) -> Vector2:
	var wl := _map_water_level()
	for ring in range(1, 10):
		var radius := 10.0 * float(ring)
		for i in range(8):
			var a := TAU * float(i) / 8.0 + float(ring) * 0.4
			var px := x + cos(a) * radius
			var pz := z + sin(a) * radius
			if absf(px) > 470.0 or absf(pz) > 470.0:
				continue
			if FrontlineTerrainScript.height_at(frontline_map, px, pz) > wl + 0.9:
				return Vector2(px, pz)
	return Vector2(clampf(x, -400.0, 400.0), clampf(z, -400.0, 400.0))


## Combat launch point: 330-400 m from the mission centroid, dry open ground,
## a new bearing on every load.  The operator has to search for the target.
func _pick_combat_spawn() -> Vector2:
	var centre := Vector2(_mission_offset.x, 90.0 + _mission_offset.z)
	var water := _map_water_level()
	# Launch from the northern edge with a small jitter.  East/west bearings
	# look straight across the whole map and cost 20-40 FPS on the Intel UHD;
	# this bearing still puts the drone 330-400 m from the objective, and the
	# target block itself moves every load.
	var base_angle := PI * 0.5
	for _attempt in range(64):
		var angle := base_angle + randf_range(-0.26, 0.26)
		var radius := randf_range(330.0, 400.0)
		var p := centre + Vector2(cos(angle), sin(angle)) * radius
		if absf(p.x) > 440.0 or absf(p.y) > 440.0:
			continue
		var h := FrontlineTerrainScript.height_at(frontline_map, p.x, p.y)
		if h < water + 1.2:
			continue
		# A physics hit far above the analytic terrain means a roof/wreck is
		# sitting on that spot; pick open ground instead.
		var phys := _find_ground_y(p.x, p.y)
		if absf(phys - h) > 2.2:
			continue
		return p
	# Fallback: dry ground on the home side of the map.
	return _find_dry_spot(0.0, 330.0)


var _spawn_inside_hall := false

## Safe spawn clearance from the terrain surface.  Keeps a quad/fixed-wing
## airframe high enough that its landing skids never start inside the clipmap,
## while still reading as "parked on the apron".
const SPAWN_SAFE_OFFSET := 0.50
const SPAWN_CLEAR_RADIUS := 0.62


## Physics ground probe for the spawn point.  A downward ray against layer 1
## finds the actual StaticBody3D surface (terrain, hall slab, pier); the
## analytic clipmap height is used as a sanity envelope so a roof or a stacked
## wreck directly overhead cannot be mistaken for the ground.
func _spawn_ground_height(x: float, z: float) -> float:
	var surface := 0.0
	if not frontline_map.is_empty():
		surface = maxf(FrontlineTerrainScript.height_at(frontline_map, x, z),
				FrontlineTerrainScript.mesh_surface_height(frontline_map, x, z))
	else:
		surface = _find_ground_y(x, z)
	var space := get_world_3d().direct_space_state
	if space == null:
		return surface
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(x, surface + 90.0, z), Vector3(x, surface - 40.0, z))
	query.collision_mask = 1
	var drone := get_node_or_null("Drone") as CollisionObject3D
	var exclusions: Array[RID] = []
	if drone != null:
		exclusions.append(drone.get_rid())
	# On a respawn the previous launch cradle is still in the tree; do not
	# treat its top as rising terrain (that would step the spawn up each time).
	if _launch_barrel != null and is_instance_valid(_launch_barrel):
		exclusions.append(_launch_barrel.get_rid())
	query.exclude = exclusions
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		var hy: float = (hit["position"] as Vector3).y
		# Only accept the ray when it agrees with the rendered height field by
		# a small margin.  A hall roof 20 m up or a tree trunk hit is ignored.
		if absf(hy - surface) <= 1.25:
			surface = hy
	return surface


## True when a drone-sized capsule at (x, z, ground + safe offset) intersects
## any static collider (building, fence, tree trunk, vehicle wreck, ...).
func _spawn_overlaps_geometry(x: float, z: float, ground: float) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var capsule := CapsuleShape3D.new()
	capsule.radius = SPAWN_CLEAR_RADIUS
	capsule.height = 1.35
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.collide_with_areas = false
	var exclusions: Array[RID] = []
	var drone := get_node_or_null("Drone") as CollisionObject3D
	if drone != null:
		exclusions.append(drone.get_rid())
	if _launch_barrel != null and is_instance_valid(_launch_barrel):
		exclusions.append(_launch_barrel.get_rid())
	query.exclude = exclusions
	# Capsule spans roughly 0.25-1.6 m above the surface, covering the skids
	# and airframe without touching flat ground under the spawn.
	query.transform = Transform3D(Basis.IDENTITY,
			Vector3(x, ground + SPAWN_SAFE_OFFSET + 0.40, z))
	var hits := space.intersect_shape(query, 4)
	if not hits.is_empty() and OS.has_environment("DRONE_SPAWN_DEBUG"):
		var first: Dictionary = hits[0]
		var collider = first.get("collider")
		print("[SPAWN] blocked at ", Vector2(x, z), " y=", ground,
				" by ", collider.name if collider is Node else str(collider))
	return not hits.is_empty()


## True only where the water mesh actually covers the ground.  The village
## water is a 60 m ribbon around the carved channel, not a global sea plane:
## using water_level() as a world-wide height wrongly rejected the dry hall
## apron (which sits only ~0.6 m above the river surface).
func _spawn_is_wet(x: float, z: float, ground: float) -> bool:
	var water := _map_water_level()
	if water < -900.0 or ground >= water + 0.30:
		return false
	match frontline_map:
		"village":
			var river_x := -170.0 + 35.0 * sin(z * 0.008)
			return absf(x - river_x) < 36.0
		"wetlands":
			return true
		_:
			return false


func _spawn_candidate(x: float, z: float) -> Dictionary:
	var ground := _spawn_ground_height(x, z)
	var valid := not _spawn_is_wet(x, z, ground)
	if valid:
		valid = not _spawn_overlaps_geometry(x, z, ground)
	return {"pos": Vector2(x, z), "ground": ground, "valid": valid}


## Spiral search over a 3-30 m grid until a dry, collision-free cell is found.
## The selected point is always re-probed against physics, never trusted from
## the analytic height alone.
func _resolve_spawn_position(origin: Vector2) -> Dictionary:
	var best := _spawn_candidate(origin.x, origin.y)
	if best["valid"]:
		return best
	var fallback := best
	for ring in range(1, 11):
		var radius := 3.0 * float(ring)
		for i in range(16):
			var angle := TAU * float(i) / 16.0 + float(ring) * 0.37
			var px := origin.x + cos(angle) * radius
			var pz := origin.y + sin(angle) * radius
			if absf(px) > 445.0 or absf(pz) > 445.0:
				continue
			var candidate := _spawn_candidate(px, pz)
			if candidate["valid"]:
				if OS.has_environment("DRONE_SPAWN_DEBUG"):
					print("[SPAWN] nudged from ", origin, " to ",
							candidate["pos"], " radius=", radius)
				return candidate
			# Keep the highest dry candidate as a graceful fallback if every
			# scanned cell is crowded.
			if candidate["ground"] > float(fallback["ground"]):
				fallback = candidate
	return fallback


func _place_drone_over_ground() -> void:
	var d := get_node_or_null("Drone") as Drone
	var respawn := get_node_or_null("Respawn") as Node3D
	if d == null or respawn == null:
		return
	_spawn_inside_hall = false
	var is_naval_boat: bool = (Global.drone_preset == 10 \
			or (Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and Global.combat_mission == 5))
	if is_naval_boat:
		_sea_y = _naval_sea_level()
		# Start in open water next to the quay, clear of the concrete pier and
		# the breakwater, so the USV never spawns on a solid collider.
		respawn.global_position = Vector3(224.0, _sea_y + 0.05, 40.0)
		respawn.rotation = Vector3(0.0, deg_to_rad(-61.0), 0.0)
	elif Global.play_mode == Global.PlayMode.SPEED:
		var t := -0.14
		var x := 165.0 * cos(t)
		var z := 115.0 * sin(t)
		var tangent := Vector3(-165.0 * sin(t), 0.0, 115.0 * cos(t)).normalized()
		respawn.global_position = Vector3(x, respawn.global_position.y, z)
		respawn.rotation = Vector3(0.0, atan2(-tangent.x, -tangent.z), 0.0)
	elif Global.play_mode == Global.PlayMode.CHAOS:
		# Spawn the player far south of the AI battle, like a normal sortie:
		# the drone starts in FPV and has to fly in.
		respawn.global_position = Vector3(10.0, respawn.global_position.y, 194.0)
		respawn.rotation = Vector3(0.0, deg_to_rad(-5.0), 0.0)
	elif Global.play_mode == Global.PlayMode.TUTORIAL:
		# The flight-school strip lives on the open north field of the village
		# map.  A fixed spawn makes the 190 m course start at the same place on
		# every load instead of landing in a random copse of the combat sector.
		var tut_spawn := _find_dry_spot(0.0, 462.0)
		respawn.global_position = Vector3(tut_spawn.x, respawn.global_position.y,
				tut_spawn.y)
		respawn.rotation = Vector3.ZERO
	elif Global.play_mode == Global.PlayMode.TRAINING:
		if OS.has_environment("DRONE_WINDOW_DEMO"):
			# Right in front of CentralFactoryWing 1st floor window (Z=-38.9 facade)
			respawn.global_position = Vector3(2.6, respawn.global_position.y, -34.2)
			respawn.rotation = Vector3(deg_to_rad(-5.0), deg_to_rad(8.0), 0.0)
		elif OS.has_environment("DRONE_CRANE_DEMO"):
			# High vantage point overlooking the 44m yellow crane and stunt complex
			respawn.global_position = Vector3(16.0, respawn.global_position.y, 18.0)
			respawn.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(-43.0), 0.0)
		elif frontline_map != "" and not FrontlineTerrainScript.HALL_SITES.get(frontline_map, {}).is_empty():
			# Start on the apron OUTSIDE the hero hall.  The old interior spawn
			# put the drone on the hall floor/road and the first view was often
			# inside a texture; the east apron gives a clear take-off and the
			# hall is still right behind the operator.
			var site: Dictionary = FrontlineTerrainScript.HALL_SITES[frontline_map]
			var c: Vector2 = site["center"]
			var half: Vector2 = site["half"]
			var spawn: Vector2 = site.get("spawn", Vector2(c.x, c.y + half.y + 26.0))
			var syaw: float = float(site.get("spawn_yaw", PI))
			_spawn_inside_hall = false
			respawn.global_position = Vector3(spawn.x, respawn.global_position.y, spawn.y)
			respawn.rotation = Vector3(0.0, syaw, 0.0)
		elif frontline_map != "":
			respawn.global_position = Vector3(-16.0, respawn.global_position.y, 44.0)
			respawn.rotation = Vector3(0.0, deg_to_rad(-8.0), 0.0)
		else:
			# Launch position overlooking the freight train and industrial factory complex.
			respawn.global_position = Vector3(-16.0, respawn.global_position.y, 44.0)
			respawn.rotation = Vector3(0.0, deg_to_rad(-8.0), 0.0)
	else:
		# COMBAT mode: keep the operator inside the hero hall where possible.
		# The mission targets still live around the map's objective centroid, so
		# the first move is: arm, climb through the skylight or fly out of the
		# door, then search for the target block.
		var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
		if not site.is_empty():
			var c: Vector2 = site["center"]
			var half: Vector2 = site["half"]
			var spawn: Vector2 = site.get("spawn", Vector2(c.x, c.y + half.y + 26.0))
			var syaw: float = float(site.get("spawn_yaw", PI))
			_spawn_inside_hall = false
			respawn.global_position = Vector3(spawn.x, respawn.global_position.y, spawn.y)
			respawn.rotation = Vector3(0.0, syaw, 0.0)
		else:
			# Legacy valley / naval mission: launch far away from the target area.
			var spawn := _pick_combat_spawn()
			if OS.has_environment("DRONE_SPAWN_AT"):
				var parts := OS.get_environment("DRONE_SPAWN_AT").split(",")
				if parts.size() == 2:
					spawn = Vector2(float(parts[0]), float(parts[1]))
			respawn.global_position = Vector3(spawn.x, respawn.global_position.y, spawn.y)
			var to_target := Vector3(0.0, 0.0, 90.0) - Vector3(spawn.x, 0.0, spawn.y)
			respawn.rotation = Vector3(0.0, atan2(-to_target.x, -to_target.z), 0.0)
	# The hall has a collidable roof, so a vertical raycast from 400 m would put
	# the spawn on top of it.  The authored interior spawns are the only ones
	# that use the analytic floor; every exterior spawn must pass the physics
	# ray + capsule-clearance probe.
	var water_y := _map_water_level()
	if _spawn_inside_hall:
		var hall_site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
		var hall_sink := float(hall_site.get("sink", 0.0))
		_ground_y = FrontlineTerrainScript.height_at(frontline_map,
				respawn.global_position.x, respawn.global_position.z) + 0.02 - hall_sink
	elif is_naval_boat:
		_ground_y = _find_ground_y(respawn.global_position.x, respawn.global_position.z)
	else:
		# Keep the combat launch point out of dense copses/crowns, then resolve
		# it against the actual physics surface.
		var nearby_trees := _tree_positions_snapshot()
		if not nearby_trees.is_empty():
			var clear_pt := _find_clear_spawn(Vector2(respawn.global_position.x,
					respawn.global_position.z), nearby_trees, 26.0)
			var clear_ground := _find_ground_y(clear_pt.x, clear_pt.y)
			if clear_ground >= water_y + 0.35:
				respawn.global_position.x = clear_pt.x
				respawn.global_position.z = clear_pt.y
		var resolved := _resolve_spawn_position(Vector2(
				respawn.global_position.x, respawn.global_position.z))
		var resolved_pos: Vector2 = resolved["pos"]
		respawn.global_position.x = resolved_pos.x
		respawn.global_position.z = resolved_pos.y
		_ground_y = float(resolved["ground"])
		if not bool(resolved["valid"]):
			push_warning("[BigLevel] no fully clear spawn cell found near %s; using the highest dry fallback" % str(resolved["pos"]))
		# Last-resort dry search if the entire scan fell into the river.
		if _spawn_is_wet(respawn.global_position.x, respawn.global_position.z,
				_ground_y):
			var dry := _find_dry_spot(respawn.global_position.x, respawn.global_position.z)
			var dry_candidate := _spawn_candidate(dry.x, dry.y)
			respawn.global_position.x = dry.x
			respawn.global_position.z = dry.y
			_ground_y = float(dry_candidate["ground"])
	var target := respawn.global_position
	if is_naval_boat:
		if _launch_barrel != null and is_instance_valid(_launch_barrel):
			_launch_barrel.queue_free()
			_launch_barrel = null
		target.y = _sea_y + 0.05
		d.set("water_surface_y", _sea_y)
	elif OS.has_environment("DRONE_WINDOW_DEMO"):
		target.y = _ground_y + 3.8
	elif OS.has_environment("DRONE_CRANE_DEMO"):
		target.y = _ground_y + 26.0
	else:
		# Park the airframe above the apron, not on top of a 0.9 m barrel.  The
		# launch stand is retained as a low cradle and the spawn uses the
		# documented 0.3-0.5 m safe offset, with skids clear of its collider.
		var barrel_top := _setup_launch_barrel(Vector3(respawn.global_position.x,
				_ground_y, respawn.global_position.z))
		target.y = maxf(_ground_y + SPAWN_SAFE_OFFSET, _ground_y + barrel_top + 0.03)
	respawn.global_position = target
	if not _spawn_inside_hall and not is_naval_boat:
		_add_spawn_pad(Vector2(target.x, target.z), _ground_y)
	d.global_transform = respawn.global_transform
	_drone_prev_pos = d.global_position
	_drone_last_speed = 0.0
	_drone_peak_speed = 0.0
	if OS.has_environment("DRONE_SPAWN_DEBUG"):
		var tgt := Vector3(_mission_offset.x, 0.0, 90.0 + _mission_offset.z)
		print("[SPAWN] map=", frontline_map, " mode=", Global.play_mode,
				" pos=", target, " ground=", _ground_y, " water=", _map_water_level(),
				" dist_target=", Vector2(target.x, target.z).distance_to(Vector2(tgt.x, tgt.z)))
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	d.freeze = true
	d.flight_controller.reset()
	if not d.flight_controller.armed.is_connected(_on_drone_armed):
		d.flight_controller.connect("armed", Callable(self, "_on_drone_armed"))
	if not d.flight_controller.arm_failed.is_connected(_on_arm_failed):
		d.flight_controller.connect("arm_failed", Callable(self, "_on_arm_failed"))
	if not d.respawned.is_connected(_on_respawned):
		d.connect("respawned", Callable(self, "_on_respawned"))


var _launch_barrel: StaticBody3D = null
var _shot_busy := false


func _add_spawn_pad(p: Vector2, y: float) -> void:
	var pad := get_node_or_null("SpawnPad") as MeshInstance3D
	if pad == null:
		pad = MeshInstance3D.new()
		pad.name = "SpawnPad"
		var box := BoxMesh.new()
		box.size = Vector3(8.0, 0.16, 8.0)
		pad.mesh = box
		pad.material_override = FrontlineTerrainScript._pbr(
				"hall_concrete", Color(0.58, 0.58, 0.56), 0.30)
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
	pad.position = Vector3(p.x, y + 0.08, p.y)


## F2: freeze the airframe for one rendered frame, grab the viewport and put
## the drone back exactly as it was.  Screenshots no longer catch a moving
## frame, and the image is saved next to the EXE (or the project in-editor).
func _capture_player_screenshot() -> void:
	if _shot_busy:
		return
	_shot_busy = true
	var d := get_node_or_null("Drone") as Drone
	var was_frozen := true
	if d != null:
		was_frozen = d.freeze
		d.freeze = true
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var base := OS.get_executable_path().get_base_dir()
	if not OS.has_feature("template"):
		base = ProjectSettings.globalize_path("res://")
	var dir := base.path_join("screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true)
	stamp = stamp.replace(":", "-").replace(" ", "_")
	var path := dir.path_join("nebesnyi_" + stamp + ".png")
	var err := image.save_png(path)
	if err != OK:
		# A read-only EXE folder (Program Files) must not lose the shot.
		dir = ProjectSettings.globalize_path("user://screenshots")
		DirAccess.make_dir_recursive_absolute(dir)
		path = dir.path_join("nebesnyi_" + stamp + ".png")
		err = image.save_png(path)
	_set_flash("СКРІНШОТ: " + ("збережено" if err == OK else "помилка " + str(err)))
	print("[SHOT_USER] ", path, " err=", err)
	if d != null:
		d.freeze = was_frozen
	_shot_busy = false


## QA: exercise the F2 screenshot path without a keyboard and verify that the
## airframe is frozen for the capture and restored afterwards.
func _shot_test() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	var before := d.global_position if d != null else Vector3.ZERO
	var was_frozen := d.freeze if d != null else true
	await _capture_player_screenshot()
	await get_tree().process_frame
	var ok := true
	if d != null:
		if d.global_position.distance_to(before) > 0.02:
			printerr("[SHOTTEST] FAIL drone moved during capture")
			ok = false
		if d.freeze != was_frozen:
			printerr("[SHOTTEST] FAIL freeze state not restored")
			ok = false
	print("[SHOTTEST] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _setup_launch_barrel(pos: Vector3) -> float:
	if _launch_barrel != null and is_instance_valid(_launch_barrel):
		_launch_barrel.queue_free()
		_launch_barrel = null
	
	var barrel := StaticBody3D.new()
	barrel.name = "TacticalLaunchBarrel"
	# Low cradle: the airframe now spawns at the documented 0.5 m safe offset
	# instead of balancing on a chest-high drum whose collider could snag the
	# landing skids on the first arm.  Top of the cradle is ~0.32 m, leaving a
	# clear gap below the 0.5 m body origin.
	var barrel_h: float = 0.30
	var barrel_r: float = 0.36
	barrel.position = Vector3(pos.x, pos.y + barrel_h * 0.5, pos.z)
	
	# Main drum body
	var body_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = barrel_r
	cyl.bottom_radius = barrel_r
	cyl.height = barrel_h
	body_mesh.mesh = cyl
	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = Color(0.20, 0.25, 0.18) # Tactical military olive
	b_mat.roughness = 0.60
	b_mat.metallic = 0.35
	body_mesh.material_override = b_mat
	# Render layer 2: visible in chase/orbit cameras, hidden from the FPV
	# camera (cull_mask = layer 1) so the launch pad cannot fill the pilot view.
	body_mesh.layers = 2
	barrel.add_child(body_mesh)
	
	# Top launch mat (rubber pad with tactical crosshair)
	var pad := MeshInstance3D.new()
	var pad_cyl := CylinderMesh.new()
	pad_cyl.top_radius = barrel_r + 0.03
	pad_cyl.bottom_radius = barrel_r + 0.03
	pad_cyl.height = 0.025
	pad.mesh = pad_cyl
	pad.position = Vector3(0.0, barrel_h * 0.5 + 0.012, 0.0)
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.08, 0.09, 0.08)
	pad_mat.roughness = 0.85
	pad_mat.metallic = 0.05
	pad.material_override = pad_mat
	pad.layers = 2
	barrel.add_child(pad)
	
	# Outer yellow/black hazard trim ring
	var trim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = barrel_r - 0.02
	torus.outer_radius = barrel_r + 0.03
	trim.mesh = torus
	trim.position = Vector3(0.0, barrel_h * 0.5 + 0.018, 0.0)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.85, 0.65, 0.10) # Military hazard amber
	trim_mat.roughness = 0.40
	trim.material_override = trim_mat
	trim.layers = 2
	barrel.add_child(trim)
	
	# Physical collision shape
	var col := CollisionShape3D.new()
	var c_shape := CylinderShape3D.new()
	c_shape.height = barrel_h + 0.03
	c_shape.radius = barrel_r + 0.03
	col.shape = c_shape
	barrel.add_child(col)
	
	add_child(barrel)
	_launch_barrel = barrel
	return barrel_h + 0.025


func _on_drone_armed(_mode: int) -> void:
	var d := get_node_or_null("Drone") as Drone
	if d != null:
		var is_naval_boat: bool = (Global.drone_preset == 10 \
				or (Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
				and Global.combat_mission == 5))
		if is_naval_boat:
			d.freeze = false
		else:
			# For aerial quads, unfreeze smoothly so throttle lifts off from the barrel without dropping
			d.freeze = false
			d.linear_velocity = Vector3.UP * 0.1
		if d.flight_controller != null and d.flight_controller.flight_mode == FlightController.FlightMode.AUTO:
			d.flight_controller.select_flight_mode(FlightController.FlightMode.RATE)
	# Once the pilot is flying, the big keyboard cheat-sheet is just clutter.
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	if not _mission_started and not _mission_finished:
		_start_mission()


func _on_arm_failed(reason) -> void:
	var text := str(reason)
	if text == "THROTTLE_NOT_LOW" or text == "1":
		_set_flash("АРМІНГ ЗАБЛОКОВАНО: ЗНИЗЬТЕ ГАЗ ДО НУЛЯ!")
	else:
		_set_flash("АРМІНГ НЕ ВДАВСЯ: %s" % text)


func _on_respawned() -> void:
	_place_drone_over_ground()
	_payload_ammo_left = int(DroneCatalog.preset(Global.drone_preset).get(
			"payload", 0))
	_reset_fpv_payload()
	_mah = 0.0
	_speed_next = 0
	_speed_time = 0.0
	_rings_passed = 0
	for r in _training_rings:
		if is_instance_valid(r):
			r.visible = true
	_set_checkpoint_states()


## R / respawn in this arcade level also re-arms, matching the on-screen
## "respawn / rearm" hint: the pilot is back in the air with one key press.
func request_respawn() -> void:
	_respawn_and_rearm()


func _respawn_and_rearm() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	await d._on_reset()
	# Let the teleport settle before arming; arming in the same physics frame
	# as the transform assignment can fling the body.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if d.flight_controller != null and not d.flight_controller.state_armed:
		d.flight_controller.request_arm()


# ------------------------------------------------------------------ mission
func _start_mission() -> void:
	_mission_started = true
	_mission_time = 0.0
	_set_message("")
	_set_flash(_mission_title())
	if Global.special_mission > 0:
		_play_radio_callout("ОПЕРАЦІЯ «%s» — ПОЧАЛИ" \
				% Global.get_special_mission_name(Global.special_mission), true)
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and not _mission_phase_active:
		_setup_mission_phases()


func _setup_mission_phases() -> void:
	_mission_phase_active = true
	_mission_phase_hold = 0.0
	var spawn := Vector3(10.0, 0.0, 190.0)
	var recon_base := Vector3.ZERO
	match Global.combat_mission:
		1:
			recon_base = Vector3(-5.0, 0.0, 100.0)
		2:
			recon_base = Vector3(0.0, 0.0, 60.0)
		3:
			recon_base = Vector3(0.0, 0.0, 80.0)
		4:
			recon_base = Vector3(0.0, 0.0, 80.0)
		_:
			# Naval strike: no recon pass, go straight to the attack run.
			_mission_phase = 1
			_extract_point = Vector3(300.0, 0.0, -145.0)
			_extract_point.y = _find_ground_y(_extract_point.x, _extract_point.z) + 1.6
			_set_flash("ФАЗА 1/2 · УДАР: ВИЙДІТЬ НА РУБІЖ АТАКИ")
			return
	recon_base += _mission_offset
	_recon_point = recon_base
	_recon_point.y = _find_ground_y(recon_base.x, recon_base.z) + 1.6
	_extract_point = spawn
	_extract_point.y = _find_ground_y(spawn.x, spawn.z) + 1.6
	_mission_phase = 0
	_set_flash("ФАЗА 1/3 · РОЗВІДКА: ПІДЛЕТІТЬ ДО ЗОНИ Й УТРИМАЙТЕ 3 с")


func _update_mission_phases(delta: float) -> void:
	if not _mission_phase_active or _mission_finished or not _mission_started:
		return
	var drone := get_node_or_null("Drone") as Node3D
	if drone == null:
		return
	match _mission_phase:
		0:
			if drone.global_position.distance_to(_recon_point) <= 38.0:
				_mission_phase_hold += delta
				if _mission_phase_hold >= 3.0:
					_enter_strike_phase()
			else:
				_mission_phase_hold = maxf(_mission_phase_hold - delta * 2.0, 0.0)
		2:
			if drone.global_position.distance_to(_extract_point) <= 42.0:
				_mission_phase_hold += delta
				if _mission_phase_hold >= 3.0:
					_finish_mission("МІСІЮ %d/5 ВИКОНАНО — ОПЕРАТОР ПОВЕРНУВСЯ!" % Global.combat_mission)
			else:
				_mission_phase_hold = maxf(_mission_phase_hold - delta * 2.0, 0.0)


func _enter_strike_phase() -> void:
	_mission_phase = 1
	_mission_phase_hold = 0.0
	_set_flash("ФАЗА 2/3 · УДАР: ЗНИЩІТЬ УСІ ЦІЛІ")
	_play_radio_callout("РОЗВІДКУ ЗАВЕРШЕНО — УДАР, УДАР", true)


func _enter_extract_phase() -> void:
	if _mission_phase == 2:
		return
	_mission_phase = 2
	_mission_phase_hold = 0.0
	_set_flash("ФАЗА 3/3 · ВИХІД: ПОВЕРНІТЬСЯ В ЗОНУ ЕВАКУАЦІЇ")
	_play_radio_callout("ЦІЛІ УРАЖЕНО — ПОВЕРТАЙСЯ НА БАЗУ", true)


func _mission_phase_name() -> String:
	if not _mission_phase_active:
		return ""
	match _mission_phase:
		0:
			return "РОЗВІДКА %d%%" % int(clampf(_mission_phase_hold / 3.0, 0.0, 1.0) * 100.0)
		2:
			return "ВИХІД %d%%" % int(clampf(_mission_phase_hold / 3.0, 0.0, 1.0) * 100.0)
		_:
			return "УДАР"


func get_mission_phase_info() -> Dictionary:
	if not _mission_phase_active or _mission_finished:
		return {}
	match _mission_phase:
		0:
			return {"phase": 0, "pos": _recon_point, "label": "РОЗВІДКА",
					"progress": clampf(_mission_phase_hold / 3.0, 0.0, 1.0),
					"color": Color(0.35, 0.95, 0.75)}
		2:
			return {"phase": 2, "pos": _extract_point, "label": "ВИХІД",
					"progress": clampf(_mission_phase_hold / 3.0, 0.0, 1.0),
					"color": Color(0.35, 0.95, 0.75)}
		_:
			return {"phase": 1, "label": "УДАР", "color": Color(1.0, 0.62, 0.20)}


## Radio callout hook (the dedicated audio layer lives in combat/sfx.gd).
## The subtitle stays on screen longer than the radio burst so the player can
## read it even with engine noise and gunfire in the background.
func _play_radio_callout(text: String, force := false) -> void:
	if not force and _radio_cooldown > 0.0:
		return
	_radio_cooldown = 2.6
	_audio_duck_timer = 2.6
	if _radio_subtitle != null:
		_radio_subtitle.text = "РАДІО · %s" % text
		_radio_subtitle.visible = true
		_radio_subtitle_timer = 4.4
	CombatSfxScript.play_radio(self, text)


func _play_alert(kind: String, volume_db: float = -9.0) -> void:
	if _alert_player == null:
		return
	_alert_player.stream = CombatSfxScript.alert_stream(kind)
	_alert_player.volume_db = volume_db
	_alert_player.play()


func _mission_title() -> String:
	if Global.special_mission > 0:
		return "СПЕЦОПЕРАЦІЯ: %s — %s" % [
			Global.get_special_mission_name(Global.special_mission),
			_special_mission_hint(Global.special_mission)]
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			return "ШКОЛА ПІЛОТА: базовий курс оператора FPV"
		Global.PlayMode.TRAINING:
			return "ТРЕНУВАННЯ: пролетіть усі 24 кільця"
		Global.PlayMode.SPEED:
			return "ТРАСА: пройдіть 20 чекпоінтів"
		_:
			return _combat_mission_banner(Global.combat_mission)


func _special_mission_hint(mission_id: int) -> String:
	match mission_id:
		1:
			return "3 ЗОНИ РОЗВІДКИ"
		2:
			return "СУПРОВІД КОЛОНИ"
		3:
			return "ЕВАКУАЦІЯ ПІЛОТА"
		4:
			return "ДОСТАВКА ВАНТАЖУ"
		5:
			return "НІЧНИЙ УДАР ПО ЗРК"
		6:
			return "ПРОРИВ КРІЗЬ РЕБ"
		_:
			return "СПЕЦОПЕРАЦІЯ"


func _combat_mission_banner(m_id: int) -> String:
	match m_id:
		1:
			return "МІСІЯ 1/5: ЗНАЙТИ І ЗНИЩИТИ ПІХОТУ"
		2:
			return "МІСІЯ 2/5: ЗНАЙТИ І ЗНИЩИТИ ТАНК І БТР"
		3:
			return "МІСІЯ 3/5: ЗНИЩИТИ ГЕЛІКОПТЕР"
		4:
			return "МІСІЯ 4/5: ПЕРЕХОПИТИ ШАХЕД"
		_:
			return "МІСІЯ 5/5: ЗНИЩИТИ КРИМСЬКУ ГЕС"


func _finish_mission(reason: String, failed: bool = false) -> void:
	if _mission_finished:
		return
	_mission_finished = true
	_mission_failed = failed
	_show_results(reason)


func _show_results(reason: String) -> void:
	if _results == null:
		return
	_results.visible = true
	if _results_title != null:
		_results_title.text = reason
		if _mission_failed:
			_results_title.add_theme_color_override("font_color", MenuUI.DANGER)
		else:
			_results_title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	var score_mult: float = Global.get_difficulty_score_multiplier() if Global.play_mode == Global.PlayMode.COMBAT else 1.0
	var final_score := int(round(_score * score_mult))
	var mission_rec: Dictionary = {}
	if Global.play_mode == Global.PlayMode.COMBAT and not _mission_failed \
			and Global.special_mission == 0:
		# Record before drawing the debrief so the campaign line shows the
		# mission that was just completed (and the newly unlocked next one).
		mission_rec = Global.record_mission_result(
				Global.combat_mission, final_score, _mission_time, Global.difficulty)
	var best_line := ""
	var campaign_line := ""
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			best_line = "ШКОЛА ПІЛОТА    КУРС ПРОЙДЕНО (10/10 МОДУЛІВ)\nКВАЛІФІКАЦІЯ     ОПЕРАТОР УДАРНОГО FPV"
		Global.PlayMode.TRAINING:
			best_line = "КІЛЬЦЯ           %d / %d" % [_rings_passed, _rings_total]
		Global.PlayMode.SPEED:
			best_line = "ЧЕКПОІНТИ        %d / %d" % [_speed_next, _speed_checkpoints.size()]
		_:
			if Global.special_mission > 0:
				var outcome := "ПРОВАЛЕНО" if _mission_failed else "ВИКОНАНО"
				var special_title := "СПЕЦОПЕРАЦІЯ «%s»" % Global.get_special_mission_name(Global.special_mission)
				match Global.special_mission:
					1:
						best_line = "%s\nЗОНИ            %d/3 · %s" % [
							special_title, _special_index, outcome]
					2:
						best_line = "%s\nКОЛОНА          %s" % [special_title, outcome]
					3:
						best_line = "%s\nПІЛОТ           %s" % [special_title, outcome]
					4:
						best_line = "%s\nВАНТАЖ          %s" % [special_title, outcome]
					_:
						best_line = "%s\nЦІЛІ            %d/%d · %s" % [
							special_title, _mission_targets_destroyed,
							_mission_targets_total, outcome]
			else:
				best_line = "%s\nЗНИЩЕНО ЦІЛЕЙ    %d / %d" % [
					_combat_mission_banner(Global.combat_mission),
					_mission_targets_destroyed, _mission_targets_total
				]
				if not _mission_failed:
					var completed := Global.campaign_completed_count()
					var stars_total := Global.campaign_stars_total()
					if Global.campaign_is_complete():
						campaign_line = "КАМПАНІЯ        5/5 · ★ %d/15 · ЗАВЕРШЕНО\n" % stars_total
						if _results_title != null:
							_results_title.text = "СПЕЦОПЕРАЦІЮ ЗАВЕРШЕНО — КАМПАНІЮ ПРОЙДЕНО!"
					else:
						campaign_line = "КАМПАНІЯ        %d/5 · ★ %d/15 · ДАЛІ: TAC-0%d\n" % [
							completed, stars_total, Global.campaign_unlocked_mission()]
	var can_next: bool = (Global.play_mode == Global.PlayMode.COMBAT \
			and Global.special_mission == 0 and not _mission_failed \
			and Global.combat_mission < 5 and not Global.campaign_is_complete())
	if _next_mission_btn != null:
		_next_mission_btn.visible = can_next
		_next_mission_btn.text = "БРИФІНГ TAC-0%d  →" % mini(Global.combat_mission + 1, 5)
	var diff_line := "СКЛАДНІСТЬ       %s (x%.2f)\n" % [Global.get_difficulty_name(), score_mult] if Global.play_mode == Global.PlayMode.COMBAT else ""
	var award_line := ""
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		award_line = "НАГОРОДА         ★★★ ЗОЛОТИЙ СЕРТИФІКАТ ОПЕРАТОРА\n"
		if _flight_school != null:
			award_line += "МОДУЛІ           %d/%d\nПОВТОРІВ         %d\nДОВІДКА          %d\n" % [
					FlightSchool.TOTAL_MODULES, FlightSchool.TOTAL_MODULES,
					_flight_school.retries, _flight_school.help_opens]
		Global.set_tutorial_completed(true)
		if _results_title != null:
			_results_title.text = "ШКОЛУ ПІЛОТА ЗАВЕРШЕНО!"
			_results_title.add_theme_color_override("font_color", MenuUI.ACCENT)
	elif Global.special_mission > 0:
		award_line = "СТАТУС           %s\n" % ("ОПЕРАЦІЮ ПРОВАЛЕНО" if _mission_failed
				else "ОПЕРАЦІЮ ВИКОНАНО · КАМПАНІЯ БЕЗ ЗМІН")
	elif Global.play_mode == Global.PlayMode.COMBAT and not _mission_failed:
		var stars: int = int(mission_rec.get("stars", 1))
		var stars_str := ""
		for s in range(stars):
			stars_str += "★"
		match stars:
			3: award_line = "НАГОРОДА         %s ЗОЛОТИЙ ХРЕСТ (АС)\n" % stars_str
			2: award_line = "НАГОРОДА         %s СРІБНА ВІДЗНАКА\n" % stars_str
			_: award_line = "НАГОРОДА         %s БРОНЗОВА ВІДЗНАКА\n" % stars_str
	_results_stats.text = "%s\n%s%s%sЧАС ПОЛЬОТУ      %s\nБОЙОВІ ОЧКИ      %d" % [
			best_line, diff_line, award_line, campaign_line, _format_time(_mission_time), final_score]
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if can_next and _next_mission_btn != null:
		_next_mission_btn.grab_focus()


func _on_next_mission_pressed() -> void:
	get_tree().paused = false
	Global.combat_mission = clampi(Global.combat_mission + 1, 1, 5)
	Global.chain_briefing_pending = true
	_show_loading_card(Global.combat_mission)
	await get_tree().create_timer(0.30).timeout
	get_tree().reload_current_scene()


func _on_retry_pressed() -> void:
	get_tree().paused = false
	_show_loading_card(Global.combat_mission)
	await get_tree().create_timer(0.30).timeout
	get_tree().reload_current_scene()


func _show_loading_card(mission_id: int) -> void:
	if get_tree().root.get_node_or_null("GlobalLoadingOverlay") != null:
		return
	var map_name := str(Global.menu_settings.get("selected_map", "steppe"))
	var overlay: Dictionary = LoadingScreen.build(Global.PlayMode.COMBAT,
			mission_id, map_name, Global.get_difficulty_name(), true)
	var layer := overlay["layer"] as CanvasLayer
	if layer == null:
		return
	get_tree().root.add_child(layer)
	var bar := overlay["bar"] as ProgressBar
	if bar != null:
		bar.value = 94.0


func _on_menu_pressed() -> void:
	get_tree().paused = false
	# Phones must return to the finger-sized tactical menu, never the desktop
	# video home screen.  This is the results-screen / mission-menu path; the
	# pause overlay has its own mobile-aware exit.
	var target := MOBILE_MENU if MenuUI.is_mobile_ui() else MAIN_MENU
	get_tree().change_scene_to_file(target)


# ------------------------------------------------------------------ triggers
func _make_ring(position: Vector3, radius: float, color: Color,
		yaw: float = 0.0) -> Area3D:
	var area := Area3D.new()
	area.position = position
	area.rotation.y = yaw
	area.collision_layer = 0
	area.collision_mask = 1
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius + 0.8
	col.shape = sphere
	area.add_child(col)
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.9
	torus.rings = 28
	torus.ring_segments = 8
	mesh.mesh = torus
	# TorusMesh is authored flat in XZ (a doughnut lying on the ground).  A
	# 90-degree X rotation makes it a vertical gate; the area yaw then points
	# its normal along the course tangent.
	mesh.rotation.x = PI * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	mesh.material_override = material
	# Holographic course rings must not drop hard shadows across the track.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mesh)
	_triggers.add_child(area)
	return area


func _training_ring_position(i: int) -> Vector3:
	var t := float(i % 24) / 24.0
	var angle := t * TAU
	# Keep every ring inside the playable 1 km terrain.  The old formula reached
	# 900 m, so most gates floated beyond the map edge.
	var radius := 120.0 + fmod(float(i % 24) * 37.0, 300.0)
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	var ground := _find_ground_y(x, z)
	var y := ground + 18.0 + fmod(float(i % 24) * 11.0, 52.0)
	return Vector3(x, y, z)


func _spawn_training_rings() -> void:
	_rings_total = 0
	_training_rings.clear()
	for i in range(24):
		var pos := _training_ring_position(i)
		var next := _training_ring_position((i + 1) % 24)
		var tangent := next - pos
		tangent.y = 0.0
		if tangent.length_squared() < 0.001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var yaw := atan2(tangent.x, tangent.z)
		var ring := _make_ring(pos, 6.5, Color(0.15, 0.9, 0.75), yaw)
		ring.body_entered.connect(_on_ring_entered.bind(ring))
		_training_rings.append(ring)
		_rings_total += 1


func _on_ring_entered(body: Node3D, ring: Area3D) -> void:
	if not (body is Drone) or not ring.visible:
		return
	_rings_passed += 1
	_score += 50
	ring.visible = false
	_set_flash("Ворота %d/%d" % [_rings_passed, _rings_total])
	if _rings_passed >= _rings_total:
		_finish_mission("ТРЕНУВАННЯ ЗАВЕРШЕНО")


func _spawn_speed_course() -> void:
	_speed_checkpoints.clear()
	var rx := 165.0
	var ry := 115.0
	var count := 20
	for i in range(count):
		var t := float(i) / float(count) * TAU
		var x := cos(t) * rx
		var z := sin(t) * ry
		var ground := _find_ground_y(x, z)
		var arch := Area3D.new()
		var tangent := Vector3(-rx * sin(t), 0.0, ry * cos(t)).normalized()
		arch.position = Vector3(x, ground + 6.5, z)
		arch.rotation = Vector3(0.0, atan2(-tangent.x, -tangent.z), 0.0)
		arch.collision_layer = 0
		arch.collision_mask = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(14.0, 12.0, 14.0)
		shape.shape = box
		arch.add_child(shape)
		var visual := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 5.2
		ring.outer_radius = 6.1
		ring.rings = 24
		ring.ring_segments = 8
		visual.mesh = ring
		# TorusMesh lies flat by default; stand it up so the hole faces the
		# racing line and the checkpoint reads as a gate, not a ground ring.
		visual.rotation.x = PI * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.55, 0.1)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.55, 0.1)
		material.emission_energy_multiplier = 2.0
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arch.add_child(visual)
		_triggers.add_child(arch)
		_speed_checkpoints.append(arch)
		arch.body_entered.connect(_on_checkpoint_entered.bind(i))
	_set_checkpoint_states()


func _checkpoint_visual(cp: Area3D) -> MeshInstance3D:
	for child in cp.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _set_checkpoint_states() -> void:
	for i in range(_speed_checkpoints.size()):
		var visual := _checkpoint_visual(_speed_checkpoints[i])
		if visual != null and visual.material_override is StandardMaterial3D:
			var material := visual.material_override as StandardMaterial3D
			material.emission = Color(0.15, 0.9, 0.4) if i == _speed_next else Color(0.35, 0.35, 0.4)
			material.albedo_color = material.emission


func _on_checkpoint_entered(body: Node3D, index: int) -> void:
	if not (body is Drone) or _mission_finished:
		return
	if index != _speed_next:
		return
	_speed_next += 1
	_score += 100
	_set_checkpoint_states()
	_set_flash("КП %d/%d" % [_speed_next, _speed_checkpoints.size()])
	if _speed_next >= _speed_checkpoints.size():
		_finish_mission("ФІНІШ ТРАСИ")


# ------------------------------------------------------------------ vehicles
func _add_vehicle(kind: int, waypoints: Array, speed: float, hostile: bool,
		track: bool, height: float = 0.0) -> Vehicle:
	if _offset_targets and not waypoints.is_empty():
		var shifted: Array = []
		for wp in waypoints:
			var v: Vector3 = (wp as Vector3) + _mission_offset
			# Never route armour through a lake: the offset is random and can
			# push a waypoint into the wetlands channels.
			if not frontline_map.is_empty() \
					and FrontlineTerrainScript.height_at(frontline_map, v.x, v.z) \
					< _map_water_level() + 0.4:
				var dry := _find_dry_spot(v.x, v.z)
				v.x = dry.x
				v.z = dry.y
			shifted.append(v)
		waypoints = shifted
	var vehicle := VEHICLE.new()
	vehicle.kind = kind
	vehicle.move_speed = speed
	vehicle.hostile = hostile
	vehicle.track_drone = track
	if kind == Vehicle.Kind.TANK:
		# Slow armour weaves across the field, then halts to mask itself.
		vehicle.meander_amplitude = 0.16
		vehicle.halt_interval = 16.0
		vehicle.halt_duration = 4.5
	elif kind == Vehicle.Kind.APC or kind == Vehicle.Kind.BMP:
		# Light armour is fast and agile: it jinks much more than a tank.
		vehicle.meander_amplitude = 0.22
	if height > 0.0:
		vehicle.cruise_height = height
	add_child(vehicle)
	var first: Vector3 = waypoints[0]
	var gy := _find_ground_y(first.x, first.z)
	var y := gy + (height if height > 0.0 else 0.1)
	vehicle.global_position = Vector3(first.x, y, first.z)
	vehicle.set_waypoints(waypoints)
	vehicle.destroyed.connect(_on_vehicle_destroyed.bind(kind))
	_vehicles.append(vehicle)
	return vehicle


func _on_vehicle_destroyed(points: int, kind: int) -> void:
	_kills[kind] = int(_kills.get(kind, 0)) + 1
	_score += points
	if Global.play_mode == Global.PlayMode.COMBAT:
		_mission_targets_destroyed += 1
		var combat := get_node_or_null("CombatSystem")
		if combat != null and combat.has_method("add_bonus_score"):
			combat.call("add_bonus_score", points, "%s ЗНИЩЕНО (%d/%d)" % [
				_kind_name(kind), _mission_targets_destroyed, _mission_targets_total
			])
		_set_flash("%s ЗНИЩЕНО! (%d/%d)" % [
			_kind_name(kind), _mission_targets_destroyed, _mission_targets_total
		])
		_play_radio_callout("ЦІЛЬ УРАЖЕНО — %s" % _kind_name(kind))
		_check_combat_mission_complete()
	else:
		_set_flash("%s +%d" % [_kind_name(kind), points])


func _add_mission_infantry(pos: Vector3, patrol_axis: Vector3, patrol_dist: float,
		patrol_spd: float, count_as_primary: bool = true) -> Node3D:
	if not count_as_primary \
			and QualityManager.get_active_level() == QualityManager.Level.LOW:
		# LOW keeps every mission-critical soldier but skips the decorative
		# patrols.  This removes dozens of skinned rigs and their per-frame AI.
		return null
	if _offset_targets:
		pos += _mission_offset
		if not frontline_map.is_empty() \
				and FrontlineTerrainScript.height_at(frontline_map, pos.x, pos.z) \
				< _map_water_level() + 0.4:
			var dry := _find_dry_spot(pos.x, pos.z)
			pos.x = dry.x
			pos.z = dry.y
	var unit := EnemyRiflemanScript.new()
	unit.name = "MissionInfantry_%d" % _infantry_units.size()
	add_child(unit)
	var gy := _find_ground_y(pos.x, pos.z)
	var ground_pos := Vector3(pos.x, gy, pos.z)
	unit.global_position = ground_pos
	var dir := patrol_axis.normalized() if patrol_axis.length_squared() > 0.001 else Vector3.FORWARD
	unit.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	unit.set_patrol(ground_pos, dir, patrol_dist, patrol_spd)
	_infantry_units.append(unit)
	if count_as_primary:
		_mission_targets_total += 1
	unit.destroyed.connect(_on_infantry_unit_destroyed.bind(count_as_primary))
	return unit


func _on_infantry_unit_destroyed(points: int, is_primary: bool) -> void:
	_kills["INF"] = int(_kills.get("INF", 0)) + 1
	_score += points
	if is_primary:
		_mission_targets_destroyed += 1
	var combat := get_node_or_null("CombatSystem")
	if combat != null and combat.has_method("add_bonus_score"):
		combat.call("add_bonus_score", points, "ПІХОТИНЦЯ ЗНИЩЕНО (%d/%d)" % [
			_mission_targets_destroyed, _mission_targets_total
		])
	_set_flash("ПІХОТИНЦЯ ЗНИЩЕНО! (%d/%d)" % [
		_mission_targets_destroyed, _mission_targets_total
	])
	if is_primary:
		_play_radio_callout("ЦІЛЬ УРАЖЕНО — ПІХОТА")
	_check_combat_mission_complete()


func _on_naval_warship_destroyed(points: int) -> void:
	_kills["WARSHIP"] = int(_kills.get("WARSHIP", 0)) + 1
	_score += points
	_mission_targets_destroyed += 1
	var combat := get_node_or_null("CombatSystem")
	if combat != null and combat.has_method("add_bonus_score"):
		combat.call("add_bonus_score", points, "КОРВЕТ ЗНИЩЕНО (1/1)")
	_set_flash("КОРВЕТ «СЕРГІЙ КОТОВ» ЗНИЩЕНО!  +1000")
	_play_radio_callout("ЦІЛЬ УРАЖЕНО — КОРВЕТ", true)
	_check_combat_mission_complete()


func _on_hydro_plant_destroyed(points: int) -> void:
	_kills["HYDRO_PLANT"] = int(_kills.get("HYDRO_PLANT", 0)) + 1
	_score += points
	_mission_targets_destroyed += 1
	var combat := get_node_or_null("CombatSystem")
	if combat != null and combat.has_method("add_bonus_score"):
		combat.call("add_bonus_score", points, "ГІДРОЕЛЕКТРОСТАНЦІЮ ЗНИЩЕНО (1/1)")
	_set_flash("«ГІДРОЕЛЕКТРОСТАНЦІЮ ЗНИЩЕНО!» ТАРАН МАГУРИ-Х УСПІШНИЙ!  +2500")
	_play_radio_callout("ЦІЛЬ УРАЖЕНО — ГЕС", true)
	_check_combat_mission_complete()


func _check_combat_mission_complete() -> void:
	if _mission_finished or _mission_targets_total <= 0:
		return
	if _mission_targets_destroyed >= _mission_targets_total:
		# All primary targets are down.  The mission is not over until the
		# operator reaches the extraction zone (phase 3/3).
		if _mission_phase_active:
			_enter_extract_phase()
		else:
			if Global.special_mission > 0:
				_enter_special_extraction()
				return
			var msg := "МІСІЮ %d/5 ВИКОНАНО!" % Global.combat_mission
			if Global.combat_mission >= 5:
				msg = "СПЕЦОПЕРАЦІЮ ПОВНІСТЮ ВИКОНАНО! КРИМСЬКУ ГЕС ЗНИЩЕНО!"
			await get_tree().create_timer(1.2).timeout
			_finish_mission(msg, false)


func _make_weather_particles(color: Color, direction: Vector3, speed: float,
		size: float, extents: Vector3, amount: int) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = 3.0
	particles.local_coords = true
	particles.visibility_aabb = AABB(-extents * 2.0, extents * 4.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = extents
	process.direction = direction
	process.spread = 8.0
	process.initial_velocity_min = speed * 0.8
	process.initial_velocity_max = speed * 1.2
	process.gravity = Vector3.ZERO
	process.scale_min = size
	process.scale_max = size * 1.6
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.06, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = material
	particles.draw_pass_1 = mesh
	return particles


func _setup_weather() -> void:
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam == null:
		return
	_rain = _make_weather_particles(Color(0.75, 0.82, 0.95, 0.5),
			Vector3(0.05, -1.0, 0.0), 22.0, 1.0, Vector3(30.0, 18.0, 30.0), 900)
	_dust = _make_weather_particles(Color(0.72, 0.60, 0.40, 0.35),
			Vector3(1.0, 0.06, 0.2), 5.0, 3.0, Vector3(34.0, 12.0, 34.0), 350)
	cam.add_child(_rain)
	cam.add_child(_dust)
	_weather = int(GameSettings.hud_config.get("weather", 0))
	_lightning_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if _lightning_light == null:
		for ch in get_children():
			if ch is DirectionalLight3D:
				_lightning_light = ch
				break
	if _lightning_light != null:
		_sun_light_energy_default = _lightning_light.light_energy

	var weather_env := OS.get_environment("DRONE_WEATHER").to_lower()
	if weather_env == "rain":
		_weather = 1
	elif weather_env == "storm" or weather_env == "thunder":
		_weather = 2
	elif weather_env == "night":
		_weather = 3
	elif weather_env == "dust":
		_weather = 4

	var vision_env := OS.get_environment("DRONE_VISION").to_lower()
	if vision_env == "nvg":
		_vision_mode = VisionMode.NVG
	elif vision_env == "flir" or vision_env == "white_hot":
		_vision_mode = VisionMode.FLIR_WHITE_HOT
	elif vision_env == "black_hot":
		_vision_mode = VisionMode.FLIR_BLACK_HOT
	_apply_weather()
	if Global.special_mission == 5:
		# Night strike: force the night palette even if the player's last
		# weather preference was clear/rain.
		_weather = 3
		_apply_weather()


func _apply_weather() -> void:
	if _rain != null:
		_rain.emitting = (_weather == 1 or _weather == 2)
	if _dust != null:
		_dust.emitting = (_weather == 4)
	if _lightning_light != null:
		match _weather:
			1:
				_lightning_light.light_energy = _sun_light_energy_default * 0.70
			2:
				_lightning_light.light_energy = _sun_light_energy_default * 0.35
				_thunder_timer = randf_range(3.0, 7.0)
			3:
				_lightning_light.light_energy = 0.05
			4:
				_lightning_light.light_energy = _sun_light_energy_default * 0.80
			_:
				_lightning_light.light_energy = _sun_light_energy_default
	match _weather:
		1:
			_set_flash(LocScript.t("WEATHER_RAIN"))
		2:
			_set_flash(LocScript.t("WEATHER_STORM"))
		3:
			_set_flash(LocScript.t("WEATHER_NIGHT"))
		4:
			_set_flash(LocScript.t("WEATHER_DUST"))
		_:
			_set_flash(LocScript.t("WEATHER_CLEAR"))


func trigger_lightning() -> void:
	_lightning_flash_timer = 0.40
	if _lightning_light != null:
		_lightning_light.light_energy = _sun_light_energy_default * 3.5
	var d_node := get_node_or_null("Drone") as Node3D
	var thunder_pos := d_node.global_position if d_node != null else Vector3.ZERO
	CombatSfx.play_thunder(self, thunder_pos, 4.0)

func _setup_vision_overlay() -> void:
	if _vision_overlay == null:
		var canvas := CanvasLayer.new()
		canvas.layer = 10
		add_child(canvas)
		_vision_overlay = ColorRect.new()
		_vision_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vision_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := load("res://shaders/tactical_vision.gdshader") as Shader
		if shader != null:
			_vision_material = ShaderMaterial.new()
			_vision_material.shader = shader
			_vision_overlay.material = _vision_material
		canvas.add_child(_vision_overlay)
	_apply_vision_mode()


func _apply_vision_mode() -> void:
	if _vision_material != null:
		_vision_material.set_shader_parameter("vision_mode", int(_vision_mode))
	if _vision_overlay != null:
		_vision_overlay.visible = (_vision_mode != VisionMode.NORMAL)
	match _vision_mode:
		VisionMode.NVG:
			_set_flash(LocScript.t("VISION_NVG"))
		VisionMode.FLIR_WHITE_HOT:
			_set_flash(LocScript.t("VISION_WHITE_HOT"))
		VisionMode.FLIR_BLACK_HOT:
			_set_flash(LocScript.t("VISION_BLACK_HOT"))
		_:
			_set_flash(LocScript.t("VISION_NORMAL"))


func cycle_vision_mode() -> void:
	_vision_mode = int((int(_vision_mode) + 1) % 4) as VisionMode
	_apply_vision_mode()


func _apply_osd_colors() -> void:
	var cols: Dictionary = LocScript.get_palette_colors()
	var txt_col: Color = cols.get("text", Color.WHITE)
	var prim_col: Color = cols.get("primary", Color.WHITE)
	var acc_col: Color = cols.get("accent", Color.GREEN)

	if _hud_label != null:
		_hud_label.add_theme_color_override("font_color", txt_col)
	if _telem_left != null:
		_telem_left.add_theme_color_override("font_color", txt_col)
	if _telem_right != null:
		_telem_right.add_theme_color_override("font_color", txt_col)
	if _nav_marker != null:
		_nav_marker.add_theme_color_override("font_color", prim_col)
	if _stick_overlay != null and _stick_overlay.has_method("set_accent_color"):
		_stick_overlay.call("set_accent_color", acc_col)


func _setup_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Audio.reset_mission_buses()
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = CombatSfxScript.wind_stream()
	_wind_player.volume_db = -46.0
	_wind_player.bus = "Wind"
	add_child(_wind_player)
	_wind_player.play()
	_beeper_player = AudioStreamPlayer.new()
	_beeper_player.stream = CombatSfxScript.beeper_stream()
	_beeper_player.volume_db = -14.0
	_beeper_player.bus = "Warning"
	add_child(_beeper_player)
	_alert_player = AudioStreamPlayer.new()
	_alert_player.volume_db = -9.0
	_alert_player.bus = "Warning"
	add_child(_alert_player)
	_ew_crackle_player = AudioStreamPlayer.new()
	_ew_crackle_player.stream = CombatSfxScript.ew_crackle_stream()
	_ew_crackle_player.volume_db = -60.0
	_ew_crackle_player.bus = "Warning"
	add_child(_ew_crackle_player)
	_ew_crackle_player.play()
	if Global.play_mode == Global.PlayMode.COMBAT or Global.play_mode == Global.PlayMode.CHAOS:
		_combat_music = AudioStreamPlayer.new()
		_combat_music.stream = CombatSfxScript.combat_music_stream()
		_combat_music.volume_db = -27.0
		_combat_music.bus = "Music"
		add_child(_combat_music)
		_combat_music.play()


## Dynamic combat mix: calm recon bed, a tighter strike layer when the drone is
## in the target area, and a quieter extract bed.  The music stays on one
## procedural stream, but its level follows the mission phase and the nearest
## threat, so contact feels different from a quiet transit.
func _update_audio_mix(delta: float) -> void:
	_audio_mix_tick -= delta
	if _audio_mix_tick > 0.0:
		return
	_audio_mix_tick = 0.45
	if _combat_music == null:
		return
	var target_db := -26.0
	if Global.play_mode == Global.PlayMode.COMBAT:
		match _mission_phase:
			0:
				target_db = -30.0
			2:
				target_db = -24.0
			_:
				target_db = -21.0
	elif Global.play_mode == Global.PlayMode.CHAOS:
		target_db = -23.0
	var drone := get_node_or_null("Drone") as Node3D
	if drone != null:
		var nearest := 1e9
		for unit in get_tree().get_nodes_in_group("combat_target"):
			if is_instance_valid(unit) and unit.get("is_destroyed") != true:
				nearest = minf(nearest, drone.global_position.distance_to(
						(unit as Node3D).global_position))
		if nearest < 130.0:
			target_db += 2.5
		if nearest < 65.0:
			target_db += 1.5
	_combat_music.volume_db = lerpf(_combat_music.volume_db,
			clampf(target_db, -30.0, -16.0), 0.16)
	if _wind_player != null and drone != null:
		# Wind level is driven at OSD rate by _update_telemetry(), which also
		# knows the current gust vector.  Keep a gentle fallback only.
		if _telem_left == null:
			var speed := 0.0
			if drone is RigidBody3D:
				speed = (drone as RigidBody3D).linear_velocity.length()
			_wind_player.volume_db = lerpf(_wind_player.volume_db,
					clampf(-46.0 + speed * 0.18, -46.0, -30.0), 0.10)


func _update_audio_priority(delta: float) -> void:
	_radio_cooldown = maxf(_radio_cooldown - delta, 0.0)
	_audio_duck_timer = maxf(_audio_duck_timer - delta, 0.0)
	if _radio_subtitle_timer > 0.0:
		_radio_subtitle_timer = maxf(_radio_subtitle_timer - delta, 0.0)
		if _radio_subtitle_timer <= 0.0 and _radio_subtitle != null:
			_radio_subtitle.visible = false

	var danger := _threat_timer > 0.0
	var link_bad := _reb != null and _reb.limits_enabled \
			and (_reb.link_quality < 0.25 or _reb.in_ew > 0.12)
	var targets := {
		"Engine": -2.0 if danger else 0.0,
		"Wind": -5.0 if danger else 0.0,
		"Combat": -4.0 if danger else 0.0,
		"Music": -9.0 if danger else 0.0,
	}
	if link_bad:
		targets["Music"] = -10.0
		targets["Wind"] = -5.0
	if _audio_duck_timer > 0.0:
		# Radio has the highest priority: engines, wind and gunfire step back.
		targets = {"Engine": -8.0, "Wind": -7.0, "Combat": -11.0, "Music": -15.0}
	var blend := clampf(delta * 2.6, 0.0, 1.0)
	for bus_name in targets.keys():
		var idx := AudioServer.get_bus_index(String(bus_name))
		if idx >= 0:
			var current := AudioServer.get_bus_volume_db(idx)
			AudioServer.set_bus_volume_db(idx, lerpf(current, float(targets[bus_name]), blend))

	if _ew_crackle_player != null:
		var ew := 0.0
		if _reb != null and _reb.limits_enabled and _reb.reb_zones_enabled:
			ew = clampf(_reb.in_ew, 0.0, 1.0)
		var crackle_target := -60.0 + ew * 42.0
		if _audio_duck_timer > 0.0:
			crackle_target -= 14.0
		_ew_crackle_player.volume_db = lerpf(_ew_crackle_player.volume_db,
				crackle_target, clampf(delta * 5.0, 0.0, 1.0))


func _on_audio_resumed() -> void:
	_audio_mix_tick = 0.0
	_audio_duck_timer = 0.0
	if _combat_music != null and not _combat_music.playing:
		_combat_music.play()
	_update_audio_mix(1.0)
	_update_audio_priority(1.0)


func _kind_name(kind: int) -> String:
	match kind:
		Vehicle.Kind.TANK:
			return "ТАНК"
		Vehicle.Kind.APC:
			return "БТР"
		Vehicle.Kind.TRUCK:
			return "ВАНТАЖІВКА"
		Vehicle.Kind.BMP:
			return "БМП"
		Vehicle.Kind.SAM:
			return "ЗРК"
		Vehicle.Kind.HELI:
			return "ГЕЛІКОПТЕР"
		Vehicle.Kind.SHAHED:
			return "ШАХЕД"
	return "ЦІЛЬ"


func _loop_waypoints(cx: float, cz: float, radius: float, count: int,
		phase := 0.0) -> Array:
	var points := []
	for i in range(count):
		var t := phase + float(i) / float(count) * TAU
		points.append(Vector3(cx + cos(t) * radius, 0.0, cz + sin(t) * radius))
	return points


func _spawn_vehicles() -> void:
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	# civilian traffic circling the start area
	for i in range(2 if lowspec else 6):
		var kind: int = [Vehicle.Kind.TRUCK, Vehicle.Kind.APC, Vehicle.Kind.TANK][i % 3]
		var points := _loop_waypoints(0.0, 0.0, 150.0 + i * 45.0, 5,
				float(i) * 0.9)
		_add_vehicle(kind, points, 8.0 + i, false, false)
	# a few extras: BMPs and two sightseeing helicopters
	for i in range(1 if lowspec else 2):
		_add_vehicle(Vehicle.Kind.BMP,
				_loop_waypoints(0.0, 0.0, 320.0 + i * 60.0, 6, 0.5 + float(i)),
				7.0, false, false)
	if not lowspec:
		for i in range(2):
			_add_vehicle(Vehicle.Kind.HELI,
					_loop_waypoints(0.0, 0.0, 260.0 + i * 80.0, 6, float(i) * 1.5),
					11.0, false, false, 55.0 + i * 15.0)


## Two-sided AI battle on the Industrial map.  No player-side targets exist:
## the drone is an observer / optional participant in an ongoing firefight.
func _spawn_chaos_battle() -> void:
	_offset_targets = false
	var cb = load("res://combat/chaos_battle.gd")
	if cb == null:
		push_error("[BigLevel] chaos_battle.gd missing")
		return
	var battle = cb.new()
	battle.name = "ChaosBattle"
	add_child(battle)
	if battle.has_method("setup"):
		battle.call("setup", self, _ground_y)


## Standalone special-operation spawner.  Campaign missions still go through
## _spawn_combat_mission(); these sorties reuse the same combat sandbox but
## have their own objectives and never write campaign records.
func _spawn_special_or_campaign() -> void:
	if Global.special_mission > 0:
		_spawn_special_mission(Global.special_mission)
	else:
		_spawn_combat_mission(Global.combat_mission)


func _special_ground_point(x: float, z: float) -> Vector3:
	var px := x
	var pz := z
	if not frontline_map.is_empty():
		var gy := FrontlineTerrainScript.height_at(frontline_map, px, pz)
		if gy < _map_water_level() + 0.4:
			var dry := _find_dry_spot(px, pz)
			px = dry.x
			pz = dry.y
			gy = FrontlineTerrainScript.height_at(frontline_map, px, pz)
		return Vector3(px, gy + 0.05, pz)
	return Vector3(px, _find_ground_y(px, pz) + 0.05, pz)


func _spawn_special_beacon(pos: Vector3, text: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "SpecialBeacon_%d" % _special_beacons.size()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 4.5
	torus.outer_radius = 5.2
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	ring.material_override = mat
	ring.position.y = 0.12
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.35
	cylinder.bottom_radius = 0.35
	cylinder.height = 18.0
	beam.mesh = cylinder
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.16)
	beam_mat.emission_enabled = true
	beam_mat.emission = color
	beam_mat.emission_energy_multiplier = 0.8
	beam.material_override = beam_mat
	beam.position.y = 9.0
	root.add_child(beam)
	var label := Label3D.new()
	label.text = text
	label.font_size = 42
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.012
	label.position.y = 4.2
	root.add_child(label)
	add_child(root)
	root.global_position = pos
	_special_beacons.append(root)
	return root


func _spawn_special_pickup_marker(pos: Vector3, pilot: bool) -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	if pilot:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.22
		capsule.height = 0.78
		mesh_instance.mesh = capsule
		mesh_instance.position.y = 0.40
		material.albedo_color = Color(0.92, 0.48, 0.18)
		material.roughness = 0.55
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.62, 0.9)
		mesh_instance.mesh = box
		mesh_instance.position.y = 0.32
		material.albedo_color = Color(0.32, 0.38, 0.22)
		material.roughness = 0.8
	mesh_instance.material_override = material
	root.add_child(mesh_instance)
	if not pilot:
		# Simple dark straps make the crate read as cargo rather than a cube.
		for offset_value in [-0.28, 0.28]:
			var offset: float = offset_value
			var strap := MeshInstance3D.new()
			var strap_mesh := BoxMesh.new()
			strap_mesh.size = Vector3(0.94, 0.05, 0.12)
			strap.mesh = strap_mesh
			strap.position = Vector3(0.0, 0.64, offset)
			var strap_mat := StandardMaterial3D.new()
			strap_mat.albedo_color = Color(0.08, 0.07, 0.06)
			strap.material_override = strap_mat
			root.add_child(strap)
	add_child(root)
	root.global_position = pos
	return root


func _add_special_zone(pos: Vector3, radius: float, hold: float, label: String) -> void:
	var ground := _special_ground_point(pos.x, pos.z)
	var beacon := _spawn_special_beacon(ground, label, Color(0.35, 0.95, 0.75))
	_special_zones.append({
		"pos": ground, "radius": radius, "hold": hold,
		"label": label, "beacon": beacon,
	})


func _spawn_special_guards(spots: Array) -> void:
	for spot in spots:
		var p: Vector3 = spot
		_add_mission_infantry(p, Vector3(1.0, 0.0, 0.4), 13.0, 1.7, false)


func _spawn_special_strike(ew_breach: bool) -> void:
	var sam_route := [
		Vector3(-60.0, 0.0, 10.0), Vector3(60.0, 0.0, 10.0),
		Vector3(60.0, 0.0, -70.0), Vector3(-60.0, 0.0, -70.0),
	]
	_add_vehicle(Vehicle.Kind.SAM, sam_route, 4.5, true, true)
	_mission_targets_total += 1
	var bmp_route := [
		Vector3(85.0, 0.0, 30.0), Vector3(-85.0, 0.0, 30.0),
		Vector3(-85.0, 0.0, -35.0), Vector3(85.0, 0.0, -35.0),
	]
	_add_vehicle(Vehicle.Kind.BMP, bmp_route, 8.8, true, true)
	_mission_targets_total += 1
	_spawn_special_guards([
		Vector3(-25.0, 0.0, 65.0), Vector3(28.0, 0.0, 45.0),
	])
	if ew_breach:
		_spawn_special_guards([Vector3(0.0, 0.0, -45.0)])


func _setup_special_escort() -> void:
	var route: Array[Vector3] = [
		_special_ground_point(-120.0, 120.0),
		_special_ground_point(-20.0, 40.0),
		_special_ground_point(90.0, -30.0),
		_special_ground_point(160.0, -110.0),
	]
	var vehicle := VEHICLE.new()
	vehicle.kind = Vehicle.Kind.TRUCK
	vehicle.hostile = false
	vehicle.track_drone = false
	vehicle.move_speed = 8.0
	add_child(vehicle)
	vehicle.global_position = route[0] + Vector3.UP * 0.2
	vehicle.set_waypoints(route)
	vehicle.remove_from_group("combat_target")
	vehicle.destroyed.connect(_on_escort_destroyed)
	_special_convoy = vehicle
	_special_convoy_start = route[0]
	_special_convoy_dest = route[route.size() - 1]
	_spawn_special_guards([
		Vector3(-60.0, 0.0, 85.0), Vector3(40.0, 0.0, 5.0),
		Vector3(110.0, 0.0, -55.0),
	])


func _spawn_special_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	_special_index = 0
	_special_hold = 0.0
	_special_zones.clear()
	_special_beacons.clear()
	_special_convoy = null
	_special_convoy_far_timer = 0.0
	_special_convoy_warned = false
	_special_extract_active = false
	_special_extract_hold = 0.0
	_special_extract_point = _special_ground_point(10.0, 185.0)
	_special_extract_beacon = null
	_special_pickup_prop = null
	_offset_targets = false

	match mission_id:
		1:
			_add_special_zone(Vector3(-55.0, 0.0, 115.0), 34.0, 2.0, "РОЗВІДКА 1/3")
			_add_special_zone(Vector3(45.0, 0.0, 35.0), 34.0, 2.0, "РОЗВІДКА 2/3")
			_add_special_zone(Vector3(-35.0, 0.0, -70.0), 34.0, 2.0, "РОЗВІДКА 3/3")
			_spawn_special_guards([
				Vector3(-20.0, 0.0, 95.0), Vector3(35.0, 0.0, 20.0),
				Vector3(-20.0, 0.0, -55.0),
			])
		2:
			_setup_special_escort()
		3:
			_add_special_zone(Vector3(75.0, 0.0, -55.0), 30.0, 3.0, "ЕВАКУАЦІЯ · ПІЛОТ")
			_add_special_zone(Vector3(10.0, 0.0, 185.0), 42.0, 3.0, "ЕВАКУАЦІЯ · БАЗА")
			_special_pickup_prop = _spawn_special_pickup_marker(
					_special_zones[0]["pos"], true)
			_spawn_special_guards([
				Vector3(30.0, 0.0, -30.0), Vector3(100.0, 0.0, -75.0),
			])
		4:
			_add_special_zone(Vector3(-75.0, 0.0, 50.0), 30.0, 2.0, "ВАНТАЖ · ЗАБРАТИ")
			_add_special_zone(Vector3(75.0, 0.0, -80.0), 32.0, 2.0, "ВАНТАЖ · ДОСТАВИТИ")
			_special_pickup_prop = _spawn_special_pickup_marker(
					_special_zones[0]["pos"], false)
			_spawn_special_guards([
				Vector3(-40.0, 0.0, 20.0), Vector3(40.0, 0.0, -45.0),
			])
		5:
			_spawn_special_strike(false)
		6:
			_spawn_special_strike(true)

	if mission_id >= 5:
		_special_extract_beacon = _spawn_special_beacon(_special_extract_point,
				"ВИХІД · БАЗА", Color(0.35, 0.95, 0.75))
		_special_extract_beacon.visible = false

	print("[BigLevel] spawned Special Operation %d (%s), targets=%d" % [
		mission_id, Global.get_special_mission_name(mission_id), _mission_targets_total
	])


func _enter_special_extraction() -> void:
	if _special_extract_active or _mission_finished:
		return
	_special_extract_active = true
	_special_extract_hold = 0.0
	if _special_extract_beacon != null and is_instance_valid(_special_extract_beacon):
		_special_extract_beacon.visible = true
	_set_flash("ЦІЛІ УРАЖЕНО — ПОВЕРТАЙСЯ НА БАЗУ")
	_play_radio_callout("ЦІЛІ УРАЖЕНО — ПОВЕРТАЙСЯ НА БАЗУ", true)


func _update_special_mission(delta: float) -> void:
	if Global.special_mission <= 0 or _mission_finished:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	if _special_extract_active:
		if drone.global_position.distance_to(_special_extract_point) <= 45.0:
			_special_extract_hold += delta
			if _special_extract_hold >= 3.0:
				_finish_special_success()
		else:
			_special_extract_hold = maxf(_special_extract_hold - delta * 2.0, 0.0)
		return
	if Global.special_mission == 2:
		_update_escort_mission(delta, drone)
		return
	if Global.special_mission >= 5:
		return
	if _special_index >= _special_zones.size():
		_finish_special_success()
		return
	var zone: Dictionary = _special_zones[_special_index]
	var dist := drone.global_position.distance_to(zone["pos"])
	if dist <= float(zone["radius"]):
		_special_hold += delta
		if _special_hold >= float(zone["hold"]):
			_complete_special_zone()
	else:
		_special_hold = maxf(_special_hold - delta * 2.0, 0.0)


func _update_escort_mission(delta: float, drone: Drone) -> void:
	if _special_convoy == null or not is_instance_valid(_special_convoy):
		_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")
		return
	var dist := drone.global_position.distance_to(_special_convoy.global_position)
	if dist > 180.0:
		_special_convoy_far_timer += delta
		if _special_convoy_far_timer > 4.0 and not _special_convoy_warned:
			_special_convoy_warned = true
			_set_flash("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОНИ!")
			_play_radio_callout("ТРИМАЙТЕСЬ БЛИЖЧЕ ДО КОЛОНИ", true)
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
		if _special_convoy_far_timer < 1.0:
			_special_convoy_warned = false
	if _special_convoy.global_position.distance_to(_special_convoy_dest) < 42.0:
		_finish_special_success()


func _complete_special_zone() -> void:
	var zone: Dictionary = _special_zones[_special_index]
	var beacon = zone.get("beacon", null)
	if beacon is Node3D and is_instance_valid(beacon):
		(beacon as Node3D).visible = false
	if _special_index == 0 and _special_pickup_prop != null \
			and is_instance_valid(_special_pickup_prop):
		_special_pickup_prop.visible = false
	_special_index += 1
	_special_hold = 0.0
	if _special_index >= _special_zones.size():
		_finish_special_success()
		return
	var next_zone: Dictionary = _special_zones[_special_index]
	_set_flash("ЗОНУ ПРОЙДЕНО — ДАЛІ: %s" % str(next_zone["label"]))
	_play_radio_callout("ЗОНУ ПРОЙДЕНО — РУХАЙТЕСЬ ДАЛІ", true)


func _finish_special_success() -> void:
	if _mission_finished:
		return
	for beacon in _special_beacons:
		if is_instance_valid(beacon):
			beacon.visible = false
	_play_radio_callout("ОПЕРАЦІЮ ВИКОНАНО — ГАРНА РОБОТА", true)
	_finish_mission("СПЕЦОПЕРАЦІЮ «%s» ВИКОНАНО!" \
			% Global.get_special_mission_name(Global.special_mission), false)


func _special_fail(reason: String) -> void:
	if _mission_finished:
		return
	_play_radio_callout("ОПЕРАЦІЮ ПРОВАЛЕНО — ПОВЕРТАЙСЯ НА БАЗУ", true)
	_finish_mission(reason, true)


func _on_escort_destroyed(_points: int) -> void:
	_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")


func get_special_objective_info() -> Dictionary:
	if _special_extract_active:
		return {
			"pos": _special_extract_point,
			"label": "ВИХІД · БАЗА",
			"progress": clampf(_special_extract_hold / 3.0, 0.0, 1.0),
			"show_progress": true,
			"color": Color(0.35, 0.95, 0.75),
		}
	if _special_convoy != null and is_instance_valid(_special_convoy):
		var total := maxf(_special_convoy_start.distance_to(_special_convoy_dest), 1.0)
		var travelled := clampf(_special_convoy_start.distance_to(
				_special_convoy.global_position) / total, 0.0, 1.0)
		return {
			"pos": _special_convoy.global_position,
			"label": "КОЛОНА",
			"progress": travelled,
			"show_progress": true,
			"color": Color(1.0, 0.82, 0.42),
		}
	if _special_index < _special_zones.size():
		var zone: Dictionary = _special_zones[_special_index]
		return {
			"pos": zone["pos"],
			"label": str(zone["label"]),
			"progress": clampf(_special_hold / maxf(float(zone["hold"]), 0.01), 0.0, 1.0),
			"show_progress": true,
			"color": Color(0.35, 0.95, 0.75),
		}
	return {}


## Structured 4-Stage Escalating Combat Missions (20-minute time limit per mission):
##   Mission 1: Find & destroy the enemy Infantry squad (6 patrolling soldiers).
##   Mission 2: Find & destroy the T-72 Tank and BTR-90 APC (guarded by infantry).
##   Mission 3: Find & destroy the attack Helicopter (covered by mobile SAM).
##   Mission 4: Intercept & destroy high-speed Shahed-136 loitering munitions + escort.
func _spawn_combat_mission(mission_id: int) -> void:
	_mission_targets_total = 0
	_mission_targets_destroyed = 0
	_kills.clear()
	randomize()
	# Dynamic operational deployment zones on every mission launch so enemy positions are unique
	_offset_targets = mission_id >= 1 and mission_id <= 4
	_mission_offset = Vector3(randf_range(-85.0, 85.0), 0.0, randf_range(-55.0, 55.0))

	match mission_id:
		1:
			# МІСІЯ 1: Знайти і знищити піхоту (Легка складність)
			# Динамічний сектор патрулювання та випадкові маршрути бійців
			var sector_roll := randi() % 3
			var base_center := Vector3(0.0, 0.0, 100.0) + _mission_offset
			if sector_roll == 1:
				base_center = Vector3(-80.0, 0.0, 70.0) + _mission_offset
			elif sector_roll == 2:
				base_center = Vector3(80.0, 0.0, 85.0) + _mission_offset

			for i in range(6):
				var angle := (float(i) / 6.0) * TAU + randf_range(-0.35, 0.35)
				var dist := randf_range(16.0, 48.0)
				var pos := base_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
				var patrol_angle := randf() * TAU
				var axis := Vector3(cos(patrol_angle), 0.0, sin(patrol_angle))
				var p_dist := randf_range(12.0, 20.0)
				var p_spd := randf_range(1.5, 1.85)
				_add_mission_infantry(pos, axis, p_dist, p_spd, true)

		2:
			# МІСІЯ 2: Знайти і знищити Танк і БТР (Середня складність)
			# Динамічні сектори маневрування та змінні кути патрульних маршрутів
			var tank_rot := randf_range(-0.35, 0.35)
			var apc_rot := randf_range(-0.35, 0.35)
			var tank_box := [
				Vector3(-55.0, 0.0, 65.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(55.0, 0.0, 65.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(55.0, 0.0, -15.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(-55.0, 0.0, -15.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.TANK, tank_box, randf_range(5.2, 6.2), true, true)
			_mission_targets_total += 1

			var apc_box := [
				Vector3(75.0, 0.0, 95.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(-75.0, 0.0, 95.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(-75.0, 0.0, 20.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(75.0, 0.0, 20.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.APC, apc_box, randf_range(9.8, 11.2), true, true)
			_mission_targets_total += 1

			# Піхота прикриття у випадкових секторах
			var p1_pos := Vector3(randf_range(-45.0, -20.0), 0.0, randf_range(60.0, 95.0)) + _mission_offset
			var p2_pos := Vector3(randf_range(20.0, 45.0), 0.0, randf_range(60.0, 95.0)) + _mission_offset
			_add_mission_infantry(p1_pos, Vector3(1.0, 0.0, 0.0), 14.0, 1.7, false)
			_add_mission_infantry(p2_pos, Vector3(-1.0, 0.0, 0.0), 14.0, 1.7, false)

		3:
			# МІСІЯ 3: Гелікоптер (Важка складність — повітряна ціль + мобільна ППО)
			var h_center_x := randf_range(-35.0, 35.0) + _mission_offset.x
			var h_center_z := randf_range(25.0, 55.0) + _mission_offset.z
			var h_radius := randf_range(110.0, 140.0)
			var h_height := randf_range(30.0, 42.0)
			var heli_pts := _loop_waypoints(h_center_x, h_center_z, h_radius, 8, 0.2)
			_add_vehicle(Vehicle.Kind.HELI, heli_pts, randf_range(12.0, 13.8), true, true, h_height)
			_mission_targets_total += 1

			var sam_rot := randf_range(-0.4, 0.4)
			var sam_box := [
				Vector3(-65.0, 0.0, 55.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(65.0, 0.0, 55.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(65.0, 0.0, -25.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(-65.0, 0.0, -25.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SAM, sam_box, 4.2, true, true)
			_mission_targets_total += 1

		4:
			# МІСІЯ 4: Шахед (Максимальна складність — швидкісні повітряні цілі + ЗРК та БМП прикриття)
			var sh1_alt := randf_range(36.0, 44.0)
			var sh2_alt := randf_range(44.0, 54.0)
			var ang := randf_range(-0.25, 0.25)
			var p_pts1 := [
				Vector3(-190.0, 0.0, 85.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(190.0, 0.0, 85.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(190.0, 0.0, -35.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(-190.0, 0.0, -35.0).rotated(Vector3.UP, ang) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts1, randf_range(23.0, 25.5), true, false, sh1_alt)
			_mission_targets_total += 1

			var p_pts2 := [
				Vector3(195.0, 0.0, 35.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(-195.0, 0.0, 35.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(-195.0, 0.0, 115.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(195.0, 0.0, 115.0).rotated(Vector3.UP, -ang) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts2, randf_range(25.0, 28.0), true, false, sh2_alt)
			_mission_targets_total += 1

			_add_vehicle(Vehicle.Kind.SAM, [
				Vector3(randf_range(-85.0, -60.0), 0.0, randf_range(45.0, 75.0)) + _mission_offset,
				Vector3(randf_range(60.0, 85.0), 0.0, randf_range(45.0, 75.0)) + _mission_offset,
			], 4.5, true, true)
			_mission_targets_total += 1

			_add_vehicle(Vehicle.Kind.BMP, [
				Vector3(randf_range(70.0, 95.0), 0.0, randf_range(15.0, 35.0)) + _mission_offset,
				Vector3(randf_range(-95.0, -70.0), 0.0, randf_range(15.0, 35.0)) + _mission_offset,
			], 9.2, true, true)
			_mission_targets_total += 1

		_:
			# МІСІЯ 5: ЗНИЩИТИ ГІДРОЕЛЕКТРОСТАНЦІЮ (Морський удар дроном Магура-Х)
			var NavalBuilder = load("res://scripts/util/naval_scene_builder.gd")
			NavalBuilder.spawn_hydroelectric_power_station(self, Vector3(380.0, _sea_y - 0.5, -50.0), _on_hydro_plant_destroyed)
			# Enemy Corvette patrolling in the outer bay waters
			NavalBuilder.spawn_enemy_warship(self, Vector3(450.0, _sea_y, 110.0), _on_naval_warship_destroyed)
			_mission_targets_total = 1

	_offset_targets = false
	if frontline_map != "" and mission_id <= 4:
		_spawn_frontline_bonus_targets()

	print("[BigLevel] spawned Combat Mission %d/5 with %d required targets" % [
		mission_id, _mission_targets_total
	])


## Dynamic pressure: every ~24 s a small enemy patrol arrives near the
## objective area.  They are bonus targets (not required for completion), so
## the mission logic stays intact while the battlefield does not feel static.
var _reinforcement_wave := 0


func _start_reinforcements() -> void:
	if Global.play_mode != Global.PlayMode.COMBAT or Global.combat_mission == 5 \
			or Global.special_mission > 0:
		return
	var timer := Timer.new()
	timer.name = "ReinforcementTimer"
	timer.wait_time = 24.0
	timer.autostart = true
	timer.timeout.connect(_spawn_reinforcement_wave)
	add_child(timer)


func _spawn_reinforcement_wave() -> void:
	if _mission_finished or _reinforcement_wave >= 4:
		return
	_reinforcement_wave += 1
	if _reinforcement_wave >= 4:
		var timer := get_node_or_null("ReinforcementTimer") as Timer
		if timer != null:
			timer.stop()
	var center := Vector3(_mission_offset.x, 0.0, 100.0 + _mission_offset.z)
	var angle := randf() * TAU
	var dist := randf_range(45.0, 85.0)
	var pos := center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	var axis := Vector3(cos(angle + 1.2), 0.0, sin(angle + 1.2))
	_add_mission_infantry(pos, axis, 12.0, 1.8, false)
	_set_flash("ПІДКРІПЛЕННЯ ПРОТИВНИКА · ПІХОТА" if not MenuUI.is_english()
			else "ENEMY REINFORCEMENTS · INFANTRY")


## Optional infantry squads guarding the authored Blender landmarks.  They are
## not required for mission completion, but award score and make the hospital,
## checkpoint, factory and bridge approaches feel defended.
func _spawn_frontline_bonus_targets() -> void:
	var spots: Array = []
	match frontline_map:
		"village":
			spots = [
				[Vector3(-210.0, 0.0, 112.0), Vector3(1.0, 0.0, 0.0), 14.0],
				[Vector3(28.0, 0.0, 208.0), Vector3(0.0, 0.0, -1.0), 12.0],
				[Vector3(-165.0, 0.0, 52.0), Vector3(0.6, 0.0, 1.0), 16.0],
			]
		"industrial":
			spots = [
				[Vector3(168.0, 0.0, 104.0), Vector3(1.0, 0.0, 0.0), 15.0],
				[Vector3(10.0, 0.0, 194.0), Vector3(0.0, 0.0, -1.0), 14.0],
				[Vector3(48.0, 0.0, 156.0), Vector3(-1.0, 0.0, 0.2), 13.0],
			]
		"wetlands":
			spots = [
				[Vector3(202.0, 0.0, 144.0), Vector3(-1.0, 0.0, 0.0), 14.0],
				[Vector3(-36.0, 0.0, -76.0), Vector3(0.0, 0.0, 1.0), 16.0],
				[Vector3(104.0, 0.0, -76.0), Vector3(1.0, 0.0, 0.0), 15.0],
			]
		_:
			spots = [
				[Vector3(-230.0, 0.0, -62.0), Vector3(1.0, 0.0, 0.0), 14.0],
				[Vector3(40.0, 0.0, -72.0), Vector3(0.0, 0.0, 1.0), 15.0],
				[Vector3(-124.0, 0.0, 108.0), Vector3(-1.0, 0.0, 0.0), 13.0],
			]
	for spot in spots:
		var p: Vector3 = spot[0]
		var axis: Vector3 = spot[1]
		_add_mission_infantry(p, axis, float(spot[2]), 1.68, false)


func _spawn_speed_traffic() -> void:
	# vehicles crossing the circuit as moving hazards. Start them at the
	# diagonals so none of them blocks the grid at the moment of launch.
	for i in range(4):
		var t := (float(i) + 0.5) / 4.0 * TAU
		var px := cos(t) * 700.0
		var pz := sin(t) * 380.0
		var normal := Vector3(-sin(t) * 380.0, 0.0, cos(t) * 700.0).normalized()
		var points := [
			Vector3(px, 0.0, pz) - normal * 60.0,
			Vector3(px, 0.0, pz) + normal * 60.0,
		]
		_add_vehicle(Vehicle.Kind.TRUCK, points, 12.0, false, false)


func _make_multimesh(mesh: Mesh, material: Material,
		transforms: Array[Transform3D], colors: Array[Color] = [],
		shadows: bool = false) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	# MultiMesh only lets use_colors change while the instance count is zero.
	multi.use_colors = not colors.is_empty()
	multi.instance_count = transforms.size()
	for i in range(transforms.size()):
		multi.set_instance_transform(i, transforms[i])
		if multi.use_colors and i < colors.size():
			multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visibility_range_end = float(QualityManagerScript.get_value("veg_range", 1100.0))
	instance.visibility_range_end_margin = 160.0
	return instance


func _spawn_vegetation(density: int, min_radius: float, max_radius: float,
		conifer_ratio: float) -> void:
	# The old procedural birch/spruce lollipops (cylinder trunk + displaced
	# ellipsoid canopy) are retired.  All trees now come from the Blender
	# vegetation library through frontline_terrain._build_treelines().
	return
	@warning_ignore("unreachable_code")
	var veg_mult := float(QualityManagerScript.get_value("veg_density", 0.85))
	density = maxi(160, int(round(float(density) * veg_mult)))
	# Pine / Spruce trunk
	var pine_trunk_mesh := CylinderMesh.new()
	pine_trunk_mesh.top_radius = 0.11
	pine_trunk_mesh.bottom_radius = 0.22
	pine_trunk_mesh.height = 4.2
	pine_trunk_mesh.radial_segments = 6
	pine_trunk_mesh.rings = 1

	# Silver Birch slender white trunk
	var birch_trunk_mesh := CylinderMesh.new()
	birch_trunk_mesh.top_radius = 0.09
	birch_trunk_mesh.bottom_radius = 0.21
	birch_trunk_mesh.height = 6.2
	birch_trunk_mesh.radial_segments = 7
	birch_trunk_mesh.rings = 1

	# Layered conifer needle tiers: narrower and rounder than the old wide
	# cylinders, with enough radial segments that a nearby tree does not show
	# giant flat facets, animated by the shared foliage wind shader.
	var cone_low := FoliageSystemScript.make_cone_mesh(2.00, 3.8, 12, 0.13)
	var cone_mid := FoliageSystemScript.make_cone_mesh(1.55, 3.3, 12, 0.13)
	var cone_top := FoliageSystemScript.make_cone_mesh(1.00, 2.8, 10, 0.13)

	# Birch & deciduous multi-clustered leafy canopies.  The noise-displaced
	# ellipsoids break the perfectly round "lollipop" outline, which is what
	# separated the old trees from the reference.
	var leaf_main := FoliageSystemScript.make_canopy_mesh(7, 4, 0.18, 1.65, 3.9)
	var leaf_side := FoliageSystemScript.make_canopy_mesh(6, 3, 0.18, 1.15, 2.5)

	# Low bushes / undergrowth
	var bush_mesh := FoliageSystemScript.make_canopy_mesh(6, 3, 0.22, 0.85, 1.5)

	var pine_trunk_mat := _veg_material(Color(0.24, 0.16, 0.10), 0.96, false)
	var birch_trunk_mat := _veg_material(Color(0.78, 0.76, 0.72), 0.92, false)
	var conifer_mat := FoliageSystemScript.make_wind_material(Color(0.94, 1.0, 0.90))
	var leaf_mat := FoliageSystemScript.make_wind_material(Color(1.0, 1.0, 1.0))
	var bush_mat := FoliageSystemScript.make_wind_material(Color(0.96, 1.0, 0.92))

	var pine_trunk_xf: Array[Transform3D] = []
	var pine_trunk_col: Array[Color] = []
	var birch_trunk_xf: Array[Transform3D] = []
	var birch_trunk_col: Array[Color] = []
	var cone_low_xf: Array[Transform3D] = []
	var cone_mid_xf: Array[Transform3D] = []
	var cone_top_xf: Array[Transform3D] = []
	var leaf_main_xf: Array[Transform3D] = []
	var leaf_side_xf: Array[Transform3D] = []
	var bush_xf: Array[Transform3D] = []
	var cone_low_col: Array[Color] = []
	var cone_mid_col: Array[Color] = []
	var cone_top_col: Array[Color] = []
	var leaf_main_col: Array[Color] = []
	var leaf_side_col: Array[Color] = []
	var bush_col: Array[Color] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026 + density

	# Palette of physically calibrated linear-friendly birch & deciduous foliage tones
	# matching the reference visual (deep forest green, birch green, sunlit lime, golden birch, russet autumn):
	var foliage_palette := [
		Color(0.050, 0.105, 0.028), # deep birch green
		Color(0.072, 0.140, 0.036), # natural summer green
		Color(0.110, 0.185, 0.048), # sunlit lime-green
		Color(0.150, 0.135, 0.042), # golden yellow birch
		Color(0.120, 0.072, 0.030), # autumn amber-russet
	]

	# 1. Curated hero silver birches around the Industrial Complex and Train
	var fac_z := -28.0 if Global.play_mode == Global.PlayMode.TRAINING else (-60.0 if Global.play_mode == Global.PlayMode.COMBAT else 0.0)
	var hero_spots := [
		Vector3(-44.0, 0.0, fac_z + 18.0),
		Vector3(-38.0, 0.0, fac_z + 21.0),
		Vector3(-21.0, 0.0, fac_z + 15.0),
		Vector3(-15.0, 0.0, fac_z + 18.0),
		Vector3(-7.0, 0.0, fac_z + 19.0),
		Vector3(-2.5, 0.0, fac_z + 15.0),
		Vector3(3.0, 0.0, fac_z + 17.0),
		Vector3(9.5, 0.0, fac_z + 19.0),
		Vector3(62.0, 0.0, fac_z - 12.0),
		Vector3(68.0, 0.0, fac_z - 6.0),
		Vector3(-62.0, 0.0, fac_z - 8.0),
		Vector3(-56.0, 0.0, fac_z + 8.0),
	]
	for idx in range(hero_spots.size()):
		var hp: Vector3 = hero_spots[idx]
		var gy := _find_ground_y(hp.x, hp.z)
		var sc := rng.randf_range(1.20, 1.75)
		var yaw := rng.randf() * TAU
		var base := Vector3(hp.x, gy, hp.z)
		var t_basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc * 0.78, sc * 1.15, sc * 0.78))
		birch_trunk_xf.append(Transform3D(t_basis, base + Vector3(0.0, 3.0 * sc, 0.0)))
		birch_trunk_col.append(Color(0.88, 0.86, 0.82))
		var leaf_col: Color = foliage_palette[idx % foliage_palette.size()]
		var c_basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc * 0.88, sc * 1.38, sc * 0.88))
		_append_veg(leaf_main_xf, leaf_main_col,
				Transform3D(c_basis, base + Vector3(0.0, 6.0 * sc, 0.0)), leaf_col)
		for cl in range(6):
			var off := Vector3(rng.randf_range(-1.25, 1.25), rng.randf_range(-1.4, 1.6),
					rng.randf_range(-1.25, 1.25)) * sc
			var sb := Basis(Vector3(rng.randf_range(-0.3, 0.3), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), rng.randf() * TAU).scaled(
					Vector3(0.82, 1.12, 0.82) * sc * rng.randf_range(0.65, 0.95))
			_append_veg(leaf_side_xf, leaf_side_col,
					Transform3D(sb, base + Vector3(0.0, 5.5 * sc, 0.0) + off),
					leaf_col.darkened(rng.randf_range(0.0, 0.22)))

	# 2. Valley & hillside forest distribution
	for i in range(density):
		var angle := rng.randf() * TAU
		var radius: float = min_radius + rng.randf() * maxf(1.0, max_radius - min_radius)
		var x: float = cos(angle) * radius
		var z: float = sin(angle) * radius
		# Keep the immediate industrial apron & railway track clear of random trunks
		if absf(x) < 72.0 and absf(z - fac_z) < 56.0:
			continue
		if Global.play_mode == Global.PlayMode.SPEED:
			var ell := (x / 165.0) * (x / 165.0) + (z / 115.0) * (z / 115.0)
			if absf(ell - 1.0) < 0.28:
				continue
		var gy := _find_ground_y(x, z)
		if gy < -40.0:
			continue
		var scale := rng.randf_range(0.95, 1.95)
		var yaw := rng.randf() * TAU
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale)
		var base := Vector3(x, gy, z)
		if rng.randf() < conifer_ratio:
			pine_trunk_xf.append(Transform3D(basis, base + Vector3(0, 2.0 * scale, 0)))
			pine_trunk_col.append(Color(0.80 + rng.randf() * 0.15, 0.75 + rng.randf() * 0.15, 0.70))
			var pine_green := Color(0.038 + rng.randf() * 0.035, 0.088 + rng.randf() * 0.055, 0.030 + rng.randf() * 0.022)
			_append_veg(cone_low_xf, cone_low_col,
					Transform3D(basis, base + Vector3(0, 3.4 * scale, 0)), pine_green)
			_append_veg(cone_mid_xf, cone_mid_col,
					Transform3D(basis, base + Vector3(0, 5.3 * scale, 0)), pine_green.lightened(0.03))
			_append_veg(cone_top_xf, cone_top_col,
					Transform3D(basis, base + Vector3(0, 7.0 * scale, 0)), pine_green.lightened(0.06))
		else:
			var b_basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale * 0.80, scale * 1.1, scale * 0.80))
			birch_trunk_xf.append(Transform3D(b_basis, base + Vector3(0, 2.9 * scale, 0)))
			birch_trunk_col.append(Color(0.85 + rng.randf() * 0.10, 0.83 + rng.randf() * 0.10, 0.78 + rng.randf() * 0.10))
			var pick_idx := 0
			var roll := rng.randf()
			if roll < 0.42:
				pick_idx = 0
			elif roll < 0.72:
				pick_idx = 1
			elif roll < 0.86:
				pick_idx = 2
			elif roll < 0.94:
				pick_idx = 3
			else:
				pick_idx = 4
			var leaf_color: Color = foliage_palette[pick_idx]
			var canopy_basis := Basis(Vector3.UP, yaw).scaled(
					Vector3(scale * 0.95, scale * 1.28, scale * 0.95))
			_append_veg(leaf_main_xf, leaf_main_col,
					Transform3D(canopy_basis, base + Vector3(0, 5.8 * scale, 0)), leaf_color)
			for cl in range(4):
				var lobe := Vector3(rng.randf_range(-1.15, 1.15), rng.randf_range(-1.0, 1.2),
						rng.randf_range(-1.15, 1.15)) * scale
				var side_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
						Vector3(0.85, 1.10, 0.85) * scale * rng.randf_range(0.68, 0.94))
				_append_veg(leaf_side_xf, leaf_side_col,
						Transform3D(side_basis, base + Vector3(0, 5.4 * scale, 0) + lobe),
						leaf_color.darkened(rng.randf_range(0.0, 0.20)))

	# 3. Scatter low bushes across the valley (keeping immediate spawn/track clean)
	var bush_count := int(density * 0.35)
	for i in range(bush_count):
		var angle := rng.randf() * TAU
		var radius: float = min_radius * 0.85 + rng.randf() * maxf(
				1.0, max_radius - min_radius * 0.85)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		if absf(x) < 75.0 and absf(z - fac_z) < 65.0:
			continue
		var gy := _find_ground_y(x, z)
		if gy < -40.0:
			continue
		var s := rng.randf_range(0.45, 0.95)
		var base := Vector3(x, gy, z)
		var tint: Color = foliage_palette[rng.randi() % 3] if rng.randf() < 0.82 else foliage_palette[4]
		for blob in range(2):
			var off := Vector3(rng.randf_range(-0.6, 0.6) * s, rng.randf_range(0.25, 0.55) * s,
					rng.randf_range(-0.6, 0.6) * s)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(
					Vector3(1.0, 0.65, 1.0) * s * rng.randf_range(0.8, 1.15))
			_append_veg(bush_xf, bush_col, Transform3D(b, base + off), tint.darkened(0.12))

	var veg_shadows := QualityManagerScript.get_active_level() >= 2
	if not pine_trunk_xf.is_empty():
		add_child(_make_multimesh(pine_trunk_mesh, pine_trunk_mat, pine_trunk_xf, pine_trunk_col, veg_shadows))
	if not birch_trunk_xf.is_empty():
		add_child(_make_multimesh(birch_trunk_mesh, birch_trunk_mat, birch_trunk_xf, birch_trunk_col, veg_shadows))
	if not cone_low_xf.is_empty():
		add_child(_make_multimesh(cone_low, conifer_mat, cone_low_xf, cone_low_col, veg_shadows))
	if not cone_mid_xf.is_empty():
		add_child(_make_multimesh(cone_mid, conifer_mat, cone_mid_xf, cone_mid_col, veg_shadows))
	if not cone_top_xf.is_empty():
		add_child(_make_multimesh(cone_top, conifer_mat, cone_top_xf, cone_top_col, veg_shadows))
	if not leaf_main_xf.is_empty():
		add_child(_make_multimesh(leaf_main, leaf_mat, leaf_main_xf, leaf_main_col, veg_shadows))
	if not leaf_side_xf.is_empty():
		add_child(_make_multimesh(leaf_side, leaf_mat, leaf_side_xf, leaf_side_col, veg_shadows))
	if not bush_xf.is_empty():
		add_child(_make_multimesh(bush_mesh, bush_mat, bush_xf, bush_col, false))


func _veg_material(color: Color, roughness: float, is_foliage: bool = true) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.vertex_color_use_as_albedo = true
	# The texture set shipped with the project is concrete and chain-link, not
	# bark.  Triplanar-mapping it onto the trunks was the main reason the old
	# trees looked dirty, so the bark is now a clean solid colour with a
	# vertically stretched normal map for relief.
	if not is_foliage and QualityManagerScript.get_active_level() > 0 \
			and ResourceLoader.exists("res://Assets/Textures/NormalMap.png"):
		mat.normal_enabled = true
		mat.normal_texture = load("res://Assets/Textures/NormalMap.png")
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(2.2, 0.30, 2.2)
		mat.normal_scale = 0.75
	return mat


func _append_veg(transforms: Array[Transform3D], colors: Array[Color],
		xf: Transform3D, color: Color) -> void:
	transforms.append(xf)
	colors.append(color)


func _spawn_destructible_buildings(count: int, radius_min: float,
		radius_max: float) -> void:
	if count <= 0:
		return
	if QualityManager.get_active_level() == QualityManager.Level.LOW:
		count = maxi(1, int(count * 0.5))
	var colors := [Color(0.46, 0.43, 0.38), Color(0.38, 0.37, 0.40),
			Color(0.50, 0.45, 0.36)]
	var centre := Vector2(_mission_offset.x, 90.0 + _mission_offset.z)
	var water := _map_water_level()
	for i in range(count):
		var x := 0.0
		var z := 0.0
		var gy := 0.0
		var placed := false
		for _try in range(24):
			var angle := randf() * TAU
			var radius := randf_range(radius_min, radius_max)
			x = centre.x + cos(angle) * radius
			z = centre.y + sin(angle) * radius
			if absf(x) > 430.0 or absf(z) > 430.0:
				continue
			var h := FrontlineTerrainScript.height_at(frontline_map, x, z)
			if h < water + 1.2:
				continue
			gy = _find_ground_y(x, z)
			if absf(gy - h) > 3.0:
				continue
			placed = true
			break
		if not placed:
			continue
		var building: DestructibleBuilding = DESTRUCTIBLE.new()
		building.configure(Vector3(randf_range(14.0, 24.0), 0.0,
				randf_range(14.0, 24.0)), randi_range(3, 6), colors[i % 3])
		add_child(building)
		building.global_position = Vector3(x, gy, z)
		building.destroyed.connect(_on_building_destroyed)


func _on_building_destroyed(points: int) -> void:
	_score += points
	if Global.play_mode == Global.PlayMode.COMBAT:
		var combat := get_node_or_null("CombatSystem")
		if combat != null and combat.has_method("add_bonus_score"):
			combat.call("add_bonus_score", points, "БУДІВЛЮ ЗРУЙНОВАНО")
	else:
		_set_flash("Будівлю зруйновано  +%d" % points)


func _spawn_boost_pads() -> void:
	var rx := 165.0
	var ry := 115.0
	for i in range(12):
		var t := float(i) / 12.0 * TAU
		var x := cos(t) * rx
		var z := sin(t) * ry
		var gy := _find_ground_y(x, z)
		var area := Area3D.new()
		area.position = Vector3(x, gy + 1.2, z)
		area.collision_layer = 0
		area.collision_mask = 1
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(18.0, 4.0, 12.0)
		shape.shape = box
		area.add_child(shape)
		var mesh := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(16.0, 10.0)
		mesh.mesh = quad
		mesh.rotation.x = -PI * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.85, 0.7, 0.5)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.emission_enabled = true
		material.emission = Color(0.1, 0.9, 0.75)
		mesh.material_override = material
		area.add_child(mesh)
		_triggers.add_child(area)
		area.body_entered.connect(_on_boost_entered)


func _on_boost_entered(body: Node3D) -> void:
	if not (body is Drone) or _mission_finished:
		return
	var drone := body as Drone
	var forward := -drone.global_transform.basis.z
	drone.linear_velocity += forward * 16.0
	_set_flash("БУСТ!")


# ------------------------------------------------------------------ HUD
func _setup_hud() -> void:
	_touch_controls = get_node_or_null("/root/TouchControls")
	var touch_enabled: bool = _touch_controls != null \
			and bool(_touch_controls.get("enabled"))
	_hud = CanvasLayer.new()
	_hud.layer = 12
	add_child(_hud)
	_stick_overlay = StickOverlayScript.new()
	_stick_overlay.name = "StickOverlay"
	_hud.add_child(_stick_overlay)
	if _touch_controls != null:
		var mode_cb := Callable(self, "_on_touch_mode_changed")
		if not _touch_controls.is_connected("mode_changed", mode_cb):
			_touch_controls.connect("mode_changed", mode_cb)
	_stick_overlay.visible = not (touch_enabled \
			and bool(_touch_controls.get("touch_mode")))
	if not GameSettings.hud_config_updated.is_connected(_apply_stick_overlay):
		GameSettings.hud_config_updated.connect(_apply_stick_overlay)
	_diag = Label.new()
	_diag.add_theme_font_size_override("font_size", 17)
	_diag.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_diag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_diag.add_theme_constant_override("outline_size", 3)
	_diag.position = Vector2(26, 300)
	_diag.visible = false
	_hud.add_child(_diag)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 14)
	_hud_label.add_theme_color_override("font_color", Color(0.92, 0.96, 0.94, 0.95))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_label.add_theme_constant_override("outline_size", 3)
	_hud_label.position = Vector2(22, 96)
	_hud_label.visible = true
	_hud.add_child(_hud_label)
	_hud_message = Label.new()
	_hud_message.add_theme_font_size_override("font_size", 18)
	_hud_message.add_theme_color_override("font_color", Color(1, 0.92, 0.5))
	_hud_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_hud_message.add_theme_constant_override("outline_size", 4)
	_hud_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_message.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud_message.offset_top = 26
	_hud.add_child(_hud_message)
	_nav_marker = Label.new()
	_nav_marker.add_theme_font_size_override("font_size", 15)
	_nav_marker.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35, 0.95))
	_nav_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_nav_marker.add_theme_constant_override("outline_size", 3)
	_nav_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_marker.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_nav_marker.offset_top = 56
	_hud.add_child(_nav_marker)
	_threat_indicator = Label.new()
	_threat_indicator.add_theme_font_size_override("font_size", 14)
	_threat_indicator.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25, 0.98))
	_threat_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_threat_indicator.add_theme_constant_override("outline_size", 3)
	_threat_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_indicator.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_threat_indicator.offset_top = 82
	_threat_indicator.visible = false
	_hud.add_child(_threat_indicator)
	# iOS / WiFi ELRS touch helpers.  The Pocket's CH5 switch also maps to
	# toggle_arm; the button is a fallback for a phone without a radio.
	if ElrsWifiInput.enabled or touch_enabled:
		_elrs_status_label = Label.new()
		_elrs_status_label.add_theme_font_size_override("font_size", 13)
		_elrs_status_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72, 0.95))
		_elrs_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_elrs_status_label.add_theme_constant_override("outline_size", 3)
		_elrs_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_elrs_status_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_elrs_status_label.offset_top = 108
		_elrs_status_label.text = ElrsWifiInput.status_text
		_hud.add_child(_elrs_status_label)
	_radio_subtitle = Label.new()
	_radio_subtitle.add_theme_font_size_override("font_size", 14)
	_radio_subtitle.add_theme_color_override("font_color", Color(0.78, 1.0, 0.88, 0.98))
	_radio_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_radio_subtitle.add_theme_constant_override("outline_size", 4)
	_radio_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_radio_subtitle.offset_left = -460
	_radio_subtitle.offset_right = 460
	_radio_subtitle.offset_top = -160
	_radio_subtitle.offset_bottom = -128
	_radio_subtitle.visible = false
	_hud.add_child(_radio_subtitle)
	_setup_telemetry()
	_build_results()
	_build_chain_briefing()
	if Global.play_mode == Global.PlayMode.TUTORIAL and _flight_school != null:
		_flight_school.setup_hud(_hud)


func _terrain_y(x: float, z: float) -> float:
	if frontline_map != "":
		var builder = load("res://scripts/util/frontline_terrain.gd")
		if builder != null:
			return builder.height_at(frontline_map, x, z)
	return _ground_y


func _setup_reb() -> void:
	if _reb != null:
		return
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var reb := RebSystem.new()
	reb.name = "RebSystem"
	reb.use_own_position_as_home = false
	reb.home_position = Vector3(d.global_position.x, _ground_y, d.global_position.z)
	add_child(reb)
	_reb = reb
	# EW laydown per map: one omnidirectional trench dome (150-250 m) and one
	# directional station covering the attack approach.  Positions are snapped
	# to the procedural terrain so the masts always sit on the ground.
	var domes: Array = []
	match frontline_map:
		"village":
			domes = [
				{"p": Vector2(-60, -80), "r": 170.0, "s": 0.80, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(210, 70), "r": 220.0, "s": 0.90, "dir": true, "yaw": -140.0, "fov": 80.0},
			]
		"industrial":
			domes = [
				{"p": Vector2(130, -40), "r": 250.0, "s": 0.88, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(-190, -100), "r": 200.0, "s": 0.82, "dir": true, "yaw": 55.0, "fov": 75.0},
			]
		"wetlands":
			domes = [
				{"p": Vector2(0, -90), "r": 220.0, "s": 0.86, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(190, -140), "r": 200.0, "s": 0.84, "dir": true, "yaw": -160.0, "fov": 85.0},
			]
		_:
			domes = [
				{"p": Vector2(-150, -120), "r": 190.0, "s": 0.78, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(170, 90), "r": 240.0, "s": 0.90, "dir": true, "yaw": -135.0, "fov": 75.0},
			]
	for dome in domes:
		var p: Vector2 = dome["p"]
		reb.add_ew_dome(Vector3(p.x, _terrain_y(p.x, p.y), p.y),
				float(dome["r"]), float(dome["s"]), bool(dome["dir"]),
				deg_to_rad(float(dome["yaw"])), float(dome["fov"]))
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0 \
			and Global.combat_mission >= 3:
		reb.add_ew_dome(Vector3(0.0, _terrain_y(0.0, -260.0), -260.0), 250.0, 0.95, true,
				deg_to_rad(0.0), 90.0)
	if Global.special_mission == 6:
		# EW breach: a deliberately dense corridor between the launch point and
		# the strike target, still using the reduced EW effect scale.
		reb.add_ew_dome(Vector3(-55.0, _terrain_y(-55.0, -40.0), -40.0),
				240.0, 0.95, false)
		reb.add_ew_dome(Vector3(75.0, _terrain_y(75.0, -105.0), -105.0),
				220.0, 0.90, true, deg_to_rad(35.0), 85.0)
	if not reb.failsafe_changed.is_connected(_on_reb_failsafe):
		reb.failsafe_changed.connect(_on_reb_failsafe)


func _on_reb_failsafe(active: bool) -> void:
	if active:
		_set_flash("FAILSAFE — ВТРАЧЕНО ЗВ'ЯЗОК")
	else:
		_set_flash("ЗВ'ЯЗОК ВІДНОВЛЕНО")


func _setup_telemetry() -> void:
	_telem_left = Label.new()
	_telem_left.add_theme_font_size_override("font_size", 14)
	_telem_left.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	_telem_left.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_telem_left.add_theme_constant_override("outline_size", 3)
	_telem_left.position = Vector2(22, 22)
	_hud.add_child(_telem_left)
	_telem_right = Label.new()
	_telem_right.add_theme_font_size_override("font_size", 14)
	_telem_right.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	_telem_right.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_telem_right.add_theme_constant_override("outline_size", 3)
	_telem_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_telem_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_telem_right.offset_left = -240
	_telem_right.offset_top = 22
	_telem_right.offset_right = -22
	_hud.add_child(_telem_right)

	# Small field-wind cue in the lower-left corner.  It is hidden in Arcade
	# (wind_sim off) and shows both the relative direction and the gust speed.
	_wind_indicator = Label.new()
	_wind_indicator.add_theme_font_size_override("font_size", 13)
	_wind_indicator.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42, 0.95))
	_wind_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_wind_indicator.add_theme_constant_override("outline_size", 3)
	_wind_indicator.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_wind_indicator.offset_left = 22
	_wind_indicator.offset_top = -46
	_wind_indicator.offset_right = 380
	_wind_indicator.offset_bottom = -18
	_wind_indicator.visible = false
	_hud.add_child(_wind_indicator)


func _update_telemetry(delta: float) -> void:
	if _telem_left == null:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	var armed: bool = drone.flight_controller != null and drone.flight_controller.state_armed
	var throttle := 0.0
	var radio := get_node_or_null("RadioController")
	if radio != null:
		var input_arr = radio.get("input")
		if input_arr is Array and input_arr.size() > 0:
			throttle = clampf(input_arr[0], 0.0, 1.0)
	var p := DroneCatalog.preset(Global.drone_preset)
	var is_boat: bool = bool(p.get("is_naval", false))
	var current := 0.4
	var cell_v := _battery / 6.0
	if armed:
		# The drone owns the real pack model (LiPo vs Li-ion internal
		# resistance, burst current, sustained heat soak).
		current = drone.battery_current_draw
		_battery = drone.battery_voltage
		cell_v = drone.battery_cell_voltage
	else:
		# Ground idle: avionics draw only, the pack is not under load.
		current = 0.4
		cell_v = _battery / 6.0
	_mah += current * delta / 3.6
	# Pack integration stays per-frame; every readout below is recomputed and
	# shaped at 12 Hz.  The old code did all of this work every frame and only
	# skipped the final Label assignment, which still burned CPU on the UHD.
	_telemetry_tick -= delta
	_telemetry_accum += delta
	if _telemetry_tick > 0.0:
		return
	delta = _telemetry_accum
	_telemetry_accum = 0.0
	_telemetry_tick = 0.083

	var speed_kmh := drone.linear_velocity.length() * 3.6
	var altitude := drone.global_position.y - _ground_y
	var mode_str := "ACRO"
	if drone.flight_controller != null:
		mode_str = FlightController.mode_name(drone.flight_controller.flight_mode)
	var is_combat: bool = bool(p.get("combat", false))
	var has_drop: bool = bool(p.get("has_drop", false))
	var ammo_line := ""
	if Global.play_mode == Global.PlayMode.COMBAT and is_combat:
		if has_drop:
			ammo_line = "СКИД %d  [G]\n" % _ammo_count()
		else:
			ammo_line = "БЧ 1x  [F]\n"
	_scene_uptime += delta
	if _scene_uptime > 0.6:
		# Engine FPS is already smoothed over real frames; deriving it from the
		# accumulated OSD delta would always read 12 FPS.
		_fps_ema = lerpf(_fps_ema, float(Engine.get_frames_per_second()), 0.35)
	var fps_val := int(round(_fps_ema))
	var batt_tag := ""
	var low_voltage := cell_v < 3.5
	if low_voltage:
		batt_tag = "  LOW VOLTAGE!"
	var jamming: bool = _reb != null and _reb.limits_enabled \
			and _reb.reb_zones_enabled and _reb.in_ew > 0.08
	var warn_phase := int(Time.get_ticks_msec() / 280) % 2 == 0
	var lq_line := ""
	if _reb != null:
		var jam_tag := ""
		if jamming:
			jam_tag = "  JAMMING" if warn_phase else ""
		lq_line = "\nLQ %d%%  %s%s  |  %.0f ms" % [
				_reb.get_lq_percent(), _reb.get_status_text(), jam_tag, _reb.latency_ms]
	var q_lvl := QualityManagerScript.get_active_level()
	var q_short := "НИЗ"
	if q_lvl == 1:
		q_short = "СЕР"
	elif q_lvl == 2:
		q_short = "ВИС"
	elif q_lvl == 3:
		q_short = "UFDS"
	if _wind_player != null:
		var airspeed_vec: Vector3 = drone.linear_velocity - _current_wind_vector
		var airspeed: float = airspeed_vec.length()
		var wind_gust: float = _current_wind_vector.length()
		# Combat wind is deliberately louder than the calm-weather bed.
		var wind_enabled := bool(GameSettings.hud_config.get("wind_sim", false))
		var db_floor := -46.0 if wind_enabled else -50.0
		var target_wind_db: float = lerpf(db_floor, -6.0,
				clampf((airspeed + wind_gust * 1.6) / 36.0, 0.0, 1.0))
		_wind_player.volume_db = lerpf(_wind_player.volume_db, target_wind_db, delta * 8.0)
		_wind_player.pitch_scale = clampf(
				0.80 + (airspeed / 55.0) * 0.45 + wind_gust * 0.006, 0.72, 1.60)

	# Low-voltage beeper: classic double beep, faster when the pack is critical.
	if low_voltage and _beeper_player != null:
		_beeper_timer -= delta
		if _beeper_timer <= 0.0:
			_beeper_timer = 0.55 if cell_v < 3.35 else 1.15
			_beeper_player.volume_db = -8.0 if cell_v < 3.35 else -14.0
			_beeper_player.play()
	else:
		_beeper_timer = 0.0
	if low_voltage and not _low_battery_announced:
		_low_battery_announced = true
		_set_flash("НИЗЬКА НАПРУГА БАТАРЕЇ — ПРИЗЕМЛЮЙТЕСЬ" if not MenuUI.is_english()
				else "LOW BATTERY — LAND NOW")
		_play_radio_callout("БАТАРЕЯ КРИТИЧНА — ПОВЕРТАЙСЯ НА БАЗУ", true)
	elif not low_voltage:
		_low_battery_announced = false
	if jamming != _ew_was_active:
		_ew_was_active = jamming
		_play_alert("ew_enter" if jamming else "ew_exit", -7.0)
		if jamming:
			_play_radio_callout("РЕБ! ГЛУШІННЯ — ВТРАТА ЗВ'ЯЗКУ", true)
	if jamming and not _jamming_announced:
		_jamming_announced = true
		_set_flash("РЕБ: ГЛУШІННЯ · JAMMING" if not MenuUI.is_english()
				else "EW: JAMMING")
	elif not jamming:
		_jamming_announced = false
	var critical_lq: bool = _reb != null and _reb.limits_enabled \
			and _reb.link_quality < 0.20
	if critical_lq and not _lq_was_critical:
		_play_alert("lq_critical", -8.0)
		_lq_warn_timer = 3.0
	_lq_was_critical = critical_lq
	if critical_lq:
		_lq_warn_timer -= delta
		if _lq_warn_timer <= 0.0:
			_lq_warn_timer = 3.0
			_play_alert("lq_critical", -10.0)
	else:
		_lq_warn_timer = 0.0

	_update_wind_indicator()
	_update_threat_indicator()
	_telem_left.text = "%s\n%s%s   GAS %d%%" % [
			"ДВИГУНИ УВІМКНЕНО" if armed else "ДВИГУНИ ВИМКНЕНО",
			ammo_line, mode_str, int(throttle * 100.0)]
	var warning := low_voltage or jamming \
			or (_reb != null and (_reb.failsafe or _reb.link_quality < 0.32))
	if warning:
		var warn_color := Color(1.0, 0.22, 0.18, 0.98) if warn_phase \
				else Color(0.55, 0.04, 0.03, 0.95)
		_telem_right.add_theme_color_override("font_color", warn_color)
	else:
		_telem_right.add_theme_color_override("font_color", Color(1, 1, 1, 0.94))
	_telem_right.text = "%d FPS  [%s]\n%.2f V  |  %.1f V%s\n%d mAh  |  %.1f A%s\n%.0f km/h   %.0f m" % [
			fps_val, q_short, cell_v, _battery, batt_tag, int(_mah), current, lq_line,
			speed_kmh, altitude]


func _update_wind_indicator() -> void:
	if _wind_indicator == null:
		return
	if not bool(GameSettings.hud_config.get("wind_sim", false)):
		_wind_indicator.visible = false
		return
	var wind := Vector3(_current_wind_vector.x, 0.0, _current_wind_vector.z)
	var speed := wind.length()
	_wind_indicator.visible = true
	if speed < 0.15:
		_wind_indicator.text = "ВІТЕР  ·  ШТИЛЬ"
		_wind_indicator.add_theme_color_override("font_color", Color(0.75, 0.82, 0.78, 0.9))
		return
	var arrow := _arrow_from_direction(wind)
	var gust := speed >= 7.0
	_wind_indicator.text = "ВІТЕР  %s  %.1f м/с%s" % [
			arrow, speed, "  ПОРИВ" if gust else ""]
	_wind_indicator.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.25, 0.98) if gust else Color(1.0, 0.82, 0.42, 0.95))


## Arrow in screen space for a world-space direction: ↑ means "ahead of the
## current view", → means "to the right", ↓ means "behind".
func _arrow_from_direction(world_dir: Vector3) -> String:
	var direction := Vector3(world_dir.x, 0.0, world_dir.z)
	if direction.length() < 0.01:
		return "·"
	direction = direction.normalized()
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	if camera != null:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.01:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		right = camera.global_transform.basis.x
		right.y = 0.0
		if right.length() > 0.01:
			right = right.normalized()
		else:
			right = Vector3.RIGHT
	var bearing := atan2(direction.dot(right), direction.dot(fwd))
	var arrow_idx := int(round(bearing / (PI / 4.0))) % 8
	if arrow_idx < 0:
		arrow_idx += 8
	var arrows := ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
	return arrows[arrow_idx]


func _update_threats(delta: float) -> void:
	_threat_timer = maxf(_threat_timer - delta, 0.0)
	_sam_warn_timer -= delta
	_kamikaze_warn_timer -= delta
	_threat_scan_tick -= delta
	if _threat_scan_tick > 0.0:
		return
	_threat_scan_tick = 0.2
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or not is_instance_valid(drone):
		return
	var nearest_sam: Vehicle = null
	var sam_dist := 1e9
	var nearest_shahed: Vehicle = null
	var shahed_dist := 1e9
	for node in get_tree().get_nodes_in_group("combat_target"):
		if not is_instance_valid(node) or not (node is Vehicle):
			continue
		var vehicle := node as Vehicle
		if vehicle.is_destroyed or not vehicle.hostile:
			continue
		var d := drone.global_position.distance_to(vehicle.global_position)
		if vehicle.kind == Vehicle.Kind.SAM and d < 450.0 and d < sam_dist:
			sam_dist = d
			nearest_sam = vehicle
		elif vehicle.kind == Vehicle.Kind.SHAHED and d < 360.0 and d < shahed_dist:
			shahed_dist = d
			nearest_shahed = vehicle
	if nearest_sam != null:
		_threat_position = nearest_sam.global_position
		_threat_kind = "ЗРК"
		_threat_timer = maxf(_threat_timer, 0.45)
		if _sam_warn_timer <= 0.0:
			_sam_warn_timer = lerpf(1.25, 0.35,
					clampf(1.0 - sam_dist / 450.0, 0.0, 1.0))
			CombatSfxScript.play_alert_3d(self, nearest_sam.global_position,
					"sam_lock", -13.0, 24.0, 520.0)
	elif nearest_shahed != null:
		_threat_position = nearest_shahed.global_position
		_threat_kind = "ШАХЕД"
		_threat_timer = maxf(_threat_timer, 0.45)
		if _kamikaze_warn_timer <= 0.0:
			_kamikaze_warn_timer = 0.85
			CombatSfxScript.play_alert_3d(self, nearest_shahed.global_position,
					"kamikaze", -12.0, 18.0, 420.0)


func _update_threat_indicator() -> void:
	if _threat_indicator == null:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or _threat_timer <= 0.0 or _threat_position == Vector3.ZERO:
		_threat_indicator.visible = false
		return
	var arrow := _arrow_from_direction(_threat_position - drone.global_position)
	_threat_indicator.text = "⚠ %s  %s" % [_threat_kind, arrow]
	_threat_indicator.add_theme_color_override("font_color",
			Color(1.0, 0.22, 0.18, 0.98) if _threat_kind == "ВОГОНЬ"
			else Color(1.0, 0.55, 0.25, 0.98))
	_threat_indicator.visible = true


## Called by the tracer / combat glue when an enemy round hits the drone.
func report_incoming_fire(source_position: Vector3, kind: String = "ВОГОНЬ") -> void:
	if source_position == Vector3.ZERO:
		return
	_threat_position = source_position
	_threat_kind = kind
	_threat_timer = maxf(_threat_timer, 1.8)


func _ammo_count() -> int:
	if _heavy_bomber:
		return _bomb_nodes.size()
	var p := DroneCatalog.preset(Global.drone_preset)
	var has_drop := bool(p.get("has_drop", false))
	if has_drop:
		if Global.play_mode == Global.PlayMode.COMBAT:
			var combat := get_node_or_null("CombatSystem")
			if combat != null and combat.get("ammo") != null:
				return int(combat.get("ammo"))
		return _payload_ammo_left
	var combat_ammo := get_node_or_null("CombatSystem")
	if combat_ammo != null and combat_ammo.get("ammo") != null:
		return int(combat_ammo.get("ammo"))
	return 0


func _setup_fpv_camera_for_preset() -> void:
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam == null:
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	cam.fov = 110.0
	cam.near = 0.05
	cam.far = 4000.0
	cam.position = p.get("fpv_cam_pos", Vector3(0.0, 0.004, -0.053))
	cam.set_meta("base_pos", cam.position)
	# The old presets all aimed 10-14 degrees at the floor.  That hides the
	# ruined interiors, so lift the lens towards the reference's eye-level
	# composition while keeping the preset-to-preset differences.
	var pitch := clampf(float(p.get("fpv_cam_pitch", -10.0)) + 8.0, -5.0, 3.0)
	cam.rotation_degrees = Vector3(pitch, 0.0, 0.0)
	cam.set_meta("base_rot", cam.rotation_degrees)


func _setup_multi_cameras() -> void:
	# First-person only.  External chase/orbit/front cameras were removed from
	# the game, menus, help and controls; the FPV lens is the only camera.
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var fpv := d.get_node_or_null("FPVCamera") as Camera3D
	if fpv == null:
		return
	cameras = [fpv]
	camera_index = 0
	camera = fpv
	fpv.current = true


func _update_orbit_cam() -> void:
	# Retained as a no-op for any legacy QA script; there is no orbit camera.
	pass


func _setup_chase_view() -> void:
	# Legacy QA hook: there is no chase camera anymore; keep the FPV lens.
	var fpv := get_node_or_null("Drone/FPVCamera") as Camera3D
	if fpv != null:
		camera = fpv
		camera_index = 0
		fpv.current = true


func _setup_recon_view() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	for _step in range(18):
		await get_tree().create_timer(0.12).timeout
		if not is_instance_valid(d):
			return
		d.freeze = true
		d.linear_velocity = Vector3.ZERO
		d.angular_velocity = Vector3.ZERO
		if not _vehicles.is_empty() and is_instance_valid(_vehicles[0]):
			var v: Vehicle = _vehicles[0]
			var fwd := -v.global_transform.basis.z
			var side := v.global_transform.basis.x
			if v.kind == Vehicle.Kind.HELI:
				d.global_position = v.global_position + fwd * 14.5 + side * 6.5 + Vector3.UP * 2.2
				d.look_at(v.global_position + Vector3.UP * 0.5, Vector3.UP)
			elif v.kind == Vehicle.Kind.SHAHED:
				d.global_position = v.global_position + fwd * 5.2 + side * 2.6 + Vector3.UP * 1.1
				d.look_at(v.global_position + Vector3.UP * 0.2, Vector3.UP)
			else:
				d.global_position = v.global_position + fwd * 13.5 + side * 5.8 + Vector3.UP * 4.8
				d.look_at(v.global_position + Vector3.UP * 1.4, Vector3.UP)
		elif not _infantry_units.is_empty() and is_instance_valid(_infantry_units[0]):
			var u: Node3D = _infantry_units[0]
			var fwd := -u.global_transform.basis.z
			var side := u.global_transform.basis.x
			d.global_position = u.global_position + fwd * 7.5 + side * 3.2 + Vector3.UP * 3.0
			d.look_at(u.global_position + Vector3.UP * 1.0, Vector3.UP)


func _attach_fpv_rig() -> void:
	# Uses the real 3D drone model (DroneModel in res://Assets/Drones/ua_norm/)
	# instead of procedurally generating cylinders or wires.
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		var old := cam.get_node_or_null("FPVRig")
		if old != null:
			old.queue_free()
	var drone := get_node_or_null("Drone")
	if drone != null:
		_model_root = drone.get_node_or_null("DroneModel") as Node3D
	_fpv_rig = _model_root
	var p := DroneCatalog.preset(Global.drone_preset)
	_heavy_bomber = bool(p.get("heavy_bomber", false))
	_payload_ammo_left = int(p.get("payload", 0))
	_fpv_payload = _find_model_payload(_model_root)
	if _fpv_payload != null:
		_payload_rest = _fpv_payload.transform
	if _heavy_bomber and _fpv_payload != null:
		_bomb_nodes.clear()
		for child in _fpv_payload.get_children():
			if child is Node3D and String(child.name).begins_with("Bomb_"):
				_bomb_nodes.append(child as Node3D)
	var is_combat: bool = bool(p.get("combat", false))
	_payload_enabled = is_combat and DroneCatalog.supports_payload_actions(Global.drone_preset)
	if not _payload_enabled:
		_fpv_payload = null
		return

	var builtin_hud := get_node_or_null("Drone/HUD")
	if builtin_hud != null:
		var mode_label := builtin_hud.get_node_or_null("MarginContainer/FlightMode") as CanvasItem
		if mode_label != null:
			mode_label.visible = false
	_rig_visible = bool(p.get("combat", false)) and not bool(p.get("is_naval", false))
	_apply_fpv_rig()


## Removes the persistent loading card created by MainMenu/HelpScreen once the
## level has built its terrain and is ready to draw.
func _dismiss_global_loading_overlay() -> void:
	var overlay := get_tree().root.get_node_or_null("GlobalLoadingOverlay")
	if overlay == null:
		# QA: a directly launched scene has no menu loading card, but the
		# prewarm can still be exercised and timed.
		if OS.has_environment("DRONE_PREWARM_TEST"):
			await _prewarm_scene_rendering()
		return
	# Pay the shader/texture/shadow-cascade upload cost while the loading card
	# is still covering the screen.  Without this the first frame after the
	# player gains control stalls for 0.5-1.1 s when a new material set enters
	# the view.  QA screenshot/benchmark runs keep the old timing.
	if DisplayServer.get_name() != "headless" \
			and not OS.has_environment("SHOT_PATH") \
			and not OS.has_environment("DRONE_SCREENSHOT") \
			and not OS.has_environment("DRONE_FPS_BENCH"):
		await _prewarm_scene_rendering()
	await get_tree().process_frame
	await get_tree().process_frame
	overlay.queue_free()


## One full yaw sweep from the spawn (plus a look down at the apron) with the
## real environment and shadow setup.  Everything visible at take-off is drawn
## at least once behind the loading card, so the first controlled frame is
## smooth on both the discrete GPU and the Intel UHD target.
func _prewarm_scene_rendering() -> void:
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	var prev := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	cam.name = "PrewarmCamera"
	cam.fov = 90.0
	cam.near = 0.1
	cam.far = 3200.0
	add_child(cam)
	cam.current = true
	var eye := drone.global_position + Vector3(0.0, 0.5, 0.0)
	var worst_ms := 0.0
	# Warm the ambient-battle blast/smoke VFX once, behind the loading card.
	# The first distant explosion used to compile its particle/dust shaders in
	# flight and froze the frame for ~0.4 s every time the map loaded.
	var fx_script = load("res://combat/explosion.gd")
	if fx_script != null:
		var blast_at: Vector3 = eye + Vector3(0.0, 0.0, -45.0)
		if not frontline_map.is_empty():
			blast_at.y = FrontlineTerrainScript.height_at(frontline_map,
					blast_at.x, blast_at.z) + 0.4
		else:
			blast_at.y = _ground_y + 0.4
		var warm_explosion = fx_script.spawn(self, blast_at, 3.0, 0.0)
		fx_script.smoke_column(self, blast_at + Vector3.UP * 2.0, 1.0)
		cam.global_position = eye
		cam.look_at(blast_at, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		if warm_explosion != null and is_instance_valid(warm_explosion):
			warm_explosion.queue_free()
	# The combat SFX are synthesised as AudioStreamWAV in GDScript on first
	# use; generating them when the first distant shell lands froze a frame
	# for ~0.4 s.  Build the cache behind the loading card instead.
	var sfx_script = load("res://combat/sfx.gd")
	if sfx_script != null:
		sfx_script.boom_stream()
		sfx_script.shot_stream()
		sfx_script.rifle_stream()
		sfx_script.cannon_stream()
		sfx_script.autocannon_stream()
		sfx_script.artillery_stream()
		sfx_script.track_clatter_stream()
		sfx_script.fire_stream()
		sfx_script.servo_stream()
		sfx_script.radio_stream()
	await get_tree().process_frame
	for i in range(10):
		var yaw := TAU * float(i) / 10.0
		cam.global_position = eye
		cam.look_at(eye + Vector3(sin(yaw), -0.10, cos(yaw)) * 400.0, Vector3.UP)
		var t0 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
	# Extra downward frame warms the apron/road/deck materials right under the
	# drone, which are the nearest and most expensive to upload.
	cam.global_position = eye
	cam.look_at(eye + Vector3(0.0, -4.0, 1.0) * 10.0, Vector3.UP)
	var t1 := Time.get_ticks_usec()
	await get_tree().process_frame
	worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t1) / 1000.0)
	# Second pass from 90 m above the spawn: compile the factory complex, tree
	# lines and far batches that are not visible from the apron.  Without it the
	# first flight towards the factory still hit a 0.4-0.5 s shader hitch.
	var eye_high := eye + Vector3(0.0, 90.0, 0.0)
	for i in range(8):
		var yaw := TAU * float(i) / 8.0
		cam.global_position = eye_high
		cam.look_at(eye_high + Vector3(sin(yaw) * 400.0, -25.0,
				cos(yaw) * 400.0), Vector3.UP)
		var t2 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t2) / 1000.0)
	# Landmark sweep: render the hall, factory complex, cooling tower, silos and
	# map centre once so their shader variants are compiled behind the card.
	if not frontline_map.is_empty():
		var points: Array[Vector2] = []
		var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
		if not site.is_empty():
			points.append(site["center"] as Vector2)
		points.append(Vector2(-300.0, 160.0))
		points.append(Vector2(-232.0, -193.0))
		points.append(Vector2(146.0, 148.0))
		points.append(Vector2(0.0, 0.0))
		points.append(Vector2(-350.0, -350.0))
		points.append(Vector2(350.0, 350.0))
		# Open-top landmarks: compile the new hollow shells and their sooty
		# inner surfaces before the player reaches them.
		if frontline_map == "industrial":
			points.append(Vector2(-138.0, -146.0))
			points.append(Vector2(-55.0, 35.0))
			points.append(Vector2(155.0, 30.0))
			points.append(Vector2(15.0, -5.0))
			points.append(Vector2(-200.0, -285.0))
		elif frontline_map == "wetlands":
			points.append(Vector2(8.0, 34.0))
			points.append(Vector2(-60.0, -140.0))
		elif not site.is_empty():
			var c2: Vector2 = site["center"]
			var h2: Vector2 = site["half"]
			points.append(Vector2(c2.x + h2.x + 66.0, c2.y - 30.0))
			points.append(Vector2(c2.x + h2.x + 44.0, c2.y - h2.y - 10.0))
		for p in points:
			var gy: float = FrontlineTerrainScript.height_at(frontline_map, p.x, p.y)
			cam.global_position = Vector3(p.x + 38.0, gy + 42.0, p.y + 38.0)
			cam.look_at(Vector3(p.x, gy + 8.0, p.y), Vector3.UP)
			var t3 := Time.get_ticks_usec()
			await get_tree().process_frame
			await get_tree().process_frame
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t3) / 2000.0)
		# Main flight corridor: walk the take-off axis at 30 m and look ahead.
		# The first close-up of the hall/factory was still a 0.4-0.7 s shader
		# hitch even after the aerial sweep.
		var corridor_x := eye.x
		for i in range(16):
			var cz := eye.z + 120.0 - float(i) * 45.0
			var cy: float = FrontlineTerrainScript.height_at(frontline_map,
					corridor_x, cz)
			cam.global_position = Vector3(corridor_x, cy + 30.0, cz)
			cam.look_at(Vector3(corridor_x, cy + 18.0, cz - 100.0), Vector3.UP)
			var t4 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t4) / 1000.0)
		# Second corridor down the map centre line.  The QA camera (and a
		# player leaving the apron towards the factory) sees the hall roof and
		# its materials from this angle, which the spawn-axis pass missed.
		if not site.is_empty():
			var mid_x: float = (site["center"] as Vector2).x
			for i in range(18):
				var cz2 := 260.0 - float(i) * 32.0
				var cy2: float = FrontlineTerrainScript.height_at(frontline_map,
						mid_x, cz2)
				cam.global_position = Vector3(mid_x, cy2 + 30.0, cz2)
				cam.look_at(Vector3(mid_x, cy2 + 16.0, cz2 - 100.0), Vector3.UP)
				var t6 := Time.get_ticks_usec()
				await get_tree().process_frame
				worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t6) / 1000.0)
	else:
		# Valley/course: warm the three open-top smokestacks and the factory
		# complex from their actual mode-dependent positions.
		var base_z := -28.0
		if Global.play_mode == Global.PlayMode.SPEED:
			base_z = -20.0
		elif Global.play_mode != Global.PlayMode.TRAINING:
			base_z = -60.0
		var valley_points: Array[Vector2] = [
			Vector2(-24.0, base_z - 32.0), Vector2(-11.0, base_z - 35.0),
			Vector2(10.0, base_z - 34.0), Vector2(0.0, base_z),
			Vector2(28.0, base_z + 18.0), Vector2(-7.0, base_z - 5.0),
		]
		for p in valley_points:
			var gy := _ground_y
			cam.global_position = Vector3(p.x + 38.0, gy + 48.0, p.y + 38.0)
			cam.look_at(Vector3(p.x, gy + 10.0, p.y), Vector3.UP)
			var t5 := Time.get_ticks_usec()
			await get_tree().process_frame
			await get_tree().process_frame
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t5) / 2000.0)
	await get_tree().process_frame
	print("[PREWARM] yaw_sweep worst_frame_ms=%.1f" % worst_ms)
	if prev != null and is_instance_valid(prev):
		prev.current = true
	else:
		var fallback := drone.find_child("FPVCamera", true, false) as Camera3D
		if fallback != null:
			fallback.current = true
	cam.queue_free()


## Any airframe with a physical drop gets the wind-corrected CCIP sight.
func _has_bomb_sight() -> bool:
	if _heavy_bomber:
		return true
	return bool(DroneCatalog.preset(Global.drone_preset).get("has_drop", false))


## Per-unit munition mass for the current airframe (total load / rounds).
func _preset_payload_unit_mass() -> float:
	var p := DroneCatalog.preset(Global.drone_preset)
	var units := maxf(1.0, float(p.get("payload", 1)))
	var total := float(p.get("payload_mass", 0.0))
	if total <= 0.0:
		return 0.0
	return total / units


func _setup_bomber_systems() -> void:
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or _hud == null:
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	if not _heavy_bomber:
		# Any future dropper reuses the same CCIP with its own munition
		# profile instead of the bomber's 82 mm default.
		_bomb_kind = BombBallisticsScript.kind_for_mass(_preset_payload_unit_mass())
	var sight_script = load("res://combat/bomb_sight.gd")
	if sight_script != null and _bomb_sight == null:
		_bomb_sight = sight_script.new()
		_bomb_sight.level = self
		_bomb_sight.drone = drone
		_bomb_sight.kind = _bomb_kind
		_hud.add_child(_bomb_sight)
		_bomb_sight.set_bomb_view(false)
	if _model_root != null:
		_bomb_release_arm = _model_root.find_child("Bomb_Release_Arm", true, false) as Node3D


func _bomber_qa_demo() -> void:
	await get_tree().create_timer(2.0).timeout
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	var ground := FrontlineTerrainScript.height_at(frontline_map, 30.0, 0.0) \
			if not frontline_map.is_empty() else _ground_y
	drone.freeze = true
	drone.global_position = Vector3(30.0, ground + 180.0, 0.0)
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	drone.rotation = Vector3.ZERO
	await get_tree().create_timer(0.5).timeout
	if OS.has_environment("DRONE_BOMBER_THERMAL"):
		_vision_mode = VisionMode.FLIR_WHITE_HOT
		_apply_vision_mode()
		if _bomb_sight != null:
			_bomb_sight.set_thermal(true)
	await get_tree().create_timer(2.0).timeout
	_drop_heavy_bomb()
	# Second bomb after the first release animation, useful for the screenshot.
	await get_tree().create_timer(1.2).timeout
	_drop_heavy_bomb()


func _drop_heavy_bomb() -> void:
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or _bomb_nodes.is_empty():
		_set_flash("БОЄКОМПЛЕКТ ВИЧЕРПАНО — R ДЛЯ ПЕРЕЗАРЯДКИ" if not MenuUI.is_english()
				else "BOMBS EXPENDED — R TO REARM")
		return
	var altitude := drone.global_position.y - FrontlineTerrainScript.height_at(
			frontline_map, drone.global_position.x, drone.global_position.z) \
			if not frontline_map.is_empty() else drone.global_position.y - _ground_y
	if altitude < 8.0:
		_set_flash("ЗАНИЗЬКО ДЛЯ СКИДУ" if not MenuUI.is_english() else "TOO LOW TO RELEASE")
		return
	var bomb: Node3D = _bomb_nodes.pop_back()
	bomb.visible = false
	var payload := PayloadScript.new()
	payload.kind = _bomb_kind
	payload.mass_override = _preset_payload_unit_mass()
	if OS.has_environment("DRONE_PAYLOAD_DEBUG"):
		print("[PAYLOAD] heavy kind=%s unit_mass=%.2f" % [
			payload.kind, payload.mass_override])
	payload.damage = BombBallisticsScript.damage_for(_bomb_kind)
	payload.blast_radius = BombBallisticsScript.blast_for(_bomb_kind)
	var spawn := bomb.global_position
	add_child(payload)
	payload.global_position = spawn
	payload.linear_velocity = drone.linear_velocity + Vector3.DOWN * 0.8
	payload.angular_velocity = Vector3(randf_range(-0.8, 0.8),
			randf_range(-1.2, 1.2), randf_range(-0.8, 0.8))
	payload.add_collision_exception_with(drone)
	payload.exploded.connect(func() -> void:
		if OS.has_environment("DRONE_PAYLOAD_DEBUG"):
			print("[PAYLOAD] heavy bomb detonated on contact")
		var cs := get_node_or_null("CombatSystem")
		if cs != null and cs.has_method("_on_payload_exploded"):
			cs.call("_on_payload_exploded"))
	var cs_now := get_node_or_null("CombatSystem")
	if cs_now != null:
		cs_now.set("ammo", _bomb_nodes.size())
	if drone.has_method("drop_payload_action"):
		drone.call("drop_payload_action")
	_bomb_cooldown = 0.55
	if _bomb_release_arm != null:
		var tw := create_tween()
		tw.tween_property(_bomb_release_arm, "rotation_degrees:x",
				_bomb_release_arm.rotation_degrees.x + 55.0, 0.08)
		tw.tween_property(_bomb_release_arm, "rotation_degrees:x",
				_bomb_release_arm.rotation_degrees.x - 55.0, 0.22)
	CombatSfxScript.play_drop(self, spawn, -2.0)
	var label := "82-мм міна" if _bomb_kind == "82mm" else _bomb_kind
	_set_message("СКИД: %s · залишилось %d" % [label, _bomb_nodes.size()])
	if _bomb_nodes.is_empty():
		_set_flash("БОЄКОМПЛЕКТ ВИЧЕРПАНО" if not MenuUI.is_english()
				else "BOMBS EXPENDED")


func _find_model_payload(node: Node) -> Node3D:
	if node == null:
		return null
	var node_name := String(node.name).to_lower()
	# "BombBay" (double b) is the authored node name.  The old single-b test
	# never matched, so the bomber's payload rack was never populated and G
	# silently did nothing.  Accept the common spellings for imported GLBs.
	if node is Node3D and (node_name == "bombbay" or node_name == "bomb_bay" \
			or node_name == "bomb bay" or node_name.begins_with("bombbay_")):
		# The heavy bomber keeps all four mines under one BombBay node.
		# Returning the container keeps the whole rack visible in FPV and lets
		# a drop hide the individual bomb instances.
		return node as Node3D
	if node is MeshInstance3D:
		var n := String(node.name).to_lower()
		if n.contains("morkovka_morkva") or n.contains("pg7") or n == "object_4" \
				or n.contains("warhead"):
			return node as Node3D
	for child in node.get_children():
		var found := _find_model_payload(child)
		if found != null:
			return found
	return null


func _configure_model_for_camera(node: Node, is_fpv: bool,
		only_payload: bool = false) -> void:
	if node == null:
		return
	if node.is_in_group("drone_prop_pivot") or node.name == "PropellerAssembly":
		if node is Node3D:
			var pn := String(node.name).to_lower()
			var front_pivot := pn.contains("fl") or pn.contains("fr") \
					or pn.ends_with("_0") or pn.ends_with("_1")
			(node as Node3D).visible = (not is_fpv) or (only_payload and front_pivot)
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if is_fpv and only_payload:
			# Combat FPV: keep the warhead, camera/nose housing and the front
			# propeller/arm silhouettes visible (the authentic FPV framing).
			# Fixed-wing recon drones show their chin camera instead of an
			# empty screen.
			var n2 := String(mi.name).to_lower()
			if _heavy_bomber:
				# The 2.8 m six-rotor airframe (battery cases, tanks, Starlink
				# mast) sat directly in front of the bomber lens.  Keep only
				# the external ordnance and its rack so the crew can see what
				# is left and judge the release, with a clean view of the
				# target beyond.
				mi.visible = _fpv_payload != null and _is_under(mi, _fpv_payload)
				return
			var is_warhead_part := n2.contains("morkva") or n2.contains("provoloka") \
					or n2.contains("styazka") or n2.contains("detonator") \
					or n2.contains("warhead")
			var is_front_part := n2.contains("propeller_fl") or n2.contains("propeller_fr") \
					or n2.contains("propeller_0") or n2.contains("propeller_1") \
					or n2.contains("motor_fl") or n2.contains("motor_fr") \
					or n2.contains("arm_fl") or n2.contains("arm_fr") \
					or n2.contains("front_arm") or n2.contains("front_frame")
			var is_camera_part := n2.contains("cam") or n2.contains("lens") \
					or n2.contains("glass") or n2.contains("thermal")
			var is_nose_part := not _heavy_bomber and (n2.contains("nose") \
					or n2.contains("chin") or n2.contains("pitot"))
			mi.visible = (_fpv_payload != null and _is_under(mi, _fpv_payload)) \
					or is_warhead_part or is_front_part \
					or is_camera_part or is_nose_part
			return
		var n := String(mi.name).to_lower()
		var is_cam_mesh := n.contains("camera_low") or n.contains("camera_holder") \
				or n.contains("bolt_cam") or n.contains("dji_avata2_lens") \
				or n.contains("dji_avata2_gimbal_housing") or n.contains("cam")
		var is_prop_mesh := n.contains("propeller") or n.contains("rotor_korpus") \
				or n.contains("motor_bl") or n.contains("motor_br") \
				or n.contains("motor_fl") or n.contains("motor_fr") \
				or n.contains("prop_blur")
		if is_cam_mesh or is_prop_mesh:
			mi.visible = not is_fpv
	for child in node.get_children():
		_configure_model_for_camera(child, is_fpv, only_payload)


## Edge-triggered poll for payload switches.  Button/key actions are handled
## immediately in `_input`; this path covers radios that expose a latching AUX
## switch as a raw Joypad Axis.  No timer or delayed coroutine is involved:
## the release/detonate method runs on the first physics tick after the toggle
## crosses its deadzone (8 ms at the project's 120 Hz physics rate).
func _poll_payload_switch_edges() -> void:
	if _chain_brief != null and _chain_brief.visible:
		return
	var drop_now := Input.is_action_pressed("deploy_payload")
	var trigger_now := Input.is_action_pressed("activate_payload")
	if not _payload_axis_poll_ready:
		# Swallow a switch that was already ON before the sortie started.
		_payload_axis_drop_prev = drop_now
		_payload_axis_trigger_prev = trigger_now
		_payload_axis_poll_ready = true
		return
	if drop_now and not _payload_axis_drop_prev:
		_drop_fpv_payload()
	if trigger_now and not _payload_axis_trigger_prev:
		_activate_fpv_payload()
	_payload_axis_drop_prev = drop_now
	_payload_axis_trigger_prev = trigger_now


func _drop_fpv_payload() -> void:
	if not _payload_enabled:
		return
	if _bomb_cooldown > 0.0:
		return
	if _heavy_bomber:
		_drop_heavy_bomb()
		return
	if _payload_dropped:
		return

	# In a live combat sortie CombatSystem owns ammo/scoring/health.  It used
	# to be guarded by a non-existent `active` property, so every drop fell
	# through to the freestyle path and the HUD ammo never decremented.
	var cs := get_node_or_null("CombatSystem")
	if Global.play_mode == Global.PlayMode.COMBAT:
		if cs == null or bool(cs.get("_lost")):
			return
		var dropped := bool(cs.call("drop_payload"))
		if not dropped:
			# Not armed / too low / no ammo: CombatSystem already flashed the
			# reason.  Do not hide the pylon or consume a local round.
			return
		_payload_dropped = true
		_bomb_cooldown = 0.35
		_payload_ammo_left = int(cs.get("ammo"))
		_hide_fpv_payload()
		var cs_timer := get_tree().create_timer(0.75)
		cs_timer.timeout.connect(_reset_fpv_payload)
		return

	# Standalone physical payload drop (TRAINING / SPEED freestyle practice)
	if _payload_ammo_left <= 0:
		return
	_payload_dropped = true
	_payload_ammo_left = maxi(_payload_ammo_left - 1, 0)
	_bomb_cooldown = 0.35
	_hide_fpv_payload()

	var drone := get_node_or_null("Drone") as Drone
	var payload := PayloadScript.new()
	var unit_mass := _preset_payload_unit_mass()
	payload.kind = BombBallisticsScript.kind_for_mass(unit_mass)
	payload.mass_override = unit_mass
	payload.damage = 480.0
	payload.blast_radius = 9.5
	add_child(payload)
	if OS.has_environment("DRONE_PAYLOAD_DEBUG"):
		print("[PAYLOAD] preset=%d kind=%s unit_mass=%.2f" % [
			Global.drone_preset, payload.kind, unit_mass])

	var drop_pos := global_position + Vector3.DOWN * 0.4
	var drop_vel := Vector3.DOWN * 1.5
	if drone != null:
		var forward := -drone.global_transform.basis.z
		drop_pos = drone.global_position + Vector3.DOWN * 0.35 + forward * 0.25
		drop_vel = drone.linear_velocity + forward * 2.5 + Vector3.DOWN * 1.0
		payload.add_collision_exception_with(drone)
		if drone.has_method("drop_payload_action"):
			var dropped_w: float = drone.drop_payload_action()
			if dropped_w > 0.001:
				_set_message("СКИД: -%.2f кг (ТЯГА ЗРОСЛА)" % dropped_w)

	payload.global_position = drop_pos
	payload.linear_velocity = drop_vel
	payload.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0), randf_range(-3.0, 3.0))
	CombatSfxScript.play_drop(self, drop_pos, -2.5)

	var timer := get_tree().create_timer(0.75)
	timer.timeout.connect(_reset_fpv_payload)


func _hide_fpv_payload() -> void:
	if _fpv_payload != null and is_instance_valid(_fpv_payload):
		_fpv_payload.visible = false


## Kamikaze / loitering warhead activation (the second payload button, next to
## the bomber's drop).  Detonates the drone's warhead where it is, damages every
## combat target in the blast radius and respawns the operator after a short
## pause.  Bombers with a physical drop are told to use the drop button.
func _activate_fpv_payload() -> void:
	if not _payload_enabled or _payload_dropped:
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	if bool(p.get("has_drop", false)):
		_set_flash("У цього дрона немає БЧ — використайте СКИД (G)")
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or not is_instance_valid(drone):
		return
	_payload_dropped = true
	var at := drone.global_position
	var naval := bool(p.get("is_naval", false))
	var blast := 34.0 if naval else 14.0
	var dmg := 9000.0 if naval else 2600.0
	ExplosionScript.spawn(self, at + Vector3.UP * 0.4, blast, dmg)
	CombatSfxScript.play_boom(self, at, 2.0)
	_set_flash("БЧ АКТИВОВАНО — ЦІЛЬ УРАЖЕНО" if naval else "БЧ АКТИВОВАНО")
	# Take the drone out of the simulation without triggering a crash message.
	drone.visible = false
	drone.freeze = true
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(drone):
			return
		drone.visible = true
		drone.freeze = false
		_payload_dropped = false
		_reset_fpv_payload()
		_respawn_and_rearm())


func _reset_fpv_payload() -> void:
	_payload_dropped = false
	if _fpv_payload == null or not is_instance_valid(_fpv_payload):
		return
	if _heavy_bomber:
		_bomb_nodes.clear()
		for child in _fpv_payload.get_children():
			if child is Node3D and String(child.name).begins_with("Bomb_"):
				(child as Node3D).visible = true
				_bomb_nodes.append(child as Node3D)
		_payload_enabled = true
		var cs := get_node_or_null("CombatSystem")
		if cs != null:
			cs.set("ammo", _bomb_nodes.size())
		return
	_fpv_payload.transform = _payload_rest
	var has_drop := bool(DroneCatalog.preset(Global.drone_preset).get(
			"has_drop", false))
	var remaining := _payload_ammo_left
	if has_drop and Global.play_mode == Global.PlayMode.COMBAT:
		var cs_ammo := get_node_or_null("CombatSystem")
		if cs_ammo != null and cs_ammo.get("ammo") != null:
			remaining = int(cs_ammo.get("ammo"))
	_fpv_payload.visible = _payload_enabled and (not has_drop or remaining > 0)


func _apply_fpv_rig() -> void:
	var drone := get_node_or_null("Drone")
	if drone != null:
		var root := drone.get_node_or_null("DroneModel") as Node3D
		if root != null:
			_model_root = root
			_fpv_rig = root
	_refresh_model_visibility()


func _apply_osd() -> void:
	if _hud != null:
		_hud.visible = _osd_visible
	var combat_hud := get_node_or_null("CombatHUD")
	if combat_hud is CanvasLayer:
		# Target/HP readouts belong to combat only; keep speed/training clean.
		(combat_hud as CanvasLayer).visible = _osd_visible \
				and Global.play_mode == Global.PlayMode.COMBAT
		for sub in ["Root/TopRight", "Root/Message", "Root/Hint"]:
			var item := combat_hud.get_node_or_null(sub) as CanvasItem
			if item != null:
				item.visible = false
	if OS.has_environment("SHOT_PATH"):
		var help := get_node_or_null("Help") as CanvasLayer
		if help != null:
			help.visible = false
		if _hud_message != null:
			_hud_message.visible = false
	var drone := get_node_or_null("Drone")
	if drone != null:
		if drone.has_method("_on_hud_config_updated"):
			drone._on_hud_config_updated()
		var drone_hud = drone.get("hud")
		if drone_hud is CanvasItem:
			var is_fpv := camera != null and camera.name == "FPVCamera"
			(drone_hud as CanvasItem).visible = _osd_visible and is_fpv
	_apply_stick_overlay()


func _on_touch_mode_changed(_using_touch: bool) -> void:
	# Touch mode has its own sticks at the screen corners; the centre-bottom
	# radio visualiser would duplicate them.
	_apply_stick_overlay()


## Bottom stick indicators in every mission, tied to the "Індикатори стіків"
## HUD switch. The drone's built-in stick widgets are hidden so only these show.
func _apply_stick_overlay() -> void:
	var on := bool(GameSettings.hud_config.get("sticks", true))
	if _touch_controls != null and bool(_touch_controls.get("enabled")) \
			and bool(_touch_controls.get("touch_mode")) \
			and not bool(GameSettings.hud_config.get("mobile_stream_mode", false)):
		on = false
	if _stick_overlay != null:
		_stick_overlay.visible = on
	var drone := get_node_or_null("Drone")
	if drone != null:
		var drone_hud = drone.get("hud")
		if drone_hud != null and drone_hud.has_method("show_component"):
			drone_hud.show_component(HUD.Component.STICKS, false)


func _build_results() -> void:
	_results = Control.new()
	_results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results.process_mode = Node.PROCESS_MODE_ALWAYS
	_results.visible = false
	_results.theme = MenuUI.theme()
	_hud.add_child(_results)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.06, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_results.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_results.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = MenuUI.PANEL
	panel_sb.border_color = MenuUI.BORDER_HIGHLIGHT
	panel_sb.set_border_width_all(2)
	panel_sb.border_width_left = 6
	panel_sb.set_corner_radius_all(3)
	panel_sb.content_margin_left = 36
	panel_sb.content_margin_right = 36
	panel_sb.content_margin_top = 28
	panel_sb.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = "МІСІЮ ВИКОНАНО"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_results_title = title

	box.add_child(MenuUI.hline())

	_results_stats = Label.new()
	_results_stats.add_theme_font_size_override("font_size", 22)
	_results_stats.add_theme_color_override("font_color", MenuUI.TEXT)
	_results_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_stats)

	box.add_child(MenuUI.hline())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	_next_mission_btn = Button.new()
	_next_mission_btn.text = "НАСТУПНА МІСІЯ  →"
	_next_mission_btn.custom_minimum_size = Vector2(0, 52)
	_next_mission_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_mission_btn.visible = false
	_next_mission_btn.pressed.connect(_on_next_mission_pressed)
	buttons.add_child(_next_mission_btn)
	var retry := Button.new()
	retry.text = "ПРОЙТИ ЩЕ РАЗ"
	retry.custom_minimum_size = Vector2(0, 52)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(_on_retry_pressed)
	buttons.add_child(retry)
	var menu := Button.new()
	menu.text = "ГОЛОВНЕ МЕНЮ"
	menu.custom_minimum_size = Vector2(0, 52)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(_on_menu_pressed)
	buttons.add_child(menu)
	box.add_child(buttons)

	_next_mission_btn.focus_neighbor_right = retry.get_path()
	retry.focus_neighbor_left = _next_mission_btn.get_path()
	retry.focus_neighbor_right = menu.get_path()
	menu.focus_neighbor_left = retry.get_path()
	retry.grab_focus()


func _build_chain_briefing() -> void:
	_chain_brief = Control.new()
	_chain_brief.name = "ChainBriefing"
	_chain_brief.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chain_brief.process_mode = Node.PROCESS_MODE_ALWAYS
	_chain_brief.visible = false
	_chain_brief.theme = MenuUI.theme()
	_hud.add_child(_chain_brief)

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.025, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chain_brief.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain_brief.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	panel.add_theme_stylebox_override("panel",
			MenuUI.feel_style(MenuUI.PANEL, MenuUI.FPV_GREEN, 2, 3, 30, 24))
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var code := Label.new()
	code.text = "БРИФІНГ КАМПАНІЇ  ·  TAC-0%d / 5" % Global.combat_mission
	code.add_theme_font_size_override("font_size", 14)
	code.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	box.add_child(code)

	var title := Label.new()
	title.text = _combat_mission_banner(Global.combat_mission)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 4)
	box.add_child(title)

	box.add_child(MenuUI.hline())

	var tasks := Label.new()
	tasks.text = _mission_chain_tasks(Global.combat_mission)
	tasks.add_theme_font_size_override("font_size", 15)
	tasks.add_theme_color_override("font_color", MenuUI.TEXT)
	tasks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tasks)

	var phases := Label.new()
	phases.text = _mission_phase_plan_text(Global.combat_mission)
	phases.add_theme_font_size_override("font_size", 13)
	phases.add_theme_color_override("font_color", MenuUI.FPV_CYAN)
	phases.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(phases)

	var progress := Label.new()
	progress.text = "КАМПАНІЯ %d/5 · ★ %d/15 · СКЛАДНІСТЬ: %s · ЛІМІТ: %s" % [
		Global.campaign_completed_count(), Global.campaign_stars_total(),
		Global.get_difficulty_name(), _format_countdown(Global.get_difficulty_time_limit())]
	progress.add_theme_font_size_override("font_size", 12)
	progress.add_theme_color_override("font_color", MenuUI.FPV_MUTED)
	box.add_child(progress)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_chain_brief_start = Button.new()
	_chain_brief_start.text = "  ▶  ПОЧАТИ ВИЛІТ  "
	_chain_brief_start.custom_minimum_size = Vector2(280, 48)
	_chain_brief_start.add_theme_font_size_override("font_size", 16)
	_chain_brief_start.add_theme_color_override("font_color", MenuUI.BUTTON_ACTIVE_TEXT)
	_chain_brief_start.add_theme_stylebox_override("normal",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE, MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_chain_brief_start.add_theme_stylebox_override("hover",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.lightened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_chain_brief_start.add_theme_stylebox_override("pressed",
			MenuUI.feel_style(MenuUI.BUTTON_ACTIVE.darkened(0.08), MenuUI.FPV_GREEN, 2, 1, 14, 6))
	_chain_brief_start.pressed.connect(_close_chain_briefing)
	actions.add_child(_chain_brief_start)


func _mission_chain_tasks(mission_id: int) -> String:
	match mission_id:
		1:
			return "ЗАВДАННЯ: виявити та знищити 6 піхотинців у лісосмузі.\nЦІЛІ: піхота, окопи, кулеметні точки."
		2:
			return "ЗАВДАННЯ: знищити танк Т-72 та БТР-90, що маневрують біля заводу.\nЦІЛІ: 2 одиниці бронетехніки + піхота прикриття."
		3:
			return "ЗАВДАННЯ: перехопити ударний гелікоптер і знищити мобільну ППО.\nЦІЛІ: гелікоптер, ЗРК, прикриття."
		4:
			return "ЗАВДАННЯ: перехопити два «Шахеди-136» на маршруті.\nЦІЛІ: 2 БПЛА, ЗРК і БМП прикриття."
		_:
			return "ЗАВДАННЯ: прорвати бонові загородження та уразити машинний зал Кримської ГЕС.\nБОРТ: USV «МАГУРА-Х» · один удар вирішує операцію."


func _mission_phase_plan_text(mission_id: int) -> String:
	if mission_id >= 5:
		return "ФАЗИ: УДАР (вийти на рубіж атаки) → ВИХІД (покинути зону ураження)."
	return "ФАЗИ: РОЗВІДКА (підлетіти до зони та утримати 3 с) → УДАР (знищити цілі) → ВИХІД (повернутися в зону евакуації)."


func _show_chain_briefing() -> void:
	if _chain_brief == null:
		return
	if OS.has_environment("DRONE_SKIP_BRIEFING"):
		return
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_chain_brief.visible = true
	if _chain_brief_start != null:
		_chain_brief_start.grab_focus()


func _close_chain_briefing() -> void:
	if _chain_brief != null:
		_chain_brief.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_flash("SPACE — УВІМКНУТИ ДВИГУНИ · ПІСЛЯ АРМУ ПОЧНЕТЬСЯ МІСІЯ")


func _set_flash(text: String) -> void:
	if _hud_message != null:
		_hud_message.text = text
	_flash_token += 1
	var token := _flash_token
	# Short-lived callouts (weather, gates, boost) must not camp in the middle
	# of the screen for the whole flight.
	await get_tree().create_timer(3.0).timeout
	if token == _flash_token and _hud_message != null and _hud_message.text == text:
		_hud_message.text = ""


func _set_message(text: String) -> void:
	if _hud_message != null:
		_hud_message.text = text


func _format_time(value: float) -> String:
	var minutes := int(value) / 60
	var seconds := int(value) % 60
	var hundredths := int((value - floor(value)) * 100.0)
	return "%02d:%02d.%02d" % [minutes, seconds, hundredths]


func _format_countdown(seconds_left: float) -> String:
	var whole := maxi(0, int(ceil(seconds_left)))
	var minutes := whole / 60
	var seconds := whole % 60
	return "%02d:%02d" % [minutes, seconds]


func _update_nav_marker() -> void:
	if _nav_marker == null:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		_nav_marker.text = ""
		return
	if not _mission_started:
		var idle_text := "« ГОТОВИЙ ДО СТАРТУ — SPACE ДЛЯ ЗАПУСКУ »"
		if Global.play_mode == Global.PlayMode.CHAOS:
			idle_text = "« БІЙ УЖЕ ЙДЕ »"
		if _nav_marker.text != idle_text:
			_nav_marker.text = idle_text
			_nav_marker.add_theme_color_override("font_color", Color(0.92, 0.69, 0.21, 0.95))
		return
	if _mission_finished:
		if not _nav_marker.text.is_empty():
			_nav_marker.text = ""
		return

	var target_pos := Vector3.ZERO
	var target_found := false
	var target_label := ""

	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			if _flight_school != null:
				var info: Dictionary = _flight_school.get_current_target_info()
				if info.has("pos") and info["pos"] != Vector3.ZERO:
					target_pos = info["pos"]
					target_found = true
					target_label = str(info.get("label", "ЦІЛЬ"))
		Global.PlayMode.TRAINING:
			for r in _training_rings:
				if is_instance_valid(r) and r.visible:
					target_pos = r.global_position
					target_found = true
					target_label = "ВОРОТА %d/%d" % [_rings_passed + 1, _rings_total]
					var m := _checkpoint_visual(r)
					if m != null and m.material_override is StandardMaterial3D:
						var mat := m.material_override as StandardMaterial3D
						mat.emission_energy_multiplier = 3.5 + sin(Time.get_ticks_msec() * 0.008) * 1.8
						mat.emission = Color(0.2, 1.0, 0.4)
					break
		Global.PlayMode.SPEED:
			if _speed_next < _speed_checkpoints.size():
				var cp := _speed_checkpoints[_speed_next]
				if is_instance_valid(cp):
					target_pos = cp.global_position
					target_found = true
					target_label = "КП %d/%d" % [_speed_next + 1, _speed_checkpoints.size()]
		_:
			var special_info := get_special_objective_info()
			if not special_info.is_empty() and special_info.has("pos"):
				target_pos = special_info["pos"]
				target_found = true
				target_label = str(special_info.get("label", "ЦІЛЬ"))
				if bool(special_info.get("show_progress", true)):
					target_label += " %d%%" % int(float(special_info.get("progress", 0.0)) * 100.0)
			else:
				var phase_info := get_mission_phase_info()
				if not phase_info.is_empty() and phase_info.has("pos"):
					target_pos = phase_info["pos"]
					target_found = true
					target_label = "%s %d%%" % [str(phase_info.get("label", "ЦІЛЬ")),
							int(float(phase_info.get("progress", 0.0)) * 100.0)]
				else:
					var min_d := 1e9
					var best_t: Node3D = null
					for t in get_tree().get_nodes_in_group("combat_target"):
						if is_instance_valid(t) and t.visible:
							var d := drone.global_position.distance_to(t.global_position)
							if d < min_d:
								min_d = d
								best_t = t
					if best_t != null:
						target_pos = best_t.global_position
						target_found = true
						target_label = "УДАР" if not phase_info.is_empty() else "ЦІЛЬ"

	if not target_found:
		_nav_marker.text = ""
		return

	var dist := drone.global_position.distance_to(target_pos)
	var local_tgt := drone.global_transform.affine_inverse() * target_pos
	var angle := atan2(local_tgt.x, -local_tgt.z)
	var deg := rad_to_deg(angle)

	var dir_arrow := "▲"
	var dir_text := "ПРЯМО"
	if deg > 120.0 or deg < -120.0:
		dir_arrow = "▼"
		dir_text = "ПОЗАДУ"
	elif deg > 65.0:
		dir_arrow = "►"
		dir_text = "ПРАВОРУЧ"
	elif deg > 20.0:
		dir_arrow = "▲►"
		dir_text = "ПРАВОРУЧ"
	elif deg < -65.0:
		dir_arrow = "◄"
		dir_text = "ЛІВОРУЧ"
	elif deg < -20.0:
		dir_arrow = "◄▲"
		dir_text = "ЛІВОРУЧ"

	var alt_diff := target_pos.y - drone.global_position.y
	var alt_hint := ""
	if alt_diff > 8.0:
		alt_hint = " [↑ +%dм]" % int(alt_diff)
	elif alt_diff < -8.0:
		alt_hint = " [↓ %dм]" % int(alt_diff)

	_nav_marker.text = "%s  %s: %s  %dм%s" % [
		dir_arrow, target_label, dir_text, int(dist), alt_hint
	]
	_nav_marker.add_theme_color_override("font_color", Color(1.0, 0.90, 0.35, 0.95))


func _process(delta: float) -> void:
	if _bomb_cooldown > 0.0:
		_bomb_cooldown = maxf(_bomb_cooldown - delta, 0.0)
	if _mission_started and not _mission_finished:
		_mission_time += delta
		var combat_time_limit: float = Global.get_difficulty_time_limit()
		if Global.play_mode == Global.PlayMode.COMBAT \
				and _mission_time >= combat_time_limit:
			_finish_mission("ЧАС ВИЙШОВ — ЗАВДАННЯ НЕ ВИКОНАНО", true)
		_update_mission_phases(delta)
		if Global.special_mission > 0:
			_update_special_mission(delta)
	# The OSD is shaped by the text server.  Refreshing formatted strings at
	# 120 Hz burns CPU for readouts that only change once a second or on a hit;
	# 12 Hz matches the refresh of a real Betaflight OSD.
	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.083
		_update_hud()
		if _elrs_status_label != null:
			if _touch_controls != null \
					and bool(_touch_controls.get("enabled")) \
					and bool(_touch_controls.get("touch_mode")):
				_elrs_status_label.text = "СЕНСОРНЕ КЕРУВАННЯ"
			else:
				_elrs_status_label.text = ElrsWifiInput.status_text
	_update_audio_mix(delta)
	# Audio-bus trimming and the nav marker only need human-perceptible update
	# rates.  Running them at 120 Hz changed four AudioServer buses and shaped
	# a Label every frame, which is pure heat on the UHD target.
	_audio_priority_tick -= delta
	if _audio_priority_tick <= 0.0:
		_audio_priority_tick = 0.1
		_update_audio_priority(0.1)
	_update_threats(delta)
	_nav_tick -= delta
	if _nav_tick <= 0.0:
		_nav_tick = 0.1
		_update_nav_marker()
	_update_telemetry(delta)
	# Safety net: if a menu transition leaves the flight HUD hidden while the
	# game is live, restore it on the next frame.  Pause/results/clean-shot
	# intentionally hide it only while paused or with _osd_visible=false.
	if _hud != null and _osd_visible and not get_tree().paused and not _hud.visible:
		_hud.visible = true
	if _flight_school != null and is_instance_valid(_flight_school):
		_flight_school.update_flight_school(delta)

	# Storm Thunder & Lightning simulation
	if _weather == 2:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = randf_range(8.0, 18.0)
			_lightning_flash_timer = randf_range(0.10, 0.25)
			var d_node := get_node_or_null("Drone") as Node3D
			var thunder_pos := d_node.global_position if d_node != null else Vector3.ZERO
			thunder_pos += Vector3(randf_range(-250, 250), randf_range(120, 300), randf_range(-250, 250))
			CombatSfxScript.play_thunder(self, thunder_pos, 8.0)

	if _lightning_flash_timer > 0.0:
		_lightning_flash_timer -= delta
		if _lightning_light != null:
			_lightning_light.light_energy = _sun_light_energy_default * 3.5
	elif _lightning_light != null and _weather == 2:
		_lightning_light.light_energy = _sun_light_energy_default * 0.35
	if _stick_overlay != null and _stick_overlay.visible:
		_stick_overlay.set_sticks(_read_left_stick(), _read_right_stick())
	if _diag != null and _diag_on:
		_diag.visible = true
		_diag.text = _diag_text()
	# Propellers are animated by Drone._process from the real motor RPM.
	# Animating them here as well rotated every pivot twice per frame.


## Frame-based QA flight test (no timers, cannot hang): arms, applies throttle
## and prints the altitude every 30 frames. Enabled with DRONE_DIAG=1.
func _physics_process(delta: float) -> void:
	_update_wind_simulation(delta)
	_poll_payload_switch_edges()
	if OS.has_environment("DRONE_PROBE") and Engine.get_physics_frames() == 30:
		for zz in range(-300, 500, 50):
			var row := ""
			for xx in range(-300, 301, 50):
				var q := PhysicsRayQueryParameters3D.create(Vector3(xx, 400, zz), Vector3(xx, -200, zz)); q.collision_mask = 1; var h := get_world_3d().direct_space_state.intersect_ray(q); row += " %s:%.1f" % [str(h["collider"].name).substr(0, 10) if not h.is_empty() else "-", h["position"].y if not h.is_empty() else 0.0]
			print("PROBE z=%d: %s" % [zz, row])
	# Active safety guard: catch drone only if it falls completely off the map into the void (Y < -25m)
	var drone_body := get_node_or_null("Drone") as Drone
	if drone_body != null and is_instance_valid(drone_body):
		# Position-derived closing speed survives the contact solver zeroing the
		# rigid-body velocity on the very frame a wall/terrain is hit.
		var step_speed := drone_body.global_position.distance_to(_drone_prev_pos) \
				/ maxf(delta, 0.0001)
		_drone_last_speed = clampf(step_speed, 0.0, 80.0)
		_drone_prev_pos = drone_body.global_position
		# Keep a short peak memory.  The contact signal is emitted after the
		# solver has already zeroed the body velocity, so the instantaneous
		# value at that moment is not the closing speed.
		_drone_peak_speed = maxf(_drone_peak_speed - 30.0 * delta, _drone_last_speed)
		var floor_limit: float = -25.0
		if drone_body.global_position.y < floor_limit:
			var safe_y := _find_ground_y(drone_body.global_position.x, drone_body.global_position.z) + 1.2
			drone_body.global_position.y = maxf(safe_y, 2.0)
			drone_body.linear_velocity = Vector3.ZERO
			drone_body.angular_velocity = Vector3.ZERO
	_enforce_ground_clearance(delta)

	# QA hook: drop the drone 5 m under the terrain and verify that the guard
	# restores it.  Only runs when DRONE_GROUND_GUARD_TEST is set.
	if OS.has_environment("DRONE_GROUND_GUARD_TEST") and not frontline_map.is_empty():
		var gf := Engine.get_physics_frames()
		if gf == 90:
			var dtest := get_node_or_null("Drone") as Drone
			if dtest != null:
				var pp := dtest.global_position
				dtest.global_position = Vector3(pp.x,
						FrontlineTerrainScript.height_at(frontline_map, pp.x, pp.z) - 5.0,
						pp.z)
		elif gf == 150:
			var dcheck := get_node_or_null("Drone") as Drone
			if dcheck != null:
				var gy := FrontlineTerrainScript.height_at(frontline_map,
						dcheck.global_position.x, dcheck.global_position.z)
				print("[GUARD] y=%.2f ground=%.2f %s" % [dcheck.global_position.y, gy,
						"PASS" if dcheck.global_position.y >= gy - 1.0 else "FAIL"])
			get_tree().quit()

	if _test_frames < 0:
		return
	_test_frames += 1
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var radio := get_node_or_null("RadioController")
	var use_radio := OS.has_environment("DRONE_DIAG_RADIO")
	if _test_frames == 5:
		_place_drone_over_ground()
	if _test_frames == 8:
		if radio != null and not use_radio:
			radio.set_physics_process(false)
	if _test_frames == 10:
		var space := InputEventKey.new()
		space.keycode = KEY_SPACE
		space.physical_keycode = KEY_SPACE
		space.pressed = true
		Input.parse_input_event(space)
	if _test_frames == 12:
		d.flight_controller.change_flight_mode(FlightController.FlightMode.RATE)
		_test_y0 = d.global_position.y
		_test_max = _test_y0
		if radio != null and use_radio:
			radio.test_throttle = 0.55
	if _test_frames >= 12:
		if not use_radio:
			d.flight_controller.input = [0.55, 0.0, 0.0, 0.0]
		_test_max = maxf(_test_max, d.global_position.y)
	if _test_frames >= 12 and _test_frames % 30 == 0:
		var rpm := 0.0
		var rt := 0.0
		if not d.motors.is_empty():
			rpm = d.motors[0].get_rpm()
			rt = d.motors[0].get_rpm_target()
		var tt := -1.0
		if radio != null:
			tt = float(radio.get("test_throttle"))
		print("[DIAG] f=", _test_frames, " armed=", d.flight_controller.state_armed,
				" mode=", d.flight_controller.flight_mode,
				" in0=", roundf(float(d.flight_controller.input[0]) * 100.0) / 100.0,
				" rpm=", roundf(rpm), " target=", roundf(rt),
				" tt=", roundf(tt * 100.0) / 100.0,
				" y=", roundf(d.global_position.y * 100.0) / 100.0,
				" vy=", roundf(d.linear_velocity.y * 100.0) / 100.0)
	if _test_frames >= 165:
		var rise := _test_max - _test_y0
		print("[DIAG] rise=", roundf(rise * 100.0) / 100.0, " ",
				"FLY-OK" if rise > 0.5 else "NO-LIFT")
		get_tree().quit()


## Keeps the drone above the analytic surface of the front-line terrain.
##
## The collision audit already reports zero ray misses, but a fast dive can hit
## a concave-chunk seam between two physics ticks and tunnel through for a
## frame.  `height_at()` is the exact same height field the mesh and the
## collision chunks are generated from, so the guard can restore the drone to
## the surface without ever guessing.
func _enforce_ground_clearance(_delta: float) -> void:
	if frontline_map.is_empty():
		return
	var drone_body := get_node_or_null("Drone") as Drone
	if drone_body == null or not is_instance_valid(drone_body):
		return
	var p := drone_body.global_position
	# Outside the 1024 m clipmap the analytic field is still defined, so the
	# guard also catches a drone that escaped past the terrain edge.
	var gy := maxf(FrontlineTerrainScript.height_at(frontline_map, p.x, p.z),
			FrontlineTerrainScript.mesh_surface_height(frontline_map, p.x, p.z))
	# The lake/river bed is below the water mesh: the surface is the real floor,
	# so a drone can never sink under the water.
	var wl := FrontlineTerrainScript.water_level(frontline_map)
	gy = maxf(gy, wl + 0.35)
	if p.y >= gy + 0.08:
		return
	drone_body.global_position = Vector3(p.x, gy + 0.22, p.z)
	if drone_body.linear_velocity.y < 0.0:
		drone_body.linear_velocity.y = 0.0


func _diag_text() -> String:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return "немає дрона"
	var thr := 0.0
	if d.flight_controller.input.size() > 0:
		thr = float(d.flight_controller.input[0])
	var rpm := 0.0
	if not d.motors.is_empty():
		rpm = d.motors[0].get_rpm()
	var radio := get_node_or_null("RadioController")
	var pad := "—"
	var sign_txt := "—"
	if radio != null:
		var dev := int(radio.get("_device"))
		if dev >= 0:
			pad = Input.get_joy_name(dev)
		sign_txt = "%.2f" % float(radio.get("_throttle_sign"))
	return ("ДВИГУНИ: %s\nГАЗ(вхід): %d%%\nМОТОР: %d об/хв\nВИСОТА: %.1f м   VY: %+.1f\n"
			+ "ПУЛЬТ: %s   знак газу: %s") % [
			"ТАК" if d.flight_controller.state_armed else "НІ",
			int(thr * 100.0), int(rpm), d.global_position.y, d.linear_velocity.y,
			pad, sign_txt]


func _read_left_stick() -> Vector2:
	var drone := get_node_or_null("Drone")
	if drone != null and drone.get("flight_controller") != null and drone.flight_controller.input.size() >= 4:
		var thr: float = clampf(float(drone.flight_controller.input[0]), 0.0, 1.0) * 2.0 - 1.0
		var yaw: float = clampf(float(drone.flight_controller.input[1]), -1.0, 1.0)
		return Vector2(yaw, thr)
	
	var yaw := _stick_channel("yaw", "yaw_right", "yaw_left")
	var thr := 0.0
	if Input.is_key_pressed(KEY_W):
		thr = 1.0
	elif Input.is_key_pressed(KEY_S):
		thr = -1.0
	else:
		var radio := get_node_or_null("RadioController")
		if radio != null and radio.has_method("_radio_throttle"):
			var p: float = radio.call("_radio_throttle")
			if p >= 0.0:
				thr = p * 2.0 - 1.0
			else:
				thr = Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
		else:
			thr = Input.get_action_strength("throttle_up") - Input.get_action_strength("throttle_down")
	return Vector2(yaw, thr)


func _read_right_stick() -> Vector2:
	var drone := get_node_or_null("Drone")
	if drone != null and drone.get("flight_controller") != null and drone.flight_controller.input.size() >= 4:
		var roll: float = clampf(float(drone.flight_controller.input[2]), -1.0, 1.0)
		# flight_controller.input[3] is pitch: -1.0 is forward/stick UP, +1.0 is backward/stick DOWN.
		# StickOverlay expects y-up (+1.0 is stick UP), so we negate pitch:
		var pitch: float = -clampf(float(drone.flight_controller.input[3]), -1.0, 1.0)
		return Vector2(roll, pitch)

	var roll := _stick_channel("roll", "roll_right", "roll_left")
	var pitch := _stick_channel("pitch", "pitch_up", "pitch_down")
	return Vector2(roll, pitch)


## The stick monitor mirrors the pilot's physical stick (calibrated but before
## the manual "invert channel" option), so it never flips when a channel is
## reversed for flight.  InputMap actions remain the keyboard fallback.
func _stick_channel(channel: String, positive_action: String, negative_action: String) -> float:
	var wifi := get_node_or_null("/root/ElrsWifiInput")
	if wifi != null and bool(wifi.get("valid")):
		match channel:
			"yaw": return float(wifi.yaw())
			"roll": return float(wifi.roll())
			"pitch": return -float(wifi.pitch())
			"throttle": return float(wifi.throttle()) * 2.0 - 1.0
	var value := Controls.physical_channel_value(channel)
	if is_nan(value):
		value = Input.get_action_strength(positive_action) \
				- Input.get_action_strength(negative_action)
	return clampf(value, -1.0, 1.0)


func _update_hud() -> void:
	if _hud_label == null:
		return
	# Compact three-line OSD: the old five-line block covered a large part of
	# the left edge and duplicated information already shown top-right.
	var short_name := str(DroneCatalog.preset(Global.drone_preset)["name"])
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			var time_str: String = _format_time(_mission_time) if _mission_started else "ГОТОВИЙ"
			var cur_step_name := "УВІМКНЕННЯ ДВИГУНІВ"
			var module_txt := "МОДУЛЬ 1/10"
			if _flight_school != null:
				var d_step: Dictionary = FlightSchool.STEP_DATA.get(_flight_school.current_step, {})
				cur_step_name = str(d_step.get("title", ""))
				module_txt = "МОДУЛЬ %d/%d" % [
						mini(_flight_school.current_step + 1, FlightSchool.TOTAL_MODULES),
						FlightSchool.TOTAL_MODULES]
			_hud_label.text = "%s · %s\n%s\n%s" % [
					short_name, time_str, module_txt, cur_step_name]
		Global.PlayMode.TRAINING:
			var time_str: String = _format_time(_mission_time) if _mission_started else "ГОТОВИЙ"
			_hud_label.text = "%s\n%s · КІЛЬЦЯ %d/%d · %d" % [
					short_name, time_str, _rings_passed, _rings_total, _score]
		Global.PlayMode.SPEED:
			var time_str: String = _format_time(_mission_time) if _mission_started else "ГОТОВИЙ"
			_hud_label.text = "%s\n%s · КП %d/%d · %d" % [
					short_name, time_str, _speed_next,
					_speed_checkpoints.size(), _score]
		Global.PlayMode.CHAOS:
			_hud_label.text = "%s\nБОЙОВИЙ ХАОС · FPV" % short_name
		_:
			var combat_time_limit: float = Global.get_difficulty_time_limit()
			var time_left := maxf(0.0, combat_time_limit - _mission_time)
			var time_str: String = _format_countdown(time_left) if _mission_started else "ГОТОВИЙ"
			if Global.special_mission > 0:
				# Standalone special operations must not reuse the campaign
				# "ПІХОТА 0/0" readout: they have their own zone/convoy/cargo
				# progress and the generic 0/0 looked like a broken objective.
				var sdetail := ""
				match Global.special_mission:
					1:
						sdetail = "ЗОНИ %d/%d" % [
							_special_index, _special_zones.size()]
					2:
						sdetail = "СУПРОВІД КОЛОНИ"
					3:
						sdetail = "ПІЛОТ %d/1 · БАЗА %d/1" % [
							1 if _special_index > 0 else 0,
							1 if _special_index > 1 else 0]
					4:
						sdetail = "ВАНТАЖ %d/2" % _special_index
					_:
						sdetail = "ЦІЛІ %d/%d" % [
							_mission_targets_destroyed, _mission_targets_total]
				_hud_label.text = "%s · СПЕЦОПЕРАЦІЯ «%s»\n%s\nОПЕРАЦІЯ · %s" % [
					short_name, Global.get_special_mission_name(Global.special_mission),
					sdetail, time_str]
				return
			var detail := ""
			match Global.combat_mission:
				1:
					detail = "ПІХОТА %d/%d" % [
						_mission_targets_destroyed, _mission_targets_total]
				2:
					detail = "ТАНК %d/1 · БТР %d/1" % [
						int(_kills.get(Vehicle.Kind.TANK, 0)),
						int(_kills.get(Vehicle.Kind.APC, 0))]
				3:
					detail = "ГЕЛІ %d/1 · ЗРК %d/1" % [
						int(_kills.get(Vehicle.Kind.HELI, 0)),
						int(_kills.get(Vehicle.Kind.SAM, 0))]
				4:
					detail = "ШАХЕД %d/2 · ППО %d/2" % [
						int(_kills.get(Vehicle.Kind.SHAHED, 0)),
						int(_kills.get(Vehicle.Kind.SAM, 0)) + int(_kills.get(Vehicle.Kind.BMP, 0))]
				_:
					detail = "ГЕС %d/1" % int(_kills.get("HYDRO_PLANT", 0))
			_hud_label.text = "%s · TAC-0%d · %s\n%s\nФАЗА: %s · %s · %d/%d" % [
				short_name, Global.combat_mission, Global.get_difficulty_name(),
				detail, _mission_phase_name(), time_str,
				_mission_targets_destroyed, _mission_targets_total]


func _input(event: InputEvent) -> void:
	if _chain_brief != null and _chain_brief.visible:
		# The chain briefing is a modal UI; do not arm, pause, drop or change
		# vision while the player is reading it.
		return
	super._input(event)
	# Level handles arm/disarm for every scene. Keep the press flags here only
	# to start the speed-mode mission on the same input edge.
	var key_event := event as InputEventKey
	var _space: bool = key_event != null and key_event.pressed and not key_event.echo \
			and key_event.keycode == KEY_SPACE
	var is_toggle_arm := _space or Controls.is_action_edge(event, "toggle_arm")
	var is_arm_press := event.is_action_pressed("arm")
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and _has_bomb_sight():
		if event.keycode == KEY_T:
			var want_hot := _vision_mode != VisionMode.FLIR_WHITE_HOT
			_vision_mode = VisionMode.FLIR_WHITE_HOT if want_hot else VisionMode.NORMAL
			_apply_vision_mode()
			if _bomb_sight != null:
				_bomb_sight.set_thermal(want_hot)
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and event.keycode == KEY_F1:
		_diag_on = not _diag_on
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and event.keycode == KEY_F2:
		_capture_player_screenshot()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.is_pressed() and not event.is_echo() \
			and event.keycode == KEY_F3:
		var next_q := (QualityManagerScript.get_active_level() + 1) % 3
		Graphics.apply_quality_preset(next_q)
		Graphics.save_graphics_settings()
		_set_flash("ГРАФІКА: %s" % QualityManagerScript.level_name_ua(next_q))
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F4:
			cycle_vision_mode()
		elif event.keycode == KEY_F5:
			_weather = (_weather + 1) % 5
			GameSettings.hud_config["weather"] = _weather
			GameSettings.save_hud_config()
			_apply_weather()
	if event.is_action_pressed("toggle_osd"):
		_osd_visible = not _osd_visible
		GameSettings.hud_config["osd"] = _osd_visible
		GameSettings.save_hud_config()
		_apply_osd()
	if event.is_action_pressed("cycle_video_mode"):
		var video_overlay := get_node_or_null("FPVOverlay")
		if video_overlay != null and video_overlay.has_method("set_user_visible"):
			video_overlay.call("set_user_visible", true)
		var mode := Graphics.cycle_fpv_video_mode()
		_set_flash("ВІДЕО: %s" % Graphics.fpv_video_mode_name(mode))
	if event.is_action_pressed("toggle_weather"):
		_weather = (_weather + 1) % 5
		GameSettings.hud_config["weather"] = _weather
		GameSettings.save_hud_config()
		_apply_weather()
	if Controls.is_action_edge(event, "deploy_payload"):
		_payload_axis_drop_prev = true
		_drop_fpv_payload()
		# CombatSystem has a legacy standalone _unhandled_input drop.  Mark the
		# edge handled here, otherwise one G press could release twice.
		get_viewport().set_input_as_handled()
	if Controls.is_action_edge(event, "activate_payload"):
		_payload_axis_trigger_prev = true
		_activate_fpv_payload()
		get_viewport().set_input_as_handled()
	if (is_toggle_arm or is_arm_press) and Global.play_mode == Global.PlayMode.SPEED:
		if not _mission_started and not _mission_finished:
			_start_mission()

	# First-person only: no orbit/chase mouse camera controls.


func _full_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var ok := true
	var d := get_node_or_null("Drone") as Drone
	print("[FULLTEST] mode=", Global.play_mode, " map_children=", _map_root.get_child_count(),
			" vehicles=", _vehicles.size(), " infantry=", _infantry_units.size(), " drone=", d != null)
	var targets_count: int = _vehicles.size() + _infantry_units.size() + _mission_targets_total
	var targets_ok: bool = (Global.play_mode != Global.PlayMode.COMBAT) or (targets_count > 0)
	ok = ok and d != null and _map_root.get_child_count() > 0 and targets_ok

	# --- settings round-trip ---
	var vol: float = Audio.audio_settings["master_volume"]
	Audio.audio_settings["master_volume"] = 0.5
	Audio.update_master_volume()
	Audio.save_audio_settings()
	Audio.load_audio_settings()
	ok = ok and absf(float(Audio.audio_settings["master_volume"]) - 0.5) < 0.01
	Audio.audio_settings["master_volume"] = vol
	Audio.update_master_volume()
	Audio.save_audio_settings()

	var cross: bool = GameSettings.hud_config["crosshair"]
	GameSettings.hud_config["crosshair"] = not cross
	GameSettings.save_hud_config()
	GameSettings.load_hud_config()
	ok = ok and bool(GameSettings.hud_config["crosshair"]) == (not cross)
	GameSettings.hud_config["crosshair"] = cross
	GameSettings.save_hud_config()
	print("[FULLTEST] settings round-trip ok=", ok)

	# --- drone presets really change the model ---
	var mass_before := d.mass
	DroneCatalog.apply_to_drone(d, 0)
	await get_tree().create_timer(0.3).timeout
	ok = ok and absf(d.mass - mass_before) > 0.05
	print("[FULLTEST] preset mass ", mass_before, " -> ", d.mass)
	DroneCatalog.apply_to_drone(d, Global.drone_preset)

	# --- arm + mission timer ---
	_place_drone_over_ground()
	await get_tree().physics_frame
	d.flight_controller.request_arm(true)
	await get_tree().create_timer(0.6).timeout
	ok = ok and d.flight_controller.state_armed and _mission_started
	var t0 := _mission_time
	await get_tree().create_timer(3.0).timeout
	ok = ok and _mission_time > t0 + 2.0
	print("[FULLTEST] armed=", d.flight_controller.state_armed, " timer ",
			t0, " -> ", _mission_time)

	# --- OSD / rig / weather toggles ---
	_osd_visible = false
	_apply_osd()
	await get_tree().process_frame
	ok = ok and not _hud.visible
	_osd_visible = true
	_apply_osd()
	ok = ok and _hud.visible
	_rig_visible = false
	_apply_fpv_rig()
	await get_tree().process_frame
	ok = ok and (_fpv_rig == null or not _fpv_rig.visible)
	_rig_visible = true
	_apply_fpv_rig()
	var w0 := _weather
	_weather = (_weather + 1) % 3
	_apply_weather()
	await get_tree().create_timer(0.2).timeout
	ok = ok and _weather != w0
	print("[FULLTEST] toggles ok=", ok, " weather ", w0, " -> ", _weather)

	# --- payload drop ---
	if _fpv_payload != null and _payload_enabled:
		_drop_fpv_payload()
		await get_tree().create_timer(0.9).timeout
		ok = ok and not _fpv_payload.visible
		_reset_fpv_payload()
		ok = ok and _fpv_payload.visible
		print("[FULLTEST] payload drop/restore ok")

	# --- mode-specific objective ---
	if Global.play_mode == Global.PlayMode.TRAINING and _rings_total > 0:
		var ring_area := _triggers.get_child(0) as Area3D
		var before := _rings_passed
		_on_ring_entered(d, ring_area)
		await get_tree().create_timer(0.1).timeout
		ok = ok and _rings_passed > before
		print("[FULLTEST] ring passed ", before, " -> ", _rings_passed)
	elif Global.play_mode == Global.PlayMode.SPEED and _speed_checkpoints.size() > 0:
		var before_s := _speed_next
		_on_checkpoint_entered(d, 0)
		await get_tree().create_timer(0.1).timeout
		ok = ok and _speed_next > before_s
		print("[FULLTEST] checkpoint ", before_s, " -> ", _speed_next)
	elif Global.play_mode == Global.PlayMode.COMBAT:
		var combat := get_node_or_null("CombatSystem")
		ok = ok and combat != null
		if _vehicles.size() > 0 and _vehicles[0] != null:
			var before_k := int(_kills.get(_vehicles[0].kind, 0))
			_vehicles[0].take_damage(99999.0, _vehicles[0].global_position + Vector3.UP)
			await get_tree().create_timer(0.2).timeout
			ok = ok and int(_kills.get(_vehicles[0].kind, 0)) > before_k
			print("[FULLTEST] vehicle kill counted")

	print("[FULLTEST] ", "PASS" if ok else "FAIL")
	get_tree().quit()


func _full_test_placeholder() -> void:
	pass


func _run_autotest() -> void:
	await get_tree().create_timer(2.0).timeout
	var d := get_node_or_null("Drone") as Drone
	print("[BIGMAP] mode=", Global.play_mode, " ground_y=", _ground_y,
			" drone=", d != null, " vehicles=", _vehicles.size())
	if d == null:
		print("[BIGMAP] FAIL no drone")
		return
	_place_drone_over_ground()
	await get_tree().physics_frame
	d.flight_controller.request_arm(true)
	await get_tree().create_timer(0.5).timeout
	print("[BIGMAP] armed=", d.flight_controller.state_armed,
			" pos=", d.global_position, " started=", _mission_started)
	if d.flight_controller.state_armed and absf(d.global_position.y - _ground_y) < 25.0:
		print("[BIGMAP] PASS big map")
	else:
		print("[BIGMAP] FAIL big map")
	get_tree().quit()


func _hide_drone_visuals(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("drone_model"):
		return
	if node is Propeller:
		# Propeller._process re-enables the blur disc every frame while the
		# motors spin, which put big red discs in front of the FPV camera.
		# Freeze its visual state here; the flight model is unaffected.
		var prop := node as Propeller
		prop.set_process(false)
		prop.set_visibility(false)
		var disk := prop.get_node_or_null("PropBlurDisk") as VisualInstance3D
		if disk != null:
			disk.visible = false
	if node is VisualInstance3D:
		(node as VisualInstance3D).visible = false
	for child in node.get_children():
		_hide_drone_visuals(child)


func change_camera() -> void:
	super.change_camera()
	_refresh_model_visibility()
	var d := get_node_or_null("Drone") as Drone
	if d != null and d.get("hud") is CanvasItem:
		(d.get("hud") as CanvasItem).visible = _osd_visible


func _on_camera_tilt_changed(tilt_deg: float) -> void:
	_set_flash("« НАХИЛ FPV КАМЕРИ: %d° »  [C / V — РЕГУЛЮВАННЯ]" % int(tilt_deg))


## FPV strike aircraft carry the warhead in the airframe.  A hard body contact
## (not a grass/tree-brush graze and never the frozen spawn state) detonates it
## through the same radial explosion path used by the manual F-key command.
func _on_drone_hard_impact(impact_speed: float) -> void:
	if OS.has_environment("DRONE_KAMIKAZE_TEST"):
		print("[KAMTEST] hard_impact signal speed=", impact_speed,
				" payload_enabled=", _payload_enabled,
				" dropped=", _payload_dropped)
	_try_kamikaze_impact(impact_speed)


## One physics-tick memory of the airframe speed.  The Area3D sensor can report
## a wall/terrain overlap on the same frame the rigid body has already been
## stopped by the contact solver, so the sensor handler compares against this
## value instead of reading a momentary zero.
var _drone_last_speed := 0.0
var _drone_peak_speed := 0.0
var _drone_prev_pos := Vector3.ZERO


## A dedicated warhead contact sensor sits at the nose of strike airframes.
## It reports the first overlap with a static body, hull or vehicle; the same
## speed/armed/airborne guards as the rigid-body hard-impact signal apply, so a
## tree-tip graze, grass or the frozen spawn cannot self-detonate the warhead.
func _setup_warhead_sensor() -> void:
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	var old := drone.get_node_or_null("WarheadSensor")
	if old != null:
		old.queue_free()
	var p := DroneCatalog.preset(Global.drone_preset)
	var strike := bool(p.get("kamikaze", false)) and bool(p.get("combat", false)) \
			and not bool(p.get("has_drop", false)) \
			and not bool(p.get("is_naval", false))
	if not strike:
		return
	var area := Area3D.new()
	area.name = "WarheadSensor"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	var model_size := float(p.get("model_size", 0.4))
	sphere.radius = clampf(model_size * 0.42, 0.16, 0.55)
	cs.shape = sphere
	# Keep the sensor at the nose and slightly above the belly so neither the
	# launch cradle nor a grass skid can trigger it at spawn.
	cs.position = Vector3(0.0, 0.08, -minf(model_size * 0.36, 0.8))
	area.add_child(cs)
	drone.add_child(area)
	area.body_entered.connect(_on_warhead_sensor_body_entered)
	# The rigid body's own contact monitor is the second, independent path.
	# Some Godot/Jolt versions do not report static contacts through
	# DirectBodyState.get_contact_count() inside a custom integrator, but the
	# RigidBody3D signal still fires on the first physical contact.
	if not drone.body_entered.is_connected(_on_drone_body_entered):
		drone.body_entered.connect(_on_drone_body_entered)
	if OS.has_environment("DRONE_KAMIKAZE_TEST"):
		print("[KAMTEST] warhead sensor radius=", sphere.radius,
				" at ", cs.position, " monitoring=", area.monitoring)


## Public bridge used by CombatSystem.  It runs before the legacy crash/target
## handling so a strike airframe produces one authoritative area explosion
## instead of a small "crash" blast plus a second warhead blast.
func try_strike_warhead_contact(_body: Node, speed: float) -> bool:
	if not _payload_enabled or _payload_dropped or _mission_finished:
		return false
	var p := DroneCatalog.preset(Global.drone_preset)
	var strike := bool(p.get("kamikaze", false)) and bool(p.get("combat", false)) \
			and not bool(p.get("has_drop", false)) \
			and not bool(p.get("is_naval", false))
	if not strike or speed < 7.0:
		return false
	_try_kamikaze_impact(speed)
	return _payload_dropped


func _on_warhead_sensor_body_entered(body: Node) -> void:
	if body == null or body == self:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or body == drone:
		return
	if body is not StaticBody3D and body is not RigidBody3D:
		return
	var speed := _contact_speed(drone)
	if OS.has_environment("DRONE_KAMIKAZE_TEST"):
		print("[KAMTEST] sensor entered by ", body.name, " speed=", speed)
	_try_kamikaze_impact(speed)


func _contact_speed(drone: Drone) -> float:
	var speed: float = maxf(drone.linear_velocity.length(),
			maxf(_drone_last_speed, _drone_peak_speed))
	var prev = drone.get("_prev_lin_vel")
	if prev is Vector3:
		speed = maxf(speed, (prev as Vector3).length())
	return speed


func _on_drone_body_entered(body: Node) -> void:
	if body == null:
		return
	if body is not StaticBody3D and body is not RigidBody3D:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		return
	var speed := _contact_speed(drone)
	if OS.has_environment("DRONE_KAMIKAZE_TEST"):
		print("[KAMTEST] rigid body contact with ", body.name, " speed=", speed)
	_try_kamikaze_impact(speed)


func _try_kamikaze_impact(impact_speed: float) -> void:
	if not _payload_enabled or _payload_dropped or _mission_finished:
		return
	var combat := get_node_or_null("CombatSystem")
	if combat != null and bool(combat.get("_lost")):
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	var strike := bool(p.get("kamikaze", false))
	if not strike:
		strike = bool(p.get("combat", false)) \
				and not bool(p.get("has_drop", false)) \
				and not bool(p.get("is_naval", false)) \
				and int(p.get("payload", 0)) > 0
	if not strike:
		return
	# Light contact with a fence, branch or ground bump must not trigger the
	# warhead.  The active airframe has to be armed, airborne and closing at a
	# meaningful speed; the spawn is frozen with zero velocity by design.
	const KAMIKAZE_CONTACT_SPEED := 7.0
	if impact_speed < KAMIKAZE_CONTACT_SPEED:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or not drone.flight_controller.state_armed:
		return
	if not bool(drone.get("_was_airborne")):
		return
	_activate_fpv_payload()
	# One authoritative blast: silence CombatSystem's separate crash/target
	# handler for the remainder of this sortie.  It resets on respawn.
	if combat != null and combat.get("_lost") != null:
		combat.set("_lost", true)


func _on_drone_crashed(reason: String) -> void:
	# A strike airframe that just detonated already ran its respawn sequence;
	# do not overwrite the kill feed with a generic crash card.  Droppers keep
	# the normal crash card (their airframe is still visible).
	var crash_node := get_node_or_null("Drone") as Drone
	if _payload_dropped and _payload_enabled \
			and crash_node != null and not crash_node.visible:
		return
	var msg := "« АВАРІЯ! ЗНИЩЕНО: %s » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]" % reason
	match reason:
		"HARD_IMPACT":
			msg = "« КРАШ: СИЛЬНИЙ УДАР ОБ ПЕРЕШКОДУ » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]"
		"INVERTED_ON_GROUND":
			msg = "« КРАШ: ДРОН ПЕРЕВЕРНУТИЙ НА ЗЕМЛІ » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]"
		_:
			msg = "« КРАШ: %s » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]" % reason
	var crash_drone := get_node_or_null("Drone") as Node3D
	if crash_drone != null:
		CombatSfxScript.play_drone_impact(self, crash_drone.global_position, 0.0)
		CombatSfxScript.play_boom(self, crash_drone.global_position, -7.0)
	_set_flash(msg)


var _wind_accum: float = 0.0
var _current_wind_vector: Vector3 = Vector3.ZERO


func _update_wind_simulation(delta: float) -> void:
	var drone_body := get_node_or_null("Drone") as Drone
	if drone_body == null or not is_instance_valid(drone_body):
		return
	if not bool(GameSettings.hud_config.get("wind_sim", true)):
		_wind_accum = 0.0
		if _current_wind_vector != Vector3.ZERO:
			_current_wind_vector = Vector3.ZERO
			drone_body.set_wind(Vector3.ZERO)
		return
	_wind_accum += delta
	var base_dir := Vector3(0.8, 0.0, 0.6).normalized()
	var base_speed := 2.0
	var gust_speed := 1.0
	var turbulence := 0.2
	
	match _weather:
		1: # Rain
			base_speed = 7.5
			gust_speed = 3.5
			turbulence = 0.8
		2: # Dust/Storm
			base_speed = 13.0
			gust_speed = 5.5
			turbulence = 1.6
		_: # Clear
			base_speed = 2.2
			gust_speed = 1.0
			turbulence = 0.2
	
	# Altitude boundary layer: wind slows near ground
	var alt := maxf(drone_body.global_position.y - _ground_y, 0.5)
	var alt_factor := clampf(log(alt + 1.0) / log(20.0), 0.35, 1.6)
	
	# Harmonic gust modulation
	var gust := sin(_wind_accum * 0.4) * 0.5 + sin(_wind_accum * 1.1) * 0.3 + sin(_wind_accum * 2.7) * 0.2
	var turb_x := sin(_wind_accum * 3.3 + 1.2) * turbulence
	var turb_y := cos(_wind_accum * 2.1 + 0.5) * turbulence * 0.4
	var turb_z := sin(_wind_accum * 4.1 + 2.5) * turbulence
	
	# Field wind was reduced after playtests: it should be readable and
	# physical, not constantly push the aircraft off the line.
	const WIND_EFFECT_SCALE := 0.65
	var diff_wind_scale: float = Global.get_difficulty_wind_scale() if Global.play_mode == Global.PlayMode.COMBAT else 1.0
	var total_speed := (base_speed + gust * gust_speed) * alt_factor * diff_wind_scale * WIND_EFFECT_SCALE
	_current_wind_vector = base_dir * total_speed \
			+ Vector3(turb_x, turb_y, turb_z) * diff_wind_scale * WIND_EFFECT_SCALE
	drone_body.set_wind(_current_wind_vector)


func _refresh_model_visibility() -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	var is_boat: bool = bool(p.get("is_naval", false))
	var third_person := camera != null and camera.name != "FPVCamera"
	if not third_person:
		# Sport/recon drones keep a clean lens.  Combat airframes show the
		# warhead at the bottom edge — the reference FPV look — with the camera
		# lifted just above the frame so the body no longer fills the centre.
		var combat_airframe := bool(p.get("combat", false)) \
				and not bool(p.get("is_naval", false))
		var show_airframe := bool(p.get("fpv_show_airframe", false))
		var hide_model := bool(p.get("fpv_hide_model", false))
		if show_airframe:
			hide_model = false
		# The 2.8 m heavy bomber cannot be framed by a 110-degree lens without
		# its rack/battery covering the crosshair.  Its external ordnance is
		# still simulated, the CCIP sight and AMMO counter carry the cue.
		if bool(p.get("heavy_bomber", false)):
			hide_model = true
		_model_root.visible = (combat_airframe or show_airframe) and not hide_model
		var mobile_front_props := _is_mobile_runtime() and not combat_airframe \
				and not show_airframe and not bool(p.get("fixed_wing", false)) \
				and not bool(p.get("is_naval", false)) \
				and not bool(p.get("heavy_bomber", false))
		if mobile_front_props:
			_model_root.visible = true
		_apply_combat_fpv_camera(combat_airframe and not show_airframe and not hide_model, p)
		if show_airframe:
			# Recon/loitering fixed-wing aircraft need enough body in frame for
			# orientation. Hide the close-up camera gimbal itself, which otherwise
			# fills the centre of the FPV image on Leleka/Furia.
			_configure_fixed_wing_fpv(_model_root)
		elif mobile_front_props:
			# iOS-only: show just the rotating front props/arms at the screen
			# edges so pilots can judge attitude. PC keeps the clean lens.
			_configure_mobile_front_props(_model_root)
		else:
			_configure_model_for_camera(_model_root, true, combat_airframe)
	else:
		_model_root.visible = true
		_apply_combat_fpv_camera(false, p)
		_configure_model_for_camera(_model_root, false, false)
	# Propellers that live outside DroneModel (the legacy flight-model blades)
	# must follow the same rule; otherwise their black tips poke into the lower
	# corners of the FPV frame.
	var drone_node := get_node_or_null("Drone")
	var preset_now := DroneCatalog.preset(Global.drone_preset)
	var mobile_side_props := _is_mobile_runtime() and not third_person \
			and not bool(preset_now.get("fixed_wing", false)) \
			and not bool(preset_now.get("is_naval", false)) \
			and not bool(preset_now.get("heavy_bomber", false))
	if drone_node != null:
		for prop in drone_node.find_children("*", "Propeller", true, false):
			if prop.has_method("set_visibility"):
				prop.call("set_visibility", third_person or bool(
					preset_now.get("fpv_show_airframe", false)))
			elif prop is VisualInstance3D:
				(prop as VisualInstance3D).visible = third_person or bool(
					preset_now.get("fpv_show_airframe", false))
	if not is_inside_tree():
		return
	for pivot in get_tree().get_nodes_in_group("drone_prop_pivot"):
		if pivot is Node3D:
			var pivot_name := String(pivot.name).to_lower()
			var front_pivot := pivot_name.contains("fl") or pivot_name.contains("fr") \
					or pivot_name.ends_with("_0") or pivot_name.ends_with("_1")
			(pivot as Node3D).visible = third_person or bool(
				preset_now.get("fpv_show_airframe", false)) \
				or (mobile_side_props and front_pivot)


func _is_mobile_runtime() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


func _configure_mobile_front_props(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("drone_prop_pivot") or node.name == "PropellerAssembly":
		if node is Node3D:
			var pn := String(node.name).to_lower()
			(node as Node3D).visible = pn.contains("fl") or pn.contains("fr") \
					or pn.ends_with("_0") or pn.ends_with("_1")
		return
	if node is MeshInstance3D:
		var n := String(node.name).to_lower()
		(node as MeshInstance3D).visible = n.contains("propeller_fl") \
				or n.contains("propeller_fr") or n.contains("motor_fl") \
				or n.contains("motor_fr") or n.contains("arm_fl") \
				or n.contains("arm_fr") or n.contains("front_arm")
	for child in node.get_children():
		_configure_mobile_front_props(child)


func _configure_fixed_wing_fpv(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_name := String(node.name).to_lower()
		var camera_part := mesh_name.contains("camera") or mesh_name.contains("cam")
		(node as MeshInstance3D).visible = not camera_part
	elif node is Node3D and (node.name == "propeller_rear" \
			or node.is_in_group("drone_prop_pivot")):
		(node as Node3D).visible = true
	for child in node.get_children():
		_configure_fixed_wing_fpv(child)


func _is_under(node: Node, ancestor: Node) -> bool:
	var cur := node
	while cur != null:
		if cur == ancestor:
			return true
		cur = cur.get_parent()
	return false


## Lift the FPV camera above the combat airframe so the warhead/nose stays in
## the lower part of the frame instead of blocking the crosshair.
func _apply_combat_fpv_camera(on: bool, p: Dictionary) -> void:
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam == null:
		return
	if not cam.has_meta("base_pos"):
		cam.set_meta("base_pos", cam.position)
	if not cam.has_meta("base_rot"):
		cam.set_meta("base_rot", cam.rotation_degrees)
	var base: Vector3 = cam.get_meta("base_pos")
	var base_rot: Vector3 = cam.get_meta("base_rot")
	if on:
		if bool(p.get("heavy_bomber", false)):
			# Baba Yaga's rack/battery filled half of the FPV frame.  Only the
			# external mines are drawn now (see _configure_model_for_camera),
			# and the lens sits behind them with a shallow down-angle so they
			# read at the lower edge without blocking the target.
			cam.position = base + Vector3(0.0, 0.10, 1.35)
			cam.rotation_degrees = Vector3(base_rot.x - 10.0, base_rot.y, base_rot.z)
			return
		var model_size := maxf(float(p.get("model_size", 0.38)), 0.2)
		var k := clampf(model_size / 0.38, 0.55, 1.6)
		cam.position = base + Vector3(0.0, 0.075 * k, 0.025 * k)
		cam.rotation_degrees = base_rot
	else:
		cam.position = base
		cam.rotation_degrees = base_rot


func _station_demo() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	d.freeze = true
	# Dynamic perspective framing the locomotive, platform canopy, station terminal, and rails
	d.global_position = Vector3(18.0, _ground_y + 4.5, -238.0)
	d.look_at(Vector3(-12.0, _ground_y + 2.2, -225.0), Vector3.UP)
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		cam.fov = 82.0


func _setup_hydro_ram_test() -> void:
	var d := get_node_or_null("Drone") as Drone
	if d == null:
		return
	var station := get_node_or_null("HydroelectricPowerStation_Dnipro") as Node3D
	var target_pt := Vector3(380.0, _ground_y + 1.0, -50.0)
	if station != null:
		target_pt = station.to_global(Vector3(0.0, 2.0, -28.0))
	var approach_dir := (target_pt - Vector3(230.0, _ground_y, 40.0)).normalized()
	d.global_position = target_pt - approach_dir * 18.0
	d.look_at(target_pt, Vector3.UP)
	d.linear_velocity = approach_dir * 38.0



## Collects the horizontal positions of every instanced tree so the combat
## spawn can avoid landing inside a copse.
func _tree_positions_snapshot() -> PackedVector2Array:
	var out := PackedVector2Array()
	if _map_root == null:
		return out
	for node in _map_root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var n := String(mmi.name).to_lower()
		if not (n.contains("leaves") or n.contains("trunks") or n.contains("canop")):
			continue
		for i in range(mmi.multimesh.instance_count):
			var origin := mmi.multimesh.get_instance_transform(i).origin
			out.append(Vector2(origin.x, origin.z))
	return out


## Picks the best point inside a spiral around `origin`, preferring a full
## `clearance` from every tree; falls back to the most open candidate.
func _find_clear_spawn(origin: Vector2, trees: PackedVector2Array,
		clearance: float) -> Vector2:
	var best := origin
	var best_d2 := -1.0
	var clear_d2 := clearance * clearance
	for ring in range(0, 5):
		var dist := 0.0 if ring == 0 else float(ring) * 7.0
		var steps := 1 if ring == 0 else 14
		for s in range(steps):
			var ang := TAU * float(s) / float(steps)
			var p := origin + Vector2(cos(ang), sin(ang)) * dist
			if absf(p.x) > 455.0 or absf(p.y) > 455.0:
				continue
			var min_d2 := 1.0e20
			for t in trees:
				min_d2 = minf(min_d2, p.distance_squared_to(t))
			if min_d2 > best_d2:
				best_d2 = min_d2
				best = p
			if min_d2 >= clear_d2:
				return p
	return best
