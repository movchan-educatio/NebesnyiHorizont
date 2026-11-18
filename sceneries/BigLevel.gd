## Big procedural maps level.
##
## Loads one of three large maps based on the menu mode and runs the
## full mission loop for it:
##   TUTORIAL - 10-module flight school course
##   TRAINING - fly through 24 rings (or free-flight with Ghost)
##   COMBAT   - the combat layer (targets / AA / infantry) plus moving armour
##
## Also spawns moving vehicles, upgrades the environment (fog, glow, SSAO,
## ACES tonemap) and shows a start banner / results screen.
extends "res://sceneries/Level.gd"

const VEHICLE := preload("res://combat/vehicle.gd")
const DESTRUCTIBLE := preload("res://combat/destructible_building.gd")
const PayloadScript = preload("res://combat/payload.gd")
const BombBallisticsScript = preload("res://combat/ballistics.gd")
const EnemyRiflemanScript = preload("res://combat/enemy_infantry.gd")
const AAGunScript = preload("res://combat/aa_gun.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const StickOverlayScript = preload("res://HUD/StickOverlay.gd")
const AmbientBattleScript = preload("res://combat/ambient_battle.gd")
const FoliageSystemScript = preload("res://scripts/util/foliage_system.gd")
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")
const ValleySceneBuilderScript = preload("res://scripts/util/valley_scene_builder.gd")
const QualityManagerScript = preload("res://scripts/util/quality_manager.gd")
const MaterialUpgraderScript = preload("res://scripts/util/material_upgrader.gd")
const FlightSchool = preload("res://scripts/util/flight_school.gd")
const CombatTrainingScript = preload("res://scripts/util/combat_training.gd")
const LocScript = preload("res://scripts/util/localization_manager.gd")
const FpvIconsScript = preload("res://scripts/util/fpv_icons.gd")
const ReconKillCamScript = preload("res://scripts/combat/recon_kill_cam.gd")
const GhostScript = preload("res://drone/Ghost.gd")
const MAIN_MENU := "res://GUI/MainMenu.tscn"
const MOBILE_MENU := "res://GUI/mobile/MobileMenu.tscn"

const MAP_FLIGHT_BOUND := 182.0
const MAP_GROUND_SAFE := 152.0
const MAP_AIR_SAFE := 172.0
const MIN_ENEMY_SPAWN_DIST_GROUND := 80.0
const MIN_ENEMY_SPAWN_DIST_AIR := 95.0

## Air-target engagement envelope for campaign missions 3 and 4.
## Both sorties are kinetic-intercept missions flown with a stock strike quad,
## so the targets must stay inside the altitude band the drone can climb to and
## at a speed the player can close on.  The old 30-54 m / 23-28 m/s band put the
## helicopter and Shaheds above the practical zoom envelope, which made the
## missions effectively unwinnable.
const AIR_MISSION_HELI_ALT := Vector2(20.0, 30.0)
const AIR_MISSION_HELI_SPEED := Vector2(10.5, 12.5)
const AIR_MISSION_SHAHED_ALT_1 := Vector2(18.0, 24.0)
const AIR_MISSION_SHAHED_ALT_2 := Vector2(22.0, 30.0)
const AIR_MISSION_SHAHED_SPEED := Vector2(16.0, 20.0)

var _map_root: Node3D = null
var _triggers: Node3D = null
var _hud: CanvasLayer = null
var _results_canvas_layer: CanvasLayer = null
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

var _rings_passed := 0
var _rings_total := 0
var _training_rings: Array[Area3D] = []
var _training_ring_positions: Array[Vector3] = []
var _training_ring_spawn_queued := false
var _ring_pulse := 0.0
var _nav_marker: Label = null
var _vehicles: Array[Vehicle] = []
var _infantry_units: Array[Node3D] = []
var _kills := {}
var _mission_targets_total := 0
var _mission_targets_destroyed := 0
var _sortie_airframes_total := 3
var _sortie_airframes_left := 3
var _airframe_consumed_this_life := false
var _low_bonus_infantry_count := 0
var _aa_guns: Array[Node3D] = []
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
var _special_convoy_stall_anchor := Vector3.ZERO
var _special_convoy_stall := 0.0
var _special_convoy_recoveries := 0
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
## Untyped on purpose: the global class cache is regenerated by the editor, so
## a preloaded script reference keeps the level runnable from a raw build.
var _combat_training = null
var _flash_token := 0
## QA: survives a scene reload so the retry test can detect its second run.
static var _retry_test_round := 0
var _rain: GPUParticles3D = null
var _dust: GPUParticles3D = null
var _kill_cam: ReconKillCamScript = null
var _kill_cam_triggered := false
var _kill_cam_last_ms := -10000
var _pending_combat_complete := false
var _pending_kamikaze_respawn := false
var _base_fpv_fov := 110.0
var _top_banner_stack: VBoxContainer = null
var _wind_row: HBoxContainer = null
var _radio_subtitle_panel: PanelContainer = null
var _perimeter_warn_timer := 0.0
var _radio_beat_01_sent := false
var _radio_beat_02_sent := false
var _radio_beat_03_sent := false
var _radio_beat_04_sent := false
var _radio_beat_02_fallback_timer := -1.0
var _ghost_node: Ghost = null
var _ghost_record_samples: Array = []
var _ghost_record_timer := 0.0
var _results_lb_btn: Button = null
var _elrs_status_timer := 2.5
var _elrs_status_last_text := ""
var _payload_drops := 0
var _payload_hits := 0
var _results_career_label: Label = null
var _results_career_bar: ProgressBar = null
var _fiber_spool_used_m := 0.0
const FIBER_CABLE_SEGMENTS := 26
const FIBER_CABLE_COLOR := Color(0.28, 0.93, 1.0, 1.0)
var _fiber_cable: MeshInstance3D = null
var _fiber_cable_mesh: ImmediateMesh = null
var _fiber_spool_marker: Node3D = null
var _fiber_core_mat: StandardMaterial3D = null
var _fiber_glow_mat: StandardMaterial3D = null
var _fiber_anchor := Vector3.ZERO
var _fiber_anchor_ready := false
var _analog_bar_a: ColorRect = null
var _analog_bar_b: ColorRect = null
var _dvr_samples: Array = []
var _dvr_sample_timer := 0.0
const DVR_FPS := 5
const DVR_MAX_FRAMES := 60
const DVR_FRAME_W := 384
const DVR_FRAME_H := 216
var _dvr_frames: Array[Texture2D] = []
var _dvr_frame_timer := 0.0
var _dvr_capture_failed := false
var _dvr_capture_pending := false
var _dvr_overlay: CanvasLayer = null
var _dvr_overlay_rect: TextureRect = null
var _dvr_overlay_stamp: Label = null
var _dvr_overlay_time: Label = null
var _last_strike_pos := Vector3.ZERO
var _results_dvr_btn: Button = null
var _dvr_replaying := false
var _dvr_banner_label: Label = null


func _is_en() -> bool:
	return LocScript.get_language() == LocScript.Language.EN or MenuUI.is_english()


func _txt(ua: String, en: String) -> String:
	return en if _is_en() else ua


func _clamp_ground_vec3(v: Vector3) -> Vector3:
	return Vector3(clampf(v.x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), v.y,
			clampf(v.z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))


func _clamp_air_vec3(v: Vector3) -> Vector3:
	return Vector3(clampf(v.x, -MAP_AIR_SAFE, MAP_AIR_SAFE), v.y,
			clampf(v.z, -MAP_AIR_SAFE, MAP_AIR_SAFE))


func _player_spawn_xz() -> Vector2:
	var d := get_node_or_null("Drone") as Node3D
	if d != null:
		return Vector2(d.global_position.x, d.global_position.z)
	var respawn := get_node_or_null("Respawn") as Node3D
	if respawn != null:
		return Vector2(respawn.global_position.x, respawn.global_position.z)
	return Vector2.ZERO


func _is_safe_enemy_xz(p: Vector2, min_dist: float, bound: float, is_air: bool) -> bool:
	if absf(p.x) > bound or absf(p.y) > bound:
		return false
	if p.distance_to(_player_spawn_xz()) < min_dist:
		return false
	if not is_air and not frontline_map.is_empty():
		if not _is_ground_spot_clear(p.x, p.y):
			return false
	return true


func _ensure_enemy_xz_clearance(pos: Vector2, min_dist: float, bound: float,
		is_air: bool) -> Vector2:
	var sp := _player_spawn_xz()
	var clamped := Vector2(clampf(pos.x, -bound, bound), clampf(pos.y, -bound, bound))
	if _is_safe_enemy_xz(clamped, min_dist, bound, is_air):
		return clamped
	var away := clamped - sp
	if away.length_squared() < 0.01:
		away = -sp
	if away.length_squared() < 0.01:
		away = Vector2(0.0, -1.0)
	var base_ang := atan2(away.y, away.x)
	for extra in [6.0, 22.0, 44.0, 72.0, 104.0, 140.0]:
		var r: float = min_dist + float(extra)
		for step_i in range(16):
			var sign_dir := 1.0 if (step_i % 2 == 0) else -1.0
			var mag := float((step_i + 1) / 2) * (TAU / 16.0)
			var ang := base_ang + sign_dir * mag
			var cand: Vector2 = sp + Vector2(cos(ang), sin(ang)) * r
			cand.x = clampf(cand.x, -bound, bound)
			cand.y = clampf(cand.y, -bound, bound)
			if _is_safe_enemy_xz(cand, min_dist, bound, is_air):
				return cand
	for gx in range(-136, 137, 24):
		for gz in range(-136, 137, 24):
			var gcand := Vector2(clampf(float(gx), -bound, bound), clampf(float(gz), -bound, bound))
			if _is_safe_enemy_xz(gcand, min_dist, bound, is_air):
				return gcand
	var opp := Vector2(
			-signf(sp.x if absf(sp.x) > 1.0 else 1.0) * minf(bound - 10.0, 95.0),
			-signf(sp.y if absf(sp.y) > 1.0 else 1.0) * minf(bound - 10.0, 95.0))
	if not is_air and not frontline_map.is_empty():
		var dry := _find_dry_spot(opp.x, opp.y)
		if _is_safe_enemy_xz(dry, min_dist, bound, false):
			return dry
	return opp


func _route_last_sfx_bus(bus_name: StringName) -> void:
	var count := get_child_count()
	if count <= 0:
		return
	var last := get_child(count - 1)
	if last is AudioStreamPlayer3D or last is AudioStreamPlayer:
		last.set("bus", bus_name)


func _exit_tree() -> void:
	if _kill_cam != null and is_instance_valid(_kill_cam):
		_kill_cam.cancel()
	_ghost_record_samples.clear()
	super._exit_tree()


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
		Global.combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 4)
		Global.special_mission = 0
	if OS.has_environment("DRONE_TUTORIAL"):
		Global.play_mode = Global.PlayMode.TUTORIAL
		Global.special_mission = 0
	elif OS.has_environment("DRONE_PLAY_MODE"):
		var pm := OS.get_environment("DRONE_PLAY_MODE").strip_edges().to_lower()
		if pm == "tutorial":
			Global.play_mode = Global.PlayMode.TUTORIAL
			Global.special_mission = 0
		elif pm == "combat":
			Global.play_mode = Global.PlayMode.COMBAT
			Global.special_mission = 0
		elif pm == "training":
			Global.play_mode = Global.PlayMode.TRAINING
			Global.special_mission = 0
	if OS.has_environment("DRONE_MAP"):
		frontline_map = OS.get_environment("DRONE_MAP")
	Global.combat_mission = clampi(Global.combat_mission, 1, 4)

	var intended_play_mode := Global.play_mode
	var intended_combat_mission := Global.combat_mission
	var intended_special_mission := Global.special_mission
	var intended_drone_preset := Global.drone_preset
	var intended_difficulty := Global.difficulty

	_apply_flight_hud_defaults()

	_map_root = get_node_or_null("MapRoot") as Node3D
	_triggers = get_node_or_null("Triggers") as Node3D
	_load_map()
	# Let the freshly instantiated map register its collision before probing it.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# PauseMenu defers MobileMenu._ready(), which reloads Menu.cfg / HUD.cfg on
	# frame 1 and can clobber env-var or menu-chosen flight mode/preset/HUD.
	Global.play_mode = intended_play_mode
	Global.combat_mission = intended_combat_mission
	Global.special_mission = intended_special_mission
	Global.drone_preset = intended_drone_preset
	Global.difficulty = intended_difficulty
	_apply_flight_hud_defaults()

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
	if Global.play_mode == Global.PlayMode.COMBAT:
		_mission_offset = Vector3(randf_range(-28.0, 28.0), 0.0,
				randf_range(-22.0, 22.0))
	_place_drone_over_ground()
	if d != null:
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
		FoliageSystemScript.spawn_dense_grass(self, g_center, g_rad, maxi(320, int(float(g_cnt) * 0.35)),
				g_base, g_tip, frontline_map,
				Vector3(d.global_position.x, 0.0, d.global_position.z), 9.0)
		var fg_script = load("res://scripts/util/follow_grass.gd")
		if fg_script != null:
			var fg = fg_script.new()
			fg.name = "FollowGrass"
			add_child(fg)
			var grass_map := frontline_map if not frontline_map.is_empty() else "valley"
			fg.setup(grass_map, QualityManagerScript.get_active_level())
			fg.set_spawn_clear(Vector3(d.global_position.x, _ground_y,
					d.global_position.z), 9.0)
			var grass_center := Vector3(d.global_position.x, _ground_y,
					d.global_position.z)
			fg.prime(grass_center)
	_hide_drone_visuals(d)
	var preset_drone := get_node_or_null("Drone")
	if preset_drone != null:
		DroneCatalog.apply_to_drone(preset_drone, Global.drone_preset)
		_model_root = preset_drone.get_node_or_null("DroneModel") as Node3D

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
		ValleySceneBuilderScript.build_railway_station(self, Vector3(0.0, _ground_y, -152.0))
		if not OS.has_environment("QA_NO_MATERIAL_UPGRADE"):
			var valley_upgrader = load("res://scripts/util/material_upgrader.gd")
			if valley_upgrader != null:
				for node_name in ["IndustrialComplex", "ConcretePipePark", "CombatFortifications", "RailwayStation"]:
					var target_node := get_node_or_null(node_name) as Node3D
					if target_node != null:
						valley_upgrader.apply_arch_weathering(target_node, "legacy", null, 400.0, _ground_y, true)
	QualityManagerScript.apply_to_scene(self)
	_tune_map_environment()
	_init_airframe_reserve()
	_setup_hud()
	_kill_cam = ReconKillCamScript.new()
	_kill_cam.name = "ReconKillCamDirector"
	add_child(_kill_cam)
	_setup_training_ghost()
	if Global.play_mode == Global.PlayMode.COMBAT:
		var markers_script = load("res://scripts/util/objective_markers.gd")
		if markers_script != null:
			var markers = markers_script.new()
			markers.name = "ObjectiveMarkers"
			_hud.add_child(markers)
			markers.setup(self)
	if _has_bomb_sight():
		call_deferred("_setup_bomber_systems")
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
	if _is_mobile_runtime():
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	var vp_main := get_viewport()
	if vp_main != null and not vp_main.size_changed.is_connected(_on_viewport_size_changed):
		vp_main.size_changed.connect(_on_viewport_size_changed)
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
	var radio := get_node_or_null("RadioController")
	var paused_now := get_tree().paused
	var d0 := d
	if d != null:
		d.flight_controller.request_arm(true)
	if radio != null:
		radio.set("test_throttle", 0.65)
	await get_tree().create_timer(0.8).timeout
	var armed: bool = d0 != null and d0.flight_controller.state_armed
	if radio != null:
		radio.set("test_throttle", -1.0)
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
	_finish_mission(_txt("ДЕМО", "DEMO"))


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
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null or we.environment == null:
		return
	var env := we.environment
	var sun := get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if QualityManager.get_active_level() != QualityManager.Level.LOW:
		env.adjustment_enabled = true
		env.adjustment_brightness = 1.0
		env.adjustment_contrast = 1.06
		env.adjustment_saturation = 1.08

	if frontline_map.is_empty():
		# Legacy Valley map: preserve authored sky/sun while sharpening terrain silhouette
		# readability with a cool opposing fill and soft valley height fog.
		env.fog_enabled = true
		env.fog_height = _ground_y + 18.0
		env.fog_height_density = 0.0065
		env.fog_aerial_perspective = maxf(env.fog_aerial_perspective, 0.35)
		if OS.get_name() == "iOS" or OS.has_feature("mobile") or OS.has_environment("MOBILE_UI"):
			env.glow_enabled = false
		var v_fill := get_node_or_null("FillLight") as DirectionalLight3D
		if v_fill == null:
			v_fill = DirectionalLight3D.new()
			v_fill.name = "FillLight"
			add_child(v_fill)
		var v_yaw := sun.rotation_degrees.y - 165.0 if sun != null else -140.0
		v_fill.rotation_degrees = Vector3(-48.0, v_yaw, 0.0)
		v_fill.light_color = Color(0.56, 0.69, 0.89)
		v_fill.light_energy = 0.28
		v_fill.shadow_enabled = false
		v_fill.light_volumetric_fog_energy = 0.0
		QualityManager.align_sky_to_sun(env, sun)
		return

	var fog_h := _ground_y + 16.0
	var fog_h_dens := 0.0085
	var fill_col := Color(0.57, 0.70, 0.89)
	var fill_energy := 0.28
	var amb_col := Color(0.46, 0.58, 0.78)
	var bg_energy := 1.0
	var contrast := 1.08
	var saturation := 1.10
	match frontline_map:
		"industrial":
			env.fog_light_color = Color(0.58, 0.64, 0.72)
			env.fog_light_energy = 0.48
			env.fog_density = 0.00024
			env.fog_aerial_perspective = 0.44
			env.volumetric_fog_density = 0.0011
			env.ambient_light_energy = 0.60
			env.ambient_light_sky_contribution = 0.78
			env.tonemap_exposure = 0.99
			env.glow_intensity = 0.22
			amb_col = Color(0.46, 0.53, 0.64)
			bg_energy = 0.76
			contrast = 1.11
			saturation = 0.98
			fog_h = _ground_y + 15.0
			fog_h_dens = 0.0095
			fill_col = Color(0.54, 0.66, 0.86)
			fill_energy = 0.30
			if sun != null:
				sun.rotation_degrees = Vector3(-22.0, 70.0, 0.0)
				sun.light_energy = 2.25
				sun.light_color = Color(0.95, 0.84, 0.72)
				sun.light_volumetric_fog_energy = 3.4
		"village":
			env.fog_light_color = Color(0.77, 0.76, 0.68)
			env.fog_light_energy = 0.52
			env.fog_density = 0.00016
			env.fog_aerial_perspective = 0.36
			env.volumetric_fog_density = 0.0010
			env.ambient_light_energy = 0.64
			env.ambient_light_sky_contribution = 0.76
			env.tonemap_exposure = 1.03
			amb_col = Color(0.48, 0.59, 0.76)
			bg_energy = 1.00
			contrast = 1.09
			saturation = 1.12
			fog_h = _ground_y + 17.0
			fog_h_dens = 0.0075
			fill_col = Color(0.58, 0.70, 0.90)
			fill_energy = 0.28
			if sun != null:
				sun.rotation_degrees = Vector3(-28.0, 42.0, 0.0)
				sun.light_energy = 2.55
				sun.light_color = Color(1.0, 0.90, 0.72)
				sun.light_volumetric_fog_energy = 3.2
		"steppe":
			env.fog_light_color = Color(0.86, 0.78, 0.62)
			env.fog_light_energy = 0.56
			env.fog_density = 0.00015
			env.fog_aerial_perspective = 0.34
			env.volumetric_fog_density = 0.0011
			env.ambient_light_energy = 0.62
			env.ambient_light_sky_contribution = 0.74
			env.tonemap_exposure = 1.04
			amb_col = Color(0.56, 0.54, 0.44)
			bg_energy = 1.04
			contrast = 1.10
			saturation = 1.14
			fog_h = _ground_y + 14.0
			fog_h_dens = 0.0065
			fill_col = Color(0.58, 0.68, 0.86)
			fill_energy = 0.26
			if sun != null:
				sun.rotation_degrees = Vector3(-20.0, 52.0, 0.0)
				sun.light_energy = 2.60
				sun.light_color = Color(1.0, 0.85, 0.64)
				sun.light_volumetric_fog_energy = 3.5
		"wetlands":
			env.fog_light_color = Color(0.60, 0.72, 0.74)
			env.fog_light_energy = 0.58
			env.fog_density = 0.00028
			env.fog_aerial_perspective = 0.52
			env.volumetric_fog_density = 0.0016
			env.ambient_light_energy = 0.58
			env.ambient_light_sky_contribution = 0.80
			env.tonemap_exposure = 1.00
			amb_col = Color(0.42, 0.55, 0.58)
			bg_energy = 0.84
			contrast = 1.07
			saturation = 1.06
			fog_h = _ground_y + 12.5
			fog_h_dens = 0.0145
			fill_col = Color(0.52, 0.67, 0.84)
			fill_energy = 0.32
			if sun != null:
				sun.rotation_degrees = Vector3(-17.0, 32.0, 0.0)
				sun.light_energy = 2.18
				sun.light_color = Color(0.96, 0.86, 0.68)
				sun.light_volumetric_fog_energy = 3.5
	# Unified ACES grade + per-map Height Fog: high key-to-fill separation keeps
	# armour, trenches and bunkers sharp against grass and mud at FPV altitude.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = clampf(env.tonemap_exposure, 0.96, 1.05)
	env.tonemap_white = 1.65
	env.background_energy_multiplier = bg_energy
	env.ambient_light_color = amb_col
	env.fog_enabled = true
	env.fog_density = clampf(env.fog_density, 0.00014, 0.00028)
	env.fog_height = fog_h
	env.fog_height_density = fog_h_dens
	env.fog_aerial_perspective = maxf(env.fog_aerial_perspective, 0.34)
	env.ambient_light_energy = clampf(env.ambient_light_energy, 0.54, 0.78)
	env.ambient_light_sky_contribution = maxf(env.ambient_light_sky_contribution, 0.72)
	if OS.get_name() == "iOS" or OS.has_feature("mobile") or OS.has_environment("MOBILE_UI"):
		env.glow_enabled = false
	env.adjustment_enabled = true
	env.adjustment_contrast = contrast
	env.adjustment_saturation = saturation
	env.adjustment_brightness = 1.0
	if sun != null:
		sun.light_energy = clampf(sun.light_energy, 1.8, 2.55)
		var mtn := get_node_or_null("FrontlineTerrain/MountainBackdrop") as MeshInstance3D
		if mtn != null and mtn.material_override is ShaderMaterial:
			var mmat := mtn.material_override as ShaderMaterial
			mmat.set_shader_parameter("sun_dir", sun.basis.z.normalized())
			mmat.set_shader_parameter("sun_scatter_color", sun.light_color)
	# Cool sky-bounce fill opposing the key sun: shapes shaded walls/tumrets
	# without flattening directional contrast.
	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		add_child(fill)
	var fill_yaw := sun.rotation_degrees.y - 165.0 if sun != null else -140.0
	fill.rotation_degrees = Vector3(-48.0, fill_yaw, 0.0)
	fill.light_color = fill_col
	fill.light_energy = fill_energy
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 0.0
	QualityManager.align_sky_to_sun(env, sun)


## Called by QualityManager after any preset change (including mid-flight):
## re-apply the map's atmosphere on top of the global profile.
func on_quality_applied() -> void:
	_tune_map_environment()


# --------------------------------------------------------------- prop builders
## Original valley content, unchanged.  Kept separate from _ready so the four
## frontline maps can swap in their own terrain without touching this code.
func _build_valley_props() -> void:
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 195.0, 820.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -28.0))
			_spawn_vegetation(300, 45.0, 510.0, 0.30)
			var d_inst := get_node_or_null("Drone") as Drone
			_flight_school = FlightSchool.new()
			add_child(_flight_school)
			_flight_school.initialize(self, d_inst, _ground_y)
		Global.PlayMode.TRAINING:
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 195.0, 620.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -28.0))
			ValleySceneBuilderScript.build_construction_crane(self, Vector3(56.0, _ground_y, -24.0), deg_to_rad(35.0))
			ValleySceneBuilderScript.build_concrete_pipe_park(self, Vector3(-58.0, _ground_y, 16.0), deg_to_rad(15.0))
			ValleySceneBuilderScript.build_container_freestyle_park(self, Vector3(22.0, _ground_y, 42.0), deg_to_rad(-10.0))
			_spawn_vegetation(410, 45.0, 175.0, 0.32)
			# Let vegetation and prop colliders enter the physics broadphase before
			# the ring course searches for clear airspace.  Combat training uses
			# one dedicated tank instead of the freestyle ring course.
			if Global.combat_training:
				var d_ct := get_node_or_null("Drone") as Drone
				_combat_training = CombatTrainingScript.new()
				add_child(_combat_training)
				_combat_training.initialize(self, d_ct, _ground_y)
			else:
				_queue_training_ring_spawn()
		_:
			if OS.has_environment("DRONE_COMBAT_MISSION"):
				Global.combat_mission = clampi(int(OS.get_environment("DRONE_COMBAT_MISSION")), 1, 4)
			ValleySceneBuilderScript.build_valley_mountains(self, _ground_y, 195.0, 640.0)
			ValleySceneBuilderScript.build_industrial_complex(self, Vector3(0.0, _ground_y, -55.0))
			ValleySceneBuilderScript.build_combat_fortifications(self, Vector3(-40.0, _ground_y, -80.0), deg_to_rad(10.0))
			ValleySceneBuilderScript.build_construction_crane(self, Vector3(64.0, _ground_y, -95.0), deg_to_rad(45.0))
			ValleySceneBuilderScript.build_container_freestyle_park(self, Vector3(45.0, _ground_y, -60.0), deg_to_rad(25.0))
			_spawn_special_or_campaign()
			_spawn_vegetation(410, 45.0, 175.0, 0.35)
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
			_spawn_vegetation(450, 45.0, 165.0, 0.30)
		"village":
			_spawn_vegetation(350, 45.0, 165.0, 0.38)
		"industrial":
			_spawn_vegetation(180, 45.0, 160.0, 0.18)
		"wetlands":
			_spawn_vegetation(250, 45.0, 160.0, 0.26)
	if Global.play_mode == Global.PlayMode.COMBAT:
		_spawn_special_or_campaign()
		_start_reinforcements()
		if frontline_map == "" and not OS.has_environment("QA_NO_DESTRUCTIBLES"):
			_spawn_destructible_buildings(4, 95.0, 148.0)
	if Global.play_mode == Global.PlayMode.TRAINING:
		if Global.combat_training:
			_combat_training = CombatTrainingScript.new()
			add_child(_combat_training)
			_combat_training.initialize(self, d, _ground_y)
		else:
			_queue_training_ring_spawn()
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		_flight_school = FlightSchool.new()
		add_child(_flight_school)
		_flight_school.initialize(self, d, _ground_y)
	var has_finalize := false
	var finalize_args := 2
	var finalize_arg0 := "level"
	for m in builder.get_script_method_list():
		if str(m.get("name", "")) == "finalize_static_batching":
			has_finalize = true
			var args: Array = m.get("args", [])
			finalize_args = args.size()
			if finalize_args >= 1:
				finalize_arg0 = str((args[0] as Dictionary).get("name", "level"))
			break
	var ft_root := get_node_or_null("FrontlineTerrain") as Node3D
	if has_finalize:
		if finalize_args <= 0:
			builder.call("finalize_static_batching")
		elif finalize_args == 1:
			builder.call("finalize_static_batching",
					ft_root if (finalize_arg0 == "root" and ft_root != null) else self)
		else:
			builder.call("finalize_static_batching",
					ft_root if (finalize_arg0 == "root" and ft_root != null) else self,
					frontline_map)
		if not OS.has_environment("QA_NO_MATERIAL_UPGRADE"):
			MaterialUpgraderScript.upgrade(self, frontline_map, QualityManagerScript.get_active_level())
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
			" infantry=", _infantry_units.size())


# ------------------------------------------------------------------ map load
func _map_path() -> String:
	if frontline_map != "":
		return ""
	match Global.play_mode:
		Global.PlayMode.TUTORIAL, Global.PlayMode.TRAINING:
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
			upgrader.apply_arch_weathering(instance, "legacy", null, 400.0, 0.0, false)
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


func _is_ground_spot_clear(x: float, z: float) -> bool:
	if absf(x) > MAP_GROUND_SAFE or absf(z) > MAP_GROUND_SAFE:
		return false
	if not frontline_map.is_empty():
		var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
		if not site.is_empty():
			var hc: Vector2 = site["center"]
			var hh: Vector2 = site["half"]
			if absf(x - hc.x) < hh.x + 6.0 and absf(z - hc.y) < hh.y + 6.0:
				return false
		var ao_list: Array = FrontlineTerrainScript.STRUCT_AO_CIRCLES.get(frontline_map, [])
		var p2 := Vector2(x, z)
		for sc in ao_list:
			var sc3: Vector3 = sc
			if p2.distance_to(Vector2(sc3.x, sc3.y)) < sc3.z + 2.0:
				return false
		var h := FrontlineTerrainScript.height_at(frontline_map, x, z)
		if frontline_map == "industrial":
			var on_bridge := absf(x) < 16.0
			var riv_z := -170.0 + 10.0 * sin(x * 0.015)
			if not on_bridge and absf(z - riv_z) < 16.0 and h < -1.7:
				return false
		var wl := _map_water_level()
		if wl > -100.0:
			var pad := 0.42 if frontline_map == "wetlands" else 0.9
			if h < wl + pad:
				return false
	return true


func _find_dry_spot(x: float, z: float) -> Vector2:
	if frontline_map.is_empty():
		return Vector2(clampf(x, -148.0, 148.0), clampf(z, -148.0, 148.0))
	if _is_ground_spot_clear(x, z):
		return Vector2(x, z)
	for ring in range(1, 15):
		var radius := 10.0 * float(ring)
		for i in range(12):
			var a := TAU * float(i) / 12.0 + float(ring) * 0.35
			var px := x + cos(a) * radius
			var pz := z + sin(a) * radius
			if _is_ground_spot_clear(px, pz):
				return Vector2(px, pz)
	var best := Vector2(clampf(x, -148.0, 148.0), clampf(z, -148.0, 148.0))
	var best_d2 := 1.0e12
	var orig := Vector2(x, z)
	for gx in range(-136, 137, 24):
		for gz in range(-136, 137, 24):
			if _is_ground_spot_clear(float(gx), float(gz)):
				var cand := Vector2(float(gx), float(gz))
				var d2 := cand.distance_squared_to(orig)
				if d2 < best_d2:
					best_d2 = d2
					best = cand
	return best


func _sanitize_ground_waypoints(wps: Array, closed_loop: bool = true) -> Array:
	if wps.is_empty() or frontline_map.is_empty():
		return wps
	var cleaned: Array = []
	for wp in wps:
		var v: Vector3 = wp as Vector3
		var dry := _find_dry_spot(v.x, v.z)
		cleaned.append(Vector3(dry.x, v.y, dry.y))
	var out: Array = []
	var count := cleaned.size()
	var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
	for i in range(count):
		var a: Vector3 = cleaned[i]
		out.append(a)
		if i == count - 1 and not closed_loop:
			continue
		var b: Vector3 = cleaned[(i + 1) % count]
		var seg_len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		if seg_len < 6.0:
			continue
		if frontline_map == "village":
			var riv_a := -140.0 + 18.0 * sin(a.z * 0.011)
			var riv_b := -140.0 + 18.0 * sin(b.z * 0.011)
			var a_west := a.x < riv_a - 8.0
			var b_west := b.x < riv_b - 8.0
			if a_west != b_west:
				var bridge_z := 40.0 if absf((a.z + b.z) * 0.5 - 40.0) <= absf((a.z + b.z) * 0.5 - 140.0) else 140.0
				var bx := -140.0 + 18.0 * sin(bridge_z * 0.011)
				var enter_x := bx - 22.0 if a_west else bx + 22.0
				var exit_x := bx + 22.0 if a_west else bx - 22.0
				out.append(Vector3(clampf(enter_x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.0, bridge_z))
				out.append(Vector3(clampf(bx, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.0, bridge_z))
				out.append(Vector3(clampf(exit_x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE), 0.0, bridge_z))
				continue
		if not site.is_empty():
			var hc: Vector2 = site["center"]
			var hh: Vector2 = site["half"]
			var steps := maxi(2, int(ceil(seg_len / 12.0)))
			var hit_hall := false
			for s_i in range(1, steps):
				var t := float(s_i) / float(steps)
				var sx := lerpf(a.x, b.x, t)
				var sz := lerpf(a.z, b.z, t)
				if absf(sx - hc.x) < hh.x + 5.0 and absf(sz - hc.y) < hh.y + 5.0:
					hit_hall = true
					break
			if hit_hall:
				var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
				var cands := [
					Vector2(hc.x - hh.x - 10.0, hc.y - hh.y - 10.0),
					Vector2(hc.x - hh.x - 10.0, hc.y + hh.y + 10.0),
					Vector2(hc.x + hh.x + 10.0, hc.y - hh.y - 10.0),
					Vector2(hc.x + hh.x + 10.0, hc.y + hh.y + 10.0),
				]
				var best_c: Vector2 = cands[0]
				var best_score := 1.0e9
				for c in cands:
					var cv: Vector2 = c
					if not _is_ground_spot_clear(cv.x, cv.y):
						continue
					var sc := Vector2(a.x, a.z).distance_to(cv) + cv.distance_to(Vector2(b.x, b.z)) + cv.distance_to(mid) * 0.2
					if sc < best_score:
						best_score = sc
						best_c = cv
				if best_score < 1.0e8:
					out.append(Vector3(best_c.x, 0.0, best_c.y))
		# Also route segments around secondary structures and reserved obstacle circles.
		var cur_a: Vector3 = out[out.size() - 1]
		var struct_circles: Array = FrontlineTerrainScript.STRUCT_AO_CIRCLES.get(frontline_map, []).duplicate()
		for r_entry in FrontlineTerrainScript.get_reserved_areas():
			var rc: Vector2 = r_entry.get("pos", Vector2.ZERO)
			var rr := float(r_entry.get("radius", 0.0))
			if rr > 4.0:
				struct_circles.append(Vector3(rc.x, rc.y, rr))
		for sc_item in struct_circles:
			var sc_v: Vector3 = sc_item
			var c_xz := Vector2(sc_v.x, sc_v.y)
			var rad := sc_v.z + 5.5
			var seg_ab := Vector2(b.x - cur_a.x, b.z - cur_a.z)
			var seg_l2 := seg_ab.length_squared()
			if seg_l2 < 1.0:
				continue
			var proj_t := clampf((c_xz - Vector2(cur_a.x, cur_a.z)).dot(seg_ab) / seg_l2, 0.05, 0.95)
			var closest := Vector2(cur_a.x, cur_a.z) + seg_ab * proj_t
			if closest.distance_to(c_xz) < rad:
				var perp := Vector2(-seg_ab.y, seg_ab.x).normalized()
				var side1 := c_xz + perp * (rad + 4.0)
				var side2 := c_xz - perp * (rad + 4.0)
				var detour := side1 if _is_ground_spot_clear(side1.x, side1.y) and side1.distance_to(closest) <= side2.distance_to(closest) else side2
				if _is_ground_spot_clear(detour.x, detour.y):
					out.append(Vector3(detour.x, 0.0, detour.y))
					cur_a = out[out.size() - 1]
	var dedup: Array = []
	for p in out:
		var pv: Vector3 = p as Vector3
		if dedup.is_empty():
			dedup.append(pv)
		else:
			var prev: Vector3 = dedup[dedup.size() - 1]
			if Vector2(prev.x, prev.z).distance_to(Vector2(pv.x, pv.z)) >= 6.0:
				dedup.append(pv)
	return dedup if not dedup.is_empty() else cleaned


## Combat launch point: 105-148 m from the mission centroid on dry open ground
## inside the compact frontline arena.
func _pick_combat_spawn() -> Vector2:
	var centre := Vector2(_mission_offset.x, 45.0 + _mission_offset.z)
	var water := _map_water_level()
	var base_angle := PI * 0.5
	for _attempt in range(64):
		var angle := base_angle + randf_range(-0.35, 0.35)
		var radius := randf_range(95.0, 142.0)
		var p := centre + Vector2(cos(angle), sin(angle)) * radius
		if absf(p.x) > MAP_GROUND_SAFE or absf(p.y) > MAP_GROUND_SAFE:
			continue
		var h := FrontlineTerrainScript.height_at(frontline_map, p.x, p.y)
		if h < water + 1.2:
			continue
		var phys := _find_ground_y(p.x, p.y)
		if absf(phys - h) > 2.2:
			continue
		return p
	return _find_dry_spot(0.0, 142.0)


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
			if absf(px) > MAP_GROUND_SAFE or absf(pz) > MAP_GROUND_SAFE:
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
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		# Flight-school strip centered inside the compact arena bounds.
		var tut_spawn := _find_dry_spot(-48.0, 138.0)
		respawn.global_position = Vector3(tut_spawn.x, respawn.global_position.y,
				tut_spawn.y)
		respawn.rotation = Vector3.ZERO
	elif Global.play_mode == Global.PlayMode.TRAINING:
		if Global.combat_training:
			# Combat training reuses the clear north-field strip of the village
			# map, so the tank always sits on open, obstacle-free ground.
			var ct_spawn := _find_dry_spot(-48.0, 138.0)
			respawn.global_position = Vector3(ct_spawn.x, respawn.global_position.y,
					ct_spawn.y)
			respawn.rotation = Vector3.ZERO
		elif OS.has_environment("DRONE_WINDOW_DEMO"):
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
			if Global != null and bool(Global.menu_settings.get("flank_spawn", false)):
				spawn = _find_dry_spot(clampf(spawn.x - 52.0, -142.0, 142.0), clampf(spawn.y - 12.0, -142.0, 142.0))
				syaw = atan2(spawn.x, spawn.y)
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
			if Global != null and bool(Global.menu_settings.get("flank_spawn", false)):
				spawn = _find_dry_spot(clampf(spawn.x - 52.0, -142.0, 142.0), clampf(spawn.y - 12.0, -142.0, 142.0))
				syaw = atan2(spawn.x, spawn.y)
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
	if absf(respawn.global_position.x) > MAP_GROUND_SAFE or absf(respawn.global_position.z) > MAP_GROUND_SAFE:
		var clamped_spawn := _find_dry_spot(
				clampf(respawn.global_position.x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE),
				clampf(respawn.global_position.z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE))
		respawn.global_position.x = clamped_spawn.x
		respawn.global_position.z = clamped_spawn.y
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
	if OS.has_environment("DRONE_WINDOW_DEMO"):
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
	if not _spawn_inside_hall:
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
		var ft_scr: Script = FrontlineTerrainScript as Script
		if not frontline_map.is_empty() and ft_scr != null and ft_scr.can_instantiate():
			pad.material_override = FrontlineTerrainScript._pbr(
					"hall_concrete", Color(0.58, 0.58, 0.56), 0.30)
		else:
			var pad_mat := StandardMaterial3D.new()
			pad_mat.albedo_color = Color(0.58, 0.58, 0.56)
			pad_mat.roughness = 0.85
			pad.material_override = pad_mat
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
	_set_flash(_txt("СКРІНШОТ: " + ("збережено" if err == OK else "помилка " + str(err)),
			"SCREENSHOT: " + ("SAVED" if err == OK else "ERROR " + str(err))))
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
		# Unfreeze smoothly so throttle lifts off from the barrel without dropping
		d.freeze = false
		d.linear_velocity = Vector3.UP * 0.1
		if d.flight_controller != null and d.flight_controller.flight_mode == FlightController.FlightMode.AUTO:
			if d.flight_controller.has_method("restore_preferred_flight_mode"):
				d.flight_controller.call("restore_preferred_flight_mode")
			elif d.flight_controller.has_method("resolve_flight_mode"):
				d.flight_controller.select_flight_mode(
						int(d.flight_controller.call("resolve_flight_mode", FlightController.FlightMode.LEVEL)))
			else:
				d.flight_controller.select_flight_mode(FlightController.FlightMode.LEVEL)
	# Once the pilot is flying, the big keyboard cheat-sheet is just clutter.
	var help := get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	if not _mission_started and not _mission_finished:
		_start_mission()


func _on_arm_failed(reason) -> void:
	var text := str(reason)
	if text == "THROTTLE_NOT_LOW" or text == "1":
		_set_flash(_txt("АРМІНГ ЗАБЛОКОВАНО: ЗНИЗЬТЕ ГАЗ ДО НУЛЯ!",
				"ARMING BLOCKED: LOWER THROTTLE TO ZERO!"))
	else:
		_set_flash(_txt("АРМІНГ НЕ ВДАВСЯ: %s", "ARMING FAILED: %s")
				% MenuUI.translate_text(text))


func _on_respawned() -> void:
	_kill_cam_triggered = false
	_pending_kamikaze_respawn = false
	_airframe_consumed_this_life = false
	_place_drone_over_ground()
	_reset_fiber_cable()
	if Global.play_mode == Global.PlayMode.TUTORIAL and _flight_school != null \
			and is_instance_valid(_flight_school) \
			and _flight_school.current_step < FlightSchool.Step.COMPLETED:
		_flight_school.reset_step()
	if Global.play_mode == Global.PlayMode.TRAINING and _combat_training != null \
			and is_instance_valid(_combat_training):
		_combat_training.on_player_respawn()
	_payload_ammo_left = int(DroneCatalog.preset(Global.drone_preset).get(
			"payload", 0))
	_reset_fpv_payload()
	_mah = 0.0
	_rings_passed = 0
	_sync_active_training_ring(false)
	_ghost_record_samples.clear()
	_ghost_record_timer = 0.0
	if _ghost_node != null and is_instance_valid(_ghost_node) and _ghost_node.has_method("reset_replay"):
		_ghost_node.reset_replay()
		if not _ghost_node.replay.is_empty():
			_ghost_node.start_replay()
	if not _mission_started:
		_radio_beat_01_sent = false
		_radio_beat_02_sent = false
		_radio_beat_03_sent = false
		_radio_beat_04_sent = false
	_radio_beat_02_fallback_timer = -1.0
	_radio_cooldown = 0.0
	_radio_subtitle_timer = 0.0
	_audio_duck_timer = 0.0
	if _radio_subtitle_panel != null:
		_radio_subtitle_panel.visible = false
	if Audio != null and Audio.has_method("stop_radio"):
		Audio.call("stop_radio")
	# Do not replay radio callouts on mid-mission respawn: radio chatter plays
	# only at initial mission start and at mission completion.


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


func _airframes_limited() -> bool:
	if Global.play_mode != Global.PlayMode.COMBAT:
		return false
	if OS.has_environment("DRONE_FULLTEST") or OS.has_environment("DRONE_AUTOTEST") \
			or OS.has_environment("DRONE_RETRY_TEST") or OS.has_environment("QA_NO_AIRFRAME_LIMIT"):
		return false
	return true


func _init_airframe_reserve() -> void:
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			_sortie_airframes_total = 6 if (Global.special_mission == 0 and Global.combat_mission == 1) else 5
		Global.Difficulty.OPERATOR:
			_sortie_airframes_total = 4 if (Global.special_mission == 0 and Global.combat_mission == 1) else 3
		_:
			_sortie_airframes_total = 3 if (Global.special_mission == 0 and Global.combat_mission == 1) else 2
	_sortie_airframes_left = _sortie_airframes_total
	_airframe_consumed_this_life = false


func consume_sortie_airframe(reason: String = "") -> bool:
	if _mission_finished or not _airframes_limited():
		return true
	if _airframe_consumed_this_life:
		return _sortie_airframes_left > 0
	_airframe_consumed_this_life = true
	_sortie_airframes_left = maxi(_sortie_airframes_left - 1, 0)
	if _sortie_airframes_left <= 0:
		var objectives_done := (_mission_targets_total > 0 and _mission_targets_destroyed >= _mission_targets_total and Global.special_mission == 0) \
				or (Global.special_mission >= 5 and _mission_targets_total > 0 and _mission_targets_destroyed >= _mission_targets_total)
		if not objectives_done:
			var delay := 1.2 if reason == "STRIKE" else 1.0
			var timer := get_tree().create_timer(delay)
			timer.timeout.connect(func() -> void:
				if _mission_finished:
					return
				# Re-evaluate at the timeout.  The last hit can land in the same
				# physics frame as the final airframe loss, and the kill-cam
				# completion is deferred by several seconds.  The old closure
				# used the stale pre-hit counters and showed "ALL AIRFRAMES
				# LOST" over a 2/2 targets-destroyed debrief.
				if _pending_combat_complete:
					return
				if _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active():
					return
				var complete_now := _mission_targets_total > 0 \
						and _mission_targets_destroyed >= _mission_targets_total
				if complete_now:
					_check_combat_mission_complete()
					return
				if Global.special_mission == 2:
					# The friendly convoy completes the operation by itself if
					# it is already on the final approach.
					if _special_convoy != null and is_instance_valid(_special_convoy) \
							and _special_convoy.global_position.distance_to(
									_special_convoy_dest) < 85.0:
						return
				elif Global.special_mission > 0 and not _special_zones.is_empty() \
						and _special_index >= _special_zones.size():
					return
				_finish_mission(_txt(
					"ВСІ БОРТИ ВТРАЧЕНО — МІСІЮ ПРОВАЛЕНО",
					"ALL AIRFRAMES LOST — MISSION FAILED"), true)
			)
			return false
	return true


# ------------------------------------------------------------------ mission
func _start_mission() -> void:
	_mission_started = true
	_mission_time = 0.0
	_payload_drops = 0
	_payload_hits = 0
	_init_airframe_reserve()
	_radio_beat_01_sent = false
	_radio_beat_02_sent = false
	_radio_beat_03_sent = false
	_radio_beat_04_sent = false
	_radio_beat_02_fallback_timer = -1.0
	_radio_cooldown = 0.0
	_radio_subtitle_timer = 0.0
	_audio_duck_timer = 0.0
	if Audio != null and Audio.has_method("stop_radio"):
		Audio.call("stop_radio")
	_set_message("")
	_set_flash(_mission_title())
	if _ghost_node != null and is_instance_valid(_ghost_node) and not _ghost_node.replay.is_empty():
		_ghost_node.reset_replay()
		_ghost_node.start_replay()
	if Global.play_mode == Global.PlayMode.COMBAT:
		if Global.special_mission > 0:
			_play_radio_callout(
				_txt("Штаб, я Борт-01. Операція «%s» — заходжу на курс. Прийом." % Global.get_special_mission_name(Global.special_mission),
					"HQ, this is Valkyrie-01. Operation %s underway, commencing run. Over." % Global.get_special_mission_name(Global.special_mission)),
				true, "01")
			_radio_beat_01_sent = true
			_radio_beat_02_fallback_timer = 5.0
		else:
			_play_radio_callout(
				_txt("Штаб, я Борт-01. Ціль у квадраті спостерігаю, заходжу на бойовий курс. Прийом.",
					"HQ, this is Valkyrie-01. Target spotted in sector, commencing attack run. Over."),
				true, "01")
			_radio_beat_01_sent = true
			if not _mission_phase_active:
				_setup_mission_phases()


func _setup_mission_phases() -> void:
	_mission_phase_active = true
	_mission_phase_hold = 0.0
	var respawn := get_node_or_null("Respawn") as Node3D
	var spawn := _clamp_ground_vec3(Vector3(respawn.global_position.x, 0.0, respawn.global_position.z)) \
			if respawn != null else Vector3(10.0, 0.0, 140.0)
	var recon_base := Vector3.ZERO
	match Global.combat_mission:
		1:
			recon_base = Vector3(-5.0, 0.0, 72.0)
		2:
			recon_base = Vector3(0.0, 0.0, 50.0)
		3:
			recon_base = Vector3(0.0, 0.0, 62.0)
		_:
			recon_base = Vector3(0.0, 0.0, 62.0)
	recon_base = _clamp_ground_vec3(recon_base + _mission_offset)
	_recon_point = recon_base
	_recon_point.y = _find_ground_y(recon_base.x, recon_base.z) + 1.6
	_extract_point = spawn
	_extract_point.y = _find_ground_y(spawn.x, spawn.z) + 1.6
	_mission_phase = 0
	_set_flash(_txt("ФАЗА 1/3 · РОЗВІДКА: ПІДЛЕТІТЬ ДО ЗОНИ Й УТРИМАЙТЕ 3 с",
			"PHASE 1/3 · RECON: APPROACH ZONE & HOLD FOR 3s"))


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
					_finish_mission(_txt("МІСІЮ %d/4 ВИКОНАНО — ОПЕРАТОР ПОВЕРНУВСЯ!" % Global.combat_mission,
							"MISSION %d/4 COMPLETE — OPERATOR RTB!" % Global.combat_mission))
			else:
				_mission_phase_hold = maxf(_mission_phase_hold - delta * 2.0, 0.0)


func _enter_strike_phase() -> void:
	_mission_phase = 1
	_mission_phase_hold = 0.0
	_set_flash(_txt("ФАЗА 2/3 · УДАР: ЗНИЩІТЬ УСІ ЦІЛІ", "PHASE 2/3 · STRIKE: DESTROY ALL TARGETS"))
	_radio_beat_02_sent = true
	_radio_beat_02_fallback_timer = -1.0
	_play_radio_callout(
		_txt("Борт-01, я Штаб. Координати підтверджено, поправка на вітер східний. Роботу дозволяю. Кінець зв'язку.",
			"Valkyrie-01, HQ copies. Coordinates confirmed, adjust for east crosswind. Cleared hot. Out."),
		true, "02")


func _enter_extract_phase() -> void:
	if _mission_phase == 2:
		return
	_mission_phase = 2
	_mission_phase_hold = 0.0
	_set_flash(_txt("ФАЗА 3/3 · ВИХІД: ПОВЕРНІТЬСЯ В ЗОНУ ЕВАКУАЦІЇ", "PHASE 3/3 · EXFIL: RETURN TO BASE ZONE"))
	_radio_beat_04_sent = true
	_play_radio_callout(
		_txt("Борт-01, ураження цілі зафіксовано камерою розвідника. Відмінна робота, повертайтесь на базу.",
			"Valkyrie-01, target destruction verified by recon feed. Good effect on target, RTB."),
		true, "04")


func _mission_phase_name() -> String:
	if not _mission_phase_active:
		return ""
	match _mission_phase:
		0:
			return "%s %d%%" % [_txt("РОЗВІДКА", "RECON"), int(clampf(_mission_phase_hold / 3.0, 0.0, 1.0) * 100.0)]
		2:
			return "%s %d%%" % [_txt("ВИХІД", "EXFIL"), int(clampf(_mission_phase_hold / 3.0, 0.0, 1.0) * 100.0)]
		_:
			return _txt("УДАР", "STRIKE")


func get_mission_phase_info() -> Dictionary:
	if not _mission_phase_active or _mission_finished:
		return {}
	match _mission_phase:
		0:
			return {"phase": 0, "pos": _recon_point, "label": _txt("РОЗВІДКА", "RECON"),
					"progress": clampf(_mission_phase_hold / 3.0, 0.0, 1.0),
					"color": Color(0.35, 0.95, 0.75)}
		2:
			return {"phase": 2, "pos": _extract_point, "label": _txt("ВИХІД", "EXFIL"),
					"progress": clampf(_mission_phase_hold / 3.0, 0.0, 1.0),
					"color": Color(0.35, 0.95, 0.75)}
		_:
			return {"phase": 1, "label": _txt("УДАР", "STRIKE"), "color": Color(1.0, 0.62, 0.20)}


## Radio callout hook: prefers synthesized VHF WAV lines on the dedicated Radio
## bus (`Audio.play_radio_line`) and falls back to CombatSfx radio tone bursts.
func _play_radio_callout(text: String, force := false, line_key: String = "") -> void:
	var r_mode := int(Global.menu_settings.get("radio_chatter_mode", 2)) if Global != null else 2
	if r_mode == 0:
		return
	var is_start_or_end := (line_key == "01" or line_key == "04" or _mission_finished \
			or text.contains("ВИКОНАНО") or text.contains("COMPLETE") \
			or text.contains("ПРОВАЛЕНО") or text.contains("FAILED"))
	# Mode 0 mutes radio voice, mode 1 keeps only start/end lines, and mode 2
	# (the default) voices every phase/kill callout with HUD subtitles.
	var play_voice := (r_mode >= 2) or is_start_or_end
	if not force and _radio_cooldown > 0.0:
		return
	_radio_cooldown = 2.6
	var dur := 2.6
	if play_voice:
		if not line_key.is_empty() and Audio != null and Audio.has_method("play_radio_line"):
			dur = maxf(float(Audio.call("play_radio_line", line_key)), 2.2)
		else:
			CombatSfxScript.play_radio(self, MenuUI.translate_text(text))
			_route_last_sfx_bus(&"Radio")
		_audio_duck_timer = maxf(dur, 2.6)
	var sub_node: Control = _radio_subtitle_panel if _radio_subtitle_panel != null else _radio_subtitle
	if _radio_subtitle != null:
		_radio_subtitle.text = "%s · %s" % [
				_txt("РАДІО", "RADIO"), MenuUI.translate_text(text)]
		if sub_node != null:
			sub_node.visible = true
		_radio_subtitle_timer = maxf(dur + 1.2, 4.4)


func _play_alert(kind: String, volume_db: float = -9.0) -> void:
	if _alert_player == null:
		return
	_alert_player.stream = CombatSfxScript.alert_stream(kind)
	_alert_player.volume_db = volume_db
	_alert_player.play()


func _mission_title() -> String:
	if Global.special_mission > 0:
		return "%s: %s — %s" % [
			_txt("СПЕЦОПЕРАЦІЯ", "SPECIAL OP"),
			Global.get_special_mission_name(Global.special_mission),
			_special_mission_hint(Global.special_mission)]
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			return _txt("ШКОЛА ПІЛОТА: базовий курс оператора FPV",
					"FLIGHT SCHOOL: FPV Operator Basic Course")
		Global.PlayMode.TRAINING:
			if Global.combat_training:
				return _txt("БОЙОВЕ ТРЕНУВАННЯ: 3 КРОКИ ДО ПЕРШОГО УРАЖЕННЯ",
						"COMBAT TRAINING: 3 STEPS TO YOUR FIRST HIT")
			return _txt("ТРЕНУВАННЯ: пролетіть усі 24 кільця",
					"TRAINING: Fly through all 24 gates")
		_:
			return _combat_mission_banner(Global.combat_mission)


func _special_mission_hint(mission_id: int) -> String:
	match mission_id:
		1:
			return _txt("3 ЗОНИ РОЗВІДКИ", "3 RECON ZONES")
		2:
			return _txt("СУПРОВІД КОЛОНИ", "CONVOY ESCORT")
		3:
			return _txt("ЕВАКУАЦІЯ ПІЛОТА", "PILOT EXTRACTION")
		4:
			return _txt("ДОСТАВКА ВАНТАЖУ", "CARGO DELIVERY")
		5:
			return _txt("НІЧНИЙ УДАР ПО ЗРК", "NIGHT SAM STRIKE")
		6:
			return _txt("ПРОРИВ КРІЗЬ РЕБ", "EW BREACH")
		7:
			return _txt("ТИЛОВА КОЛОНА", "REAR CONVOY")
		8:
			return _txt("ОРЕШНИК", "ORESHNIK")
		9:
			return _txt("ГЛИБОКИЙ ТИЛ", "DEEP STRIKE")
		_:
			return _txt("СПЕЦОПЕРАЦІЯ", "SPECIAL OP")


func _combat_mission_banner(m_id: int) -> String:
	match m_id:
		1:
			return _txt("МІСІЯ 1/4: ЗНАЙТИ І ЗНИЩИТИ ПІХОТУ", "MISSION 1/4: LOCATE & DESTROY INFANTRY")
		2:
			return _txt("МІСІЯ 2/4: ЗНАЙТИ І ЗНИЩИТИ ТАНК І БТР", "MISSION 2/4: DESTROY TANK & APC")
		3:
			return _txt("МІСІЯ 3/4: ЗНИЩИТИ ГЕЛІКОПТЕР", "MISSION 3/4: DESTROY HELICOPTER")
		_:
			return _txt("МІСІЯ 4/4: ПЕРЕХОПИТИ ШАХЕД", "MISSION 4/4: INTERCEPT SHAHED-136")


func _finish_mission(reason: String, failed: bool = false) -> void:
	if _mission_finished:
		return
	_mission_finished = true
	_mission_failed = failed
	_mission_phase_active = false
	_special_extract_active = false
	_pending_combat_complete = false
	_pending_kamikaze_respawn = false
	if _special_extract_beacon != null and is_instance_valid(_special_extract_beacon):
		_special_extract_beacon.visible = false
	_show_results(reason)


func _compute_mission_rating(final_score: int, duration_sec: float) -> Dictionary:
	var passed := 0
	var total := 1
	match Global.play_mode:
		Global.PlayMode.TRAINING:
			passed = _rings_passed
			total = _rings_total
		Global.PlayMode.COMBAT:
			if Global.special_mission > 0:
				passed = 1 if not _mission_failed else 0
				total = 1
			else:
				passed = _mission_targets_destroyed
				total = maxi(_mission_targets_total, 1)
		_:
			passed = 1 if not _mission_failed else 0
			total = 1
	if Global.has_method("compute_rating"):
		var res := Global.compute_rating(final_score, duration_sec, passed, total, _mission_failed)
		if res is Dictionary and not (res as Dictionary).is_empty():
			return res
	if _mission_failed:
		return {"stars": 0, "rank": "C", "grade": "C"}
	var par_time := 95.0 if Global.play_mode == Global.PlayMode.TRAINING else 160.0
	if duration_sec <= par_time and final_score >= 900:
		return {"stars": 3, "rank": "S", "grade": "S"}
	if duration_sec <= par_time * 1.45 or final_score >= 500:
		return {"stars": 2, "rank": "A", "grade": "A"}
	return {"stars": 1, "rank": "B", "grade": "B"}


func _show_results(reason: String) -> void:
	if _results == null:
		return
	if _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active():
		_kill_cam.cancel()
	if _is_mobile_runtime():
		_hide_mobile_gameplay_hud()
		if _results_canvas_layer != null:
			_results_canvas_layer.visible = true
	_results.visible = true
	if _results_title != null:
		_results_title.text = MenuUI.translate_text(reason)
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
	elif Global.play_mode == Global.PlayMode.COMBAT and not _mission_failed \
			and Global.special_mission > 0:
		if Global.has_method("record_special_mission_result"):
			mission_rec = Global.record_special_mission_result(
					Global.special_mission, final_score, _mission_time, Global.difficulty)
	elif Global.play_mode == Global.PlayMode.TRAINING and not _mission_failed:
		if Global.has_method("record_training_result"):
			var map_id := frontline_map if not frontline_map.is_empty() else str(Global.menu_settings.get("selected_map", "village"))
			Global.record_training_result(map_id, _mission_time, _rings_passed, _rings_total)
	if not _mission_failed and Global.has_method("get_daily_challenge"):
		var daily_ch: Dictionary = Global.get_daily_challenge()
		var cur_map := frontline_map if not frontline_map.is_empty() else str(Global.menu_settings.get("selected_map", "village"))
		var mode_matches := (int(daily_ch.get("mode", -1)) == int(Global.play_mode))
		var map_matches := (str(daily_ch.get("map", "")) == cur_map)
		var combat_ok := (Global.play_mode != Global.PlayMode.COMBAT) \
				or (Global.special_mission == 0 and Global.combat_mission >= int(daily_ch.get("mission", 1)))
		var training_ok := (Global.play_mode != Global.PlayMode.TRAINING) \
				or (_rings_total > 0 and _rings_passed >= _rings_total)
		if mode_matches and map_matches and combat_ok and training_ok \
				and not bool(daily_ch.get("completed", false)):
			Global.mark_daily_challenge_completed()
			final_score += int(daily_ch.get("bonus_score", 0))
	var gc := get_node_or_null("/root/GameCenter")
	if gc != null and not _mission_failed and gc.has_method("submit_score"):
		gc.call("submit_score", final_score)
	var rating := _compute_mission_rating(final_score, _mission_time)
	var best_line := ""
	var campaign_line := ""
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			best_line = _txt(
				"ШКОЛА ПІЛОТА    КУРС ПРОЙДЕНО (10/10 МОДУЛІВ)\nКВАЛІФІКАЦІЯ     ОПЕРАТОР УДАРНОГО FPV",
				"FLIGHT SCHOOL    COURSE COMPLETE (10/10 MODULES)\nQUALIFICATION    FPV STRIKE OPERATOR")
		Global.PlayMode.TRAINING:
			var ghost_tag := _txt(" · ПРИВИД ЗБЕРЕЖЕНО", " · GHOST SAVED") if not _ghost_record_samples.is_empty() else ""
			best_line = "%s   %d / %d%s" % [
				_txt("КІЛЬЦЯ          ", "GATES           "), _rings_passed, _rings_total, ghost_tag]
		_:
			if Global.special_mission > 0:
				var outcome := _txt("ПРОВАЛЕНО", "FAILED") if _mission_failed else _txt("ВИКОНАНО", "COMPLETED")
				var special_title := "%s «%s»" % [
					_txt("СПЕЦОПЕРАЦІЯ", "SPECIAL OP"),
					Global.get_special_mission_name(Global.special_mission)]
				match Global.special_mission:
					1:
						best_line = "%s\n%s %d/3 · %s" % [
							special_title, _txt("ЗОНИ           ", "ZONES          "), _special_index, outcome]
					2:
						best_line = "%s\n%s %s" % [special_title, _txt("КОЛОНА         ", "CONVOY         "), outcome]
					3:
						best_line = "%s\n%s %s" % [special_title, _txt("ПІЛОТ          ", "PILOT          "), outcome]
					4:
						best_line = "%s\n%s %s" % [special_title, _txt("ВАНТАЖ         ", "CARGO          "), outcome]
					_:
						best_line = "%s\n%s %d/%d · %s" % [
							special_title, _txt("ЦІЛІ           ", "TARGETS        "),
							_mission_targets_destroyed, _mission_targets_total, outcome]
			else:
				best_line = "%s\n%s %d / %d" % [
					_combat_mission_banner(Global.combat_mission),
					_txt("ЗНИЩЕНО ЦІЛЕЙ   ", "TARGETS DESTROYED "),
					_mission_targets_destroyed, _mission_targets_total
				]
				if not _mission_failed:
					var completed := Global.campaign_completed_count()
					var stars_total := Global.campaign_stars_total()
					if Global.campaign_is_complete():
						campaign_line = _txt(
							"КАМПАНІЯ        4/4 · ★ %d/12 · ЗАВЕРШЕНО\n" % stars_total,
							"CAMPAIGN        4/4 · ★ %d/12 · COMPLETED\n" % stars_total)
						if _results_title != null:
							_results_title.text = _txt(
								"ОПЕРАЦІЮ ЗАВЕРШЕНО — КАМПАНІЮ ПРОЙДЕНО!",
								"OPERATION COMPLETE — CAMPAIGN FINISHED!")
					else:
						campaign_line = _txt(
							"КАМПАНІЯ        %d/4 · ★ %d/12 · ДАЛІ: TAC-0%d\n" % [
								completed, stars_total, Global.campaign_unlocked_mission()],
							"CAMPAIGN        %d/4 · ★ %d/12 · NEXT: TAC-0%d\n" % [
								completed, stars_total, Global.campaign_unlocked_mission()])
	var can_next: bool = (Global.play_mode == Global.PlayMode.COMBAT \
			and Global.special_mission == 0 and not _mission_failed \
			and Global.combat_mission < 4 \
			and Global.is_mission_unlocked(Global.combat_mission + 1))
	if _next_mission_btn != null:
		_next_mission_btn.visible = can_next
		_next_mission_btn.text = "%s TAC-0%d  →" % [
			_txt("БРИФІНГ", "BRIEFING"), mini(Global.combat_mission + 1, 4)]
	if _results_lb_btn != null:
		_results_lb_btn.visible = (gc != null)
	var diff_line := "%s %s (x%.2f)\n" % [
		_txt("СКЛАДНІСТЬ      ", "DIFFICULTY      "), Global.get_difficulty_name(), score_mult] \
		if Global.play_mode == Global.PlayMode.COMBAT else ""
	var stars_count: int = int(rating.get("stars", int(mission_rec.get("stars", 1))))
	var grade_str := str(rating.get("rank", rating.get("grade", "S" if stars_count >= 3 else ("A" if stars_count == 2 else "B"))))
	var stars_str := ""
	for _s in range(clampi(stars_count, 0, 3)):
		stars_str += "★"
	while stars_str.length() < 3:
		stars_str += "☆"
	var award_line := ""
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		award_line = _txt(
			"НАГОРОДА         ★★★ ЗОЛОТИЙ СЕРТИФІКАТ ОПЕРАТОРА [S]\n",
			"AWARD            ★★★ GOLD OPERATOR CERTIFICATE [S]\n")
		if _flight_school != null:
			award_line += _txt(
				"МОДУЛІ           %d/%d\nПОВТОРІВ         %d\nДОВІДКА          %d\n" % [
					FlightSchool.TOTAL_MODULES, FlightSchool.TOTAL_MODULES,
					_flight_school.retries, _flight_school.help_opens],
				"MODULES          %d/%d\nRETRIES          %d\nHELP             %d\n" % [
					FlightSchool.TOTAL_MODULES, FlightSchool.TOTAL_MODULES,
					_flight_school.retries, _flight_school.help_opens])
		Global.set_tutorial_completed(true)
		if _results_title != null:
			_results_title.text = _txt("ШКОЛУ ПІЛОТА ЗАВЕРШЕНО!", "FLIGHT SCHOOL COMPLETE!")
			_results_title.add_theme_color_override("font_color", MenuUI.ACCENT)
	elif Global.special_mission > 0:
		award_line = "%s %s · %s [%s]\n" % [
			_txt("РЕЙТИНГ         ", "RATING          "),
			stars_str,
			_txt("ОПЕРАЦІЮ ПРОВАЛЕНО" if _mission_failed else "ОПЕРАЦІЮ ВИКОНАНО",
				"OPERATION FAILED" if _mission_failed else "OPERATION COMPLETE"),
			grade_str]
	elif Global.play_mode == Global.PlayMode.COMBAT and not _mission_failed:
		var m_stars: int = int(mission_rec.get("stars", stars_count))
		var m_grade := "S" if m_stars >= 3 else ("A" if m_stars == 2 else "B")
		var m_stars_str := "★".repeat(clampi(m_stars, 1, 3)) + "☆".repeat(maxi(0, 3 - m_stars))
		match m_stars:
			3:
				award_line = "%s %s %s [%s]\n" % [
					_txt("НАГОРОДА        ", "AWARD           "), m_stars_str,
					_txt("ЗОЛОТИЙ ХРЕСТ (АС)", "GOLD CROSS (ACE)"), m_grade]
			2:
				award_line = "%s %s %s [%s]\n" % [
					_txt("НАГОРОДА        ", "AWARD           "), m_stars_str,
					_txt("СРІБНА ВІДЗНАКА", "SILVER CITATION"), m_grade]
			_:
				award_line = "%s %s %s [%s]\n" % [
					_txt("НАГОРОДА        ", "AWARD           "), m_stars_str,
					_txt("БРОНЗОВА ВІДЗНАКА", "BRONZE CITATION"), m_grade]
	elif not _mission_failed:
		award_line = "%s %s [%s]\n" % [
			_txt("РЕЙТИНГ         ", "RATING          "), stars_str, grade_str]
	var cs_res := get_node_or_null("CombatSystem")
	var cs_drops: int = int(cs_res.get("drops_count")) if (cs_res != null and cs_res.get("drops_count") != null) else 0
	var cs_aa_kills: int = int(cs_res.get("aa_destroyed")) if (cs_res != null and cs_res.get("aa_destroyed") != null) else 0
	var drops_total := _payload_drops + cs_drops
	var hits_total := _payload_hits + cs_aa_kills
	var armor_kills := int(_kills.get(Vehicle.Kind.TANK, 0)) \
			+ int(_kills.get(Vehicle.Kind.BMP, 0)) \
			+ int(_kills.get(Vehicle.Kind.APC, 0))
	var aa_kills := int(_kills.get(Vehicle.Kind.SAM, 0)) + cs_aa_kills
	var inf_kills := int(_kills.get("INF", 0))
	var air_kills := int(_kills.get(Vehicle.Kind.HELI, 0)) \
			+ int(_kills.get(Vehicle.Kind.SHAHED, 0)) \
			+ int(_kills.get(Vehicle.Kind.TRUCK, 0))
	var acc_text := "—"
	if drops_total > 0:
		var hits_clamped := mini(hits_total, drops_total)
		var acc_pct := int(round(100.0 * float(hits_clamped) / float(maxi(drops_total, 1))))
		acc_text = "%d%% (%d/%d)" % [acc_pct, hits_clamped, drops_total]
	var breakdown_line := ""
	if Global.play_mode == Global.PlayMode.COMBAT:
		breakdown_line = "%s %s %d · %s %d · %s %d · %s %d\n%s %s\n" % [
			_txt("УРАЖЕННЯ        ", "KILLS           "),
			_txt("БРОНЯ", "ARMOR"), armor_kills,
			_txt("ППО", "AA"), aa_kills,
			_txt("ПІХОТА", "INF"), inf_kills,
			_txt("ПОВІТРЯ/ТИЛ", "AIR/TRK"), air_kills,
			_txt("ТОЧНІСТЬ        ", "ACCURACY        "), acc_text,
		]
	var mission_bonus := 0 if _mission_failed else (250 if Global.play_mode == Global.PlayMode.COMBAT else 100)
	var xp_gain := maxi(0, int(round(float(final_score) / 4.0)) + mission_bonus)
	if Global.has_method("record_sortie_career"):
		var career_raw = Global.call("record_sortie_career", xp_gain, {
			"armor": armor_kills,
			"aa": aa_kills,
			"infantry": inf_kills,
			"air": air_kills,
		}, hits_total, drops_total)
		if career_raw is Dictionary and _results_career_label != null and _results_career_bar != null:
			var cinfo := career_raw as Dictionary
			var rank_name := String(cinfo.get("rank_en" if _is_en() else "rank_ua", ""))
			var total_xp := int(cinfo.get("xp", xp_gain))
			var next_xp := int(cinfo.get("next_xp", total_xp))
			var promoted := bool(cinfo.get("promoted", false))
			var promo_tag := _txt("  ★ ПІДВИЩЕННЯ!", "  ★ PROMOTED!") if promoted else ""
			var xp_progress := clampf(float(cinfo.get("progress", 0.0)) * 100.0, 0.0, 100.0)
			if next_xp > total_xp:
				_results_career_label.text = "%s: %s  ·  +%d XP (%d / %d XP)%s" % [
					_txt("ЗВАННЯ", "RANK"), rank_name, xp_gain, total_xp, next_xp, promo_tag]
			else:
				_results_career_label.text = "%s: %s  ·  +%d XP (%d XP MAX)%s" % [
					_txt("ЗВАННЯ", "RANK"), rank_name, xp_gain, total_xp, promo_tag]
			_results_career_label.visible = true
			_results_career_bar.value = xp_progress
			_results_career_bar.visible = true
	_results_stats.text = "%s\n%s%s%s%s%s %s\n%s %d" % [
			best_line, diff_line, award_line, campaign_line, breakdown_line,
			_txt("ЧАС ПОЛЬОТУ     ", "FLIGHT TIME     "), _format_time(_mission_time),
			_txt("БОЙОВІ ОЧКИ     ", "COMBAT SCORE    "), final_score]
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if can_next and _next_mission_btn != null:
		_next_mission_btn.grab_focus()


func _hide_mobile_gameplay_hud() -> void:
	# The debrief has its own top-priority CanvasLayer.  Hide every flight-only
	# layer explicitly so neither the game OSD nor touch controls show beneath it.
	if _hud != null:
		_hud.visible = false
	for node_name in ["CombatHUD", "Help", "FPVOverlay"]:
		var ui_node := get_node_or_null(node_name)
		if ui_node is CanvasLayer:
			(ui_node as CanvasLayer).visible = false
		elif ui_node is CanvasItem:
			(ui_node as CanvasItem).visible = false
	var drone := get_node_or_null("Drone")
	if drone != null:
		var drone_hud = drone.get("hud")
		if drone_hud is CanvasItem:
			(drone_hud as CanvasItem).visible = false
	if _touch_controls != null:
		if _touch_controls.has_method("set_enabled"):
			_touch_controls.call("set_enabled", false)
		elif _touch_controls is CanvasLayer:
			(_touch_controls as CanvasLayer).visible = false


func _on_next_mission_pressed() -> void:
	if Audio != null and Audio.has_method("stop_radio"):
		Audio.call("stop_radio")
	get_tree().paused = false
	Global.combat_mission = clampi(Global.combat_mission + 1, 1, 4)
	Global.chain_briefing_pending = true
	if _results != null:
		_results.visible = false
	get_tree().reload_current_scene()


func _on_retry_pressed() -> void:
	if Audio != null and Audio.has_method("stop_radio"):
		Audio.call("stop_radio")
	get_tree().paused = false
	if _results != null:
		_results.visible = false
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
	if Audio != null and Audio.has_method("stop_radio"):
		Audio.call("stop_radio")
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
	material.emission_energy_multiplier = 1.0
	mesh.material_override = material
	# The next gate pulses while the rest dim; the ring material is kept on the
	# Area3D so the training HUD can drive it without another lookup path.
	area.set_meta("ring_material", material)
	# Holographic course rings must not drop hard shadows across the track.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	area.add_child(mesh)
	_triggers.add_child(area)
	return area


func _queue_training_ring_spawn() -> void:
	if _training_ring_spawn_queued:
		return
	_training_ring_spawn_queued = true
	call_deferred("_spawn_training_rings_after_world_sync")


func _spawn_training_rings_after_world_sync() -> void:
	# StaticBody3D colliders added during map construction are not queryable until
	# the next physics frame.  Waiting here makes placement consistent on every map.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_training_ring_spawn_queued = false
	if Global.play_mode == Global.PlayMode.TRAINING and not Global.combat_training \
			and not _mission_finished:
		_spawn_training_rings()


func _training_ring_position(i: int) -> Vector3:
	if _training_ring_positions.size() == 24:
		return _training_ring_positions[posmod(i, _training_ring_positions.size())]
	var xz := _training_ring_candidate_xz(i, 0)
	return Vector3(xz.x, _find_ground_y(xz.x, xz.y) + 25.0, xz.y)


func _training_ring_candidate_xz(i: int, attempt: int) -> Vector2:
	var angle := TAU * float(i % 24) / 24.0
	var course_radius := 98.0 if frontline_map.is_empty() else 124.0
	var radius := course_radius + 9.0 * sin(angle * 2.0 + 0.35)
	var radial := Vector2(cos(angle), sin(angle))
	var tangent := Vector2(-radial.y, radial.x)
	var z_scale := 0.90 if frontline_map.is_empty() else 0.88
	var base := Vector2(radial.x * radius, radial.y * radius * z_scale)
	var offset := Vector2.ZERO
	match attempt:
		1: offset = radial * 15.0
		2: offset = -radial * 15.0
		3: offset = tangent * 15.0
		4: offset = -tangent * 15.0
		5: offset = (radial + tangent).normalized() * 23.0
		6: offset = (radial - tangent).normalized() * 23.0
		7: offset = -tangent * 28.0
		8: offset = radial * 30.0
		9: offset = -radial * 30.0
		10: offset = tangent * 30.0
		11: offset = (radial + tangent).normalized() * 36.0
		12: offset = (radial - tangent).normalized() * 36.0
		13: offset = tangent * 48.0
		14: offset = -tangent * 48.0
		15: offset = (radial + tangent).normalized() * 52.0
		16: offset = (radial - tangent).normalized() * 52.0
	return base + offset


func _training_ring_map_clearance(x: float, z: float) -> bool:
	if absf(x) > MAP_GROUND_SAFE - 9.5 or absf(z) > MAP_GROUND_SAFE - 9.5:
		return false
	if frontline_map.is_empty():
		return true
	if not _is_ground_spot_clear(x, z):
		return false
	var p := Vector2(x, z)
	var site: Dictionary = FrontlineTerrainScript.HALL_SITES.get(frontline_map, {})
	if not site.is_empty():
		var center: Vector2 = site["center"]
		var half: Vector2 = site["half"]
		if absf(x - center.x) < half.x + 9.5 and absf(z - center.y) < half.y + 9.5:
			return false
	for structure in FrontlineTerrainScript.STRUCT_AO_CIRCLES.get(frontline_map, []):
		var item: Vector3 = structure
		if p.distance_to(Vector2(item.x, item.y)) < item.z + 9.5:
			return false
	# The reservation list also covers handcrafted GLBs and procedural yards
	# whose collision meshes do not have a corresponding AO-circle entry.
	for reserved in FrontlineTerrainScript.get_reserved_areas():
		var center: Vector2 = reserved.get("pos", Vector2.ZERO)
		var radius := float(reserved.get("radius", 0.0))
		if p.distance_to(center) < radius + 9.5:
			return false
	# Moving industrial cranes sweep a large volume.  Avoid their complete
	# operating envelopes, not only the frame's position on the spawn frame.
	if frontline_map == "industrial":
		for hall_site in [
			{"center": Vector2(-120.0, -40.0), "half": Vector2(38.0, 24.0)},
			{"center": Vector2(-30.0, -120.0), "half": Vector2(31.0, 21.0)},
		]:
			var center: Vector2 = hall_site["center"]
			var half: Vector2 = hall_site["half"]
			if absf(x - center.x) < half.x and absf(z - center.y) < half.y:
				return false
		if p.distance_to(Vector2(85.0, -95.0)) < 76.0:
			return false
		if p.distance_to(Vector2(45.0, -40.0)) < 50.0:
			return false
	return true


func _training_ring_ground_height(x: float, z: float) -> float:
	var highest := _find_ground_y(x, z)
	for offset_x in [-8.0, 0.0, 8.0]:
		for offset_z in [-8.0, 0.0, 8.0]:
			var sx := x + float(offset_x)
			var sz := z + float(offset_z)
			if frontline_map.is_empty():
				highest = maxf(highest, _find_ground_y(sx, sz))
			else:
				highest = maxf(highest,
						FrontlineTerrainScript.height_at(frontline_map, sx, sz))
				highest = maxf(highest,
						FrontlineTerrainScript.mesh_surface_height(frontline_map, sx, sz))
	return highest


func _training_ring_overlaps_world(pos: Vector3, clearance: BoxShape3D) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = clearance
	query.transform = Transform3D(Basis.IDENTITY, pos)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excludes: Array[RID] = []
	var drone := get_node_or_null("Drone")
	if drone is CollisionObject3D:
		excludes.append((drone as CollisionObject3D).get_rid())
	query.exclude = excludes
	return not world.direct_space_state.intersect_shape(query, 12).is_empty()


func _training_ring_spacing_ok(pos: Vector3) -> bool:
	for previous in _training_ring_positions:
		var horizontal := Vector2(pos.x - previous.x, pos.z - previous.z)
		if horizontal.length() < 17.0:
			return false
	return true


func _find_training_ring_fallback(i: int, clearance: BoxShape3D) -> Vector3:
	var base := _training_ring_candidate_xz(i, 0)
	# Search an expanding local spiral first so a relocated checkpoint still
	# follows the course smoothly around a hall, landmark or tree line.
	for shell in range(1, 8):
		var offset_radius := float(shell) * 12.0
		for sample in range(16):
			var angle := TAU * float(sample) / 16.0 + float(i) * 0.11
			var xz := base + Vector2(cos(angle), sin(angle)) * offset_radius
			if not _training_ring_map_clearance(xz.x, xz.y):
				continue
			var ground := _training_ring_ground_height(xz.x, xz.y)
			for altitude in [40.0, 48.0, 56.0]:
				var candidate := Vector3(xz.x, ground + float(altitude), xz.y)
				if _training_ring_spacing_ok(candidate) \
						and not _training_ring_overlaps_world(candidate, clearance):
					return candidate
	# A deterministic arena-wide grid is the last resort; it is still clear of
	# map landmarks and prior gates, and avoids silently stacking at the origin.
	for row in range(-6, 7):
		for column in range(-6, 7):
			var xz := Vector2(float(column) * 21.0, float(row) * 21.0)
			if not _training_ring_map_clearance(xz.x, xz.y):
				continue
			var ground := _training_ring_ground_height(xz.x, xz.y)
			var candidate := Vector3(xz.x, ground + 56.0, xz.y)
			if _training_ring_spacing_ok(candidate) \
					and not _training_ring_overlaps_world(candidate, clearance):
				return candidate
	var last_resort := Vector3(base.x, _training_ring_ground_height(base.x, base.y) + 56.0, base.y)
	for _lift in range(5):
		if not _training_ring_overlaps_world(last_resort, clearance):
			return last_resort
		last_resort.y += 8.0
	return last_resort


func _build_training_ring_positions() -> void:
	_training_ring_positions.clear()
	var clearance := BoxShape3D.new()
	# The gate's outer radius is 7.4 m.  This slightly larger envelope gives
	# props, roofs and tree trunks a visible margin rather than merely avoiding
	# the torus centreline.
	clearance.size = Vector3(18.0, 18.0, 18.0)
	var relocated := 0
	var raised := 0
	for i in range(24):
		var placed := false
		var chosen := Vector3.ZERO
		for height_bonus in [0.0, 8.0, 16.0]:
			for attempt in range(17):
				var xz := _training_ring_candidate_xz(i, attempt)
				if not _training_ring_map_clearance(xz.x, xz.y):
					continue
				var ground := _training_ring_ground_height(xz.x, xz.y)
				var altitude := 24.0 + float(i % 6) * 1.4 + float(height_bonus)
				var candidate := Vector3(xz.x, ground + altitude, xz.y)
				if not _training_ring_spacing_ok(candidate) \
						or _training_ring_overlaps_world(candidate, clearance):
					continue
				chosen = candidate
				placed = true
				if attempt > 0:
					relocated += 1
				if altitude > 36.0:
					raised += 1
				break
			if placed:
				break
		if not placed:
			# Go around the obstruction before raising a gate over it.
			chosen = _find_training_ring_fallback(i, clearance)
			placed = true
			if _training_ring_overlaps_world(chosen, clearance):
				push_warning("[TRAINING] no clear gate cell for ring %d; lifting fallback" % (i + 1))
			raised += 1
		_training_ring_positions.append(chosen)
	print("[TRAINING] safe gate course: 24 rings, relocated=", relocated,
			" raised=", raised, " map=", frontline_map if not frontline_map.is_empty() else "valley")


var _next_ring_preview: MeshInstance3D = null
var _next_turn_arrow: Node3D = null
var _ring_clean_streak: int = 0


func _spawn_training_rings() -> void:
	_rings_total = 0
	for old_ring in _training_rings:
		if is_instance_valid(old_ring):
			old_ring.queue_free()
	_training_rings.clear()
	if _next_ring_preview != null and is_instance_valid(_next_ring_preview):
		_next_ring_preview.queue_free()
	_next_ring_preview = null
	if _next_turn_arrow != null and is_instance_valid(_next_turn_arrow):
		_next_turn_arrow.queue_free()
	_next_turn_arrow = null
	_ring_clean_streak = 0
	_build_training_ring_positions()
	for i in range(24):
		var pos := _training_ring_position(i)
		var next := _training_ring_position((i + 1) % 24)
		var tangent := next - pos
		tangent.y = 0.0
		if tangent.length_squared() < 0.001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var yaw := atan2(tangent.x, tangent.z)
		var ring := _make_ring(pos, 6.2, Color(0.20, 0.86, 0.78), yaw)
		ring.set_meta("training_ring_index", i)
		ring.visible = (i == 0)
		ring.monitoring = (i == 0)
		ring.body_entered.connect(_on_ring_entered.bind(ring))
		_training_rings.append(ring)
		_rings_total += 1
	_ensure_next_ring_preview()
	_sync_active_training_ring(false)


func _ensure_next_ring_preview() -> void:
	if _triggers == null:
		return
	if _next_ring_preview != null and is_instance_valid(_next_ring_preview):
		return
	var preview := MeshInstance3D.new()
	preview.name = "NextTrainingRingPreview"
	var torus := TorusMesh.new()
	torus.inner_radius = 5.4
	torus.outer_radius = 5.85
	torus.rings = 24
	torus.ring_segments = 8
	preview.mesh = torus
	preview.rotation.x = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.20, 0.86, 0.78, 0.24)
	mat.emission_enabled = true
	mat.emission = Color(0.20, 0.86, 0.78)
	mat.emission_energy_multiplier = 0.35
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview.material_override = mat
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_triggers.add_child(preview)
	_next_ring_preview = preview
	if _next_turn_arrow == null or not is_instance_valid(_next_turn_arrow):
		var arrow_root := Node3D.new()
		arrow_root.name = "NextTurnChevron"
		var arrow_mat := StandardMaterial3D.new()
		arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		arrow_mat.albedo_color = Color(1.0, 0.86, 0.25, 0.72)
		arrow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# 4 glowing trajectory guide dashes leading from the active gate toward the next gate
		for di in range(4):
			var dash := Node3D.new()
			dash.name = "GuideDash_%d" % di
			for side_s in [-1.0, 1.0]:
				var wing := MeshInstance3D.new()
				var w_box := BoxMesh.new()
				w_box.size = Vector3(0.16, 0.16, 1.15)
				wing.mesh = w_box
				wing.position = Vector3(float(side_s) * 0.36, -1.8, 0.0)
				wing.rotation.y = float(side_s) * deg_to_rad(36.0)
				wing.material_override = arrow_mat
				wing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				dash.add_child(wing)
			arrow_root.add_child(dash)
		_triggers.add_child(arrow_root)
		_next_turn_arrow = arrow_root


func _sync_active_training_ring(animate_pop: bool = false) -> void:
	for i in range(_training_rings.size()):
		var r := _training_rings[i]
		if r == null or not is_instance_valid(r):
			continue
		var is_active := (i == _rings_passed and _rings_passed < _rings_total)
		r.visible = is_active
		r.set_deferred("monitoring", is_active)
		if is_active:
			if animate_pop and is_inside_tree():
				r.scale = Vector3.ONE * 0.42
				var tw := create_tween()
				tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(r, "scale", Vector3.ONE, 0.22)
			else:
				r.scale = Vector3.ONE
	_ensure_next_ring_preview()
	if _next_ring_preview != null and is_instance_valid(_next_ring_preview):
		var next_idx := _rings_passed + 1
		if next_idx < _training_rings.size() and _rings_passed < _rings_total:
			var nr := _training_rings[next_idx]
			var cur_r := _training_rings[_rings_passed] if _rings_passed < _training_rings.size() else null
			if nr != null and is_instance_valid(nr):
				_next_ring_preview.visible = true
				_next_ring_preview.global_position = nr.global_position
				_next_ring_preview.global_rotation = Vector3(PI * 0.5, nr.global_rotation.y, 0.0)
				if _next_turn_arrow != null and is_instance_valid(_next_turn_arrow) \
						and cur_r != null and is_instance_valid(cur_r):
					_next_turn_arrow.visible = true
					_next_turn_arrow.global_position = cur_r.global_position
					for di in range(_next_turn_arrow.get_child_count()):
						var d_node := _next_turn_arrow.get_child(di) as Node3D
						if d_node == null:
							continue
						var frac := float(di + 1) / 5.0
						d_node.global_position = cur_r.global_position.lerp(nr.global_position, frac)
						if d_node.global_position.distance_squared_to(nr.global_position) > 0.5:
							d_node.look_at(nr.global_position, Vector3.UP)
			else:
				_next_ring_preview.visible = false
				if _next_turn_arrow != null and is_instance_valid(_next_turn_arrow):
					_next_turn_arrow.visible = false
		else:
			_next_ring_preview.visible = false
			if _next_turn_arrow != null and is_instance_valid(_next_turn_arrow):
				_next_turn_arrow.visible = false


func _spawn_ring_pass_effect(ring_xf: Transform3D) -> void:
	if _triggers == null or not is_inside_tree():
		return
	var fx := MeshInstance3D.new()
	fx.name = "RingPassBurst"
	var torus := TorusMesh.new()
	torus.inner_radius = 6.2
	torus.outer_radius = 7.2
	torus.rings = 24
	torus.ring_segments = 8
	fx.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.45, 1.0, 0.88, 0.88)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fx.material_override = mat
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_triggers.add_child(fx)
	fx.global_position = ring_xf.origin
	fx.global_rotation = Vector3(PI * 0.5, ring_xf.basis.get_euler().y, 0.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(fx, "scale", Vector3.ONE * 1.48, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(fx.queue_free)


func _on_ring_entered(body: Node3D, ring: Area3D) -> void:
	if not (body is Drone) or not ring.visible:
		return
	# The highlighted gate is the active checkpoint.  Touching a later marker
	# cannot skip the course or inflate the training score.
	if _rings_passed >= _training_rings.size() \
			or _training_rings[_rings_passed] != ring:
		return
	var passed_xf := ring.global_transform
	_rings_passed += 1
	_ring_clean_streak += 1
	_score += 50 + mini(_ring_clean_streak, 10) * 10
	_spawn_ring_pass_effect(passed_xf)
	if Audio != null and Audio.has_method("play_radio_confirm_beep"):
		Audio.call("play_radio_confirm_beep", -9.0)
	Haptics.trigger_ui_tap()
	_sync_active_training_ring(true)
	_set_flash("%s %d/%d · %.1fs · ×%d" % [
		_txt("Ворота", "Gate"), _rings_passed, _rings_total, _mission_time, _ring_clean_streak])
	if _rings_passed >= _rings_total:
		_save_training_ghost()
		_finish_mission(_txt("ТРЕНУВАННЯ ЗАВЕРШЕНО", "TRAINING COMPLETE"))


## Training UX: pulse the next gate and dim the rest, so the course is readable
## at range instead of 24 identical rings scattered across the map.
func _update_training_ring_highlight(delta: float) -> void:
	if _training_rings.is_empty():
		return
	_ring_pulse += delta * 3.6
	var next_idx := mini(_rings_passed, _training_rings.size() - 1)
	var course_live := _rings_passed < _rings_total
	for i in range(_training_rings.size()):
		var ring := _training_rings[i]
		if ring == null or not is_instance_valid(ring):
			continue
		var mat := ring.get_meta("ring_material", null) as StandardMaterial3D
		if mat == null:
			continue
		if course_live and i == next_idx and ring.visible:
			# Keep the active gate clearly brighter than the course, but below
			# the tonemap roll-off so it reads as teal instead of a white blob.
			mat.emission_energy_multiplier = 1.15 + sin(_ring_pulse) * 0.20
		else:
			mat.emission_energy_multiplier = 0.45


func _checkpoint_visual(cp: Area3D) -> MeshInstance3D:
	for child in cp.get_children():
		if child is MeshInstance3D:
			return child
	return null


func _ghost_replay_file() -> String:
	var key := frontline_map if not frontline_map.is_empty() else "valley"
	return "user://ghost_training_%s.rpl" % key


func _setup_training_ghost() -> void:
	if Global.play_mode != Global.PlayMode.TRAINING or Global.combat_training:
		return
	_ghost_record_samples.clear()
	_ghost_record_timer = 0.0
	var path := _ghost_replay_file()
	if not FileAccess.file_exists(path):
		return
	var g := GhostScript.new()
	g.name = "TrainingGhost"
	g.type = GhostScript.Type.PREVIOUS
	g.replay_path = path
	add_child(g)
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var samples: Array = []
		var model_path := ""
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line.is_empty():
				continue
			if line.begins_with("MODEL:"):
				model_path = line.substr(6)
			else:
				var parts := line.split(",")
				if parts.size() >= 12:
					samples.append(parts)
		f.close()
		if not samples.is_empty():
			g.set_samples(samples, model_path)
			_ghost_node = g
			if _mission_started:
				g.start_replay()
			else:
				g.stop_replay()


func _update_training_ghost(delta: float) -> void:
	if Global.play_mode != Global.PlayMode.TRAINING or Global.combat_training \
			or not _mission_started or _mission_finished:
		return
	var drone := get_node_or_null("Drone") as Node3D
	if drone != null and _ghost_record_samples.size() < 7200:
		_ghost_record_timer += delta
		if _ghost_record_timer >= 0.05:
			_ghost_record_timer = 0.0
			var t := drone.global_transform
			_ghost_record_samples.append([
				t.basis.x.x, t.basis.x.y, t.basis.x.z,
				t.basis.y.x, t.basis.y.y, t.basis.y.z,
				t.basis.z.x, t.basis.z.y, t.basis.z.z,
				t.origin.x, t.origin.y, t.origin.z,
			])
	if _ghost_node != null and is_instance_valid(_ghost_node) and _ghost_node.state == GhostScript.State.PLAYING:
		_ghost_node.update_transform()
		_ghost_node.frame += 1
		if _ghost_node.frame >= _ghost_node.replay.size():
			_ghost_node.frame = 0


func _save_training_ghost() -> void:
	if Global.play_mode != Global.PlayMode.TRAINING or Global.combat_training \
			or _ghost_record_samples.is_empty():
		return
	var path := _ghost_replay_file()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	for sample in _ghost_record_samples:
		var vals: Array = sample
		var strs: PackedStringArray = []
		for v in vals:
			strs.append("%.4f" % float(v))
		f.store_line(",".join(strs))
	f.close()


# ------------------------------------------------------------------ vehicles
func _add_vehicle(kind: int, waypoints: Array, speed: float, hostile: bool,
		track: bool, height: float = 0.0, is_mission_target: bool = true,
		variant: String = "") -> Vehicle:
	var is_air := (kind == Vehicle.Kind.HELI or kind == Vehicle.Kind.SHAHED)
	if not waypoints.is_empty():
		var shifted: Array = []
		for wp in waypoints:
			var v: Vector3 = wp as Vector3
			if _offset_targets:
				v += _mission_offset
			v = _clamp_air_vec3(v) if is_air else _clamp_ground_vec3(v)
			# Never route ground armour through water: clamp into dry arena cells.
			if not is_air and not frontline_map.is_empty() \
					and not _is_ground_spot_clear(v.x, v.z):
				var dry := _find_dry_spot(v.x, v.z)
				v.x = dry.x
				v.z = dry.y
			shifted.append(v)
		if not is_air and not frontline_map.is_empty():
			shifted = _sanitize_ground_waypoints(shifted, true)
		if hostile and not shifted.is_empty():
			var min_dist := MIN_ENEMY_SPAWN_DIST_AIR if is_air else MIN_ENEMY_SPAWN_DIST_GROUND
			var bound := minf(MAP_AIR_SAFE, Vehicle.VEHICLE_AIR_BOUND) if is_air else MAP_GROUND_SAFE
			var sp := _player_spawn_xz()
			var best_idx := 0
			var best_d := -1.0
			for wi in range(shifted.size()):
				var wpv: Vector3 = shifted[wi]
				var d_xz := Vector2(wpv.x, wpv.z).distance_to(sp)
				if d_xz > best_d:
					best_d = d_xz
					best_idx = wi
			if best_idx > 0:
				var rotated: Array = []
				for wi in range(shifted.size()):
					rotated.append(shifted[(best_idx + wi) % shifted.size()])
				shifted = rotated
			var first_wp: Vector3 = shifted[0]
			if Vector2(first_wp.x, first_wp.z).distance_to(sp) < min_dist:
				var safe_xz := _ensure_enemy_xz_clearance(
						Vector2(first_wp.x, first_wp.z), min_dist, bound, is_air)
				shifted[0] = Vector3(safe_xz.x, first_wp.y, safe_xz.y)
			if not is_air and not frontline_map.is_empty():
				shifted = _sanitize_ground_waypoints(shifted, true)
		waypoints = shifted
	var vehicle := VEHICLE.new()
	vehicle.kind = kind
	vehicle.variant = variant
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
	vehicle.set_meta("is_primary_target", is_mission_target)
	if is_mission_target:
		vehicle.add_to_group("primary_combat_target")
	else:
		vehicle.add_to_group("bonus_combat_target")
	vehicle.destroyed.connect(_on_vehicle_destroyed.bind(kind, vehicle))
	_vehicles.append(vehicle)
	return vehicle


func _maybe_trigger_kill_cam(impact_pos: Vector3, is_key_target: bool) -> bool:
	if not is_key_target or _kill_cam == null or not is_instance_valid(_kill_cam):
		return false
	if _kill_cam.is_active():
		return false
	var now_ms := Time.get_ticks_msec()
	if _kill_cam_triggered and (now_ms - _kill_cam_last_ms) < 450:
		return false
	if (OS.has_environment("DRONE_FULLTEST") or OS.has_environment("DRONE_AUTOTEST") \
			or OS.has_environment("DRONE_RETRY_TEST")) and not OS.has_environment("DRONE_KILLCAM_TEST"):
		return false
	if DisplayServer.get_name() == "headless" and not OS.has_environment("DRONE_KILLCAM_TEST"):
		return false
	var drone := get_node_or_null("Drone") as Node3D
	var drone_pos := drone.global_position if drone != null else impact_pos + Vector3(0.0, 20.0, 45.0)
	var prev_cam := camera if camera != null else get_node_or_null("Drone/FPVCamera") as Camera3D
	_kill_cam_triggered = true
	_kill_cam_last_ms = now_ms
	var ok: bool = _kill_cam.trigger(self, impact_pos, drone_pos, prev_cam, Callable(self, "_on_kill_cam_finished"))
	if not ok:
		_kill_cam_triggered = false
	return ok


func _on_kill_cam_finished() -> void:
	_kill_cam_triggered = false
	if _pending_combat_complete:
		_pending_combat_complete = false
		_check_combat_mission_complete()
	if _pending_kamikaze_respawn and not _mission_finished and not _pending_combat_complete:
		_pending_kamikaze_respawn = false
		call_deferred("_execute_kamikaze_respawn")
	else:
		_pending_kamikaze_respawn = false


func _on_vehicle_destroyed(points: int, kind: int, vehicle: Vehicle = null) -> void:
	_kills[kind] = int(_kills.get(kind, 0)) + 1
	_score += points
	_payload_hits += 1
	var is_primary_target := true if (vehicle == null or not is_instance_valid(vehicle)) \
			else bool(vehicle.get_meta("is_primary_target", true))
	if Global.play_mode == Global.PlayMode.COMBAT:
		if is_primary_target:
			_mission_targets_destroyed += 1
		var combat := get_node_or_null("CombatSystem")
		if combat != null and combat.has_method("add_bonus_score"):
			if is_primary_target:
				combat.call("add_bonus_score", points, "%s (%s %d/%d)" % [
					_kind_name(kind), _txt("ОСН.", "MAIN"),
					_mission_targets_destroyed, _mission_targets_total
				])
			else:
				combat.call("add_bonus_score", points, "%s +%d (%s %d/%d)" % [
					_kind_name(kind), points, _txt("ОСН.", "MAIN"),
					_mission_targets_destroyed, _mission_targets_total
				])
		if is_primary_target:
			_set_flash("%s (%s %d/%d)" % [
				_kind_name(kind), _txt("ОСН.", "MAIN"),
				_mission_targets_destroyed, _mission_targets_total
			])
		else:
			_set_flash("%s +%d (%s %d/%d)" % [
				_kind_name(kind), points, _txt("ОСН.", "MAIN"),
				_mission_targets_destroyed, _mission_targets_total
			])
		var drone := get_node_or_null("Drone") as Node3D
		var impact_pos := vehicle.global_position if (vehicle != null and is_instance_valid(vehicle)) \
				else (drone.global_position if drone != null else Vector3.ZERO)
		_last_strike_pos = impact_pos
		var is_key: bool = is_primary_target \
				or kind in [Vehicle.Kind.TANK, Vehicle.Kind.BMP, Vehicle.Kind.APC, Vehicle.Kind.HELI, Vehicle.Kind.SHAHED, Vehicle.Kind.SAM]
		var kc_started := _maybe_trigger_kill_cam(impact_pos, is_key)
		var kc_active := kc_started or (_kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active())
		if is_primary_target and not _radio_beat_03_sent:
			_radio_beat_03_sent = true
			_play_radio_callout(
				_txt("Штаб! Пряме влучання в моторний відсік! Спостерігаю вторинну детонацію боєкомплекту!",
					"HQ! Direct hit on the engine deck! Secondary ammo cook-off confirmed!"),
				true, "03")
		elif is_primary_target:
			var is_crit := bool(vehicle.get_meta("critical_weak_spot_kill", false)) if vehicle != null else false
			if is_crit:
				_set_flash(_txt("★ ДЕТОНАЦІЯ БК! УРАЗЛИВА ЗОНА +200 XP", "★ AMMO COOK-OFF! WEAK SPOT +200 XP"))
			_play_radio_callout("%s — %s" % [_txt("ЦІЛЬ УРАЖЕНО", "TARGET HIT"), _kind_name(kind)])
		CombatSfxScript.play_hitmarker(self, true)
		_advance_phase_after_kill(is_primary_target, kc_active and _mission_targets_destroyed >= _mission_targets_total)
	else:
		CombatSfxScript.play_hitmarker(self, true)
		_set_flash("%s +%d" % [_kind_name(kind), points])


func _add_mission_infantry(pos: Vector3, patrol_axis: Vector3, patrol_dist: float,
		patrol_spd: float, count_as_primary: bool = true,
		variant: String = "") -> Node3D:
	if not count_as_primary \
			and QualityManager.get_active_level() == QualityManager.Level.LOW:
		# LOW caps decorative patrols rather than removing all guards and
		# reinforcement waves so objectives still push back dynamically.
		if _low_bonus_infantry_count >= 8:
			return null
		_low_bonus_infantry_count += 1
	if _offset_targets:
		pos += _mission_offset
	pos = _clamp_ground_vec3(pos)
	if not frontline_map.is_empty():
		if not _is_ground_spot_clear(pos.x, pos.z):
			var dry := _find_dry_spot(pos.x, pos.z)
			pos.x = dry.x
			pos.z = dry.y
	var safe_inf := _ensure_enemy_xz_clearance(
			Vector2(pos.x, pos.z), MIN_ENEMY_SPAWN_DIST_GROUND, MAP_GROUND_SAFE, false)
	pos.x = safe_inf.x
	pos.z = safe_inf.y
	var unit := EnemyRiflemanScript.new()
	unit.name = "MissionInfantry_%d" % _infantry_units.size()
	unit.variant = variant
	if variant == "spetsnaz":
		unit.max_health = 75.0
		unit.points = 220
	add_child(unit)
	var gy := _find_ground_y(pos.x, pos.z)
	var ground_pos := Vector3(pos.x, gy, pos.z)
	unit.global_position = ground_pos
	var dir := patrol_axis.normalized() if patrol_axis.length_squared() > 0.001 else Vector3.FORWARD
	unit.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)
	unit.set_patrol(ground_pos, dir, patrol_dist, patrol_spd)
	unit.set_meta("is_primary_target", count_as_primary)
	if count_as_primary:
		unit.add_to_group("primary_combat_target")
	else:
		unit.add_to_group("bonus_combat_target")
	_infantry_units.append(unit)
	if count_as_primary:
		_mission_targets_total += 1
	unit.destroyed.connect(_on_infantry_unit_destroyed.bind(count_as_primary, unit))
	return unit


func _on_infantry_unit_destroyed(points: int, is_primary: bool, unit: Node3D = null) -> void:
	_kills["INF"] = int(_kills.get("INF", 0)) + 1
	_score += points
	_payload_hits += 1
	if is_primary:
		_mission_targets_destroyed += 1
	var flash_msg := ""
	if is_primary:
		flash_msg = "%s %d/%d)" % [
			_txt("ПІХОТИНЕЦЬ (ОСН.", "INFANTRY (MAIN"),
			_mission_targets_destroyed, _mission_targets_total
		]
	else:
		flash_msg = "%s +%d (%s %d/%d)" % [
			_txt("ПІДКРІПЛЕННЯ", "REINFORCEMENT"),
			points,
			_txt("ОСН.", "MAIN"),
			_mission_targets_destroyed, _mission_targets_total
		]
	var combat := get_node_or_null("CombatSystem")
	if combat != null and combat.has_method("add_bonus_score"):
		combat.call("add_bonus_score", points, flash_msg)
	_set_flash(flash_msg)
	var kc_started := false
	if is_primary:
		var drone := get_node_or_null("Drone") as Node3D
		var impact_pos := unit.global_position if (unit != null and is_instance_valid(unit)) \
				else (drone.global_position if drone != null else Vector3.ZERO)
		kc_started = _maybe_trigger_kill_cam(impact_pos, true)
	var kc_active := kc_started or (_kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active())
	if is_primary:
		if not _radio_beat_03_sent and _mission_targets_destroyed >= _mission_targets_total:
			_radio_beat_03_sent = true
			_play_radio_callout(
				_txt("Штаб! Пряме влучання в сектор! Ціль ліквідовано!",
					"HQ! Direct hit on target sector! Enemy neutralized!"),
				true, "03")
		else:
			_play_radio_callout(_txt("ЦІЛЬ УРАЖЕНО — ПІХОТА", "TARGET HIT — INFANTRY"))
	CombatSfxScript.play_hitmarker(self, true)
	_advance_phase_after_kill(is_primary, kc_active and _mission_targets_destroyed >= _mission_targets_total)


func _advance_phase_after_kill(is_primary: bool, defer_for_kill_cam: bool) -> void:
	if is_primary and _mission_phase_active and _mission_phase == 0 \
			and not _mission_finished and _mission_targets_destroyed < _mission_targets_total:
		_enter_strike_phase()
	if defer_for_kill_cam:
		_pending_combat_complete = true
	else:
		_check_combat_mission_complete()


func _check_combat_mission_complete() -> void:
	if _mission_finished or _mission_targets_total <= 0:
		return
	if _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active():
		_pending_combat_complete = true
		return
	if _mission_targets_destroyed >= _mission_targets_total:
		# All primary targets (infantry + armor/air) are destroyed: complete
		# directly without leaving a lingering blue extraction marker.
		_mission_phase_active = false
		_mission_phase = 1
		_special_extract_active = false
		if _special_extract_beacon != null and is_instance_valid(_special_extract_beacon):
			_special_extract_beacon.visible = false
		if Global.special_mission > 0:
			_finish_special_success()
			return
		var msg := _txt("МІСІЮ %d/4 ВИКОНАНО!" % Global.combat_mission,
				"MISSION %d/4 COMPLETE!" % Global.combat_mission)
		if Global.combat_mission >= 4:
			msg = _txt("БОЙОВУ КАМПАНІЮ 4/4 ПОВНІСТЮ ВИКОНАНО!",
					"COMBAT CAMPAIGN 4/4 FULLY COMPLETED!")
		await get_tree().create_timer(0.8).timeout
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
	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		if _weather == 3:
			we.environment.ambient_light_energy = 0.24
		elif frontline_map != "":
			_tune_map_environment()
		else:
			we.environment.ambient_light_energy = maxf(we.environment.ambient_light_energy, 0.72)
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
	CombatSfxScript.play_thunder(self, thunder_pos, 4.0)
	_route_last_sfx_bus(&"Combat")

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
	if Global.play_mode == Global.PlayMode.COMBAT:
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
		if _radio_subtitle_timer <= 0.0:
			if _radio_subtitle_panel != null:
				_radio_subtitle_panel.visible = false
			elif _radio_subtitle != null:
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
			return _txt("ТАНК", "TANK")
		Vehicle.Kind.APC:
			return _txt("БТР", "APC")
		Vehicle.Kind.TRUCK:
			return _txt("ВАНТАЖІВКА", "TRUCK")
		Vehicle.Kind.BMP:
			return _txt("БМП", "IFV")
		Vehicle.Kind.SAM:
			return _txt("ЗРК", "SAM")
		Vehicle.Kind.HELI:
			return _txt("ГЕЛІКОПТЕР", "HELICOPTER")
		Vehicle.Kind.SHAHED:
			return _txt("ШАХЕД", "SHAHED-136")
	return _txt("ЦІЛЬ", "TARGET")


func _loop_waypoints(cx: float, cz: float, radius: float, count: int,
		phase := 0.0) -> Array:
	var points := []
	for i in range(count):
		var t := phase + float(i) / float(count) * TAU
		points.append(Vector3(cx + cos(t) * radius, 0.0, cz + sin(t) * radius))
	return points


func _spawn_vehicles() -> void:
	var lowspec := QualityManager.get_active_level() == QualityManager.Level.LOW
	# civilian traffic circling within the compact arena bounds
	for i in range(2 if lowspec else 6):
		var kind: int = [Vehicle.Kind.TRUCK, Vehicle.Kind.APC, Vehicle.Kind.TANK][i % 3]
		var points := _loop_waypoints(0.0, 0.0, 82.0 + float(i) * 11.0, 5,
				float(i) * 0.9)
		_add_vehicle(kind, points, 8.0 + i, false, false, 0.0, false)
	# a few extras: BMPs and two sightseeing helicopters
	for i in range(1 if lowspec else 2):
		_add_vehicle(Vehicle.Kind.BMP,
				_loop_waypoints(0.0, 0.0, 128.0 + float(i) * 16.0, 6, 0.5 + float(i)),
				7.0, false, false, 0.0, false)
	if not lowspec:
		for i in range(2):
			_add_vehicle(Vehicle.Kind.HELI,
					_loop_waypoints(0.0, 0.0, 130.0 + float(i) * 24.0, 6, float(i) * 1.5),
					11.0, false, false, 55.0 + i * 15.0, false)


## Standalone special-operation spawner.  Campaign missions still go through
## _spawn_combat_mission(); these sorties reuse the same combat sandbox but
## have their own objectives and never write campaign records.
func _spawn_special_or_campaign() -> void:
	if Global.special_mission > 0:
		_spawn_special_mission(Global.special_mission)
	else:
		_spawn_combat_mission(Global.combat_mission)


func _special_ground_point(x: float, z: float) -> Vector3:
	var px := clampf(x, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	var pz := clampf(z, -MAP_GROUND_SAFE, MAP_GROUND_SAFE)
	if not frontline_map.is_empty():
		if not _is_ground_spot_clear(px, pz):
			var dry := _find_dry_spot(px, pz)
			px = dry.x
			pz = dry.y
		var gy := FrontlineTerrainScript.height_at(frontline_map, px, pz)
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
	# Objective beams used to be 18 m tall and 0.7 m wide, which filled the
	# whole screen like a giant green wall in the convoy mission.  Keep a slim
	# navigation column that marks the point without obscuring the scene.
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.16
	cylinder.height = 6.0
	beam.mesh = cylinder
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.10)
	beam_mat.emission_enabled = true
	beam_mat.emission = color
	beam_mat.emission_energy_multiplier = 0.55
	beam.material_override = beam_mat
	beam.position.y = 3.0
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


func _spawn_special_guards(spots: Array, count_as_primary: bool = false,
		variant: String = "") -> void:
	for spot in spots:
		var p: Vector3 = spot
		_add_mission_infantry(p, Vector3(1.0, 0.0, 0.4), 13.0, 1.7,
				count_as_primary, variant)


func _add_aa_gun(pos: Vector3, count_as_primary: bool = false) -> Node3D:
	if _offset_targets:
		pos += _mission_offset
	pos = _clamp_ground_vec3(pos)
	if not frontline_map.is_empty() and not _is_ground_spot_clear(pos.x, pos.z):
		var dry := _find_dry_spot(pos.x, pos.z)
		pos.x = dry.x
		pos.z = dry.y
	var safe := _ensure_enemy_xz_clearance(Vector2(pos.x, pos.z), 72.0, MAP_GROUND_SAFE - 14.0, true)
	pos.x = safe.x
	pos.z = safe.y
	pos.y = _find_ground_y(pos.x, pos.z)
	var gun: Node3D = AAGunScript.new()
	add_child(gun)
	gun.global_position = pos
	if count_as_primary:
		gun.add_to_group("primary_combat_target")
	else:
		gun.add_to_group("bonus_combat_target")
	gun.destroyed.connect(_on_aa_gun_destroyed)
	_aa_guns.append(gun)
	return gun


func _on_aa_gun_destroyed(points: int) -> void:
	_score += points
	var combat := get_node_or_null("CombatSystem")
	if combat != null and combat.has_method("add_bonus_score"):
		combat.call("add_bonus_score", points,
				_txt("ЗЕНІТНУ УСТАНОВКУ ЗНИЩЕНО", "AA EMPLACEMENT DESTROYED"))
	CombatSfxScript.play_hitmarker(self, true)
	_set_flash("%s +%d" % [_txt("Зенітка", "AA Gun"), points])


func _on_vehicle_mobility_kill(_vehicle: Node3D) -> void:
	Haptics.trigger_ui_tap()
	CombatSfxScript.play_hitmarker(self, false)
	_set_flash(_txt("⚡ ХІД ЗБИТО (MOBILITY KILL)! ЦІЛЬ ЗНЕРУХОМЛЕНО — ДОБИВАЙТЕ!",
			"⚡ MOBILITY KILL! TARGET IMMOBILIZED — FINISH IT!"))


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
	], false, "spetsnaz" if ew_breach else "")
	_add_aa_gun(Vector3(-42.0, 0.0, -18.0), false)
	if ew_breach:
		_spawn_special_guards([Vector3(0.0, 0.0, -45.0)], false, "spetsnaz")
		_add_aa_gun(Vector3(46.0, 0.0, -52.0), false)


func _spawn_special_rear_convoy() -> void:
	var btr_route := [
		Vector3(-92.0, 0.0, 32.0), Vector3(88.0, 0.0, -32.0),
		Vector3(72.0, 0.0, -82.0), Vector3(-92.0, 0.0, -24.0),
	]
	_add_vehicle(Vehicle.Kind.APC, btr_route, 8.6, true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	var mtsm_route := [
		Vector3(78.0, 0.0, -18.0), Vector3(-78.0, 0.0, 22.0),
		Vector3(-78.0, 0.0, -64.0), Vector3(78.0, 0.0, -64.0),
	]
	_add_vehicle(Vehicle.Kind.APC, mtsm_route, 6.6, true, true, 0.0, true, "mtsm")
	_mission_targets_total += 1
	var ural_route := [
		Vector3(-72.0, 0.0, -52.0), Vector3(72.0, 0.0, 14.0),
		Vector3(86.0, 0.0, -44.0),
	]
	_add_vehicle(Vehicle.Kind.TRUCK, ural_route, 7.4, true, false, 0.0, true, "ural")
	_mission_targets_total += 1
	_spawn_special_guards([
		Vector3(-38.0, 0.0, 28.0), Vector3(40.0, 0.0, -48.0),
	], true, "spetsnaz")
	_add_aa_gun(Vector3(0.0, 0.0, -36.0), false)


func _spawn_special_oreshnik(deep_strike: bool) -> void:
	var oreshnik_route := [
		Vector3(-52.0, 0.0, -45.0), Vector3(52.0, 0.0, -45.0),
		Vector3(52.0, 0.0, -95.0), Vector3(-52.0, 0.0, -95.0),
	]
	_add_vehicle(Vehicle.Kind.SAM, oreshnik_route, 3.4 if deep_strike else 3.2,
			true, true, 0.0, true, "oreshnik")
	_mission_targets_total += 1
	var btr_route := [
		Vector3(-78.0, 0.0, 18.0), Vector3(78.0, 0.0, 18.0),
		Vector3(78.0, 0.0, -28.0), Vector3(-78.0, 0.0, -28.0),
	]
	_add_vehicle(Vehicle.Kind.APC, btr_route, 9.0 if deep_strike else 8.4,
			true, true, 0.0, true, "btr8")
	_mission_targets_total += 1
	_add_aa_gun(Vector3(-48.0, 0.0, -28.0), false)
	if deep_strike:
		var sam_route := [
			Vector3(-68.0, 0.0, -10.0), Vector3(68.0, 0.0, -10.0),
			Vector3(68.0, 0.0, -78.0), Vector3(-68.0, 0.0, -78.0),
		]
		_add_vehicle(Vehicle.Kind.SAM, sam_route, 4.5, true, true)
		_mission_targets_total += 1
		var mtsm_route := [
			Vector3(82.0, 0.0, 28.0), Vector3(-82.0, 0.0, 28.0),
			Vector3(-82.0, 0.0, -56.0), Vector3(82.0, 0.0, -56.0),
		]
		_add_vehicle(Vehicle.Kind.APC, mtsm_route, 6.8, true, true, 0.0, true, "mtsm")
		_mission_targets_total += 1
		_spawn_special_guards([
			Vector3(-28.0, 0.0, 35.0), Vector3(32.0, 0.0, -45.0),
		], true, "spetsnaz")
		_add_aa_gun(Vector3(44.0, 0.0, -68.0), false)
	else:
		var ural_route := [
			Vector3(-45.0, 0.0, -15.0), Vector3(45.0, 0.0, -65.0),
		]
		_add_vehicle(Vehicle.Kind.TRUCK, ural_route, 6.8, true, false, 0.0, true, "ural")
		_mission_targets_total += 1
		_spawn_special_guards([
			Vector3(-32.0, 0.0, -25.0), Vector3(36.0, 0.0, -58.0),
		], false, "spetsnaz")


func _setup_special_escort() -> void:
	var raw_pts: Array = []
	match frontline_map:
		"village":
			raw_pts = [Vector2(-115.0, -22.0), Vector2(-65.0, -17.0), Vector2(-20.0, -10.0), Vector2(45.0, -16.0), Vector2(115.0, -18.0)]
		"industrial":
			raw_pts = [Vector2(-115.0, -24.0), Vector2(-65.0, -29.0), Vector2(-16.0, -34.0), Vector2(52.0, -29.0), Vector2(115.0, -26.0)]
		"wetlands":
			raw_pts = [Vector2(-128.0, 70.0), Vector2(-108.0, 12.0), Vector2(-42.0, -18.0), Vector2(54.0, -8.0), Vector2(124.0, 20.0)]
		_:
			raw_pts = [Vector2(-95.0, 122.0), Vector2(-40.0, 96.0), Vector2(22.0, 42.0), Vector2(56.0, -28.0), Vector2(64.0, -110.0)]
	var raw_route: Array = []
	for p2 in raw_pts:
		var v2: Vector2 = p2
		raw_route.append(_special_ground_point(v2.x, v2.y))
	if not frontline_map.is_empty():
		raw_route = _sanitize_ground_waypoints(raw_route, false)
	var route: Array[Vector3] = []
	for wp in raw_route:
		var v: Vector3 = wp as Vector3
		route.append(_special_ground_point(v.x, v.z))
	var vehicle := VEHICLE.new()
	vehicle.kind = Vehicle.Kind.TRUCK
	vehicle.hostile = false
	vehicle.track_drone = false
	vehicle.move_speed = 8.0
	add_child(vehicle)
	vehicle.max_health = 480.0
	vehicle.health = 480.0
	vehicle.global_position = route[0] + Vector3.UP * 0.2
	vehicle.set_waypoints(route)
	vehicle.remove_from_group("combat_target")
	vehicle.add_to_group("escort_convoy")
	vehicle.destroyed.connect(_on_escort_destroyed)
	_special_convoy = vehicle
	_special_convoy_start = route[0]
	_special_convoy_dest = route[route.size() - 1]
	_spawn_special_guards([
		Vector3(-35.0, 0.0, 18.0), Vector3(24.0, 0.0, 16.0),
		Vector3(82.0, 0.0, -42.0),
	])
	var ambush_route := _sanitize_ground_waypoints([
		Vector3(24.0, 0.0, -48.0), Vector3(68.0, 0.0, -42.0),
	])
	_add_vehicle(Vehicle.Kind.APC, ambush_route, 5.5, true, false, 0.0, false, "btr8")


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
	_special_convoy_stall_anchor = Vector3.ZERO
	_special_convoy_stall = 0.0
	_special_convoy_recoveries = 0
	_special_extract_active = false
	_special_extract_hold = 0.0
	_special_extract_point = _special_ground_point(10.0, 145.0)
	_special_extract_beacon = null
	_special_pickup_prop = null
	_offset_targets = false

	match mission_id:
		1:
			_add_special_zone(Vector3(-55.0, 0.0, 110.0), 34.0, 2.0, "РОЗВІДКА 1/3")
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
			_add_special_zone(Vector3(10.0, 0.0, 145.0), 42.0, 3.0, "ЕВАКУАЦІЯ · БАЗА")
			_special_pickup_prop = _spawn_special_pickup_marker(
					_special_zones[0]["pos"], true)
			_spawn_special_guards([
				Vector3(30.0, 0.0, -30.0), Vector3(95.0, 0.0, -75.0),
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
		7:
			_spawn_special_rear_convoy()
		8:
			_spawn_special_oreshnik(false)
		9:
			_spawn_special_oreshnik(true)

	if mission_id >= 5:
		_special_extract_beacon = _spawn_special_beacon(_special_extract_point,
				_txt("ВИХІД · БАЗА", "EXFIL · BASE"), Color(0.35, 0.95, 0.75))
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
	_set_flash(_txt("ЦІЛІ УРАЖЕНО — ПОВЕРТАЙСЯ НА БАЗУ", "TARGETS DESTROYED — RTB"))
	_radio_beat_04_sent = true
	_play_radio_callout(
		_txt("Борт-01, ураження цілі зафіксовано камерою розвідника. Відмінна робота, повертайтесь на базу.",
			"Valkyrie-01, target destruction verified by recon feed. Good effect on target, RTB."),
		true, "04")


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
			_set_flash(_txt("НЕ ВІДРИВАЙТЕСЯ ВІД КОЛОНИ!", "STAY WITH THE CONVOY!"))
			_play_radio_callout(_txt("ТРИМАЙТЕСЬ БЛИЖЧЕ ДО КОЛОНИ",
					"KEEP CLOSER TO THE CONVOY"), true)
		if _special_convoy_far_timer > 12.0:
			_special_fail("КОЛОНУ ВТРАЧЕНО — СУПРОВІД ПРОВАЛЕНО")
	else:
		_special_convoy_far_timer = maxf(_special_convoy_far_timer - delta * 2.0, 0.0)
		if _special_convoy_far_timer < 1.0:
			_special_convoy_warned = false
	var convoy_dist := _special_convoy.global_position.distance_to(_special_convoy_dest)
	if convoy_dist < 55.0:
		_finish_special_success()
		return
	# The truck is kinematic: if a blocker or a bad nav segment stops it, the
	# old code could sit at the same spot until the mission timer expired.
	# Watch real displacement and force waypoint skips / a direct goal run.
	if _special_convoy_stall_anchor == Vector3.ZERO:
		_special_convoy_stall_anchor = _special_convoy.global_position
	if _special_convoy.global_position.distance_to(_special_convoy_stall_anchor) < 0.35:
		_special_convoy_stall += delta
	else:
		_special_convoy_stall_anchor = _special_convoy.global_position
		_special_convoy_stall = 0.0
	if _special_convoy_stall >= 4.0:
		_special_convoy_stall = 0.0
		_special_convoy_recoveries += 1
		_special_convoy.call("escort_emergency_advance")
		if _special_convoy_recoveries == 1:
			_set_flash(_txt("КОЛОНА ОБ'ЇЗДИТЬ ПЕРЕШКОДУ", "CONVOY BYPASSING OBSTACLE"))
		# Last-resort recovery: after four blocked attempts place the convoy on
		# the final approach so a level-geometry dead end can never soft-lock the
		# operation.  The move happens off the normal route and preserves the
		# success condition (arrival at the checkpoint).
		if _special_convoy_recoveries >= 4:
			_special_convoy_recoveries = 0
			var approach := _special_convoy_dest - _special_convoy_start
			approach.y = 0.0
			if approach.length_squared() > 0.01:
				approach = approach.normalized()
			var drop := _special_ground_point(
					_special_convoy_dest.x - approach.x * 30.0,
					_special_convoy_dest.z - approach.z * 30.0)
			_special_convoy.global_position = drop + Vector3.UP * 0.2
			_special_convoy.call("escort_emergency_advance")
			_play_radio_callout(_txt("КОЛОНА ПРОРВАЛАСЬ ДО КП — СУПРОВІД ТРИВАЄ",
					"CONVOY BROKE THROUGH TO THE CP — ESCORT CONTINUES"), true)


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
	var next_label := MenuUI.translate_text(str(next_zone["label"]))
	_set_flash(_txt("ЗОНУ ПРОЙДЕНО — ДАЛІ: %s", "ZONE CLEARED — NEXT: %s") % next_label)
	_play_radio_callout(_txt("ЗОНУ ПРОЙДЕНО — РУХАЙТЕСЬ ДАЛІ",
			"ZONE CLEARED — MOVE TO THE NEXT"), true)


func _finish_special_success() -> void:
	if _mission_finished:
		return
	for beacon in _special_beacons:
		if is_instance_valid(beacon):
			beacon.visible = false
	_play_radio_callout(_txt("ОПЕРАЦІЮ ВИКОНАНО — ГАРНА РОБОТА",
			"OPERATION COMPLETE — GOOD WORK"), true)
	_finish_mission(_txt("СПЕЦОПЕРАЦІЮ «%s» ВИКОНАНО!",
			"SPECIAL OPERATION ‘%s’ COMPLETE!") \
			% Global.get_special_mission_name(Global.special_mission), false)


func _special_fail(reason: String) -> void:
	if _mission_finished:
		return
	_play_radio_callout(_txt("ОПЕРАЦІЮ ПРОВАЛЕНО — ПОВЕРТАЙСЯ НА БАЗУ",
			"MISSION FAILED — RETURN TO BASE"), true)
	_finish_mission(reason, true)


func _on_escort_destroyed(_points: int) -> void:
	_special_fail("КОЛОНУ ЗНИЩЕНО — СУПРОВІД ПРОВАЛЕНО")


func get_special_objective_info() -> Dictionary:
	if _special_extract_active:
		return {
			"pos": _special_extract_point,
			"label": _txt("ВИХІД · БАЗА", "EXFIL · BASE"),
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
			"label": _txt("КОЛОНА", "CONVOY"),
			"progress": travelled,
			"show_progress": true,
			"color": Color(1.0, 0.82, 0.42),
		}
	if _special_index < _special_zones.size():
		var zone: Dictionary = _special_zones[_special_index]
		return {
			"pos": zone["pos"],
			"label": MenuUI.translate_text(str(zone["label"])),
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
	# Dynamic operational deployment zones per sortie (_mission_offset is added directly below).
	_offset_targets = false
	_mission_offset = Vector3(randf_range(-28.0, 28.0), 0.0, randf_range(-22.0, 22.0))

	match mission_id:
		1:
			# МІСІЯ 1: Знайти і знищити піхоту (Легка складність)
			var sector_roll := randi() % 3
			var base_center := Vector3(0.0, 0.0, 75.0) + _mission_offset
			if sector_roll == 1:
				base_center = Vector3(-65.0, 0.0, 55.0) + _mission_offset
			elif sector_roll == 2:
				base_center = Vector3(65.0, 0.0, 65.0) + _mission_offset
			var sp_xz := _player_spawn_xz()
			if Vector2(base_center.x, base_center.z).distance_to(sp_xz) < 95.0:
				var safe_bc := _ensure_enemy_xz_clearance(
						Vector2(base_center.x, base_center.z), 98.0, MAP_GROUND_SAFE - 24.0, false)
				base_center.x = safe_bc.x
				base_center.z = safe_bc.y

			for i in range(6):
				var angle := (float(i) / 6.0) * TAU + randf_range(-0.22, 0.22)
				var dist := randf_range(9.0, 21.0)
				var pos := base_center + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
				var patrol_angle := randf() * TAU
				var axis := Vector3(cos(patrol_angle), 0.0, sin(patrol_angle))
				var p_dist := randf_range(8.0, 13.0)
				var p_spd := randf_range(1.05, 1.35)
				_add_mission_infantry(pos, axis, p_dist, p_spd, true)

		2:
			# МІСІЯ 2: Знайти і знищити Танк і БТР (Середня складність)
			var tank_rot := randf_range(-0.35, 0.35)
			var apc_rot := randf_range(-0.35, 0.35)
			var tank_box := [
				Vector3(-48.0, 0.0, 52.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(48.0, 0.0, 52.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(48.0, 0.0, -14.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
				Vector3(-48.0, 0.0, -14.0).rotated(Vector3.UP, tank_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.TANK, tank_box, randf_range(5.2, 6.2), true, true)
			_mission_targets_total += 1

			var apc_box := [
				Vector3(62.0, 0.0, 76.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(-62.0, 0.0, 76.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(-62.0, 0.0, 16.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
				Vector3(62.0, 0.0, 16.0).rotated(Vector3.UP, apc_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.APC, apc_box, randf_range(9.8, 11.2), true, true)
			_mission_targets_total += 1

			var p1_pos := Vector3(randf_range(-42.0, -18.0), 0.0, randf_range(48.0, 80.0)) + _mission_offset
			var p2_pos := Vector3(randf_range(18.0, 42.0), 0.0, randf_range(48.0, 80.0)) + _mission_offset
			_add_mission_infantry(p1_pos, Vector3(1.0, 0.0, 0.0), 14.0, 1.7, false)
			_add_mission_infantry(p2_pos, Vector3(-1.0, 0.0, 0.0), 14.0, 1.7, false)
			_add_aa_gun(Vector3(0.0, 0.0, 32.0), false)

		3:
			# МІСІЯ 3: Гелікоптер (Важка складність — повітряна ціль + мобільна ППО)
			var h_center_x := randf_range(-25.0, 25.0) + _mission_offset.x
			var h_center_z := randf_range(15.0, 42.0) + _mission_offset.z
			var h_radius := randf_range(65.0, 88.0)
			var h_height := randf_range(AIR_MISSION_HELI_ALT.x, AIR_MISSION_HELI_ALT.y)
			var heli_pts := _loop_waypoints(h_center_x, h_center_z, h_radius, 8, 0.2)
			_add_vehicle(Vehicle.Kind.HELI, heli_pts,
					randf_range(AIR_MISSION_HELI_SPEED.x, AIR_MISSION_HELI_SPEED.y),
					true, true, h_height)
			_mission_targets_total += 1

			var sam_rot := randf_range(-0.4, 0.4)
			var sam_box := [
				Vector3(-55.0, 0.0, 48.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(55.0, 0.0, 48.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(55.0, 0.0, -22.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
				Vector3(-55.0, 0.0, -22.0).rotated(Vector3.UP, sam_rot) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SAM, sam_box, 4.2, true, true)
			_mission_targets_total += 1
			_add_aa_gun(Vector3(-56.0, 0.0, 42.0), false)
			_add_aa_gun(Vector3(56.0, 0.0, 12.0), false)

		4:
			# МІСІЯ 4: Шахед (Максимальна складність — швидкісні повітряні цілі + ЗРК та БМП прикриття)
			var sh1_alt := randf_range(AIR_MISSION_SHAHED_ALT_1.x,
					AIR_MISSION_SHAHED_ALT_1.y)
			var sh2_alt := randf_range(AIR_MISSION_SHAHED_ALT_2.x,
					AIR_MISSION_SHAHED_ALT_2.y)
			var ang := randf_range(-0.25, 0.25)
			var p_pts1 := [
				Vector3(-115.0, 0.0, 62.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(115.0, 0.0, 62.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(115.0, 0.0, -26.0).rotated(Vector3.UP, ang) + _mission_offset,
				Vector3(-115.0, 0.0, -26.0).rotated(Vector3.UP, ang) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts1,
					randf_range(AIR_MISSION_SHAHED_SPEED.x,
							AIR_MISSION_SHAHED_SPEED.y),
					true, false, sh1_alt)
			_mission_targets_total += 1

			var p_pts2 := [
				Vector3(120.0, 0.0, 24.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(-120.0, 0.0, 24.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(-120.0, 0.0, 82.0).rotated(Vector3.UP, -ang) + _mission_offset,
				Vector3(120.0, 0.0, 82.0).rotated(Vector3.UP, -ang) + _mission_offset,
			]
			_add_vehicle(Vehicle.Kind.SHAHED, p_pts2,
					randf_range(AIR_MISSION_SHAHED_SPEED.x,
							AIR_MISSION_SHAHED_SPEED.y),
					true, false, sh2_alt)
			_mission_targets_total += 1

			_add_vehicle(Vehicle.Kind.SAM, [
				Vector3(randf_range(-72.0, -50.0), 0.0, randf_range(40.0, 65.0)) + _mission_offset,
				Vector3(randf_range(50.0, 72.0), 0.0, randf_range(40.0, 65.0)) + _mission_offset,
			], 4.5, true, true)
			_mission_targets_total += 1

			_add_vehicle(Vehicle.Kind.BMP, [
				Vector3(randf_range(58.0, 82.0), 0.0, randf_range(12.0, 32.0)) + _mission_offset,
				Vector3(randf_range(-82.0, -58.0), 0.0, randf_range(12.0, 32.0)) + _mission_offset,
			], 9.2, true, true)
			_mission_targets_total += 1
			_add_aa_gun(Vector3(-68.0, 0.0, 26.0), false)
			_add_aa_gun(Vector3(68.0, 0.0, 48.0), false)
			_mission_targets_total += 1

	_offset_targets = false
	if frontline_map != "" and mission_id != 1:
		_spawn_frontline_bonus_targets()

	print("[BigLevel] spawned Combat Mission %d/4 with %d required targets" % [
		mission_id, _mission_targets_total
	])


## Dynamic pressure: every ~24 s a small enemy patrol arrives near the
## objective area.  They are bonus targets (not required for completion), so
## the mission logic stays intact while the battlefield does not feel static.
var _reinforcement_wave := 0


func _start_reinforcements() -> void:
	if Global.play_mode != Global.PlayMode.COMBAT or Global.special_mission > 0 \
			or Global.combat_mission == 1:
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
				[Vector3(-135.0, 0.0, 85.0), Vector3(1.0, 0.0, 0.0), 14.0],
				[Vector3(28.0, 0.0, 138.0), Vector3(0.0, 0.0, -1.0), 12.0],
				[Vector3(-105.0, 0.0, 48.0), Vector3(0.6, 0.0, 1.0), 16.0],
			]
		"industrial":
			spots = [
				[Vector3(128.0, 0.0, 84.0), Vector3(1.0, 0.0, 0.0), 15.0],
				[Vector3(-64.0, 0.0, -34.0), Vector3(1.0, 0.0, 0.2), 14.0],
				[Vector3(-96.0, 0.0, 26.0), Vector3(0.4, 0.0, -1.0), 13.0],
			]
		"wetlands":
			spots = [
				[Vector3(135.0, 0.0, 110.0), Vector3(-1.0, 0.0, 0.0), 14.0],
				[Vector3(-36.0, 0.0, -72.0), Vector3(0.0, 0.0, 1.0), 16.0],
				[Vector3(96.0, 0.0, -72.0), Vector3(1.0, 0.0, 0.0), 15.0],
			]
		_:
			spots = [
				[Vector3(-140.0, 0.0, -58.0), Vector3(1.0, 0.0, 0.0), 14.0],
				[Vector3(40.0, 0.0, -68.0), Vector3(0.0, 0.0, 1.0), 15.0],
				[Vector3(-110.0, 0.0, 96.0), Vector3(-1.0, 0.0, 0.0), 13.0],
			]
	for spot in spots:
		var p: Vector3 = spot[0]
		var axis: Vector3 = spot[1]
		_add_mission_infantry(p, axis, float(spot[2]), 1.68, false)


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
			and ResourceLoader.exists("res://Assets/textures/NormalMap.png"):
		mat.normal_enabled = true
		mat.normal_texture = load("res://Assets/textures/NormalMap.png")
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
			if absf(x) > MAP_GROUND_SAFE or absf(z) > MAP_GROUND_SAFE:
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
	_payload_hits += 1
	if Global.play_mode == Global.PlayMode.COMBAT:
		var combat := get_node_or_null("CombatSystem")
		if combat != null and combat.has_method("add_bonus_score"):
			combat.call("add_bonus_score", points, _txt("БУДІВЛЮ ЗРУЙНОВАНО", "STRUCTURE DESTROYED"))
	else:
		_set_flash("%s  +%d" % [_txt("Будівлю зруйновано", "Structure destroyed"), points])


# ------------------------------------------------------------------ HUD
func _get_hud_safe_insets() -> Dictionary:
	var insets := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	if DisplayServer.get_name() == "headless":
		return insets
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	var win: Vector2i = DisplayServer.window_get_size()
	var vp := get_viewport()
	if win.x <= 0 or win.y <= 0 or vp == null:
		return insets
	var vp_size := vp.get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return insets
	var sx := vp_size.x / float(win.x)
	var sy := vp_size.y / float(win.y)
	insets["left"] = clampf(float(safe.position.x) * sx, 0.0, 96.0)
	insets["top"] = clampf(float(safe.position.y) * sy, 0.0, 96.0)
	insets["right"] = clampf(float(win.x - safe.end.x) * sx, 0.0, 96.0)
	insets["bottom"] = clampf(float(win.y - safe.end.y) * sy, 0.0, 96.0)
	return insets


func _make_hud_icon(icon_id: String, icon_size: Vector2, tint: Color) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = icon_size
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = FpvIconsScript.get_icon(icon_id, Color.WHITE)
	rect.modulate = tint
	return rect
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
	if not GameSettings.hud_config_updated.is_connected(_on_hud_config_rig_updated):
		GameSettings.hud_config_updated.connect(_on_hud_config_rig_updated)
	var safe := _get_hud_safe_insets()
	var safe_l := float(safe["left"])
	var safe_r := float(safe["right"])
	var safe_t := float(safe["top"])
	var safe_b := float(safe["bottom"])
	_diag = Label.new()
	_diag.add_theme_font_size_override("font_size", 17)
	_diag.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	_diag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_diag.add_theme_constant_override("outline_size", 3)
	_diag.position = Vector2(26 + safe_l, 300 + safe_t)
	_diag.visible = false
	_hud.add_child(_diag)
	var hud_row := HBoxContainer.new()
	hud_row.name = "MissionBadgeRow"
	hud_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_row.add_theme_constant_override("separation", 8)
	hud_row.position = Vector2(22 + safe_l, 92 + safe_t)
	_hud.add_child(hud_row)
	var wing_icon := _make_hud_icon("icon_wing_emblem", Vector2(20, 20), Color(0.22, 0.91, 1.0, 0.92))
	wing_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hud_row.add_child(wing_icon)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 18)
	_hud_label.add_theme_color_override("font_color", Color(0.95, 0.99, 0.96, 0.98))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_hud_label.add_theme_constant_override("outline_size", 5)
	_hud_label.visible = true
	hud_row.add_child(_hud_label)
	# Non-overlapping centered stack for flash banners, arm/nav cue, threat alert, and ELRS status.
	_top_banner_stack = VBoxContainer.new()
	_top_banner_stack.name = "TopBannerStack"
	_top_banner_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_banner_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top_banner_stack.add_theme_constant_override("separation", 4)
	_top_banner_stack.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top_banner_stack.offset_left = 180.0 + safe_l
	_top_banner_stack.offset_right = -(180.0 + safe_r)
	_top_banner_stack.offset_top = 10.0 + safe_t
	_top_banner_stack.offset_bottom = 114.0 + safe_t
	_hud.add_child(_top_banner_stack)
	_hud_message = Label.new()
	_hud_message.add_theme_font_size_override("font_size", 22)
	_hud_message.add_theme_color_override("font_color", Color(1, 0.93, 0.52))
	_hud_message.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_hud_message.add_theme_constant_override("outline_size", 5)
	_hud_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_message.visible = false
	_top_banner_stack.add_child(_hud_message)
	_nav_marker = Label.new()
	_nav_marker.add_theme_font_size_override("font_size", 19)
	_nav_marker.add_theme_color_override("font_color", Color(1.0, 0.90, 0.36, 0.98))
	_nav_marker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_nav_marker.add_theme_constant_override("outline_size", 5)
	_nav_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_nav_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_banner_stack.add_child(_nav_marker)
	_threat_indicator = Label.new()
	_threat_indicator.add_theme_font_size_override("font_size", 17)
	_threat_indicator.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25, 0.98))
	_threat_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_threat_indicator.add_theme_constant_override("outline_size", 4)
	_threat_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threat_indicator.visible = false
	_top_banner_stack.add_child(_threat_indicator)
	# iOS / WiFi ELRS touch helpers.  The Pocket's CH5 switch also maps to
	# toggle_arm; the button is a fallback for a phone without a radio.
	if ElrsWifiInput.enabled or touch_enabled:
		_elrs_status_label = Label.new()
		_elrs_status_label.add_theme_font_size_override("font_size", 15)
		_elrs_status_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72, 0.95))
		_elrs_status_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_elrs_status_label.add_theme_constant_override("outline_size", 4)
		_elrs_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_elrs_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_elrs_status_label.text = ElrsWifiInput.status_text
		_elrs_status_last_text = ElrsWifiInput.status_text
		_elrs_status_timer = 2.5
		_elrs_status_label.visible = not ElrsWifiInput.status_text.is_empty()
		_top_banner_stack.add_child(_elrs_status_label)
	_radio_subtitle_panel = PanelContainer.new()
	_radio_subtitle_panel.name = "RadioSubtitlePanel"
	_radio_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radio_subtitle_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_radio_subtitle_panel.offset_left = -380.0
	_radio_subtitle_panel.offset_right = 380.0
	_radio_subtitle_panel.offset_top = safe_t + 114.0
	_radio_subtitle_panel.offset_bottom = safe_t + 162.0
	var r_sb := StyleBoxFlat.new()
	r_sb.bg_color = Color(0.03, 0.07, 0.08, 0.82)
	r_sb.border_color = Color(0.22, 0.91, 1.0, 0.48)
	r_sb.set_border_width_all(1)
	r_sb.border_width_left = 4
	r_sb.set_corner_radius_all(3)
	r_sb.content_margin_left = 12
	r_sb.content_margin_right = 12
	r_sb.content_margin_top = 6
	r_sb.content_margin_bottom = 6
	_radio_subtitle_panel.add_theme_stylebox_override("panel", r_sb)
	_radio_subtitle_panel.visible = false
	_hud.add_child(_radio_subtitle_panel)
	var radio_hbox := HBoxContainer.new()
	radio_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radio_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	radio_hbox.add_theme_constant_override("separation", 8)
	_radio_subtitle_panel.add_child(radio_hbox)
	radio_hbox.add_child(_make_hud_icon("icon_signal_link", Vector2(18, 18), Color(0.22, 0.91, 1.0, 0.95)))
	_radio_subtitle = Label.new()
	_radio_subtitle.add_theme_font_size_override("font_size", 17)
	_radio_subtitle.add_theme_color_override("font_color", Color(0.78, 1.0, 0.88, 0.98))
	_radio_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_radio_subtitle.add_theme_constant_override("outline_size", 4)
	_radio_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radio_hbox.add_child(_radio_subtitle)
	_setup_telemetry()
	_build_results()
	_build_chain_briefing()
	if Global.play_mode == Global.PlayMode.TUTORIAL and _flight_school != null:
		_flight_school.setup_hud(_hud)
	if Global.play_mode == Global.PlayMode.TRAINING and _combat_training != null \
			and is_instance_valid(_combat_training):
		_combat_training.setup_hud(_hud)


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
				{"p": Vector2(-52, -68), "r": 120.0, "s": 0.80, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(138, 56), "r": 148.0, "s": 0.90, "dir": true, "yaw": -140.0, "fov": 80.0},
			]
		"industrial":
			domes = [
				{"p": Vector2(105, -36), "r": 158.0, "s": 0.88, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(-135, -78), "r": 135.0, "s": 0.82, "dir": true, "yaw": 55.0, "fov": 75.0},
			]
		"wetlands":
			domes = [
				{"p": Vector2(0, -74), "r": 145.0, "s": 0.86, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(135, -108), "r": 135.0, "s": 0.84, "dir": true, "yaw": -160.0, "fov": 85.0},
			]
		_:
			domes = [
				{"p": Vector2(-115, -92), "r": 128.0, "s": 0.78, "dir": false, "yaw": 0.0, "fov": 70.0},
				{"p": Vector2(128, 72), "r": 155.0, "s": 0.90, "dir": true, "yaw": -135.0, "fov": 75.0},
			]
	for dome in domes:
		var p: Vector2 = dome["p"]
		reb.add_ew_dome(Vector3(p.x, _terrain_y(p.x, p.y), p.y),
				float(dome["r"]), float(dome["s"]), bool(dome["dir"]),
				deg_to_rad(float(dome["yaw"])), float(dome["fov"]))
	if Global.play_mode == Global.PlayMode.COMBAT and Global.special_mission == 0:
		if Global.combat_mission == 2:
			reb.add_ew_dome(Vector3(58.0, _terrain_y(58.0, 10.0), 10.0), 118.0, 0.78, true,
					deg_to_rad(-165.0), 80.0)
		elif Global.combat_mission >= 3:
			reb.add_ew_dome(Vector3(0.0, _terrain_y(0.0, -148.0), -148.0), 165.0, 0.95, true,
					deg_to_rad(0.0), 90.0)
	if Global.special_mission in [6, 9]:
		# EW breach: a deliberately dense corridor within compact arena bounds.
		reb.add_ew_dome(Vector3(-48.0, _terrain_y(-48.0, -35.0), -35.0),
				155.0, 0.95, false)
		reb.add_ew_dome(Vector3(65.0, _terrain_y(65.0, -88.0), -88.0),
				145.0, 0.90, true, deg_to_rad(35.0), 85.0)
	if not reb.failsafe_changed.is_connected(_on_reb_failsafe):
		reb.failsafe_changed.connect(_on_reb_failsafe)


func _on_reb_failsafe(active: bool) -> void:
	if active:
		_set_flash("FAILSAFE — ВТРАЧЕНО ЗВ'ЯЗОК")
	else:
		_set_flash("ЗВ'ЯЗОК ВІДНОВЛЕНО")


func _setup_telemetry() -> void:
	var safe := _get_hud_safe_insets()
	var safe_l := float(safe["left"])
	var safe_r := float(safe["right"])
	var safe_t := float(safe["top"])
	var safe_b := float(safe["bottom"])
	var left_row := HBoxContainer.new()
	left_row.name = "TelemetryLeftRow"
	left_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_row.add_theme_constant_override("separation", 8)
	left_row.position = Vector2(22 + safe_l, 22 + safe_t)
	_hud.add_child(left_row)
	left_row.add_child(_make_hud_icon("icon_drone_topdown", Vector2(18, 18), Color(0.91, 0.96, 0.98, 0.92)))
	_telem_left = Label.new()
	_telem_left.add_theme_font_size_override("font_size", 16)
	_telem_left.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_telem_left.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_telem_left.add_theme_constant_override("outline_size", 4)
	left_row.add_child(_telem_left)
	var right_row := HBoxContainer.new()
	right_row.name = "TelemetryRightRow"
	right_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_row.alignment = BoxContainer.ALIGNMENT_END
	right_row.add_theme_constant_override("separation", 8)
	right_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_row.offset_left = -(290.0 + safe_r)
	right_row.offset_top = 22.0 + safe_t
	right_row.offset_right = -(22.0 + safe_r)
	_hud.add_child(right_row)
	_telem_right = Label.new()
	_telem_right.add_theme_font_size_override("font_size", 16)
	_telem_right.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	_telem_right.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_telem_right.add_theme_constant_override("outline_size", 4)
	_telem_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_telem_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_row.add_child(_telem_right)
	right_row.add_child(_make_hud_icon("icon_battery_pack", Vector2(18, 18), Color(0.22, 0.91, 1.0, 0.92)))

	# Small field-wind cue in the lower-left corner.  It is hidden in Arcade
	# (wind_sim off) and shows both the relative direction and the gust speed.
	_wind_row = HBoxContainer.new()
	_wind_row.name = "WindIndicatorRow"
	_wind_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind_row.add_theme_constant_override("separation", 6)
	_wind_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_wind_row.offset_left = 22.0 + safe_l
	_wind_row.offset_top = -(46.0 + safe_b)
	_wind_row.offset_right = 380.0 + safe_l
	_wind_row.offset_bottom = -(18.0 + safe_b)
	_wind_row.visible = false
	_hud.add_child(_wind_row)
	_wind_row.add_child(_make_hud_icon("icon_wind_sock", Vector2(16, 16), Color(1.0, 0.82, 0.42, 0.95)))
	_wind_indicator = Label.new()
	_wind_indicator.add_theme_font_size_override("font_size", 15)
	_wind_indicator.add_theme_color_override("font_color", Color(1.0, 0.82, 0.42, 0.95))
	_wind_indicator.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_wind_indicator.add_theme_constant_override("outline_size", 3)
	_wind_indicator.visible = true
	_wind_row.add_child(_wind_indicator)


func _on_viewport_size_changed() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	var safe := _get_hud_safe_insets()
	var safe_l := float(safe["left"])
	var safe_r := float(safe["right"])
	var safe_t := float(safe["top"])
	var safe_b := float(safe["bottom"])
	var left_row := _hud.get_node_or_null("TelemetryLeftRow") as Control
	if left_row != null:
		left_row.position = Vector2(22.0 + safe_l, 22.0 + safe_t)
	var badge_row := _hud.get_node_or_null("MissionBadgeRow") as Control
	if badge_row != null:
		badge_row.position = Vector2(22.0 + safe_l, 96.0 + safe_t)
	var right_row := _hud.get_node_or_null("TelemetryRightRow") as Control
	if right_row != null:
		right_row.offset_left = -(290.0 + safe_r)
		right_row.offset_top = 22.0 + safe_t
		right_row.offset_right = -(22.0 + safe_r)
	if _top_banner_stack != null and is_instance_valid(_top_banner_stack):
		_top_banner_stack.offset_left = 180.0 + safe_l
		_top_banner_stack.offset_right = -(180.0 + safe_r)
		_top_banner_stack.offset_top = 10.0 + safe_t
		_top_banner_stack.offset_bottom = 114.0 + safe_t
	if _wind_row != null and is_instance_valid(_wind_row):
		_wind_row.offset_left = 22.0 + safe_l
		_wind_row.offset_top = -(46.0 + safe_b)
		_wind_row.offset_right = 380.0 + safe_l
		_wind_row.offset_bottom = -(18.0 + safe_b)
	if TouchControls != null and TouchControls.has_method("_layout_controls"):
		TouchControls.call("_layout_controls")


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
			ammo_line = _txt("СКИД %d  [G]\n", "DROP %d  [G]\n") % _ammo_count()
		else:
			ammo_line = _txt("БЧ 1x  [F]\n", "WARHEAD 1x  [F]\n")
	_scene_uptime += delta
	if _scene_uptime > 0.6:
		# Engine FPS is already smoothed over real frames; deriving it from the
		# accumulated OSD delta would always read 12 FPS.
		_fps_ema = lerpf(_fps_ema, float(Engine.get_frames_per_second()), 0.35)
	var fps_val := int(round(_fps_ema))
	var batt_tag := ""
	var low_voltage := cell_v < 3.5
	if low_voltage:
		batt_tag = _txt("  НИЗЬКА НАПРУГА!", "  LOW VOLTAGE!")
	var fiber_mode: bool = Global != null and bool(Global.menu_settings.get("fiber_optic_mode", false))
	if fiber_mode and _reb != null:
		_reb.in_ew = 0.0
		_reb.link_quality = 1.0
		_reb.failsafe = false
	var jamming: bool = (not fiber_mode) and _reb != null and _reb.limits_enabled \
			and _reb.reb_zones_enabled and _reb.in_ew > 0.08
	var warn_phase := int(Time.get_ticks_msec() / 280) % 2 == 0
	var lq_line := ""
	if fiber_mode:
		lq_line = "\n%s %d / 10000 %s [%s]" % [
			_txt("ОПТО", "FIBER"),
			int(round(_fiber_spool_used_m)),
			_txt("м", "m"),
			_txt("БЕЗ РЕБ", "EW IMMUNE")
		]
	elif _reb != null:
		var jam_tag := ""
		if jamming:
			jam_tag = _txt("  ПРИДУШЕННЯ", "  JAMMED") if warn_phase else ""
		var link_status := _reb.get_status_text()
		# The REB subsystem keeps English tokens for QA; the HUD speaks
		# Ukrainian, so translate only the displayed copy.
		if not MenuUI.is_english():
			match link_status:
				"UNLIMITED":
					link_status = "БЕЗ ОБМЕЖЕНЬ"
				"FAILSAFE":
					link_status = "ФЕЙЛСЕЙФ"
				"CRITICAL":
					link_status = "КРИТИЧНО"
				"WEAK":
					link_status = "СЛАБКИЙ"
				"OK":
					link_status = "НОРМА"
				"LINK":
					link_status = "ЗВ'ЯЗОК"
		lq_line = "\nLQ %d%%  %s%s  |  %.0f ms" % [
				_reb.get_lq_percent(), link_status, jam_tag, _reb.latency_ms]
	var q_lvl := QualityManagerScript.get_active_level()
	var q_short := _txt("НИЗ", "LOW")
	if q_lvl == 1:
		q_short = _txt("СЕР", "MED")
	elif q_lvl == 2:
		q_short = _txt("ВИС", "HIGH")
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
		_play_radio_callout(_txt("БАТАРЕЯ КРИТИЧНА — ПОВЕРТАЙСЯ НА БАЗУ",
				"BATTERY CRITICAL — RETURN TO BASE"), true)
	elif not low_voltage:
		_low_battery_announced = false
	if jamming != _ew_was_active:
		_ew_was_active = jamming
		_play_alert("ew_enter" if jamming else "ew_exit", -7.0)
		if jamming:
			Haptics.pulse(80, 0.35, "ew")
			_play_radio_callout(_txt("РЕБ! ГЛУШІННЯ — ВТРАТА ЗВ'ЯЗКУ",
				"EW JAMMING — CONTROL LINK DEGRADED"), true)
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
			_txt("ДВИГУНИ УВІМКНЕНО" if armed else "ДВИГУНИ ВИМКНЕНО",
				"MOTORS ARMED" if armed else "MOTORS DISARMED"),
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
	var show_wind := bool(GameSettings.hud_config.get("wind_sim", false))
	if _wind_row != null:
		_wind_row.visible = show_wind
	if not show_wind:
		_wind_indicator.visible = false
		return
	var wind := Vector3(_current_wind_vector.x, 0.0, _current_wind_vector.z)
	var speed := wind.length()
	_wind_indicator.visible = true
	if speed < 0.15:
		_wind_indicator.text = _txt("ВІТЕР  ·  ШТИЛЬ", "WIND  ·  CALM")
		_wind_indicator.add_theme_color_override("font_color", Color(0.75, 0.82, 0.78, 0.9))
		return
	var arrow := _arrow_from_direction(wind)
	var gust := speed >= 7.0
	_wind_indicator.text = "%s  %s  %.1f %s%s" % [
			_txt("ВІТЕР", "WIND"), arrow, speed, _txt("м/с", "m/s"),
			_txt("  ПОРИВ", "  GUST") if gust else ""]
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
	_base_fpv_fov = 110.0
	cam.fov = _base_fpv_fov
	cam.near = 0.05
	cam.far = 4000.0
	cam.position = p.get("fpv_cam_pos", Vector3(0.0, 0.004, -0.053))
	cam.set_meta("base_pos", cam.position)
	# Respect each preset's camera tilt with a gentle +3 deg sightline lift
	# without ever pointing an FPV lens upward into the sky.
	var pitch := clampf(float(p.get("fpv_cam_pitch", -10.0)) + 3.0, -18.0, -3.0)
	cam.rotation_degrees = Vector3(pitch, 0.0, 0.0)
	cam.set_meta("base_rot", cam.rotation_degrees)


func _ensure_fiber_cable() -> void:
	if _fiber_cable != null and is_instance_valid(_fiber_cable):
		return
	_fiber_cable = MeshInstance3D.new()
	_fiber_cable.name = "FiberOpticCable"
	_fiber_cable.top_level = true
	_fiber_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fiber_cable_mesh = ImmediateMesh.new()
	_fiber_cable.mesh = _fiber_cable_mesh
	add_child(_fiber_cable)
	_fiber_cable.global_transform = Transform3D.IDENTITY
	_fiber_cable.visible = false
	_fiber_core_mat = _fiber_cable_material(true)
	_fiber_glow_mat = _fiber_cable_material(false)

	_fiber_spool_marker = Node3D.new()
	_fiber_spool_marker.name = "FiberSpool"
	_fiber_spool_marker.top_level = true
	add_child(_fiber_spool_marker)
	var drum := MeshInstance3D.new()
	var drum_mesh := CylinderMesh.new()
	drum_mesh.top_radius = 0.16
	drum_mesh.bottom_radius = 0.16
	drum_mesh.height = 0.11
	drum.mesh = drum_mesh
	drum.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drum_mat := StandardMaterial3D.new()
	drum_mat.albedo_color = Color(0.045, 0.085, 0.075, 1.0)
	drum_mat.metallic = 0.45
	drum_mat.roughness = 0.55
	drum.material_override = drum_mat
	drum.position.y = 0.055
	_fiber_spool_marker.add_child(drum)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.17
	ring_mesh.outer_radius = 0.235
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = FIBER_CABLE_COLOR
	ring_mat.emission_enabled = true
	ring_mat.emission = FIBER_CABLE_COLOR
	ring_mat.emission_energy_multiplier = 2.2
	ring.material_override = ring_mat
	ring.position.y = 0.085
	_fiber_spool_marker.add_child(ring)
	_fiber_spool_marker.visible = false


func _fiber_cable_material(core: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(FIBER_CABLE_COLOR.r, FIBER_CABLE_COLOR.g,
			FIBER_CABLE_COLOR.b, 0.96 if core else 0.16)
	mat.emission_enabled = true
	mat.emission = FIBER_CABLE_COLOR
	mat.emission_energy_multiplier = 3.4 if core else 1.2
	mat.render_priority = 2 if core else 1
	return mat


func _fiber_cable_path(anchor: Vector3, tip: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var horizontal := Vector2(tip.x - anchor.x, tip.z - anchor.z).length()
	var height := maxf(tip.y - anchor.y, 0.0)
	var sag := minf(horizontal * 0.012, 0.32 + height * 0.055)
	sag = minf(sag, 2.6)
	for i in range(FIBER_CABLE_SEGMENTS + 1):
		var t := float(i) / float(FIBER_CABLE_SEGMENTS)
		var p := anchor.lerp(tip, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		# A cable cannot sink through the launch apron even while slack.
		if i > 0:
			p.y = maxf(p.y, anchor.y + 0.018)
		pts.append(p)
	pts[pts.size() - 1] = tip
	return pts


func _fiber_ribbon_vertices(points: PackedVector3Array, cam_pos: Vector3,
		core: bool) -> PackedVector3Array:
	var verts := PackedVector3Array()
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var dir := b - a
		if dir.length_squared() < 0.000001:
			continue
		dir = dir.normalized()
		var mid := (a + b) * 0.5
		var to_cam := cam_pos - mid
		if to_cam.length_squared() < 0.000001:
			to_cam = Vector3.UP
		var side := dir.cross(to_cam.normalized())
		if side.length_squared() < 0.000001:
			side = Vector3.RIGHT
		var cam_dist := mid.distance_to(cam_pos)
		# Perspective-correct screen width: the strand stays legible hundreds of
		# metres out without becoming a pipe as the drone passes the camera.
		var half := 0.022 + minf(cam_dist * 0.0012, 0.18)
		if not core:
			half = 0.060 + minf(cam_dist * 0.0034, 0.46)
		side = side.normalized() * half
		verts.append(a - side)
		verts.append(a + side)
		verts.append(b + side)
		verts.append(a - side)
		verts.append(b + side)
		verts.append(b - side)
	return verts


func _rebuild_fiber_cable(tip: Vector3, cam_pos: Vector3) -> void:
	_ensure_fiber_cable()
	if _fiber_cable_mesh == null:
		return
	var pts := _fiber_cable_path(_fiber_anchor, tip)
	_fiber_cable_mesh.clear_surfaces()
	for core in [false, true]:
		var verts := _fiber_ribbon_vertices(pts, cam_pos, core)
		if verts.is_empty():
			continue
		_fiber_cable_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,
				_fiber_core_mat if core else _fiber_glow_mat)
		for v in verts:
			_fiber_cable_mesh.surface_add_vertex(v)
		_fiber_cable_mesh.surface_end()
	_fiber_cable.visible = true
	if _fiber_spool_marker != null:
		_fiber_spool_marker.global_position = _fiber_anchor
		_fiber_spool_marker.visible = true


func _update_fiber_cable(drone: Node3D, cam: Camera3D, fiber_mode: bool) -> void:
	if drone == null or not is_instance_valid(drone):
		return
	if not fiber_mode or _dvr_replaying:
		if _fiber_cable != null and is_instance_valid(_fiber_cable):
			_fiber_cable.visible = false
		if _fiber_spool_marker != null and is_instance_valid(_fiber_spool_marker):
			_fiber_spool_marker.visible = false
		return
	if not _fiber_anchor_ready:
		var behind := drone.global_transform.basis.z
		behind.y = 0.0
		if behind.length_squared() < 0.0001:
			behind = Vector3.BACK
		behind = behind.normalized() * 2.4
		var anchor := drone.global_position + behind
		anchor.y = _terrain_y(anchor.x, anchor.z) + 0.16
		_fiber_anchor = anchor
		_fiber_anchor_ready = true
	var tip := drone.global_position + drone.global_transform.basis.z * 0.34
	var cam_pos := cam.global_position if cam != null and is_instance_valid(cam) \
			else drone.global_position + Vector3.UP * 0.15
	_rebuild_fiber_cable(tip, cam_pos)


func _reset_fiber_cable() -> void:
	_fiber_anchor_ready = false
	_fiber_anchor = Vector3.ZERO
	_fiber_spool_used_m = 0.0
	if _fiber_cable != null and is_instance_valid(_fiber_cable):
		_fiber_cable.visible = false
	if _fiber_spool_marker != null and is_instance_valid(_fiber_spool_marker):
		_fiber_spool_marker.visible = false


func _update_fpv_camera_fx(delta: float) -> void:
	var drone := get_node_or_null("Drone") as Drone
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if drone == null or cam == null:
		return
	var speed := drone.linear_velocity.length()
	var armed: bool = drone.flight_controller != null and drone.flight_controller.state_armed
	var fiber_mode: bool = Global != null and bool(Global.menu_settings.get("fiber_optic_mode", false))
	_update_fiber_cable(drone, cam, fiber_mode)
	if armed and fiber_mode:
		_fiber_spool_used_m = clampf(_fiber_spool_used_m + speed * delta, 0.0, 10000.0)
	if armed and not _dvr_replaying and not _mission_finished:
		_dvr_sample_timer += delta
		if _dvr_sample_timer >= 0.05:
			_dvr_sample_timer = 0.0
			_dvr_samples.append({
				"pos": drone.global_position,
				"rot": drone.global_rotation,
				"cam_pos": cam.global_position,
				"cam_rot": cam.global_rotation,
				"cam_fov": cam.fov,
			})
			if _dvr_samples.size() > 300:
				_dvr_samples.pop_front()
		# Record the real FPV picture, not only transforms.  5 fps at a reduced
		# resolution is enough for the debrief replay and keeps the rolling
		# buffer around 20 MB.  The previous implementation teleported the live
		# drone around the current world, so the "replay" looked like gameplay
		# with a REC banner on top.
		_dvr_frame_timer += delta
		if _dvr_frame_timer >= 1.0 / float(DVR_FPS):
			_dvr_frame_timer = 0.0
			_capture_dvr_frame()
	# Low-altitude radio horizon multipath scanlines (when flying standard radio below 2.6 m)
	if _hud != null and _analog_bar_a == null:
		_analog_bar_a = ColorRect.new()
		_analog_bar_a.name = "AnalogMultipathBarA"
		_analog_bar_a.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_analog_bar_a.color = Color(0.85, 0.92, 0.88, 0.0)
		_analog_bar_a.visible = false
		_hud.add_child(_analog_bar_a)
		_analog_bar_b = ColorRect.new()
		_analog_bar_b.name = "AnalogMultipathBarB"
		_analog_bar_b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_analog_bar_b.color = Color(0.12, 0.16, 0.14, 0.0)
		_analog_bar_b.visible = false
		_hud.add_child(_analog_bar_b)
	if _analog_bar_a != null and _analog_bar_b != null:
		var alt := drone.global_position.y - _ground_y
		var show_multipath := armed and (not fiber_mode) \
				and Global.play_mode == Global.PlayMode.COMBAT \
				and alt < 2.6 and speed > 3.2 and not _dvr_replaying
		if show_multipath:
			var vs := get_viewport().get_visible_rect().size
			var intensity := clampf((2.6 - alt) / 2.6, 0.0, 1.0)
			var t_sec := float(Time.get_ticks_msec()) * 0.001
			var y1 := fposmod(t_sec * 340.0, maxf(vs.y, 100.0))
			var y2 := fposmod(t_sec * 520.0 + vs.y * 0.42, maxf(vs.y, 100.0))
			_analog_bar_a.position = Vector2(0.0, y1)
			_analog_bar_a.size = Vector2(vs.x, 10.0 + intensity * 16.0)
			_analog_bar_a.color.a = 0.16 * intensity
			_analog_bar_a.visible = true
			_analog_bar_b.position = Vector2(0.0, y2)
			_analog_bar_b.size = Vector2(vs.x, 6.0 + intensity * 12.0)
			_analog_bar_b.color.a = 0.22 * intensity
			_analog_bar_b.visible = true
		else:
			_analog_bar_a.visible = false
			_analog_bar_b.visible = false
	if not cam.current:
		return
	var target_fov := _base_fpv_fov
	if armed and speed > 12.0:
		target_fov += clampf((speed - 12.0) / 36.0 * 6.0, 0.0, 6.0)
	cam.fov = lerpf(cam.fov, target_fov, clampf(delta * 6.5, 0.0, 1.0))


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
	# Uses the real 3D drone model (DroneModel GLB in res://Assets/Drones/ua_norm/)
	# instead of procedurally generating cylinders or wires.
	var cam := get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null:
		var old := cam.get_node_or_null("FPVRig")
		if old != null:
			old.name = "FPVRig_Old"
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

	var builtin_hud := get_node_or_null("Drone/HUD")
	if builtin_hud != null:
		var mode_label := builtin_hud.get_node_or_null("MarginContainer/FlightMode") as CanvasItem
		if mode_label != null:
			mode_label.visible = false
	_rig_visible = bool(GameSettings.hud_config.get("fpv_rig", true)) if GameSettings != null else true
	_apply_fpv_rig()


func _on_hud_config_rig_updated() -> void:
	if GameSettings != null:
		_rig_visible = bool(GameSettings.hud_config.get("fpv_rig", true))
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
		var corridor_x := clampf(eye.x, -165.0, 165.0)
		for i in range(12):
			var cz := clampf(eye.z + 90.0 - float(i) * 28.0, -165.0, 165.0)
			var cy: float = FrontlineTerrainScript.height_at(frontline_map,
					corridor_x, cz)
			cam.global_position = Vector3(corridor_x, cy + 30.0, cz)
			cam.look_at(Vector3(corridor_x, cy + 18.0, clampf(cz - 80.0, -175.0, 175.0)), Vector3.UP)
			var t4 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t4) / 1000.0)
		# Second corridor down the map centre line within the compact 384 m arena.
		if not site.is_empty():
			var mid_x: float = clampf((site["center"] as Vector2).x, -165.0, 165.0)
			for i in range(14):
				var cz2 := clampf(165.0 - float(i) * 24.0, -165.0, 165.0)
				var cy2: float = FrontlineTerrainScript.height_at(frontline_map,
						mid_x, cz2)
				cam.global_position = Vector3(mid_x, cy2 + 30.0, cz2)
				cam.look_at(Vector3(mid_x, cy2 + 16.0, clampf(cz2 - 80.0, -175.0, 175.0)), Vector3.UP)
				var t6 := Time.get_ticks_usec()
				await get_tree().process_frame
				worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t6) / 1000.0)
	else:
		# Valley/course: warm the three open-top smokestacks and the factory
		# complex from their actual mode-dependent positions.
		var base_z := -28.0
		if Global.play_mode != Global.PlayMode.TRAINING:
			base_z = -55.0
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


## Exact release state for the current airframe.  The heavy bomber releases
## from its modelled BombBay; every other dropper uses the shared hardpoint.
## BombSight calls this too, so the CCIP pipper and the spawned rigid body
## always start from the same point with the same velocity.
func _bomb_release_state(drone_node: Node3D, _kind: String = "82mm") -> Dictionary:
	var override := Vector3.INF
	if _heavy_bomber and _fpv_payload != null and is_instance_valid(_fpv_payload):
		override = _fpv_payload.global_position
	return BombBallisticsScript.release_state(drone_node, override)


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
	_payload_drops += 1
	var bomb: Node3D = _bomb_nodes[_bomb_nodes.size() - 1]
	var state := _bomb_release_state(drone, _bomb_kind)
	_bomb_nodes.pop_back()
	bomb.visible = false
	var payload := PayloadScript.new()
	payload.kind = _bomb_kind
	payload.mass_override = _preset_payload_unit_mass()
	if OS.has_environment("DRONE_PAYLOAD_DEBUG"):
		print("[PAYLOAD] heavy kind=%s unit_mass=%.2f" % [
			payload.kind, payload.mass_override])
	payload.damage = BombBallisticsScript.damage_for(_bomb_kind)
	payload.blast_radius = BombBallisticsScript.blast_for(_bomb_kind)
	var spawn: Vector3 = state.get("origin", bomb.global_position)
	add_child(payload)
	payload.global_position = spawn
	payload.linear_velocity = state.get("velocity", drone.linear_velocity + Vector3.DOWN * 0.8)
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
	var label := _txt("82-мм міна", "82 mm mortar") if _bomb_kind == "82mm" else _bomb_kind
	_set_message(_txt("СКИД: %s · залишилось %d", "DROP: %s · %d remaining")
			% [label, _bomb_nodes.size()])
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
			# Never show a spinning blade in the FPV lens: the front props of
			# the Grim-7 sit millimetres from the camera and sweep through the
			# near plane, producing huge clipped black arcs across the frame.
			(node as Node3D).visible = not is_fpv
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if is_fpv and only_payload:
			# Combat FPV: keep only the warhead, camera/nose housing and the
			# fixed arms.  Propellers and motor bells belong to the airframe
			# silhouette, not the lens: at this camera distance they clip
			# through the near plane and fill the corners with black arcs.
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
					or n2.contains("warhead") or n2.contains("pg7")
			var is_front_part := n2.contains("arm_fl") or n2.contains("arm_fr") \
					or n2.contains("front_arm") or n2.contains("front_frame")
			var is_camera_part := n2.contains("cam") or n2.contains("lens") \
					or n2.contains("glass") or n2.contains("thermal")
			var is_prop_part := n2.contains("propeller") or n2.contains("prop_") \
					or n2.contains("rotor") or n2.contains("motor_f") \
					or n2.contains("motor_b")
			var is_nose_part := not _heavy_bomber and (n2.contains("nose") \
					or n2.contains("chin") or n2.contains("pitot"))
			mi.visible = not is_prop_part and ((_fpv_payload != null \
					and _is_under(mi, _fpv_payload)) \
					or is_warhead_part or is_front_part \
					or is_camera_part or is_nose_part)
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
	_payload_drops += 1
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
		var state := BombBallisticsScript.release_state(drone)
		drop_pos = state.get("origin", drop_pos)
		drop_vel = state.get("velocity", drop_vel)
		payload.add_collision_exception_with(drone)
		if drone.has_method("drop_payload_action"):
			var dropped_w: float = drone.drop_payload_action()
			if dropped_w > 0.001:
				_set_message(_txt("СКИД: -%.2f кг (ТЯГА ЗРОСЛА)",
						"PAYLOAD DROP: -%.2f kg (THRUST INCREASED)") % dropped_w)

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
		_set_flash(_txt("У цього дрона немає БЧ — використайте СКИД (G)",
				"THIS AIRCRAFT HAS NO WARHEAD — USE DROP (G)"))
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or not is_instance_valid(drone):
		return
	_payload_dropped = true
	_payload_drops += 1
	var hits_before := _payload_hits
	var at := drone.global_position
	var blast := 10.5
	var dmg := 1350.0
	ExplosionScript.spawn(self, at + Vector3.UP * 0.4, blast, dmg)
	CombatSfxScript.play_boom(self, at, 2.0)
	Haptics.trigger_explosion(1.15)
	var has_next_airframe := consume_sortie_airframe("STRIKE")
	_set_flash(_txt("БЧ АКТИВОВАНО", "WARHEAD DETONATED") if has_next_airframe else _txt("БЧ АКТИВОВАНО · ОСТАННІЙ БОРТ", "WARHEAD DETONATED · FINAL AIRFRAME"))
	var kc_active_now := _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active()
	if (_payload_hits > hits_before or _mission_targets_destroyed >= _mission_targets_total) \
			and not kc_active_now:
		_maybe_trigger_kill_cam(at, true)
		kc_active_now = _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active()
	if kc_active_now and _mission_targets_destroyed >= _mission_targets_total:
		_pending_combat_complete = true
	# Take the drone out of the simulation without triggering a crash message.
	drone.visible = false
	drone.freeze = true
	drone.linear_velocity = Vector3.ZERO
	drone.angular_velocity = Vector3.ZERO
	_refresh_model_visibility()
	if not has_next_airframe:
		_pending_kamikaze_respawn = false
		return
	if kc_active_now:
		_pending_kamikaze_respawn = true
	else:
		var timer := get_tree().create_timer(2.4)
		timer.timeout.connect(func() -> void:
			if _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active():
				_pending_kamikaze_respawn = true
				return
			_execute_kamikaze_respawn())


func _execute_kamikaze_respawn() -> void:
	if _mission_finished:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null or not is_instance_valid(drone):
		return
	drone.visible = true
	drone.freeze = false
	_payload_dropped = false
	_reset_fpv_payload()
	_refresh_model_visibility()
	_respawn_and_rearm()


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
	if _is_mobile_runtime():
		_results_canvas_layer = CanvasLayer.new()
		_results_canvas_layer.name = "MobileResultsCanvasLayer"
		_results_canvas_layer.layer = 120
		_results_canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_results_canvas_layer)
		_results_canvas_layer.add_child(_results)
	else:
		# Preserve the original desktop canvas and sort order.
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
	title.text = _txt("МІСІЮ ВИКОНАНО", "MISSION COMPLETE")
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_results_title = title

	box.add_child(MenuUI.hline())

	_results_stats = Label.new()
	_results_stats.add_theme_font_size_override("font_size", 20)
	_results_stats.add_theme_color_override("font_color", MenuUI.TEXT)
	_results_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_results_stats)

	_results_career_label = Label.new()
	_results_career_label.add_theme_font_size_override("font_size", 18)
	_results_career_label.add_theme_color_override("font_color", MenuUI.ACCENT)
	_results_career_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_career_label.visible = false
	box.add_child(_results_career_label)

	_results_career_bar = ProgressBar.new()
	_results_career_bar.min_value = 0.0
	_results_career_bar.max_value = 100.0
	_results_career_bar.value = 0.0
	_results_career_bar.show_percentage = false
	_results_career_bar.custom_minimum_size = Vector2(460, 14)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.12, 0.09, 0.9)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = MenuUI.ACCENT
	bar_fill.set_corner_radius_all(4)
	_results_career_bar.add_theme_stylebox_override("background", bar_bg)
	_results_career_bar.add_theme_stylebox_override("fill", bar_fill)
	_results_career_bar.visible = false
	box.add_child(_results_career_bar)

	box.add_child(MenuUI.hline())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	_next_mission_btn = Button.new()
	_next_mission_btn.text = _txt("НАСТУПНА МІСІЯ  →", "NEXT MISSION  →")
	_next_mission_btn.custom_minimum_size = Vector2(0, 52)
	_next_mission_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_mission_btn.visible = false
	_next_mission_btn.pressed.connect(_on_next_mission_pressed)
	buttons.add_child(_next_mission_btn)
	_results_lb_btn = Button.new()
	_results_lb_btn.text = _txt("ТАБЛИЦЯ ЛІДЕРІВ", "LEADERBOARD")
	_results_lb_btn.custom_minimum_size = Vector2(0, 52)
	_results_lb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_lb_btn.visible = get_node_or_null("/root/GameCenter") != null
	_results_lb_btn.pressed.connect(_on_leaderboard_pressed)
	buttons.add_child(_results_lb_btn)
	_results_dvr_btn = Button.new()
	_results_dvr_btn.name = "ButtonStrikeDVR"
	_results_dvr_btn.text = _txt("ПОВТОР УДАРУ (DVR)", "STRIKE REPLAY (DVR)")
	_results_dvr_btn.custom_minimum_size = Vector2(0, 52)
	_results_dvr_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_dvr_btn.visible = (Global.play_mode == Global.PlayMode.COMBAT)
	_results_dvr_btn.pressed.connect(_on_dvr_replay_pressed)
	buttons.add_child(_results_dvr_btn)
	var retry := Button.new()
	retry.text = _txt("ПРОЙТИ ЩЕ РАЗ", "RETRY")
	retry.custom_minimum_size = Vector2(0, 52)
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(_on_retry_pressed)
	buttons.add_child(retry)
	var menu := Button.new()
	menu.text = _txt("ГОЛОВНЕ МЕНЮ", "MAIN MENU")
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


func _on_leaderboard_pressed() -> void:
	var gc := get_node_or_null("/root/GameCenter")
	if gc != null:
		if gc.has_method("show_leaderboard"):
			gc.call("show_leaderboard")
			return
		if gc.has_method("show_leaderboards"):
			gc.call("show_leaderboards")
			return
	_set_flash(_txt("ТАБЛИЦЯ ЛІДЕРІВ НЕДОСТУПНА ОФЛАЙН", "LEADERBOARD UNAVAILABLE OFFLINE"))


## Grabs one low-resolution frame of the live FPV viewport for the DVR buffer.
func _capture_dvr_frame() -> void:
	if _dvr_capture_failed or _dvr_capture_pending:
		return
	if DisplayServer.get_name() == "headless":
		_dvr_capture_failed = true
		return
	# The viewport texture is only readable after the frame has actually been
	# drawn.  Reading it from _process returned an all-black image, so the
	# "replay" looked like a black screen with a REC stamp on top.
	_dvr_capture_pending = true
	await RenderingServer.frame_post_draw
	_dvr_capture_pending = false
	if not is_inside_tree() or _dvr_capture_failed or _mission_finished or _dvr_replaying:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var img := vp.get_texture().get_image() if vp.get_texture() != null else null
	if img == null or img.is_empty():
		_dvr_capture_failed = true
		return
	img.resize(DVR_FRAME_W, DVR_FRAME_H, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	_dvr_frames.append(tex)
	while _dvr_frames.size() > DVR_MAX_FRAMES:
		_dvr_frames.pop_front()


func _ensure_dvr_overlay() -> void:
	if _dvr_overlay != null and is_instance_valid(_dvr_overlay):
		return
	_dvr_overlay = CanvasLayer.new()
	_dvr_overlay.name = "DvrReplayLayer"
	_dvr_overlay.layer = 300
	_dvr_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dvr_overlay)
	var root := Control.new()
	root.name = "DvrReplayRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_dvr_overlay.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.005, 0.008, 0.006, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	_dvr_overlay_rect = TextureRect.new()
	_dvr_overlay_rect.name = "DvrFrame"
	_dvr_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dvr_overlay_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dvr_overlay_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dvr_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_dvr_overlay_rect)
	# Thin viewfinder frame + scanline tint sell the recording as archive
	# footage rather than live gameplay.
	var frame := Panel.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 10.0
	frame.offset_top = 10.0
	frame.offset_right = -10.0
	frame.offset_bottom = -10.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0, 0, 0, 0)
	frame_style.border_color = Color(0.92, 0.94, 0.90, 0.28)
	frame_style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", frame_style)
	root.add_child(frame)
	var scan := ColorRect.new()
	scan.color = Color(1, 1, 1, 1)
	scan.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A multiply-blended black ColorRect erased the recorded frame completely.
	# Draw real (subtle) scanlines instead so the footage stays visible.
	var scan_shader := Shader.new()
	scan_shader.code = """
shader_type canvas_item;
void fragment() {
	float line = step(0.5, fract(SCREEN_UV.y * 160.0));
	COLOR = vec4(0.0, 0.0, 0.0, 0.035 + line * 0.045);
}
"""
	var scan_mat := ShaderMaterial.new()
	scan_mat.shader = scan_shader
	scan.material = scan_mat
	root.add_child(scan)
	_dvr_overlay_stamp = Label.new()
	_dvr_overlay_stamp.name = "DvrStamp"
	_dvr_overlay_stamp.position = Vector2(28.0, 24.0)
	_dvr_overlay_stamp.add_theme_font_size_override("font_size", 18)
	_dvr_overlay_stamp.add_theme_color_override("font_color", Color(1.0, 0.30, 0.22, 1.0))
	_dvr_overlay_stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_dvr_overlay_stamp.add_theme_constant_override("outline_size", 5)
	root.add_child(_dvr_overlay_stamp)
	_dvr_overlay_time = Label.new()
	_dvr_overlay_time.name = "DvrTimecode"
	_dvr_overlay_time.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_dvr_overlay_time.offset_left = -300.0
	_dvr_overlay_time.offset_top = -52.0
	_dvr_overlay_time.offset_right = -28.0
	_dvr_overlay_time.offset_bottom = -24.0
	_dvr_overlay_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dvr_overlay_time.add_theme_font_size_override("font_size", 18)
	_dvr_overlay_time.add_theme_color_override("font_color", Color(0.86, 0.96, 0.88, 0.95))
	_dvr_overlay_time.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_dvr_overlay_time.add_theme_constant_override("outline_size", 5)
	root.add_child(_dvr_overlay_time)
	_dvr_overlay.visible = false


func _on_dvr_replay_pressed() -> void:
	if _dvr_replaying or _results == null:
		return
	_dvr_replaying = true
	var was_paused := get_tree().paused
	var results_was_visible := _results_canvas_layer == null \
			or _results_canvas_layer.visible
	var hud_was_visible := _hud == null or _hud.visible
	_results.visible = false
	if _results_canvas_layer != null:
		_results_canvas_layer.visible = false
	_ensure_dvr_overlay()
	if _dvr_overlay != null:
		_dvr_overlay.visible = true
	if _dvr_overlay_stamp != null:
		var b_name := DroneCatalog.get_drone_name(Global.drone_preset)
		_dvr_overlay_stamp.text = ("● REC  DVR STRIKE REPLAY · %s" if _is_en() \
				else "● REC  БОРТОВИЙ ЗАПИС (DVR) · %s") % b_name
	if _dvr_overlay_time != null:
		_dvr_overlay_time.text = ""
	# Freeze the world so the replay is a playback, not live gameplay.
	if _hud != null:
		_hud.visible = false
	get_tree().paused = true
	if _dvr_frames.size() >= 6:
		await _play_dvr_frames()
	else:
		await _play_dvr_camera_path()
	# Restore the debrief exactly as it was before playback.
	if _dvr_overlay != null:
		_dvr_overlay.visible = false
	if _dvr_overlay_rect != null:
		_dvr_overlay_rect.texture = null
	if _hud != null:
		_hud.visible = hud_was_visible
	if _results_canvas_layer != null:
		_results_canvas_layer.visible = results_was_visible
	if _results != null:
		_results.visible = true
	get_tree().paused = was_paused
	_dvr_replaying = false


func _play_dvr_frames() -> void:
	var total := _dvr_frames.size()
	for i in range(total):
		if not is_inside_tree() or _dvr_overlay_rect == null:
			break
		_dvr_overlay_rect.texture = _dvr_frames[i]
		if _dvr_overlay_time != null:
			var t_sec := int(float(i) / float(DVR_FPS))
			var total_sec := int(float(total) / float(DVR_FPS))
			_dvr_overlay_time.text = "▶ PLAY  %02d:%02d / %02d:%02d" % [
				t_sec / 60, t_sec % 60, total_sec / 60, total_sec % 60]
		await get_tree().create_timer(1.0 / float(DVR_FPS), true).timeout
	# Hold the final (strike) frame for a moment before returning to debrief.
	await get_tree().create_timer(0.65, true).timeout


func _play_dvr_camera_path() -> void:
	var drone := get_node_or_null("Drone") as Drone
	var old_cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if _dvr_samples.is_empty():
		if _dvr_overlay_time != null:
			_dvr_overlay_time.text = _txt("ЗАПИС ВІДСУТНІЙ", "NO RECORDING")
		await get_tree().create_timer(1.2, true).timeout
		return
	var replay_cam := Camera3D.new()
	replay_cam.name = "DvrReplayCamera"
	replay_cam.fov = 100.0
	replay_cam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(replay_cam)
	replay_cam.current = true
	var drone_was_visible := drone != null and drone.visible
	if drone != null:
		drone.visible = false
	var total := _dvr_samples.size()
	for i in range(total):
		if not is_inside_tree():
			break
		var sd: Dictionary = _dvr_samples[i]
		var cp: Vector3 = sd.get("cam_pos", sd.get("pos", Vector3.ZERO))
		var cr: Vector3 = sd.get("cam_rot", sd.get("rot", Vector3.ZERO))
		replay_cam.global_position = cp
		replay_cam.global_rotation = cr
		replay_cam.fov = float(sd.get("cam_fov", 100.0))
		if _dvr_overlay_time != null:
			var t_sec := int(float(i) * 0.05)
			var total_sec := int(float(total) * 0.05)
			_dvr_overlay_time.text = "▶ PLAY  %02d:%02d / %02d:%02d" % [
				t_sec / 60, t_sec % 60, total_sec / 60, total_sec % 60]
		await get_tree().create_timer(0.05, true).timeout
	await get_tree().create_timer(0.4, true).timeout
	if old_cam != null and is_instance_valid(old_cam):
		old_cam.current = true
	if drone != null:
		drone.visible = drone_was_visible
	replay_cam.queue_free()


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
	code.text = _txt("БРИФІНГ КАМПАНІЇ  ·  TAC-0%d / 4",
			"CAMPAIGN BRIEFING  ·  TAC-0%d / 4") % Global.combat_mission
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
	progress.text = _txt(
		"КАМПАНІЯ %d/4 · ★ %d/12 · СКЛАДНІСТЬ: %s · ЛІМІТ: %s",
		"CAMPAIGN %d/4 · ★ %d/12 · DIFFICULTY: %s · TIME LIMIT: %s") % [
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
	_chain_brief_start.text = _txt("  ▶  ПОЧАТИ ВИЛІТ  ", "  ▶  START SORTIE  ")
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
			return _txt(
				"ЗАВДАННЯ: виявити та знищити 6 піхотинців у лісосмузі.\nЦІЛІ: піхота, окопи, кулеметні точки.",
				"MISSION: Locate and neutralize six infantry in the tree line.\nTARGETS: infantry, trenches, and machine-gun positions.")
		2:
			return _txt(
				"ЗАВДАННЯ: знищити танк Т-72 та БТР-90, що маневрують біля заводу.\nЦІЛІ: 2 одиниці бронетехніки + піхота прикриття.",
				"MISSION: Destroy the T-72 tank and BTR-90 maneuvering near the plant.\nTARGETS: two armored vehicles with infantry escort.")
		3:
			return _txt(
				"ЗАВДАННЯ: перехопити ударний гелікоптер і знищити мобільну ППО.\nЦІЛІ: гелікоптер, ЗРК, прикриття.",
				"MISSION: Intercept the attack helicopter and destroy the mobile air-defense unit.\nTARGETS: helicopter, SAM system, and escort.")
		_:
			return _txt(
				"ЗАВДАННЯ: перехопити два «Шахеди-136» на маршруті.\nЦІЛІ: 2 БПЛА, ЗРК і БМП прикриття.",
				"MISSION: Intercept two Shahed-136 UAVs along their route.\nTARGETS: two UAVs, a SAM system, and an IFV escort.")


func _mission_phase_plan_text(_mission_id: int) -> String:
	return _txt(
		"ФАЗИ: РОЗВІДКА (підлетіти до зони та утримати 3 с) → УДАР (знищити цілі) → ВИХІД (повернутися в зону евакуації).",
		"PHASES: RECON (reach and hold the zone for 3 s) → STRIKE (destroy the targets) → EXFIL (return to the extraction zone).")


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
	if _is_mobile_runtime():
		_set_flash(_txt("АРМ — УВІМКНУТИ ДВИГУНИ · ПІСЛЯ АРМУ ПОЧНЕТЬСЯ МІСІЯ",
				"TAP ARM TO START MOTORS · THE MISSION BEGINS WHEN ARMED"))
	else:
		_set_flash(_txt("ARM — УВІМКНУТИ ДВИГУНИ · ПІСЛЯ АРМУ ПОЧНЕТЬСЯ МІСІЯ",
				"PRESS ARM TO START MOTORS · THE MISSION BEGINS WHEN ARMED"))


func _set_flash(text: String) -> void:
	text = MenuUI.translate_text(text)
	if _hud_message != null:
		_hud_message.text = text
		_hud_message.visible = not text.is_empty()
	_flash_token += 1
	var token := _flash_token
	# Short-lived callouts (weather, gates, boost) must not camp in the middle
	# of the screen for the whole flight.
	await get_tree().create_timer(3.0).timeout
	if token == _flash_token and _hud_message != null and _hud_message.text == text:
		_hud_message.text = ""
		_hud_message.visible = false


func _set_message(text: String) -> void:
	text = MenuUI.translate_text(text)
	if _hud_message != null:
		_hud_message.text = text
		_hud_message.visible = not text.is_empty()


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


func _idle_start_hint() -> String:
	return _txt("« ГОТОВИЙ ДО СТАРТУ — НАТИСНІТЬ ARM »",
			"« READY FOR LAUNCH — PRESS ARM »")


func _update_nav_marker() -> void:
	if _nav_marker == null:
		return
	var drone := get_node_or_null("Drone") as Drone
	if drone == null:
		_nav_marker.text = ""
		return
	if not _mission_started:
		var idle_text := _idle_start_hint()
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
					target_label = str(info.get("label", _txt("ЦІЛЬ", "TARGET")))
		Global.PlayMode.TRAINING:
			if _combat_training != null and is_instance_valid(_combat_training):
				var ct_info: Dictionary = _combat_training.get_target_info()
				if ct_info.has("pos"):
					target_pos = ct_info["pos"]
					target_found = true
					target_label = str(ct_info.get("label", _txt("ЦІЛЬ", "TARGET")))
			if not target_found:
				for r in _training_rings:
					if is_instance_valid(r) and r.visible:
						target_pos = r.global_position
						target_found = true
						target_label = "%s %d/%d" % [_txt("ВОРОТА", "GATE"), _rings_passed + 1, _rings_total]
						var m := _checkpoint_visual(r)
						if m != null and m.material_override is StandardMaterial3D:
							var mat := m.material_override as StandardMaterial3D
							# Match the ring pulse above; the old 3.5 bloomed the gate
							# to pure white and hid its opening against the sky.
							mat.emission_energy_multiplier = 1.15 + sin(Time.get_ticks_msec() * 0.008) * 0.20
							mat.emission = Color(0.12, 0.92, 0.80)
						break
		_:
			var special_info := get_special_objective_info()
			if not special_info.is_empty() and special_info.has("pos"):
				target_pos = special_info["pos"]
				target_found = true
				target_label = str(special_info.get("label", _txt("ЦІЛЬ", "TARGET")))
				if bool(special_info.get("show_progress", true)):
					target_label += " %d%%" % int(float(special_info.get("progress", 0.0)) * 100.0)
			else:
				var phase_info := get_mission_phase_info()
				if not phase_info.is_empty() and phase_info.has("pos"):
					target_pos = phase_info["pos"]
					target_found = true
					target_label = "%s %d%%" % [str(phase_info.get("label", _txt("ЦІЛЬ", "TARGET"))),
							int(float(phase_info.get("progress", 0.0)) * 100.0)]
				else:
					var min_d := 1e9
					var best_t: Node3D = null
					for t in get_tree().get_nodes_in_group("primary_combat_target"):
						if is_instance_valid(t) and t.visible and t.get("is_destroyed") != true:
							var d := drone.global_position.distance_to(t.global_position)
							if d < min_d:
								min_d = d
								best_t = t
					if best_t == null:
						for t in get_tree().get_nodes_in_group("combat_target"):
							if is_instance_valid(t) and t.visible and t.get("is_destroyed") != true:
								var d := drone.global_position.distance_to(t.global_position)
								if d < min_d:
									min_d = d
									best_t = t
					if best_t != null:
						target_pos = best_t.global_position
						target_found = true
						target_label = _txt("УДАР", "STRIKE") if not phase_info.is_empty() else _txt("ЦІЛЬ", "TARGET")

	if not target_found:
		_nav_marker.text = ""
		return

	var dist := drone.global_position.distance_to(target_pos)
	var local_tgt := drone.global_transform.affine_inverse() * target_pos
	var angle := atan2(local_tgt.x, -local_tgt.z)
	var deg := rad_to_deg(angle)

	var dir_arrow := "▲"
	var dir_text := _txt("ПРЯМО", "AHEAD")
	if deg > 120.0 or deg < -120.0:
		dir_arrow = "▼"
		dir_text = _txt("ПОЗАДУ", "BEHIND")
	elif deg > 65.0:
		dir_arrow = "►"
		dir_text = _txt("ПРАВОРУЧ", "RIGHT")
	elif deg > 20.0:
		dir_arrow = "▲►"
		dir_text = _txt("ПРАВОРУЧ", "RIGHT")
	elif deg < -65.0:
		dir_arrow = "◄"
		dir_text = _txt("ЛІВОРУЧ", "LEFT")
	elif deg < -20.0:
		dir_arrow = "◄▲"
		dir_text = _txt("ЛІВОРУЧ", "LEFT")

	var alt_diff := target_pos.y - drone.global_position.y
	var alt_hint := ""
	var unit_m := _txt("м", "m")
	if alt_diff > 8.0:
		alt_hint = " [↑ +%d%s]" % [int(alt_diff), unit_m]
	elif alt_diff < -8.0:
		alt_hint = " [↓ %d%s]" % [int(alt_diff), unit_m]

	_nav_marker.text = "%s  %s: %s  %d%s%s" % [
		dir_arrow, target_label, dir_text, int(dist), unit_m, alt_hint
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
			_finish_mission(_txt("ЧАС ВИЙШОВ — ЗАВДАННЯ НЕ ВИКОНАНО", "TIME EXPIRED — MISSION FAILED"), true)
		_update_mission_phases(delta)
		if Global.special_mission > 0:
			_update_special_mission(delta)
		if _radio_beat_02_fallback_timer > 0.0 and not _radio_beat_02_sent:
			_radio_beat_02_fallback_timer -= delta
			if _radio_beat_02_fallback_timer <= 0.0:
				_radio_beat_02_sent = true
				_play_radio_callout(
					_txt("Борт-01, я Штаб. Координати підтверджено, поправка на вітер східний. Роботу дозволяю. Кінець зв'язку.",
						"Valkyrie-01, HQ copies. Coordinates confirmed, adjust for east crosswind. Cleared hot. Out."),
					false, "02")
	_update_fpv_camera_fx(delta)
	_update_training_ghost(delta)
	# The OSD is shaped by the text server.  Refreshing formatted strings at
	# 120 Hz burns CPU for readouts that only change once a second or on a hit;
	# 12 Hz matches the refresh of a real Betaflight OSD.
	_hud_tick -= delta
	if _hud_tick <= 0.0:
		_hud_tick = 0.083
		var kc_live := _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active()
		if _telem_left != null:
			_telem_left.visible = not kc_live
		if _telem_right != null:
			_telem_right.visible = not kc_live
		_update_hud()
		if _elrs_status_label != null:
			var next_elrs := ElrsWifiInput.status_text
			if _touch_controls != null \
					and bool(_touch_controls.get("enabled")) \
					and bool(_touch_controls.get("touch_mode")):
				next_elrs = "СЕНСОРНЕ КЕРУВАННЯ" if not _is_en() else "TOUCH CONTROLS"
			if next_elrs != _elrs_status_last_text:
				_elrs_status_last_text = next_elrs
				_elrs_status_label.text = next_elrs
				_elrs_status_label.visible = not next_elrs.is_empty()
				_elrs_status_timer = 2.5
			elif _elrs_status_timer > 0.0:
				_elrs_status_timer = maxf(_elrs_status_timer - 0.083, 0.0)
				if _elrs_status_timer <= 0.0:
					_elrs_status_label.visible = false
	_update_audio_mix(delta)
	# Audio-bus trimming and the nav marker only need human-perceptible update
	# rates.  Running them at 120 Hz changed four AudioServer buses and shaped
	# a Label every frame, which is pure heat on the UHD target.
	_audio_priority_tick -= delta
	if _audio_priority_tick <= 0.0:
		_audio_priority_tick = 0.1
		_update_audio_priority(0.1)
	_update_threats(delta)
	if Global.play_mode == Global.PlayMode.TRAINING:
		_update_training_ring_highlight(delta)
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
			thunder_pos += Vector3(randf_range(-140, 140), randf_range(110, 220), randf_range(-140, 140))
			CombatSfxScript.play_thunder(self, thunder_pos, 8.0)
			_route_last_sfx_bus(&"Combat")

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
		# Compact arena perimeter barrier (MAP_FLIGHT_BOUND = 182 m)
		_perimeter_warn_timer = maxf(_perimeter_warn_timer - delta, 0.0)
		var px := drone_body.global_position.x
		var pz := drone_body.global_position.z
		var soft_bound := MAP_FLIGHT_BOUND - 16.0
		if (absf(px) > soft_bound or absf(pz) > soft_bound) and _perimeter_warn_timer <= 0.0:
			_perimeter_warn_timer = 2.4
			_set_flash(_txt("МЕЖА ЗОНИ ПОЛЬОТІВ — ПОВЕРТАЙТЕСЬ",
					"FLIGHT PERIMETER — TURN BACK"))
		if absf(px) > MAP_FLIGHT_BOUND or absf(pz) > MAP_FLIGHT_BOUND:
			var clamped_pos := drone_body.global_position
			var vel := drone_body.linear_velocity
			if absf(clamped_pos.x) > MAP_FLIGHT_BOUND:
				clamped_pos.x = clampf(clamped_pos.x, -(MAP_FLIGHT_BOUND - 0.8), MAP_FLIGHT_BOUND - 0.8)
				if signf(vel.x) == signf(px):
					vel.x = -vel.x * 0.35
			if absf(clamped_pos.z) > MAP_FLIGHT_BOUND:
				clamped_pos.z = clampf(clamped_pos.z, -(MAP_FLIGHT_BOUND - 0.8), MAP_FLIGHT_BOUND - 0.8)
				if signf(vel.z) == signf(pz):
					vel.z = -vel.z * 0.35
			drone_body.global_position = clamped_pos
			drone_body.linear_velocity = vel
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
	var ready_word := _txt("ГОТОВИЙ", "READY")
	match Global.play_mode:
		Global.PlayMode.TUTORIAL:
			var time_str: String = _format_time(_mission_time) if _mission_started else ready_word
			var cur_step_name := _txt("УВІМКНЕННЯ ДВИГУНІВ", "ARMING MOTORS")
			var module_txt := "%s 1/10" % _txt("МОДУЛЬ", "MODULE")
			if _flight_school != null:
				var d_step: Dictionary = FlightSchool.STEP_DATA.get(_flight_school.current_step, {})
				cur_step_name = str(d_step.get("title", ""))
				module_txt = "%s %d/%d" % [
						_txt("МОДУЛЬ", "MODULE"),
						mini(_flight_school.current_step + 1, FlightSchool.TOTAL_MODULES),
						FlightSchool.TOTAL_MODULES]
			_hud_label.text = "%s · %s\n%s\n%s" % [
					short_name, time_str, module_txt, cur_step_name]
		Global.PlayMode.TRAINING:
			var time_str: String = _format_time(_mission_time) if _mission_started else ready_word
			if _combat_training != null and is_instance_valid(_combat_training):
				_hud_label.text = "%s\n%s · %s\n%s" % [
						short_name, time_str, _txt("ТРЕНУВАННЯ", "TRAINING"),
						_combat_training.get_status_line()]
			else:
				_hud_label.text = "%s\n%s · %s %d/%d · %d" % [
						short_name, time_str, _txt("КІЛЬЦЯ", "GATES"), _rings_passed, _rings_total, _score]
		_:
			var combat_time_limit: float = Global.get_difficulty_time_limit()
			var time_left := maxf(0.0, combat_time_limit - _mission_time)
			var time_str: String = _format_countdown(time_left) if _mission_started else ready_word
			if Global.special_mission > 0:
				var sdetail := ""
				match Global.special_mission:
					1:
						sdetail = "%s %d/%d" % [
							_txt("ЗОНИ", "ZONES"), _special_index, _special_zones.size()]
					2:
						sdetail = _txt("СУПРОВІД КОЛОНИ", "CONVOY ESCORT")
					3:
						sdetail = "%s %d/1 · %s %d/1" % [
							_txt("ПІЛОТ", "PILOT"), 1 if _special_index > 0 else 0,
							_txt("БАЗА", "BASE"), 1 if _special_index > 1 else 0]
					4:
						sdetail = "%s %d/2" % [_txt("ВАНТАЖ", "CARGO"), _special_index]
					_:
						sdetail = "%s %d/%d" % [
							_txt("ЦІЛІ", "TARGETS"), _mission_targets_destroyed, _mission_targets_total]
				var craft_tag := (" · %s %d/%d" % [_txt("БОРТ", "CRAFT"), _sortie_airframes_left, _sortie_airframes_total]) if _airframes_limited() else ""
				_hud_label.text = "%s · %s «%s»\n%s\n%s · %s%s" % [
					short_name, _txt("СПЕЦОПЕРАЦІЯ", "SPEC OP"),
					Global.get_special_mission_name(Global.special_mission),
					sdetail, _txt("ОПЕРАЦІЯ", "OPERATION"), time_str, craft_tag]
				return
			var detail := ""
			match Global.combat_mission:
				1:
					detail = "%s %d/%d" % [
						_txt("ПІХОТА", "INFANTRY"), _mission_targets_destroyed, _mission_targets_total]
				2:
					detail = "%s %d/1 · %s %d/1" % [
						_txt("ТАНК", "TANK"), int(_kills.get(Vehicle.Kind.TANK, 0)),
						_txt("БТР", "APC"), int(_kills.get(Vehicle.Kind.APC, 0))]
				3:
					detail = "%s %d/1 · %s %d/1" % [
						_txt("ГЕЛІ", "HELI"), int(_kills.get(Vehicle.Kind.HELI, 0)),
						_txt("ЗРК", "SAM"), int(_kills.get(Vehicle.Kind.SAM, 0))]
				4:
					detail = "%s %d/2 · %s %d/2" % [
						_txt("ШАХЕД", "SHAHED"), int(_kills.get(Vehicle.Kind.SHAHED, 0)),
						_txt("ППО", "ADA"), int(_kills.get(Vehicle.Kind.SAM, 0)) + int(_kills.get(Vehicle.Kind.BMP, 0))]
				_:
					detail = "%s %d/1" % [_txt("ГЕС", "HYDRO"), int(_kills.get("HYDRO_PLANT", 0))]
			var craft_info := (" · %s %d/%d" % [_txt("БОРТ", "CRAFT"), _sortie_airframes_left, _sortie_airframes_total]) if _airframes_limited() else ""
			_hud_label.text = "%s · TAC-0%d · %s\n%s\n%s: %s · %s · %d/%d%s" % [
				short_name, Global.combat_mission, Global.get_difficulty_name(),
				detail, _txt("ФАЗА", "PHASE"), _mission_phase_name(), time_str,
				_mission_targets_destroyed, _mission_targets_total, craft_info]


func _input(event: InputEvent) -> void:
	if _kill_cam != null and is_instance_valid(_kill_cam) and _kill_cam.is_active():
		return
	if _chain_brief != null and _chain_brief.visible:
		# The chain briefing is a modal UI; do not arm, pause, drop or change
		# vision while the player is reading it.
		return
	super._input(event)
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
		var quality_ua: String = ["НИЗЬКА", "СЕРЕДНЯ", "ВИСОКА"][clampi(next_q, 0, 2)]
		var quality_en: String = ["LOW", "MEDIUM", "HIGH"][clampi(next_q, 0, 2)]
		_set_flash(_txt("ГРАФІКА: %s", "GRAPHICS: %s")
				% _txt(quality_ua, quality_en))
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_F4:
			cycle_vision_mode()
		elif event.keycode == KEY_F5:
			_weather = (_weather + 1) % 5
			GameSettings.hud_config["weather"] = _weather
			GameSettings.save_hud_config()
			_apply_weather()
		elif event.keycode == KEY_J:
			_rig_visible = not _rig_visible
			if GameSettings != null:
				GameSettings.hud_config["fpv_rig"] = _rig_visible
				GameSettings.save_hud_config()
			_apply_fpv_rig()
			_set_flash(_txt("FPV-ОБВІС: УВІМК" if _rig_visible else "FPV-ОБВІС: ВИМК",
					"FPV RIG: ON" if _rig_visible else "FPV RIG: OFF"))
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
		_set_flash(_txt("ВІДЕО: %s", "VIDEO: %s") % Graphics.fpv_video_mode_name(mode))
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

	# First-person only: no orbit/chase mouse camera controls.


func _full_test() -> void:
	await get_tree().create_timer(3.0).timeout
	var ok := true
	var d := get_node_or_null("Drone") as Drone
	print("[FULLTEST] mode=", Global.play_mode, " map_children=", _map_root.get_child_count(),
			" vehicles=", _vehicles.size(), " infantry=", _infantry_units.size(), " drone=", d != null)
	var targets_count: int = _vehicles.size() + _infantry_units.size() + _mission_targets_total
	var targets_ok: bool = (Global.play_mode != Global.PlayMode.COMBAT) or (targets_count > 0)
	var ft_node := get_node_or_null("FrontlineTerrain")
	var map_ok: bool = (_map_root != null and _map_root.get_child_count() > 0) or (not frontline_map.is_empty() and ft_node != null and ft_node.get_child_count() > 0)
	ok = ok and d != null and map_ok and targets_ok

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

	var wind_cfg: bool = bool(GameSettings.hud_config.get("wind_sim", false))
	GameSettings.hud_config["wind_sim"] = not wind_cfg
	GameSettings.save_hud_config()
	GameSettings.load_hud_config()
	ok = ok and bool(GameSettings.hud_config.get("wind_sim", false)) == (not wind_cfg)
	GameSettings.hud_config["wind_sim"] = wind_cfg
	GameSettings.save_hud_config()
	print("[FULLTEST] settings round-trip ok=", ok)

	# --- drone presets really change the model ---
	var mass_before := d.mass
	var test_preset := 1 if Global.drone_preset == 0 else 0
	DroneCatalog.apply_to_drone(d, test_preset)
	await get_tree().create_timer(0.3).timeout
	ok = ok and absf(d.mass - mass_before) > 0.05
	print("[FULLTEST] preset mass ", mass_before, " -> ", d.mass)
	DroneCatalog.apply_to_drone(d, Global.drone_preset)

	# --- arm + mission timer ---
	_place_drone_over_ground()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var radio := get_node_or_null("RadioController")
	d.flight_controller.request_arm(true)
	if radio != null:
		radio.set("test_throttle", 0.65)
	await get_tree().create_timer(0.6).timeout
	ok = ok and d.flight_controller.state_armed and _mission_started
	var t0 := _mission_time
	await get_tree().create_timer(3.0).timeout
	ok = ok and _mission_time > t0 + 2.0
	print("[FULLTEST] armed=", d.flight_controller.state_armed, " timer ",
			t0, " -> ", _mission_time)
	if radio != null:
		radio.set("test_throttle", -1.0)

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
			and not bool(p.get("has_drop", false))
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
			and not bool(p.get("has_drop", false))
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
	var msg := _txt("« АВАРІЯ! ЗНИЩЕНО: %s » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]",
			"« CRASH: %s » [PRESS R TO RESPAWN]") % reason
	match reason:
		"HARD_IMPACT":
			msg = _txt("« КРАШ: СИЛЬНИЙ УДАР ОБ ПЕРЕШКОДУ » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]",
					"« CRASH: HARD OBSTACLE IMPACT » [PRESS R TO RESPAWN]")
		"INVERTED_ON_GROUND":
			msg = _txt("« КРАШ: ДРОН ПЕРЕВЕРНУТИЙ НА ЗЕМЛІ » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]",
					"« CRASH: INVERTED ON GROUND » [PRESS R TO RESPAWN]")
		_:
			msg = _txt("« КРАШ: %s » [НАТИСНІТЬ R ДЛЯ ВІДНОВЛЕННЯ]",
					"« CRASH: %s » [PRESS R TO RESPAWN]") % reason
	var crash_drone := get_node_or_null("Drone") as Node3D
	if crash_drone != null:
		CombatSfxScript.play_drone_impact(self, crash_drone.global_position, 0.0)
		_route_last_sfx_bus(&"Combat")
		CombatSfxScript.play_boom(self, crash_drone.global_position, -7.0)
		_route_last_sfx_bus(&"Combat")
	var has_next := consume_sortie_airframe(reason)
	if not has_next:
		msg = _txt("« ОСТАННІЙ БОРТ ВТРАЧЕНО (0/%d) »", "« FINAL AIRFRAME LOST (0/%d) »") % _sortie_airframes_total
	elif _airframes_limited():
		msg += " [%s %d/%d]" % [_txt("БОРТ", "CRAFT"), _sortie_airframes_left, _sortie_airframes_total]
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
	var third_person := camera != null and camera.name != "FPVCamera"
	if not third_person:
		# Combat airframes show the warhead at the bottom edge with the camera
		# lifted just above the frame so the body no longer fills the centre.
		var combat_airframe := bool(p.get("combat", false))
		var show_airframe := bool(p.get("fpv_show_airframe", false))
		var hide_model := bool(p.get("fpv_hide_model", false))
		if show_airframe:
			hide_model = false
		# The 2.8 m heavy bomber cannot be framed by a 110-degree lens without
		# its rack/battery covering the crosshair.  Its external ordnance is
		# still simulated, the CCIP sight and AMMO counter carry the cue.
		if bool(p.get("heavy_bomber", false)):
			hide_model = true
		_model_root.visible = ((combat_airframe and _rig_visible) or show_airframe) and not hide_model
		_apply_combat_fpv_camera(combat_airframe and _rig_visible and not show_airframe and not hide_model, p)
		if show_airframe:
			# Recon/loitering fixed-wing aircraft need enough body in frame for
			# orientation. Hide the close-up camera gimbal itself, which otherwise
			# fills the centre of the FPV image on Leleka/Furia.
			_configure_fixed_wing_fpv(_model_root)
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
			(pivot as Node3D).visible = third_person or bool(
					preset_now.get("fpv_show_airframe", false))


## The mobile HUD is customized and persisted by the player. Loading a level
## must not silently overwrite those preferences. Keep legacy non-mobile defaults.
func _apply_flight_hud_defaults() -> void:
	if _is_mobile_runtime():
		return
	GameSettings.hud_config["crosshair"] = true
	GameSettings.hud_config["status"] = false
	GameSettings.hud_config["speed"] = false
	GameSettings.hud_config["altitude"] = false
	GameSettings.hud_config["heading"] = false
	GameSettings.hud_config["sticks"] = true
	GameSettings.hud_config["osd"] = true


func _is_mobile_runtime() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


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
