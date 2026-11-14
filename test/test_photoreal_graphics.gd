extends Node

## Automated verification suite for the 7 photorealistic mobile graphics upgrades:
##   1. Baked AO in terrain COLOR.a + UV anti-tiling
##   2. Depth-texture-free water with baked vertex depth shoreline + Fresnel/sky reflection
##   3. Single-pass ContactShadows MultiMesh + trimmed shadow casters + near sun cascade split
##   4. Tree BACKLIGHT + INSTANCE_CUSTOM variation + visibility fade + LOW/MED leaf detail
##   5. Mountain solar scatter + sky hemisphere ambient/reflection + map environment balance
##   6. Architectural base weathering shader + bilinear upscale RCAS sharpen
##   7. Zero hint_depth_texture / 3D screen-texture copies across all 7 scenes

const FT := preload("res://scripts/util/frontline_terrain.gd")

const MAPS := [
	{"path": "res://sceneries/SteppeLevel.tscn", "name": "steppe", "has_water": false},
	{"path": "res://sceneries/VillageLevel.tscn", "name": "village", "has_water": true},
	{"path": "res://sceneries/IndustrialLevel.tscn", "name": "industrial", "has_water": true},
	{"path": "res://sceneries/WetlandsLevel.tscn", "name": "wetlands", "has_water": true},
	{"path": "res://sceneries/BigLevel.tscn", "name": "", "has_water": false},
	{"path": "res://sceneries/CityLevel.tscn", "name": "", "has_water": false},
	{"path": "res://sceneries/CourseLevel.tscn", "name": "", "has_water": false},
]

var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", label)
	else:
		_failed += 1
		push_error("  FAIL: " + label)
		print("  FAIL: ", label)


static func _strip_shader_comments(src: String) -> String:
	var out := PackedStringArray()
	for line in src.split("\n"):
		var idx := line.find("//")
		if idx >= 0:
			out.append(line.substr(0, idx))
		else:
			out.append(line)
	return "\n".join(out)


func _ready() -> void:
	call_deferred("_run_all")


func _run_all() -> void:
	print("=== PHOTOREAL GRAPHICS VERIFICATION SUITE ===")
	_verify_shader_sources()
	_verify_quality_manager_presets()
	for entry in MAPS:
		await _verify_level(entry)
	print("=== PHOTOREAL RESULTS: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _verify_shader_sources() -> void:
	print("\n[1] Verifying shader sources & zero depth/screen texture leaks...")
	var water_raw := FileAccess.get_file_as_string("res://Assets/water.gdshader")
	var water_src := _strip_shader_comments(water_raw)
	_check(not water_raw.is_empty(), "Assets/water.gdshader readable")
	_check(water_src.find("hint_depth_texture") == -1, "water.gdshader has NO hint_depth_texture")
	_check(water_src.find("SCREEN_UV") == -1, "water.gdshader has NO SCREEN_UV reads")
	_check(water_src.find("v_water_depth") != -1 and water_src.find("COLOR.r") != -1,
			"water.gdshader encodes depth via COLOR.r -> v_water_depth")
	_check(water_src.find("sky_reflect") != -1 and water_src.find("ripple_normal") != -1,
			"water.gdshader includes sky_reflect & ripple_normal")

	for p in ["res://shaders/terrain_pbr_lite.gdshader", "res://shaders/terrain_pbr.gdshader"]:
		var src := _strip_shader_comments(FileAccess.get_file_as_string(p))
		_check(src.find("COLOR.a") != -1 and src.find("AO_LIGHT_AFFECT") != -1,
				"%s consumes baked COLOR.a cavity AO" % p)
	var lite_src := _strip_shader_comments(FileAccess.get_file_as_string("res://shaders/terrain_pbr_lite.gdshader"))
	_check(lite_src.find("rot") != -1 or lite_src.find("warp") != -1,
			"terrain_pbr_lite.gdshader adds anti-tiling UV rotation/warp")

	var tree_src := _strip_shader_comments(FileAccess.get_file_as_string("res://Assets/tree_wind.gdshader"))
	_check(tree_src.find("BACKLIGHT") != -1 and tree_src.find("INSTANCE_CUSTOM") != -1,
			"tree_wind.gdshader enables BACKLIGHT & INSTANCE_CUSTOM variation")
	_check(tree_src.find("leaf_detail") != -1, "tree_wind.gdshader exposes leaf_detail")

	var mtn_src := _strip_shader_comments(FileAccess.get_file_as_string("res://shaders/mountain_backdrop.gdshader"))
	_check(mtn_src.find("sun_dir") != -1 and mtn_src.find("sun_scatter_color") != -1,
			"mountain_backdrop.gdshader includes sun_dir solar scatter")

	var aw_src := _strip_shader_comments(FileAccess.get_file_as_string("res://shaders/arch_weathering.gdshader"))
	var awd_src := _strip_shader_comments(FileAccess.get_file_as_string("res://shaders/arch_weathering_double.gdshader"))
	_check(aw_src.find("cull_back") != -1 and awd_src.find("cull_disabled") != -1,
			"arch_weathering cull_back & arch_weathering_double cull_disabled variants exist")
	_check(aw_src.find("terrain_height_tex") != -1 and aw_src.find("grime_height") != -1 and aw_src.find("micro_var_strength") != -1,
			"arch_weathering exposes plinth grime & micro-variation uniforms")

	var fpv_src := _strip_shader_comments(FileAccess.get_file_as_string("res://shaders/fpv_composite.gdshader"))
	_check(fpv_src.find("rcas_sharpen") != -1 and fpv_src.find("render_scale_3d") != -1 and fpv_src.find("clean_sharpen_only") != -1,
			"fpv_composite.gdshader includes RCAS sharpen for bilinear upscale")


func _verify_quality_manager_presets() -> void:
	print("\n[2] Verifying QualityManager shadow splits, atlas & static sky...")
	var prev_mobile_env := OS.get_environment("MOBILE_UI")
	OS.set_environment("MOBILE_UI", "1")
	var gfx := get_tree().root.get_node_or_null("Graphics")
	var gs: Variant = gfx.get("graphics_settings") if gfx != null else null
	var prev_q: int = int(gs.get("quality", QualityManager.Level.LOW)) if gs is Dictionary else QualityManager.Level.LOW
	var sun := DirectionalLight3D.new()
	var env := Environment.new()
	env.sky = Sky.new()
	add_child(sun)

	if gs is Dictionary and OS.get_environment("DRONE_QUALITY").is_empty():
		(gs as Dictionary)["quality"] = QualityManager.Level.MEDIUM
		var p_med := QualityManager.params()
		var med_atlas := int(p_med.get("shadow_atlas", 0))
		_check(med_atlas >= 1536, "MEDIUM mobile preset shadow_atlas >= 1536 (got %d)" % med_atlas)
		QualityManager.apply_sun(sun)
		_check(sun.directional_shadow_split_1 >= 0.16 and sun.directional_shadow_split_1 <= 0.36,
				"MEDIUM near sun cascade split_1 in [0.16, 0.36] (got %.3f)" % sun.directional_shadow_split_1)
		_check(sun.directional_shadow_blend_splits, "MEDIUM enables directional_shadow_blend_splits")

		(gs as Dictionary)["quality"] = QualityManager.Level.LOW
	var p_low := QualityManager.params()
	_check(int(p_low.get("shadow_atlas", 0)) == 1024 or QualityManager.level() != QualityManager.Level.LOW,
			"LOW preset shadow_atlas == 1024 (got %d)" % int(p_low.get("shadow_atlas", 0)))
	QualityManager.apply_sun(sun)
	_check(sun.directional_shadow_split_1 >= 0.16 and sun.directional_shadow_split_1 <= 0.36,
			"LOW near sun cascade split_1 in [0.16, 0.36] (got %.3f)" % sun.directional_shadow_split_1)

	QualityManager._apply_static_sky(env)
	_check(env.background_mode == Environment.BG_SKY, "static sky keeps BG_SKY")
	_check(env.ambient_light_source == Environment.AMBIENT_SOURCE_SKY and env.ambient_light_sky_contribution >= 0.65,
			"static sky uses AMBIENT_SOURCE_SKY with sky hemisphere tint (contrib=%.2f)" % env.ambient_light_sky_contribution)
	_check(env.reflected_light_source == Environment.REFLECTION_SOURCE_SKY,
			"static sky uses REFLECTION_SOURCE_SKY for metallic/water glint")
	QualityManager.apply_environment(env)
	_check(not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled and not env.sdfgi_enabled,
			"heavy screen-space passes remain OFF on mobile environment")

	sun.queue_free()
	if gs is Dictionary and OS.get_environment("DRONE_QUALITY").is_empty():
		(gs as Dictionary)["quality"] = prev_q
	OS.set_environment("MOBILE_UI", prev_mobile_env)


func _verify_level(entry: Dictionary) -> void:
	var path: String = entry["path"]
	var map_name: String = entry["name"]
	print("\n[3] Verifying scene %s (map='%s')..." % [path.get_file(), map_name])
	var packed := load(path) as PackedScene
	_check(packed != null, "%s loads cleanly" % path.get_file())
	if packed == null:
		return
	var lvl := packed.instantiate()
	add_child(lvl)
	if path.ends_with("CourseLevel.tscn"):
		# CourseLevel._batch_city_static yields 1.0s before calling batch_static_fast + weathering
		await get_tree().create_timer(1.25).timeout
	else:
		for _f in range(6):
			await get_tree().process_frame

	# 1) Mobile environment constraints (no heavy passes)
	var we := _find_first(lvl, "WorldEnvironment") as WorldEnvironment
	_check(we != null and we.environment != null, "%s has WorldEnvironment" % path.get_file())
	if we != null and we.environment != null:
		var env := we.environment
		_check(not env.ssao_enabled and not env.ssil_enabled and not env.ssr_enabled and not env.volumetric_fog_enabled and not env.sdfgi_enabled,
				"%s heavy screen-space effects OFF" % path.get_file())

	# 2) Zero 3D ShaderMaterials reading hint_depth_texture or hint_screen_texture
	var bad_3d_shaders := 0
	var weathering_mats := 0
	for n in lvl.find_children("*", "GeometryInstance3D", true, false):
		var gi := n as GeometryInstance3D
		var mats: Array[Material] = []
		if gi.material_override != null:
			mats.append(gi.material_override)
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			if mi.mesh != null:
				for si in range(mi.mesh.get_surface_count()):
					var sm := mi.get_active_material(si)
					if sm != null:
						mats.append(sm)
		elif gi is MultiMeshInstance3D:
			var mmi := gi as MultiMeshInstance3D
			if mmi.multimesh != null and mmi.multimesh.mesh != null:
				for si in range(mmi.multimesh.mesh.get_surface_count()):
					var sm := mmi.multimesh.mesh.surface_get_material(si)
					if sm != null:
						mats.append(sm)
		for m in mats:
			if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
				var spath: String = (m as ShaderMaterial).shader.resource_path
				var code := _strip_shader_comments((m as ShaderMaterial).shader.code)
				if code.find("hint_depth_texture") != -1 or code.find("hint_screen_texture") != -1:
					bad_3d_shaders += 1
				if spath.ends_with("arch_weathering.gdshader") or spath.ends_with("arch_weathering_double.gdshader"):
					weathering_mats += 1
	_check(bad_3d_shaders == 0, "%s has 0 3D shaders sampling depth/screen textures (got %d)" % [path.get_file(), bad_3d_shaders])
	_check(weathering_mats > 0, "%s applies arch_weathering shader on buildings/concrete (mats=%d)" % [path.get_file(), weathering_mats])

	# 3) FPVOverlay RCAS check
	var fpv := lvl.find_child("FPVOverlay", true, false)
	_check(fpv != null, "%s has FPVOverlay" % path.get_file())
	if fpv != null:
		var mat := fpv.get("_material") as ShaderMaterial
		_check(mat != null and mat.shader != null and mat.shader.code.find("rcas_sharpen") != -1,
				"%s FPVOverlay shader exposes rcas_sharpen" % path.get_file())

	# 4) Frontline-specific terrain AO, water depth, ContactShadows, foliage & sky/mountains
	if not map_name.is_empty():
		var ft := lvl.get_node_or_null("FrontlineTerrain")
		_check(ft != null, "%s has FrontlineTerrain" % map_name)
		if ft != null:
			# Heightmap texture for weathering
			var htex: Texture2D = FT.height_map_tex(map_name)
			_check(htex != null and htex.get_width() == 128 and htex.get_height() == 128,
					"%s caches 128x128 terrain height_map_tex" % map_name)

			# Baked COLOR.a AO in terrain chunk meshes (identified by terrain_pbr shader)
			var min_a := 2.0
			var max_a := -1.0
			var chunk_meshes := 0
			for child in ft.find_children("*", "MeshInstance3D", true, false):
				var mi := child as MeshInstance3D
				if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
					continue
				var tmat := mi.get_active_material(0) as ShaderMaterial
				if tmat == null and mi.material_override is ShaderMaterial:
					tmat = mi.material_override as ShaderMaterial
				if tmat == null or tmat.shader == null:
					continue
				var spath := tmat.shader.resource_path
				if not (spath.ends_with("terrain_pbr_lite.gdshader") or spath.ends_with("terrain_pbr.gdshader")):
					continue
				var arrs := mi.mesh.surface_get_arrays(0)
				if arrs.size() > Mesh.ARRAY_COLOR and arrs[Mesh.ARRAY_COLOR] is PackedColorArray:
					var cols: PackedColorArray = arrs[Mesh.ARRAY_COLOR]
					chunk_meshes += 1
					for ci in range(0, cols.size(), 3):
						var a := cols[ci].a
						min_a = minf(min_a, a)
						max_a = maxf(max_a, a)
			_check(chunk_meshes > 0 and min_a < 0.85 and max_a >= 0.90,
					"%s terrain COLOR.a encodes cavity AO variation [%.2f..%.2f] across %d terrain meshes" % [map_name, min_a, max_a, chunk_meshes])

			# Batched ContactShadows MultiMesh (no unbatched ContactShadow_* nodes)
			var cs_mm := ft.get_node_or_null("ContactShadows") as MultiMeshInstance3D
			var stray_cs := 0
			for c in ft.find_children("ContactShadow_*", "MeshInstance3D", true, false):
				stray_cs += 1
			_check(cs_mm != null and cs_mm.multimesh != null and cs_mm.multimesh.instance_count > 10,
					"%s batches ContactShadows MultiMesh (%d instances)" % [map_name, cs_mm.multimesh.instance_count if cs_mm and cs_mm.multimesh else 0])
			_check(cs_mm != null and cs_mm.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and stray_cs == 0,
					"%s ContactShadows shadowless & 0 stray ContactShadow_* nodes" % map_name)

			# Trimmed shadow casters on small foliage/rocks/scrub
			for sname in ["HallScrub", "GroundScrub", "FieldTufts", "Wildflowers", "GroundStones"]:
				var sn := ft.get_node_or_null(sname) as GeometryInstance3D
				if sn != null:
					_check(sn.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
							"%s %s has SHADOW_CASTING_SETTING_OFF" % [map_name, sname])

			# Foliage custom-data tinting & fade across all leaf MultiMeshes
			var leaf_mms := 0
			var leaf_custom_ok := true
			var leaf_fade_ok := true
			for mmi_n in ft.find_children("*", "MultiMeshInstance3D", true, false):
				var mmi := mmi_n as MultiMeshInstance3D
				if mmi == null:
					continue
				if String(mmi.name) == "HeroTrees_leaves" or String(mmi.name).ends_with("_Leaves"):
					leaf_mms += 1
					if mmi.multimesh == null or not mmi.multimesh.use_custom_data:
						leaf_custom_ok = false
					if mmi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF:
						leaf_fade_ok = false
			_check(leaf_mms > 0 and leaf_custom_ok,
					"%s leaf MultiMeshes (%d) enable use_custom_data per-crown tinting" % [map_name, leaf_mms])
			_check(leaf_mms > 0 and leaf_fade_ok,
					"%s leaf MultiMeshes use VISIBILITY_RANGE_FADE_SELF" % map_name)

			# MountainBackdrop solar scatter uniform
			var mtn := ft.get_node_or_null("MountainBackdrop") as MeshInstance3D
			_check(mtn != null and mtn.material_override is ShaderMaterial, "%s MountainBackdrop uses ShaderMaterial" % map_name)
			if mtn != null and mtn.material_override is ShaderMaterial:
				var mm_mat := mtn.material_override as ShaderMaterial
				var sd: Variant = mm_mat.get_shader_parameter("sun_dir")
				_check(sd is Vector3 and (sd as Vector3).length() > 0.5,
						"%s MountainBackdrop sun_dir uniform bound (%s)" % [map_name, str(sd)])

			# Water vertex depth & ripple_normal checks
			if bool(entry["has_water"]):
				var saw_depth_water := false
				var pond_ok := true
				for wn in ft.find_children("*", "MeshInstance3D", true, false):
					var wmi := wn as MeshInstance3D
					var wmat := wmi.material_override as ShaderMaterial
					if wmat == null and wmi.mesh != null and wmi.mesh.get_surface_count() > 0:
						wmat = wmi.get_active_material(0) as ShaderMaterial
					if wmat != null and wmat.shader != null and wmat.shader.resource_path.ends_with("water.gdshader"):
						_check(wmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
								"%s water node %s shadowless" % [map_name, wmi.name])
						if wmat.get_shader_parameter("ripple_normal") == null:
							pond_ok = false
						if wmi.mesh != null and wmi.mesh.get_surface_count() > 0:
							var warrs := wmi.mesh.surface_get_arrays(0)
							if warrs.size() > Mesh.ARRAY_COLOR and warrs[Mesh.ARRAY_COLOR] is PackedColorArray:
								var wcols: PackedColorArray = warrs[Mesh.ARRAY_COLOR]
								var min_r := 2.0
								var max_r := -1.0
								for wc in wcols:
									min_r = minf(min_r, wc.r)
									max_r = maxf(max_r, wc.r)
								if min_r < 0.65 and max_r >= 0.80:
									saw_depth_water = true
				_check(saw_depth_water, "%s water encodes shoreline depth gradient in ARRAY_COLOR.r" % map_name)
				_check(pond_ok, "%s all water ShaderMaterials bind ripple_normal" % map_name)

	lvl.queue_free()
	await get_tree().process_frame


func _find_first(root_node: Node, type_name: String) -> Node:
	for n in root_node.find_children("*", type_name, true, false):
		return n
	return null
