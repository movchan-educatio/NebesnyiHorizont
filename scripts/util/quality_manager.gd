class_name QualityManager
extends RefCounted

## Desktop presets remain fixed. The mobile profile alone uses adaptive 3D
## resolution: it raises clarity while frame-time has room, then steps down
## before sustained GPU load becomes a long-lived FPS drop. HUD stays native.
##
## The "smart" part: the costs that are almost invisible in a fast FPV flight
## are cut first, the things the eye actually notices are kept:
##   * 3D is rendered at a lower internal resolution and upscaled with AMD FSR
##     (HUD/OSD stays at native resolution and razor sharp);
##   * SSAO runs at half resolution (a soft effect - no visible loss);
##   * volumetric fog is replaced by tuned analytic depth+height fog on
##     Low/Medium (looks the same at a distance, costs ~nothing);
##   * sun shadows use fewer cascades and a shorter distance, the far range is
##     covered by fog anyway;
##   * vegetation / grass fade out by distance (visibility ranges + fog);
##   * physics interpolation renders smooth 120 FPS motion from the 60 Hz
##     flight physics (see project.godot), so the flight model is unchanged.

enum Level {LOW, MEDIUM, HIGH}

const NAMES := ["НИЗЬКА", "СЕРЕДНЯ", "ВИСОКА"]
const DESCRIPTIONS := [
	"Максимум FPS: FSR 40-72%, без SSAO, тіні 90 м, легка рослинність",
	"Баланс: FSR 55-85%, тіні 120 м, щільна трава, без SSAO",
	"Максимум якості: нативна роздільність, SSAO, м'які тіні 180 м",
]

## Per-preset parameters.
const PRESETS := {
	Level.LOW: {
		"scale_3d": 0.67, "min_scale": 0.40, "max_scale": 0.72,
		"adaptive": false, "target_fps": 118.0,
		"physics_hz": 60,
		"static_sky": true,
		"fsr_sharpness": 0.85, "msaa": 0, "fxaa": false,
		"ssao": false, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		"ssil": false, "volumetric_fog": false, "glow": false,
		"shadows": true, "shadow_splits": 2, "shadow_distance": 90.0,
		"shadow_atlas": 1024, "soft_shadow": RenderingServer.SHADOW_QUALITY_HARD,
		"grass_count": 1400, "grass_range": 18.0,
		"veg_range": 560.0, "veg_density": 0.5, "mesh_lod": 1.8,
		"world_detail_factor": 0.25, "grass_tuft_mult": 0.35,
		"ground_detail_level": 0, "far_grass_mult": 0.30,
		"motion_blur": 0.0,
	},
	Level.MEDIUM: {
		"scale_3d": 0.8, "min_scale": 0.55, "max_scale": 0.85,
		"adaptive": false, "target_fps": 118.0,
		"physics_hz": 60,
		"static_sky": true,
		# 0.38 was soft enough to read as a low-resolution image on a 1080p
		# panel; 0.55 keeps the FSR2-style upscale while restoring micro-detail
		# on grass, concrete and armour edges.
		"fsr_sharpness": 0.55, "msaa": 0, "fxaa": true,
		"ssao": false, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_VERY_LOW,
		"ssil": false, "volumetric_fog": false, "glow": false,
		"shadows": true, "shadow_splits": 2, "shadow_distance": 120.0,
		"shadow_atlas": 1024, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"grass_count": 2600, "grass_range": 22.0,
		"veg_range": 740.0, "veg_density": 0.58, "mesh_lod": 1.2,
		"world_detail_factor": 0.30, "grass_tuft_mult": 0.45,
		"ground_detail_level": 1, "far_grass_mult": 0.40,
		"motion_blur": 0.0,
	},
	Level.HIGH: {
		"scale_3d": 1.0, "min_scale": 1.0, "max_scale": 1.0,
		"adaptive": false, "target_fps": 60.0,
		"physics_hz": 60,
		"fsr_sharpness": 0.7, "msaa": 0, "fxaa": true,
		"ssao": true, "ssao_quality": RenderingServer.ENV_SSAO_QUALITY_LOW,
		"ssao_intensity": 1.10,
		"ssil": false, "ssil_quality": RenderingServer.ENV_SSIL_QUALITY_LOW,
		"volumetric_fog": false, "volumetric_density": 0.0011, "glow": false,
		"shadows": true, "shadow_splits": 2, "shadow_distance": 180.0,
		"shadow_atlas": 2048, "soft_shadow": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"grass_count": 3200, "grass_range": 28.0,
		"veg_range": 920.0, "veg_density": 0.65, "mesh_lod": 0.8,
		"world_detail_factor": 0.35, "grass_tuft_mult": 0.55,
		"ground_detail_level": 1, "far_grass_mult": 0.50,
		"static_sky": true,
		"motion_blur": 0.0,
	},
}


static func level() -> int:
	var env := OS.get_environment("DRONE_QUALITY").strip_edges().to_lower()
	match env:
		"low", "0":
			return Level.LOW
		"medium", "1":
			return Level.MEDIUM
		"high", "2":
			return Level.HIGH
		# Legacy names kept for QA scripts and old shortcuts.
		"ufds", "3":
			return Level.HIGH
		"competitive", "120fps", "120", "4", \
				"smooth", "smooth60", "60", "5", \
				"lowspec", "flat", "6":
			return Level.LOW
	var g := Engine.get_main_loop() as SceneTree
	if g != null and g.root.has_node("Graphics"):
		var settings: Dictionary = g.root.get_node("Graphics").get("graphics_settings")
		if settings != null and settings.has("quality"):
			var q := int(settings["quality"])
			# Configs from the 7-preset builds: UFDS -> HIGH, the rest -> LOW.
			if q > Level.HIGH:
				q = Level.HIGH if q == 3 else Level.LOW
			return clampi(q, Level.LOW, Level.HIGH)
	return Level.LOW


static func get_active_level() -> int:
	return level()


static func level_name_ua(lvl: int) -> String:
	return NAMES[clampi(lvl, 0, NAMES.size() - 1)]


static func params() -> Dictionary:
	# Return a mutable copy: const preset dictionaries are read-only in Godot
	# 4.6, and apply_environment() adjusts ssao/ssil/fog for the Mobile
	# renderer.  Mutating the const directly raised "Dictionary is in
	# read-only state" on iOS.
	var p: Dictionary = PRESETS[level()].duplicate(true)
	# Phone profile preserves high-quality materials and near-field shadows,
	# while limiting fill-rate/foliage and keeping costly post effects off.
	# The governor changes only 3D scale; the HUD remains at native resolution.
	var mobile := OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")
	if mobile:
		p["mobile_profile"] = true
		var refresh := DisplayServer.screen_get_refresh_rate()
		var mobile_target := 58.0 if refresh < 90.0 else 118.0
		match level():
			Level.LOW:
				p.merge({"scale_3d": 0.67, "min_scale": 0.42, "max_scale": 0.80,
					"fsr_sharpness": 0.85,
					"adaptive": true, "target_fps": mobile_target,
					"grass_count": 1100, "grass_range": 18.0,
					"veg_range": 520.0, "veg_density": 0.48, "mesh_lod": 1.8,
					"shadow_distance": 80.0, "shadow_atlas": 1024,
					"ssao": false, "ssil": false, "volumetric_fog": false,
					"glow": false, "fxaa": false}, true)
			Level.MEDIUM:
				p.merge({"scale_3d": 0.72, "min_scale": 0.50, "max_scale": 0.84,
					"adaptive": true, "target_fps": minf(mobile_target, 60.0),
					"grass_count": 1900, "grass_range": 24.0,
					"veg_range": 740.0, "veg_density": 0.68, "mesh_lod": 1.35,
					"shadow_distance": 100.0, "shadow_atlas": 1024,
					"msaa": Viewport.MSAA_DISABLED,
					"ssao": false, "ssil": false, "volumetric_fog": false,
					"glow": false, "fxaa": false}, true)
			Level.HIGH:
				p.merge({"scale_3d": 0.78, "min_scale": 0.56, "max_scale": 0.84,
					"adaptive": true, "target_fps": 58.0,
					"grass_count": 2600, "grass_range": 26.0,
					"veg_range": 900.0, "veg_density": 0.76, "mesh_lod": 1.15,
					"shadow_distance": 115.0, "shadow_atlas": 1024,
					"msaa": Viewport.MSAA_DISABLED,
					"ssao": false, "ssil": false, "volumetric_fog": false,
					"glow": false, "fxaa": false}, true)
	# QA switches used by the FPS benchmark to isolate expensive passes.
	if OS.has_environment("QA_NO_FOG"):
		p = p.duplicate(true)
		p["volumetric_fog"] = false
	if OS.has_environment("QA_NO_SSAO"):
		p = p.duplicate(true)
		p["ssao"] = false
	if OS.has_environment("QA_NO_GLOW"):
		p = p.duplicate(true)
		p["glow"] = false
	var qa_veg := OS.get_environment("QA_VEG_RANGE")
	if not qa_veg.is_empty():
		p = p.duplicate(true)
		p["veg_range"] = float(qa_veg)
	if OS.has_environment("QA_NO_SHADOW"):
		p = p.duplicate(true)
		p["shadows"] = false
	if OS.has_environment("QA_NO_GRASS"):
		p = p.duplicate(true)
		p["grass_count"] = 0
	var qa_splits := OS.get_environment("QA_SHADOW_SPLITS")
	if not qa_splits.is_empty():
		p = p.duplicate(true)
		p["shadow_splits"] = int(qa_splits)
	return p


static func get_value(key: String, fallback: Variant = null) -> Variant:
	return params().get(key, fallback)


## QA-only switch used to A/B FSR 1.0 and FSR 2.2 without editing the preset.
static func scaling_mode() -> Viewport.Scaling3DMode:
	var env := OS.get_environment("QA_SCALING_MODE").to_lower()
	if env == "fsr2":
		return Viewport.SCALING_3D_MODE_FSR2
	if env == "bilinear":
		return Viewport.SCALING_3D_MODE_BILINEAR
	if env == "fsr":
		return Viewport.SCALING_3D_MODE_FSR
	# FSR is a Forward+ feature; on the Mobile renderer Godot logs a warning
	# and ignores it.  Bilinear keeps the internal-resolution saving (the
	# single most important mobile FPS lever) without the warning.
	if RenderingServer.get_current_rendering_method() == "mobile":
		return Viewport.SCALING_3D_MODE_BILINEAR
	# Per-preset upscaler.  Bilinear is ~9% faster than FSR1 on the Intel UHD
	# target; the low-end profile takes it because frame rate is the goal.
	if String(params().get("scaling", "fsr")) == "bilinear":
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_FSR


## Viewport-level settings: internal 3D resolution + FSR upscale and AA.
static func apply_viewport(vp: Viewport) -> void:
	if vp == null:
		return
	var p := params()
	var scale: float = p["scale_3d"]
	var forced := OS.get_environment("QA_FORCE_SCALE")
	if not forced.is_empty():
		scale = clampf(float(forced), 0.25, 1.0)
	if scale < 0.999:
		vp.scaling_3d_mode = scaling_mode()
		vp.scaling_3d_scale = scale
		vp.fsr_sharpness = p["fsr_sharpness"]
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.msaa_3d = int(p["msaa"]) as Viewport.MSAA
	var use_fxaa: bool = bool(p["fxaa"]) and not OS.has_environment("QA_NO_FXAA")
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if use_fxaa \
			else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.mesh_lod_threshold = p["mesh_lod"]
	# Lower-cost global effect quality; half-size SSAO/SSIL are visually
	# indistinguishable for soft contact shadows.
	RenderingServer.environment_set_ssao_quality(p["ssao_quality"], true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(
			p.get("ssil_quality", RenderingServer.ENV_SSIL_QUALITY_LOW),
			true, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_volumetric_fog_volume_size(48, 32)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	RenderingServer.directional_shadow_atlas_set_size(int(p["shadow_atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p["soft_shadow"])
	RenderingServer.positional_soft_shadow_filter_set_quality(p["soft_shadow"])


## Static sky shared by the presets.  The cloud panorama is baked to a texture
## once, so the sky costs a single cubemap sample instead of running the
## procedural cloud shader and regenerating the radiance map every frame.
##
## Desktop MEDIUM/HIGH use the 4K panorama with the distant ridge silhouette:
## the extra aerial depth is the single strongest "expensive look" cue on the
## horizon and costs no per-frame work once the radiance cubemap is baked.
## Desktop LOW and every phone profile keep the compact 2K panorama to save
## memory and bandwidth on the target hardware.
static var _static_sky_materials: Dictionary = {}

## Golden-hour grade of the same baked panoramas (tools/grade_mobile_sky.py).
## The original midday textures are kept in the repo as the source of truth.
const SKY_PANORAMA_HI := "res://Assets/textures/sky_mountains_golden.png"
const SKY_PANORAMA_COMPACT := "res://Assets/textures/sky_static_golden.png"
## Azimuth of the baked sun glow measured from +Z toward +X.  Godot's
## equirectangular sky maps u=0 to -Z, u=0.25 to +X and u=0.5 to +Z, so the
## 4K panorama's glow at u=0.17 sits at 118.8 degrees.
const SKY_SUN_AZIMUTH_HI := 118.8
const SKY_SUN_AZIMUTH_COMPACT := 298.8


static func _is_phone_profile() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


static func _use_hi_res_sky() -> bool:
	return level() >= Level.MEDIUM and not _is_phone_profile()


static func _get_static_sky() -> PanoramaSkyMaterial:
	var hi := _use_hi_res_sky()
	var key := "hi" if hi else "compact"
	if not _static_sky_materials.has(key):
		var tex := load(SKY_PANORAMA_HI if hi else SKY_PANORAMA_COMPACT) as Texture2D
		if tex != null:
			var mat := PanoramaSkyMaterial.new()
			mat.panorama = tex
			mat.filter = true
			_static_sky_materials[key] = mat
	return _static_sky_materials.get(key, null)


## Puts the baked sun glow in the same world direction as the map's key light.
## Shadows, terrain highlights and the glow in the sky then agree, which is the
## detail that makes a baked panorama read as a real sky instead of wallpaper.
## Called by BigLevel after it applies its per-map sun rotation.
static func align_sky_to_sun(env: Environment, sun: DirectionalLight3D) -> void:
	if env == null or env.sky == null or sun == null:
		return
	if not env.sky.has_meta("lowspec_sky_sun_azimuth"):
		return
	var az := float(env.sky.get_meta("lowspec_sky_sun_azimuth"))
	env.sky_rotation.y = deg_to_rad(sun.rotation_degrees.y - az)


static func _apply_static_sky(env: Environment) -> void:
	if env == null or env.sky == null:
		return
	var hi := _use_hi_res_sky()
	var mat := _get_static_sky()
	if mat == null:
		return
	var sun_az := SKY_SUN_AZIMUTH_HI if hi else SKY_SUN_AZIMUTH_COMPACT
	if not env.sky.has_meta("lowspec_sky_backup"):
		env.sky.set_meta("lowspec_sky_backup", env.sky.sky_material)
		env.sky.set_meta("lowspec_sky_process", env.sky.process_mode)
		env.sky.set_meta("lowspec_sky_rot", env.sky_rotation)
	env.background_mode = Environment.BG_SKY
	if _is_phone_profile():
		env.background_energy_multiplier = 1.0
	env.sky.sky_material = mat
	env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	# Default orientation until the map aligns the glow with its own key light.
	env.sky_rotation.y = deg_to_rad(52.0 - sun_az)
	env.sky.set_meta("lowspec_sky_sun_azimuth", sun_az)
	# Baked sky radiance ambient (0 SSAO/GI per-frame cost): shadows receive cool
	# sky-dome blue instead of flat grey-blue, while metal & roofs reflect sky.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.46, 0.58, 0.78)
	env.ambient_light_sky_contribution = 0.78
	env.ambient_light_energy = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY


static func _restore_sky(env: Environment) -> void:
	if env == null or env.sky == null:
		return
	if env.sky.has_meta("lowspec_sky_backup"):
		env.sky.sky_material = env.sky.get_meta("lowspec_sky_backup")
		env.sky.process_mode = int(env.sky.get_meta("lowspec_sky_process",
				Sky.PROCESS_MODE_AUTOMATIC))
		if env.sky.has_meta("lowspec_sky_rot"):
			env.sky_rotation = env.sky.get_meta("lowspec_sky_rot")
			env.sky.remove_meta("lowspec_sky_rot")
		env.sky.remove_meta("lowspec_sky_backup")
		env.sky.remove_meta("lowspec_sky_process")
		env.sky.remove_meta("lowspec_sky_sun_azimuth")


## Environment-level settings. Expensive effects are swapped for cheap
## look-alikes instead of just being switched off.
static func apply_environment(env: Environment) -> void:
	if env == null:
		return
	var p := params()
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	if mobile:
		# The Mobile renderer has no screen-space stack/volumetric fog; force
		# them off even if a HIGH preset is selected.
		p["ssao"] = false
		p["ssil"] = false
		p["volumetric_fog"] = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.volumetric_fog_enabled = false
	# Every preset now uses the same baked mountain panorama: the look is part
	# of the art direction and the per-frame cost is a single cubemap sample.
	var use_static_sky := true
	if use_static_sky:
		_apply_static_sky(env)
	else:
		_restore_sky(env)
	if not mobile:
		env.ssao_enabled = p["ssao"]
		env.ssao_radius = float(p.get("ssao_radius", 1.5))
		env.ssao_intensity = float(p.get("ssao_intensity", 1.0))
		env.ssil_enabled = p["ssil"]
		env.ssil_radius = float(p.get("ssil_radius", 5.0))
		env.ssil_intensity = 1.15 if p["ssil"] else 0.0
		env.volumetric_fog_enabled = p["volumetric_fog"]
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 1.10
	env.adjustment_brightness = 1.01
	env.glow_enabled = p["glow"]
	if p["volumetric_fog"]:
		# Height fog over the steppe: dense near the ground, thin at altitude,
		# 800 m of aerial perspective and faint god rays through tree lines.
		# The per-preset density is deliberately low: over-strong volumetric fog
		# washes the horizon out and hides the PBR ground detail.
		env.volumetric_fog_density = float(p.get("volumetric_density", 0.0016))
		env.volumetric_fog_length = 800.0
		env.volumetric_fog_albedo = Color(0.82, 0.86, 0.88)
		env.volumetric_fog_anisotropy = 0.45
		env.volumetric_fog_sky_affect = 0.08
		env.fog_enabled = true
		env.fog_density = 0.00028
		env.fog_aerial_perspective = 0.55
		env.fog_height = 22.0
		env.fog_height_density = 0.0045
	if not p["volumetric_fog"]:
		# Compensate with soft height fog + aerial perspective even on LOW.
		env.fog_enabled = true
		env.fog_density = 0.00055
		env.fog_aerial_perspective = 0.55
		env.fog_sky_affect = 0.25
		env.fog_height = 24.0
		env.fog_height_density = 0.0045
	# SDFGI / reflections are never needed for this outdoor scene.
	env.sdfgi_enabled = false
	env.ssr_enabled = false
	if OS.has_environment("QA_SKY_INCREMENTAL") and env.sky != null:
		env.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	if OS.has_environment("QA_FLAT_SKY"):
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.45, 0.62, 0.85)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.55, 0.60, 0.70)
		env.ambient_light_energy = 0.6
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG


static func apply_sun(sun: DirectionalLight3D) -> void:
	if sun == null:
		return
	var p := params()
	sun.shadow_enabled = p["shadows"]
	# Slight bias/normal-bias kills the acne on the merged terrain without
	# visible peter-panning at FPV distances.
	sun.shadow_bias = 0.09
	sun.shadow_normal_bias = 2.0
	var d := float(p["shadow_distance"])
	sun.directional_shadow_max_distance = d
	var cur_lvl := level()
	# Focus peak shadow-atlas texel density on the near 0-28 m FPV flight corridor
	# (24 m on LOW, 28 m on MEDIUM/HIGH) instead of stretching split_1 thinly.
	var near_m := 24.0 if cur_lvl == Level.LOW else 28.0
	var two_split_1 := clampf(near_m / maxf(d, 1.0), 0.16, 0.36)
	match int(p["shadow_splits"]):
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_split_1 = two_split_1
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# FPV cascade profile: 0-28 m near flight/obstacles/trees, mid range trenches
	# and structures, outer falloff covered by contact shadows and height fog.
	var is_mobile_sun := OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")
	if cur_lvl == Level.HIGH:
		if int(p["shadow_splits"]) >= 4:
			sun.directional_shadow_split_1 = clampf(16.0 / maxf(d, 1.0), 0.08, 0.25)
			sun.directional_shadow_split_2 = clampf(60.0 / maxf(d, 1.0), 0.28, 0.55)
			sun.directional_shadow_split_3 = clampf(140.0 / maxf(d, 1.0), 0.58, 0.88)
		else:
			sun.directional_shadow_split_1 = two_split_1
		sun.directional_shadow_blend_splits = not is_mobile_sun
		sun.shadow_blur = 0.85
		sun.directional_shadow_fade_start = 0.85
	else:
		sun.directional_shadow_blend_splits = (cur_lvl == Level.MEDIUM and not is_mobile_sun)
		sun.directional_shadow_fade_start = 0.8
		sun.shadow_blur = 1.0


## Applies everything to a running 3D level.
static func apply_to_scene(scene_root: Node, _override_lvl: int = -1) -> void:
	if scene_root == null or not scene_root.is_inside_tree():
		return
	apply_viewport(scene_root.get_viewport())
	var world_env := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null:
		apply_environment(world_env.environment)
	var sun := scene_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = scene_root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	apply_sun(sun)
	var cam := scene_root.get_node_or_null("Drone/FPVCamera") as Camera3D
	if cam != null and cam.environment != null:
		apply_environment(cam.environment)
	var p := params()
	# Weak-PC profiles tick physics at 60 Hz.  Physics interpolation keeps the
	# image smooth while the CPU cost of the 120 Hz world tick is halved
	# (measured on the Intel UHD target: avg +4%, 1% low +20%).  The flight
	# controller still integrates 8 substeps per tick, i.e. a 480 Hz control
	# loop, which is well inside the range used by real FPV firmware.
	var qa_hz := OS.get_environment("DRONE_PHYSICS_HZ")
	if qa_hz.is_empty():
		Engine.physics_ticks_per_second = int(p.get("physics_hz", 120))
	# Optional 720p content-scale path for very slow panels.
	var win := scene_root.get_window()
	if win != null:
		var want_cs := bool(p.get("content_scale", false))
		if want_cs and DisplayServer.screen_get_size().y > 720:
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			win.content_scale_size = Vector2i(1280, 720)
		elif win.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
			win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			win.content_scale_size = Vector2i(0, 0)
	var allow_grass := not scene_root.has_meta("disable_procedural_grass")
	var grass := scene_root.get_node_or_null("DenseGrassFoliage") as MultiMeshInstance3D
	if grass != null:
		grass.visible = allow_grass
		grass.visibility_range_end = float(p["grass_range"])
		grass.visibility_range_end_margin = clampf(float(p["grass_range"]) * 0.26, 3.0, 8.0)
	var grass_far := scene_root.get_node_or_null("DenseGrassFar") as MultiMeshInstance3D
	if grass_far != null:
		grass_far.visible = allow_grass
		grass_far.visibility_range_end = float(p["grass_range"])
		grass_far.visibility_range_end_margin = clampf(float(p["grass_range"]) * 0.26, 3.0, 8.0)
	for child in scene_root.get_children():
		if child is MultiMeshInstance3D and not String(child.name).contains("Grass"):
			(child as MultiMeshInstance3D).visibility_range_end = float(p["veg_range"])
	# Re-arm the adaptive resolution when the player switches presets mid-flight.
	var governor := scene_root.get_node_or_null("PerformanceGovernor")
	if governor != null and governor.has_method("configure"):
		governor.configure(p)
	# Let the map re-apply its per-map fog/ambient after the preset overwrote
	# the Environment.  Without this a mid-flight quality switch resets every
	# map to the same global atmosphere.
	if scene_root.has_method("on_quality_applied"):
		scene_root.call("on_quality_applied")
	print("[Quality] preset=", NAMES[level()], " scale3d=", p["scale_3d"])
