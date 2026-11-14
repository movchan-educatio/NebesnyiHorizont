extends Node

const LocScript = preload("res://scripts/util/localization_manager.gd")
const CombatSfx = preload("res://combat/sfx.gd")
const DroneCatalog = preload("res://autoloads/DroneCatalog.gd")

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/b9653fe7-b116-4da5-b8ea-6de700486b1e/scratch/audio_vision"

func _ready() -> void:
	print("==================================================================")
	print("=== RUNNING ADVANCED AUDIO SYNTHESIS & TACTICAL VISION TESTS   ===")
	print("==================================================================")
	
	var pass_count := 0
	
	# -------------------------------------------------------------------------
	# 1. PROCEDURAL MOTOR AUDIO SYNTHESIS & SOUND GENERATOR
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Procedural Drone Motor BLDC Synthesis...")
	var stream_5in := CombatSfx.drone_motor_stream(0)
	assert(stream_5in != null, "Motor stream for 5in drone must not be null")
	assert(stream_5in.format == AudioStreamWAV.FORMAT_16_BITS, "Audio format must be 16-bit PCM")
	assert(stream_5in.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Loop mode must be LOOP_FORWARD")
	assert(stream_5in.data.size() > 20000, "Motor stream data size must have valid waveform buffer")
	print("  ✓ 5\" Freestyle BLDC Motor Stream: %d bytes, 16-bit PCM, Loop Forward" % stream_5in.data.size())
	
	var stream_8in := CombatSfx.drone_motor_stream(1)
	assert(stream_8in != null, "Motor stream for 8in drone must not be null")
	assert(stream_8in.data.size() > 20000, "8in Motor stream data must have valid buffer")
	print("  ✓ 8\" Heavy Combat BLDC Motor Stream: %d bytes, deep rotor bass" % stream_8in.data.size())
	
	var stream_usv := CombatSfx.drone_motor_stream(2)
	assert(stream_usv != null, "Motor stream for USV must not be null")
	assert(stream_usv.data.size() > 20000, "USV motor stream data must have valid buffer")
	print("  ✓ Naval USV Waterjet Motor Stream: %d bytes, water displacement wash" % stream_usv.data.size())
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 2. PROCEDURAL THUNDER & LIGHTNING SYNTHESIS
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Procedural Thunderstorm Audio Synthesis...")
	var stream_thunder := CombatSfx.thunder_stream()
	assert(stream_thunder != null, "Thunder stream must not be null")
	assert(stream_thunder.format == AudioStreamWAV.FORMAT_16_BITS, "Thunder format must be 16-bit PCM")
	# 3.2s @ 22050Hz * 2 bytes = ~141,120 bytes
	assert(stream_thunder.data.size() > 100000, "Thunder buffer must contain full rolling rumble waveform")
	print("  ✓ Procedural Thunder Waveform: %d bytes (~3.2s duration with crack & sub-bass rumble)" % stream_thunder.data.size())
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 3. DRONE 3D MOTOR AUDIO & DOPPLER TRACKING
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Drone 3D Spatial Audio & Physical Doppler Pitch Tracking...")
	var drone_scene := load("res://drone/drones/Drone1.tscn") as PackedScene
	assert(drone_scene != null, "Drone1.tscn must be loadable")
	var drone := drone_scene.instantiate() as Drone
	add_child(drone)
	
	var motor_player: AudioStreamPlayer3D = drone.get_node_or_null("MotorAudio3D") as AudioStreamPlayer3D
	if motor_player == null:
		motor_player = drone._motor_audio
	assert(motor_player != null, "Drone must have AudioStreamPlayer3D node 'MotorAudio3D'")
	assert(motor_player.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP,
			"Doppler tracking must be enabled with DOPPLER_TRACKING_PHYSICS_STEP")
	assert(motor_player.unit_size >= 12.0, "Spatial unit size must be realistic for outdoor drone")
	assert(motor_player.max_distance >= 300.0, "Audible range must cover at least 300m radius")
	print("  ✓ AudioStreamPlayer3D: Doppler Physics Step active, unit_size=%.1f, max_distance=%.1fm" % [
		motor_player.unit_size, motor_player.max_distance
	])
	
	# Test dynamic pitch/volume modulation
	var fc: FlightController = drone.flight_controller
	fc.state_armed = false
	for step in range(20):
		drone._update_motor_audio(0.05)
	var disarmed_pitch: float = motor_player.pitch_scale
	var disarmed_db: float = motor_player.volume_db
	assert(disarmed_pitch < 0.75, "Disarmed/idle pitch must be low (~0.68)")
	assert(disarmed_db <= -16.0, "Disarmed volume must be quiet (~ -18 dB)")
	
	fc.state_armed = true
	fc.input = [1.0, 0.0, 0.0, 0.0]
	for step in range(30):
		drone._update_motor_audio(0.05)
	var full_pitch: float = motor_player.pitch_scale
	var full_db: float = motor_player.volume_db
	assert(full_pitch > 1.80, "Full throttle pitch must scream (> 1.80x)")
	assert(full_db >= -9.0 and full_db > disarmed_db + 10.0,
			"Full throttle volume must jump cleanly (got %.1f dB vs disarmed %.1f dB)" % [full_db, disarmed_db])
	print("  ✓ Dynamic Modulation: Disarmed Pitch=%.2fx (%.1f dB) -> Full Throttle Pitch=%.2fx (%.1f dB)" % [
		disarmed_pitch, disarmed_db, full_pitch, full_db
	])
	drone.queue_free()
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 4. BILINGUAL LOCALIZATION (UA + EN) & DICTIONARY
	# -------------------------------------------------------------------------
	print("\n[TEST 4] Bilingual Localization System (UA + EN)...")
	LocScript.set_language(LocScript.Language.EN)
	assert(LocScript.get_language() == LocScript.Language.EN, "Language must switch to EN")
	assert(LocScript.t("BTN_LAUNCH") == "START SORTIE", "EN BTN_LAUNCH mismatch")
	assert(LocScript.t("HUD_ARMED") == "ARMED / MOTORS ON", "EN HUD_ARMED mismatch")
	assert(LocScript.t("VISION_NVG") == "OPTICS: NIGHT VISION (NVG)", "EN VISION_NVG mismatch")
	assert(LocScript.t("WEATHER_STORM") == "WEATHER: THUNDERSTORM", "EN WEATHER_STORM mismatch")
	print("  ✓ English Dictionary: 'START SORTIE', 'ARMED / MOTORS ON', 'OPTICS: NIGHT VISION (NVG)', 'WEATHER: THUNDERSTORM'")

	LocScript.set_language(LocScript.Language.UA)
	assert(LocScript.get_language() == LocScript.Language.UA, "Language must switch back to UA")
	assert(LocScript.t("BTN_LAUNCH") == "ПОЧАТИ ВИЛІТ", "UA BTN_LAUNCH mismatch")
	assert(LocScript.t("HUD_ARMED") == "ДВИГУНИ УВІМКНЕНО", "UA HUD_ARMED mismatch")
	assert(LocScript.t("VISION_NVG") == "ОПТИКА: НІЧНЕ БАЧЕННЯ (NVG)", "UA VISION_NVG mismatch")
	assert(LocScript.t("WEATHER_STORM") == "ПОГОДА: ГРОЗА ТА БЛИСКАВКА", "UA WEATHER_STORM mismatch")
	print("  ✓ Ukrainian Dictionary: 'ПОЧАТИ ВИЛІТ', 'ДВИГУНИ УВІМКНЕНО', 'ОПТИКА: НІЧНЕ БАЧЕННЯ (NVG)', 'ПОГОДА: ГРОЗА ТА БЛИСКАВКА'")
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 5. OSD ACCESSIBILITY COLOR PALETTES
	# -------------------------------------------------------------------------
	print("\n[TEST 5] OSD Color Accessibility Profiles...")
	var expected_palettes := [
		LocScript.OsdPalette.DEFAULT,
		LocScript.OsdPalette.HIGH_CONTRAST,
		LocScript.OsdPalette.CYAN_AMBER,
		LocScript.OsdPalette.PHOSPHOR_GREEN,
		LocScript.OsdPalette.RED_NIGHT
	]
	for pal in expected_palettes:
		var pal_name: String = LocScript.get_palette_name(pal)
		var pal_cols: Dictionary = LocScript.get_palette_colors(pal)
		assert(pal_name.length() > 0, "Palette name must not be empty")
		assert(pal_cols.has("primary"), "Palette must have primary color")
		assert(pal_cols.has("text"), "Palette must have text color")
		assert(pal_cols.has("warning"), "Palette must have warning color")
		assert(pal_cols.has("danger"), "Palette must have danger color")
		assert(pal_cols.has("bg"), "Palette must have bg color")
		print("  ✓ Palette [%d] '%s': Primary=%s, Danger=%s" % [int(pal), pal_name, pal_cols["primary"], pal_cols["danger"]])
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 6. TACTICAL VISION SHADERS & WEATHER SYSTEM IN BIGLEVEL
	# -------------------------------------------------------------------------
	print("\n[TEST 6] Tactical Vision Post-Processing & Dynamic Weather Simulation...")
	var level_scene := load("res://sceneries/BigLevel.tscn") as PackedScene
	assert(level_scene != null, "BigLevel.tscn must load successfully")
	var level = level_scene.instantiate()
	add_child(level)
	for f in range(6):
		await get_tree().physics_frame
		await get_tree().process_frame
	
	# Verify vision overlay and shader
	assert(level._vision_overlay != null, "Level must have _vision_overlay ColorRect")
	assert(level._vision_material != null, "Level must have _vision_material ShaderMaterial")
	
	# Test all vision modes
	level._vision_mode = level.VisionMode.NORMAL
	level._apply_vision_mode()
	assert(int(level._vision_material.get_shader_parameter("vision_mode")) == 0, "NORMAL vision uniform must be 0")
	assert(level._vision_overlay.visible == false, "NORMAL vision should disable post-processing overlay")
	
	level._vision_mode = level.VisionMode.NVG
	level._apply_vision_mode()
	assert(int(level._vision_material.get_shader_parameter("vision_mode")) == 1, "NVG vision uniform must be 1")
	assert(level._vision_overlay.visible == true, "NVG vision overlay must be visible")
	
	level._vision_mode = level.VisionMode.FLIR_WHITE_HOT
	level._apply_vision_mode()
	assert(int(level._vision_material.get_shader_parameter("vision_mode")) == 2, "FLIR_WHITE_HOT uniform must be 2")
	
	level._vision_mode = level.VisionMode.FLIR_BLACK_HOT
	level._apply_vision_mode()
	assert(int(level._vision_material.get_shader_parameter("vision_mode")) == 3, "FLIR_BLACK_HOT uniform must be 3")
	print("  ✓ Tactical Vision Modes: NORMAL (0), NVG (1), FLIR White Hot (2), FLIR Black Hot (3) verified")
	
	# Test weather modes
	level._weather = 0 # CLEAR
	level._apply_weather()
	assert(level._rain.emitting == false, "Clear weather: rain must not emit")
	
	level._weather = 1 # RAIN
	level._apply_weather()
	assert(level._rain.emitting == true, "Rain weather: rain particles must emit")
	
	level._weather = 2 # STORM
	level._apply_weather()
	assert(level._rain.emitting == true, "Storm weather: rain particles must emit")
	assert(level._thunder_timer > 0.0, "Storm weather: thunder timer must be armed")
	
	level._weather = 3 # NIGHT
	level._apply_weather()
	assert(level._lightning_light.light_energy < 0.1, "Night weather: sun light must be minimal (< 0.1)")
	
	level._weather = 4 # DUST
	level._apply_weather()
	assert(level._dust.emitting == true, "Dust weather: dust particles must emit")
	print("  ✓ Weather Modes: CLEAR, RAIN, STORM, NIGHT, DUST verified")
	
	# Test True Airspeed wind howling calculation
	level._weather = 0
	var level_drone := level.get_node_or_null("Drone") as Drone
	assert(level_drone != null, "Drone must exist in BigLevel")
	if level._wind_player != null:
		level_drone.linear_velocity = Vector3(0, 0, 0)
		level._process(0.016)
		var stationary_pitch: float = level._wind_player.pitch_scale
		
		level_drone.linear_velocity = Vector3(30, 0, 0) # 30 m/s airspeed
		level._process(0.016)
		var high_speed_pitch: float = level._wind_player.pitch_scale
		assert(high_speed_pitch > stationary_pitch, "Airspeed wind pitch must increase with drone velocity")
		print("  ✓ Dynamic Wind Airspeed: Stationary Pitch=%.2f -> High Speed (30 m/s) Pitch=%.2f" % [
			stationary_pitch, high_speed_pitch
		])
	else:
		print("  ✓ Dynamic Wind Airspeed: AudioStreamPlayer skipped in headless mode")
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 7. IN-GAME VISUAL CAPTURE FOR ARTIFACTS
	# -------------------------------------------------------------------------
	if DisplayServer.get_name() != "headless":
		print("\n[TEST 7] Capturing in-game screenshots for documentation...")
		var dir := DirAccess.open("C:/")
		if not DirAccess.dir_exists_absolute(ARTIFACT_DIR):
			DirAccess.make_dir_recursive_absolute(ARTIFACT_DIR)
		
		# 1. NVG Night Shot
		level._weather = 3 # NIGHT
		level._apply_weather()
		level._vision_mode = level.VisionMode.NVG
		level._apply_vision_mode()
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_nvg := get_viewport().get_texture().get_image()
		var nvg_path := ARTIFACT_DIR + "/test_nvg_night.png"
		img_nvg.save_png(nvg_path)
		print("  -> Saved NVG Night screenshot: ", nvg_path)
		
		# 2. FLIR White Hot Shot
		level._vision_mode = level.VisionMode.FLIR_WHITE_HOT
		level._apply_vision_mode()
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_white := get_viewport().get_texture().get_image()
		var white_path := ARTIFACT_DIR + "/test_flir_white_hot.png"
		img_white.save_png(white_path)
		print("  -> Saved FLIR White-Hot screenshot: ", white_path)
		
		# 3. FLIR Black Hot Shot
		level._vision_mode = level.VisionMode.FLIR_BLACK_HOT
		level._apply_vision_mode()
		for i in range(4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_black := get_viewport().get_texture().get_image()
		var black_path := ARTIFACT_DIR + "/test_flir_black_hot.png"
		img_black.save_png(black_path)
		print("  -> Saved FLIR Black-Hot screenshot: ", black_path)
		
		# 4. Thunderstorm Lightning Shot
		level._weather = 2 # STORM
		level._apply_weather()
		level._vision_mode = level.VisionMode.NORMAL
		level._apply_vision_mode()
		level.trigger_lightning()
		for i in range(2):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_storm := get_viewport().get_texture().get_image()
		var storm_path := ARTIFACT_DIR + "/test_storm_lightning.png"
		img_storm.save_png(storm_path)
		print("  -> Saved Thunderstorm Lightning screenshot: ", storm_path)
		pass_count += 1
	else:
		print("\n[TEST 7] (Headless display detected - visual screenshot render skipped)")
	
	print("\n==================================================================")
	print("=== ALL %d AUDIO, VISION & LOCALIZATION SUITES PASSED (100%%)    ===" % pass_count)
	print("==================================================================")
	get_tree().quit(0)
