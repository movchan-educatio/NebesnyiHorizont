extends Node


const QualityManagerScript = preload("res://scripts/util/quality_manager.gd")

signal quality_changed(level: int)
signal shadows_updated
signal fisheye_mode_changed
signal fisheye_resolution_changed
signal fisheye_msaa_changed
signal fpv_video_mode_changed(mode: int)


enum QualityPreset {LOW, MEDIUM, HIGH}
enum FpvVideoMode {ANALOG_58, DIGITAL_O3, THERMAL_WHITE_HOT, THERMAL_BLACK_HOT}
enum WindowMode {FULLSCREEN, FULLSCREEN_WINDOW, WINDOW, BORDERLESS_WINDOW}
enum GameMSAA {OFF, X2, X4, X8, X16}
enum GameAF {OFF, X2, X4, X8, X16}
enum Shadows {OFF, LOW, MEDIUM, HIGH, ULTRA}
enum FisheyeMode {OFF, FULL, FAST}
enum FisheyeResolution {FISHEYE_2160P, FISHEYE_1440P, FISHEYE_1080P,
		FISHEYE_720P, FISHEYE_480P, FISHEYE_240P}
enum FisheyeMSAA {OFF, X2, X4, X8, X16, SAME_AS_GAME}


var graphics_settings_path := "%s/Graphics.cfg" % Global.config_dir

var graphics_settings := {"quality": QualityPreset.HIGH,
		"window_mode": WindowMode.FULLSCREEN,
		"defaults_version": 6,
		"resolution": "100",
		"msaa": GameMSAA.X2,
		"af": GameAF.X8,
		"shadows": Shadows.HIGH,
		"fisheye_mode": FisheyeMode.OFF,
		"fisheye_resolution": FisheyeResolution.FISHEYE_720P,
		"fisheye_msaa": FisheyeMSAA.OFF,
		"vsync": false,
		"fps_limit": 120,
		"fpv_video_mode": FpvVideoMode.ANALOG_58}
var fisheye_resolution := 720
## Active FPV downlink look. Kept in Graphics so every level and the pause
## menu agree on it, and so the composite shader can be switched live.
var fpv_video_mode: int = FpvVideoMode.ANALOG_58
## FPV downlink effects are opt-in: the clean camera is the default for new
## pilots and every fresh session.
var fpv_effects_enabled := false


func _is_weak_gpu() -> bool:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	return adapter.contains("intel") and (adapter.contains("uhd") or adapter.contains("hd graphics"))


## Older Intel HD (not UHD) starts on LOW; UHD can run MEDIUM at 0.8 scale
## with real shadows and still hold 60+ FPS at 720p.
func _is_very_weak_gpu() -> bool:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	return adapter.contains("intel") and adapter.contains("hd graphics") \
			and not adapter.contains("uhd")


func _is_mobile_platform() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


func _mobile_refresh_cap(requested: int) -> int:
	if not _is_mobile_platform():
		return requested
	var refresh := DisplayServer.screen_get_refresh_rate()
	if refresh < 30.0:
		refresh = 60.0
	return mini(requested, int(round(refresh))) if requested > 0 else int(round(refresh))


func load_graphics_settings() -> String:
	var config := ConfigFile.new()
	var text := ""
	var err := config.load(graphics_settings_path)
	if err == OK:
		var has_quality := config.has_section_key("graphics", "quality")
		for key in graphics_settings.keys():
			if config.has_section_key("graphics", key):
				graphics_settings[key] = config.get_value("graphics", key)
		if not has_quality or bool(graphics_settings.get("vsync", false)):
			graphics_settings["quality"] = QualityPreset.MEDIUM if _is_mobile_platform() \
					else int(graphics_settings.get("quality", QualityPreset.MEDIUM))
			graphics_settings["msaa"] = GameMSAA.OFF
			graphics_settings["fisheye_mode"] = FisheyeMode.OFF
			graphics_settings["vsync"] = false
			if _is_mobile_platform():
				graphics_settings["fps_limit"] = _mobile_refresh_cap(
						int(graphics_settings.get("fps_limit", 120)))
			elif int(graphics_settings.get("fps_limit", 0)) == 30 or int(graphics_settings.get("fps_limit", 0)) == 60:
				graphics_settings["fps_limit"] = 120
			save_graphics_settings()
		# Version 3 defaults: fullscreen, native resolution, 120 FPS cap.
		var defaults_version: int = int(config.get_value("graphics", "defaults_version", 0))
		if defaults_version < 3:
			graphics_settings["window_mode"] = WindowMode.FULLSCREEN
			graphics_settings["resolution"] = "100"
			graphics_settings["msaa"] = GameMSAA.X2
			graphics_settings["af"] = GameAF.X8
			graphics_settings["shadows"] = Shadows.HIGH
			graphics_settings["fisheye_mode"] = FisheyeMode.OFF
			graphics_settings["fisheye_msaa"] = FisheyeMSAA.OFF
			graphics_settings["fpv_video_mode"] = FpvVideoMode.ANALOG_58
			graphics_settings["vsync"] = false
			graphics_settings["fps_limit"] = 120
		# Version 6: the seven-preset list collapsed to LOW / MEDIUM / HIGH.
		# Old UFDS (3) maps to HIGH; the 120/SMOOTH/LOWSPEC profiles map to LOW.
		if defaults_version < 6:
			var q := int(graphics_settings.get("quality", QualityPreset.HIGH))
			if q > QualityPreset.HIGH:
				q = QualityPreset.HIGH if q == 3 else QualityPreset.LOW
			graphics_settings["quality"] = q
			if _is_weak_gpu() and q == QualityPreset.HIGH:
				graphics_settings["quality"] = QualityPreset.MEDIUM
				graphics_settings["msaa"] = GameMSAA.OFF
				graphics_settings["fps_limit"] = 60
			graphics_settings["defaults_version"] = 6
			save_graphics_settings()
		# v7: cap mobile rendering to the physical display refresh.  Keep an
		# explicit saved quality selection intact; the mobile QualityManager
		# profile applies safe adaptive scale/foliage/shadow budgets at runtime.
		if _is_mobile_platform() and defaults_version < 7:
			graphics_settings["fps_limit"] = _mobile_refresh_cap(
					int(graphics_settings.get("fps_limit", 120)))
			graphics_settings["defaults_version"] = 7
			save_graphics_settings()
		update_window_mode()
		update_resolution()
		update_msaa()
		update_af()
		update_shadows()
		update_fisheye_mode()
		update_fisheye_resolution()
		update_fisheye_msaa()
		update_vsync()
		update_fps_limit()
		update_quality()
		update_fpv_video_mode()
	elif err == ERR_PARSE_ERROR:
		Global.log_error(err, "Parse error while loading graphics configuration file.")
		text = "Failed to read graphics configuration file."
		text = "%s\nThe default settings will be loaded." % text
	elif err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Could not open graphics config file.")
		text = "Could not open graphics configuration file."
		text = "%s\nThe defaut settings will be loaded." % err
	else:
		# Fresh install: pick a preset the GPU can actually run.  UHD handles
		# MEDIUM (0.8x, shadows, textures); older HD gets LOW.
		graphics_settings["defaults_version"] = 7 if _is_mobile_platform() else 6
		if _is_weak_gpu():
			if _is_very_weak_gpu():
				graphics_settings["quality"] = QualityPreset.LOW
			else:
				graphics_settings["quality"] = QualityPreset.MEDIUM
			graphics_settings["msaa"] = GameMSAA.OFF
			graphics_settings["fps_limit"] = 60
		else:
			graphics_settings["quality"] = QualityPreset.MEDIUM if _is_mobile_platform() \
					else QualityPreset.HIGH
		if _is_mobile_platform():
			graphics_settings["fps_limit"] = _mobile_refresh_cap(120)
		update_msaa()
		update_shadows()
		update_fps_limit()
		update_quality()
		save_graphics_settings()
	return text


func save_graphics_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(graphics_settings_path)
	if err == OK or err == ERR_FILE_NOT_FOUND or err == ERR_PARSE_ERROR:
		for key in graphics_settings.keys():
			config.set_value("graphics", key, graphics_settings[key])
		err = config.save(graphics_settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Error while saving graphics settings.")


func update_window_mode() -> void:
	var mode: int = graphics_settings["window_mode"]
	if mode == WindowMode.FULLSCREEN:
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (true) else Window.MODE_WINDOWED
		get_window().size = DisplayServer.screen_get_size()
		get_window().unresizable = not (false)
	else:
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (false) else Window.MODE_WINDOWED
		if mode == WindowMode.FULLSCREEN_WINDOW:
			get_window().borderless = true
			get_window().size = DisplayServer.screen_get_size()
			get_window().unresizable = not (false)
		else:
			get_window().unresizable = not (true)
			if get_window().size > DisplayServer.screen_get_size():
				get_window().size = DisplayServer.screen_get_size()
			if mode == WindowMode.BORDERLESS_WINDOW:
				get_window().borderless = true
			else:
				get_window().borderless = false


func update_resolution() -> void:
	var resolution_multiplier := float(graphics_settings["resolution"]) / 100.0
	var screen_resolution := DisplayServer.screen_get_size()
	var mode: int = graphics_settings["window_mode"]
	if mode == WindowMode.FULLSCREEN or mode == WindowMode.FULLSCREEN_WINDOW:
		get_window().size = DisplayServer.screen_get_size()
	else:
		get_window().size = screen_resolution * resolution_multiplier
		get_window().move_to_center()
	get_viewport().size = screen_resolution * resolution_multiplier


func update_msaa() -> void:
	# Godot 4 exposes MSAA as two Viewport properties; the project stores one
	# combined enum (OFF..X16). X16 has no 3D equivalent, so clamp to 8X.
	var level := clampi(int(graphics_settings["msaa"]), 0, 3)
	get_viewport().msaa_3d = level
	get_viewport().msaa_2d = level
	if graphics_settings["fisheye_msaa"] == FisheyeMSAA.SAME_AS_GAME:
		update_fisheye_msaa()


func update_af() -> void:
	ProjectSettings.set_setting("rendering/quality/filters/anisotropic_filter_level", \
			int(pow(2, graphics_settings["af"])))


func update_shadows(viewport: Viewport = null) -> void:
	if not viewport:
		viewport = get_viewport()
	# Positional shadows are the spot/omni shadows inside the hero halls and
	# around fires, not the sun.  A 4096 atlas was overkill there: the hall has
	# at most five shadow-casting spots, and at 1024/2048 they still get a
	# quadrant each.  Halving the atlas saves bandwidth on the UHD target and
	# makes the soft shadows slightly softer, which reads naturally indoors.
	match graphics_settings["shadows"]:
		Shadows.OFF:
			viewport.positional_shadow_atlas_size = 1024
			viewport.positional_shadow_atlas_quad_0 = 0
			viewport.positional_shadow_atlas_quad_1 = 0
			viewport.positional_shadow_atlas_quad_2 = 0
			viewport.positional_shadow_atlas_quad_3 = 0
		Shadows.LOW:
			viewport.positional_shadow_atlas_size = 1024
			viewport.positional_shadow_atlas_quad_0 = 1
			viewport.positional_shadow_atlas_quad_1 = 2
			viewport.positional_shadow_atlas_quad_2 = 3
			viewport.positional_shadow_atlas_quad_3 = 4
		Shadows.MEDIUM:
			viewport.positional_shadow_atlas_size = 2048
			viewport.positional_shadow_atlas_quad_0 = 2
			viewport.positional_shadow_atlas_quad_1 = 3
			viewport.positional_shadow_atlas_quad_2 = 4
			viewport.positional_shadow_atlas_quad_3 = 5
		Shadows.HIGH:
			viewport.positional_shadow_atlas_size = 2048
			viewport.positional_shadow_atlas_quad_0 = 3
			viewport.positional_shadow_atlas_quad_1 = 4
			viewport.positional_shadow_atlas_quad_2 = 5
			viewport.positional_shadow_atlas_quad_3 = 6
		Shadows.ULTRA:
			viewport.positional_shadow_atlas_size = 4096
			viewport.positional_shadow_atlas_quad_0 = 3
			viewport.positional_shadow_atlas_quad_1 = 4
			viewport.positional_shadow_atlas_quad_2 = 5
			viewport.positional_shadow_atlas_quad_3 = 6
	emit_signal("shadows_updated")


func update_fisheye_mode() -> void:
	emit_signal("fisheye_mode_changed")


func update_fisheye_resolution(resolution_string: String = "") -> void:
	var new_resolution: int
	match resolution_string:
		"2160p":
			new_resolution = FisheyeResolution.FISHEYE_2160P
		"1440p":
			new_resolution = FisheyeResolution.FISHEYE_1440P
		"1080p":
			new_resolution = FisheyeResolution.FISHEYE_1080P
		"720p":
			new_resolution = FisheyeResolution.FISHEYE_720P
		"480p":
			new_resolution = FisheyeResolution.FISHEYE_480P
		"240p":
			new_resolution = FisheyeResolution.FISHEYE_240P
		"":
			new_resolution = graphics_settings["fisheye_resolution"]
	graphics_settings["fisheye_resolution"] = new_resolution
	match graphics_settings["fisheye_resolution"]:
		FisheyeResolution.FISHEYE_2160P:
			fisheye_resolution = 2160
		FisheyeResolution.FISHEYE_1440P:
			fisheye_resolution = 1440
		FisheyeResolution.FISHEYE_1080P:
			fisheye_resolution = 1080
		FisheyeResolution.FISHEYE_720P:
			fisheye_resolution = 720
		FisheyeResolution.FISHEYE_480P:
			fisheye_resolution = 480
		FisheyeResolution.FISHEYE_240P:
			fisheye_resolution = 240
	emit_signal("fisheye_resolution_changed")


func update_fisheye_msaa() -> void:
	emit_signal("fisheye_msaa_changed")


func update_vsync() -> void:
	var enabled: bool = bool(graphics_settings["vsync"])
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED)


func update_fps_limit() -> void:
	Engine.max_fps = _mobile_refresh_cap(int(graphics_settings["fps_limit"]))


func update_quality() -> void:
	var lvl := clampi(int(graphics_settings.get("quality", QualityPreset.HIGH)), 0,
			QualityPreset.HIGH)
	graphics_settings["quality"] = lvl
	var current_scene := get_tree().current_scene
	if current_scene != null:
		QualityManagerScript.apply_to_scene(current_scene, lvl)
	emit_signal("quality_changed", lvl)


func apply_quality_preset(level: int) -> void:
	var lvl := clampi(level, 0, QualityPreset.HIGH)
	graphics_settings["quality"] = lvl
	match lvl:
		QualityPreset.LOW:
			graphics_settings["msaa"] = GameMSAA.OFF
			graphics_settings["af"] = GameAF.X2
			graphics_settings["shadows"] = Shadows.LOW
			graphics_settings["vsync"] = false
			graphics_settings["fps_limit"] = 120
		QualityPreset.MEDIUM:
			graphics_settings["msaa"] = GameMSAA.OFF
			graphics_settings["af"] = GameAF.X4
			graphics_settings["shadows"] = Shadows.MEDIUM
			graphics_settings["vsync"] = false
			graphics_settings["fps_limit"] = 120
		QualityPreset.HIGH:
			graphics_settings["msaa"] = GameMSAA.X2
			graphics_settings["af"] = GameAF.X8
			graphics_settings["shadows"] = Shadows.HIGH
			graphics_settings["vsync"] = false
			graphics_settings["fps_limit"] = 120
	update_msaa()
	update_af()
	update_shadows()
	update_vsync()
	update_fps_limit()
	update_quality()


func update_fpv_video_mode() -> void:
	fpv_video_mode = clampi(int(graphics_settings.get("fpv_video_mode", FpvVideoMode.ANALOG_58)), 0, 3)
	graphics_settings["fpv_video_mode"] = fpv_video_mode
	emit_signal("fpv_video_mode_changed", fpv_video_mode)


func set_fpv_video_mode(mode: int) -> void:
	fpv_video_mode = clampi(mode, 0, 3)
	graphics_settings["fpv_video_mode"] = fpv_video_mode
	save_graphics_settings()
	update_fpv_video_mode()


func cycle_fpv_video_mode() -> int:
	set_fpv_video_mode((fpv_video_mode + 1) % 4)
	return fpv_video_mode


func fpv_video_mode_name(mode: int = -1) -> String:
	var m := fpv_video_mode if mode < 0 else mode
	match m:
		FpvVideoMode.DIGITAL_O3:
			return "DIGITAL O3 / AVATAR"
		FpvVideoMode.THERMAL_WHITE_HOT:
			return "FLIR WHITE-HOT"
		FpvVideoMode.THERMAL_BLACK_HOT:
			return "FLIR BLACK-HOT"
		_:
			return "ANALOG 5.8 GHz"


func get_fisheye_resolution(resolution_setting: int) -> int:
	var resolution: int
	match resolution_setting:
		FisheyeResolution.FISHEYE_2160P:
			resolution = 2160
		FisheyeResolution.FISHEYE_1440P:
			resolution = 1440
		FisheyeResolution.FISHEYE_1080P:
			resolution = 1080
		FisheyeResolution.FISHEYE_720P:
			resolution = 720
		FisheyeResolution.FISHEYE_480P:
			resolution = 480
		FisheyeResolution.FISHEYE_240P:
			resolution = 240
	return resolution
