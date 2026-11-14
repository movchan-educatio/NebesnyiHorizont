extends Node

## End-to-end headless verification for the -40% map shrink, themed distant
## backgrounds, enlarged/added PBR military stunt structures, default LOW
## graphics preset, AI/mission boundaries, and City/Course/Valley modes.

const FT := preload("res://scripts/util/frontline_terrain.gd")
const MS := preload("res://scripts/util/military_structures.gd")
const GFxScript := preload("res://autoloads/Graphics.gd")
const FpvIconsScript := preload("res://scripts/util/fpv_icons.gd")
const ReconKillCamScript := preload("res://scripts/combat/recon_kill_cam.gd")

const KEY_TRICK_STRUCTURES := [
	"ConstructionSkeletonRubik",
	"PipelinePowerloopArch",
	"CoolingTowerDiveFunnel",
	"ShippingContainerComplex",
	"GeneratorSubstation",
	"DamagedHangarArch",
	"RadarRelayStation",
	"HardenedTrenchBunker",
	"FuelStorageRevetment",
	"AirDefenseRadarDome",
	"CheckpointFortification",
	"SandbagMortarPit",
	"ObservationWatchtower",
	"CamoVehicleShed",
	"ConcretePipeCulvertCourse",
	"MilitaryContainerHQ",
	"PipelineOverpass",
	"CommunicationMastGuyed",
	"MilitaryArchPortal",
	"ScaffoldingFreestyleCube",
	"SamBatteryGantry",
	"FortifiedHelipadHangar",
	"BaileyTrussBridge",
	"HeavyRadarGciComplex",
	"ArtilleryBunkerComplex",
]

const LEGACY_BG_BOX_NODES := {
	"steppe": ["BgSteppeShelterbelts", "BgSteppeTurbines", "BgSteppeTurbineBlades", "BgSteppeBarns"],
	"village": ["BgVillageWalls", "BgVillageRoofs", "BgVillageWoods"],
	"industrial": ["BgIndHalls", "BgIndCoolingTowers", "BgIndStacks", "BgIndPlumes"],
	"wetlands": ["BgWetLagoons", "BgWetIslets", "BgWetTrees"],
}

var _fails := 0
var _checks := 0


func _ready() -> void:
	print("=== QA WORLD SHRINK VERIFY START ===")
	_check_default_low_preset()
	_check(is_equal_approx(FT.OUTER_SIZE, 384.0),
			"FrontlineTerrain.OUTER_SIZE == 384.0 (got %.1f)" % FT.OUTER_SIZE)

	for spec in [
		{"scene": "res://sceneries/SteppeLevel.tscn", "map": "steppe", "campaign": 1},
		{"scene": "res://sceneries/VillageLevel.tscn", "map": "village", "campaign": 3},
		{"scene": "res://sceneries/IndustrialLevel.tscn", "map": "industrial", "campaign": 2},
		{"scene": "res://sceneries/WetlandsLevel.tscn", "map": "wetlands", "campaign": 4},
	]:
		await _verify_frontline_combat_map(spec["scene"], spec["map"], int(spec["campaign"]))

	await _verify_tutorial_mode("res://sceneries/SteppeLevel.tscn", "steppe")
	await _verify_tutorial_mode("res://sceneries/IndustrialLevel.tscn", "industrial")
	await _verify_valley_biglevel()
	await _verify_special_missions()
	await _verify_city_and_course()
	_verify_block6_assets_and_systems()

	print("[SHRINK-QA] SUMMARY checks=%d fails=%d -> %s" % [
		_checks, _fails, "PASS" if _fails == 0 else "FAIL"
	])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("[SHRINK-QA] PASS ", msg)
	else:
		_fails += 1
		printerr("[SHRINK-QA] FAIL ", msg)


func _check_default_low_preset() -> void:
	var fresh = GFxScript.new()
	var fresh_q := int(fresh.graphics_settings.get("quality", -1))
	fresh.free()
	_check(fresh_q == Graphics.QualityPreset.LOW,
			"Fresh Graphics default quality is LOW (%d)" % fresh_q)
	_check(QualityManager.level() == QualityManager.Level.LOW,
			"Active QualityManager level is LOW (%d)" % QualityManager.level())
	var scale3d := float(QualityManager.params().get("scale_3d", -1.0))
	_check(is_equal_approx(scale3d, 0.67),
			"LOW preset scale_3d == 0.67 (got %.2f)" % scale3d)


func _instantiate_level(path: String, wait_sec: float) -> Node3D:
	Global.chain_briefing_pending = false
	Global.drone_preset = 6
	var packed := load(path) as PackedScene
	if packed == null:
		_check(false, "Loaded scene " + path)
		return null
	var lvl := packed.instantiate() as Node3D
	add_child(lvl)
	await get_tree().create_timer(wait_sec).timeout
	get_tree().paused = false
	return lvl


func _free_level(lvl: Node) -> void:
	if lvl != null and is_instance_valid(lvl):
		lvl.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _node_has_no_colliders(n: Node) -> bool:
	return n.find_children("*", "CollisionShape3D", true, false).is_empty()


func _node_is_shadowless(n: Node) -> bool:
	if n is GeometryInstance3D and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return false
	for c in n.find_children("*", "GeometryInstance3D", true, false):
		if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			return false
	return true


func _within_sq(p: Vector3, lim: float) -> bool:
	return absf(p.x) <= lim and absf(p.z) <= lim


func _verify_frontline_combat_map(scene_path: String, map_name: String, campaign_id: int) -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = campaign_id
	var lvl := await _instantiate_level(scene_path, 0.5)
	if lvl == null:
		return

	var ft := lvl.get_node_or_null("FrontlineTerrain") as Node3D
	_check(ft != null, "%s has FrontlineTerrain" % map_name)
	if ft != null:
		var ring := ft.get_node_or_null("HorizonRing")
		var mtn := ft.get_node_or_null("MountainBackdrop")
		_check(ring != null and _node_is_shadowless(ring),
				"%s HorizonRing present & shadowless" % map_name)
		_check(mtn != null and _node_has_no_colliders(mtn) and _node_is_shadowless(mtn),
				"%s MountainBackdrop present, 0 colliders & shadowless" % map_name)
		for hnode_name in ["BgHorizonTreeline", "BgHorizonHills"]:
			var hn := ft.get_node_or_null(hnode_name)
			_check(hn != null and _node_has_no_colliders(hn) and _node_is_shadowless(hn),
					"%s horizon %s 0-col & shadowless" % [map_name, hnode_name])
		for legacy_bg in LEGACY_BG_BOX_NODES.get(map_name, []):
			_check(ft.get_node_or_null(legacy_bg) == null,
					"%s legacy dark horizon box %s removed" % [map_name, legacy_bg])

		# Photoreal mobile graphics checks: baked COLOR.a AO, ContactShadows MultiMesh, depth-free water
		var cs_mm := ft.get_node_or_null("ContactShadows") as MultiMeshInstance3D
		_check(cs_mm != null and cs_mm.multimesh != null and cs_mm.multimesh.instance_count > 10 \
				and _node_is_shadowless(cs_mm),
				"%s ContactShadows MultiMesh present (%d instances) & shadowless" % [map_name, cs_mm.multimesh.instance_count if cs_mm and cs_mm.multimesh else 0])
		_check(ft.find_children("ContactShadow_*", "MeshInstance3D", true, false).is_empty(),
				"%s has 0 unbatched ContactShadow_* nodes" % map_name)
		var ao_min := 2.0
		var ao_max := -1.0
		var ao_meshes := 0
		for tm in ft.find_children("*", "MeshInstance3D", true, false):
			var tmi := tm as MeshInstance3D
			if tmi == null or tmi.mesh == null or tmi.mesh.get_surface_count() == 0:
				continue
			var tmat := tmi.get_active_material(0) as ShaderMaterial
			if tmat != null and tmat.shader != null and (
					tmat.shader.resource_path.ends_with("terrain_pbr_lite.gdshader")
					or tmat.shader.resource_path.ends_with("terrain_pbr.gdshader")):
				var tarrs := tmi.mesh.surface_get_arrays(0)
				if tarrs.size() > Mesh.ARRAY_COLOR and tarrs[Mesh.ARRAY_COLOR] is PackedColorArray:
					ao_meshes += 1
					for col in (tarrs[Mesh.ARRAY_COLOR] as PackedColorArray):
						ao_min = minf(ao_min, col.a)
						ao_max = maxf(ao_max, col.a)
		_check(ao_meshes > 0 and ao_min < 0.85 and ao_max >= 0.90,
				"%s baked terrain COLOR.a AO spans [%.2f..%.2f]" % [map_name, ao_min, ao_max])
		if map_name in ["village", "industrial", "wetlands"]:
			var wnode := ft.get_node_or_null("Water") as MeshInstance3D
			if wnode == null:
				wnode = ft.get_node_or_null("RiverWater") as MeshInstance3D
			var w_ok := wnode != null and _node_is_shadowless(wnode) and wnode.mesh != null
			if w_ok and wnode.mesh.get_surface_count() > 0:
				var warrs := wnode.mesh.surface_get_arrays(0)
				w_ok = warrs.size() > Mesh.ARRAY_COLOR and warrs[Mesh.ARRAY_COLOR] is PackedColorArray
			_check(w_ok, "%s water mesh shadowless with baked vertex depth ARRAY_COLOR" % map_name)

		var reserved: Array = FT.get_reserved_structures(ft)
		var res_in_bounds := true
		var min_corridor := 9999.0
		for idx_a in range(reserved.size()):
			var ra: Dictionary = reserved[idx_a]
			var pa: Vector2 = ra.get("pos", Vector2.ZERO)
			var rad_a: float = float(ra.get("radius", 0.0))
			if absf(pa.x) > 162.0 or absf(pa.y) > 162.0:
				res_in_bounds = false
			for idx_b in range(idx_a + 1, reserved.size()):
				var rb: Dictionary = reserved[idx_b]
				var pb: Vector2 = rb.get("pos", Vector2.ZERO)
				var rad_b: float = float(rb.get("radius", 0.0))
				min_corridor = minf(min_corridor, pa.distance_to(pb) - (rad_a + rad_b))
		_check(reserved.size() >= 12 and reserved.size() <= 16 and res_in_bounds,
				"%s reserved key structures 12..16 within ±162m (got %d)" % [map_name, reserved.size()])
		_check(reserved.size() < 2 or min_corridor >= 24.5,
				"%s structure flight corridor >= 24.5m (min_gap=%.1f)" % [map_name, min_corridor])

		var sites: Array = MS.spawned_positions.get(map_name, [])
		var all_sites_in := not sites.is_empty()
		var ind_river_ok := true
		for sp in sites:
			if absf(sp.x) > 162.0 or absf(sp.y) > 162.0:
				all_sites_in = false
			if map_name == "industrial" and sp.y > 148.0:
				ind_river_ok = false
		_check(all_sites_in, "%s spawned %d MilitaryStructures within ±162m" % [map_name, sites.size()])
		if map_name == "industrial":
			_check(ind_river_ok, "industrial MilitaryStructures stay north of river (z <= 148m)")

		if map_name == "steppe":
			_verify_key_structures_geometry(lvl, ft, map_name)

	var drone := lvl.get_node_or_null("Drone") as Node3D
	_check(drone != null and _within_sq(drone.global_position, 178.0),
			"%s combat TAC-%02d drone spawn within ±178m" % [map_name, campaign_id])
	var wl := FT.water_level(map_name)
	if drone != null and wl > -100.0:
		_check(drone.global_position.y > wl + 0.25,
				"%s drone spawn dry above water_level (y=%.2f wl=%.2f)" % [map_name, drone.global_position.y, wl])

	lvl.call("_start_mission")
	lvl.call("_enter_extract_phase")
	var ext: Vector3 = lvl.get("_extract_point")
	_check(_within_sq(ext, 178.0) and ext != Vector3.ZERO, "%s TAC-%02d extract point inside ±178m (%s)" % [map_name, campaign_id, str(ext)])
	if wl > -100.0:
		var ext_h := FT.height_at(map_name, ext.x, ext.z)
		_check(ext_h >= wl - 0.1, "%s TAC-%02d extract ground dry (h=%.2f wl=%.2f)" % [map_name, campaign_id, ext_h, wl])

	# Step 1.0s of physics to verify vehicles & infantry stay bounded & grounded.
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	var vehs: Array = lvl.get("_vehicles")
	var infs: Array = lvl.get("_infantry_units")
	var units_ok := true
	var bad_info := ""
	for v in vehs:
		if not is_instance_valid(v):
			continue
		if not _within_sq(v.global_position, 185.0):
			units_ok = false
			bad_info = "veh %s out of bounds %s" % [str(v.name), str(v.global_position)]
			break
	for u in infs:
		if not is_instance_valid(u):
			continue
		if not _within_sq(u.global_position, 185.0):
			units_ok = false
			bad_info = "inf %s out of bounds %s" % [str(u.name), str(u.global_position)]
			break
		var gh := FT.height_at(map_name, u.global_position.x, u.global_position.z)
		if absf(u.global_position.y - gh) > 2.2:
			units_ok = false
			bad_info = "inf %s not grounded (y=%.2f gh=%.2f)" % [str(u.name), u.global_position.y, gh]
			break
	_check(units_ok, "%s TAC-%02d vehicles(%d) & infantry(%d) bounded <=185m (%s)" % [
		map_name, campaign_id, vehs.size(), infs.size(), bad_info if bad_info != "" else "ok"
	])

	await _free_level(lvl)


func _verify_key_structures_geometry(lvl: Node3D, ft: Node3D, map_name: String) -> void:
	var space := lvl.get_world_3d().direct_space_state
	var present: Array[String] = []
	for sname in KEY_TRICK_STRUCTURES:
		if ft.get_node_or_null(sname) != null:
			present.append(sname)
	_check(present.size() >= 4, "%s spawns >=4 MilitaryStructures trick buildings (got %d)" % [map_name, present.size()])
	for sname in present:
		var st := ft.get_node_or_null(sname) as Node3D
		var cols := st.find_children("*", "CollisionShape3D", true, false)
		var min_bot := INF
		for c in cols:
			var cs := c as CollisionShape3D
			var shape := cs.shape
			var half_y := 0.5
			if shape is BoxShape3D:
				half_y = (shape as BoxShape3D).size.y * 0.5
			elif shape is CylinderShape3D:
				half_y = (shape as CylinderShape3D).height * 0.5
			min_bot = minf(min_bot, cs.global_position.y - half_y)
		var ground_y := FT.footprint_surface_height(
				map_name, Vector2(st.global_position.x, st.global_position.z), 12.0, 12.0, 0.0)
		var grounded := cols.size() >= 2 and (min_bot - ground_y) <= 1.25
		_check(grounded, "%s %s cols=%d grounded (bot=%.2f g=%.2f)" % [
			map_name, sname, cols.size(), min_bot, ground_y
		])

		# Probe rays through local cross-sections to prove both solid hits & open fly-through holes.
		var xf := st.global_transform
		var base := st.global_position
		var any_solid := false
		var any_open := false
		for h in [2.6, 5.2, 8.0]:
			for lat in [-4.0, 0.0, 4.0]:
				var a1 := xf * Vector3(-22.0, h, lat)
				var b1 := xf * Vector3(22.0, h, lat)
				var hit1 := space.intersect_ray(PhysicsRayQueryParameters3D.create(a1, b1))
				if hit1.is_empty():
					any_open = true
				else:
					any_solid = true
				var a2 := xf * Vector3(lat, h, -22.0)
				var b2 := xf * Vector3(lat, h, 22.0)
				var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(a2, b2))
				if hit2.is_empty():
					any_open = true
				else:
					any_solid = true
		var vert_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				base + Vector3(0.0, 38.0, 0.0), base + Vector3(0.0, 1.5, 0.0)))
		if vert_hit.is_empty():
			any_open = true
		else:
			any_solid = true
		_check(any_solid and any_open,
				"%s %s has solid collision & open fly-through gaps (solid=%s open=%s)" % [
					map_name, sname, str(any_solid), str(any_open)
				])


func _verify_tutorial_mode(scene_path: String, map_name: String) -> void:
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.special_mission = 0
	var lvl := await _instantiate_level(scene_path, 0.5)
	if lvl == null:
		return
	var drone := lvl.get_node_or_null("Drone") as Node3D
	var school: Variant = lvl.get("_flight_school")
	var wl := FT.water_level(map_name)
	var dry := drone != null and (wl < -100.0 or drone.global_position.y > wl + 0.25)
	_check(drone != null and _within_sq(drone.global_position, 178.0) and dry and school != null,
			"%s TUTORIAL FlightSchool active & drone spawn dry within ±178m" % map_name)
	await _free_level(lvl)


func _verify_valley_biglevel() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0
	var lvl := await _instantiate_level("res://sceneries/BigLevel.tscn", 0.5)
	if lvl == null:
		return
	var gm := lvl.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	var pm_ok := gm != null and gm.mesh is PlaneMesh \
			and is_equal_approx((gm.mesh as PlaneMesh).size.x, 3600.0)
	var gs := lvl.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
	var bedrock_ok := gs != null and gs.shape is BoxShape3D
	_check(pm_ok and bedrock_ok, "BigLevel Valley Ground mesh == 3600m & bedrock collider active")
	var vm := lvl.get_node_or_null("ValleyMountains")
	_check(vm != null and _node_has_no_colliders(vm) and _node_is_shadowless(vm),
			"BigLevel ValleyMountains 0-col & shadowless")
	var rings: Array = lvl.get("_training_rings")
	var rings_in := rings.size() == 24
	for r in rings:
		if is_instance_valid(r) and Vector2(r.global_position.x, r.global_position.z).length() > 270.0:
			rings_in = false
	_check(rings_in, "BigLevel Valley has 24 training rings within 270m radius (got %d)" % rings.size())
	await _free_level(lvl)


func _verify_special_missions() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	for mid in [1, 2, 3, 4, 5, 6]:
		Global.special_mission = mid
		Global.combat_mission = 1
		var lvl := await _instantiate_level("res://sceneries/VillageLevel.tscn", 0.4)
		if lvl == null:
			continue
		var ext: Vector3 = lvl.get("_special_extract_point")
		var wl := FT.water_level("village")
		var ext_h := FT.height_at("village", ext.x, ext.z)
		var zones: Array = lvl.get("_special_zones")
		var zones_in := true
		for z in zones:
			if z is Vector3 and not _within_sq(z, 178.0):
				zones_in = false
		_check(_within_sq(ext, 178.0) and ext_h >= wl - 0.1 and zones_in,
				"Special Mission %d extract (%s) & zones within ±178m and dry" % [mid, str(ext)])
		await _free_level(lvl)
	Global.special_mission = 0


func _verify_block6_assets_and_systems() -> void:
	var loaded_icons := 0
	for icon_id in FpvIconsScript.ICON_IDS:
		var tex := FpvIconsScript.get_icon(icon_id)
		if tex != null:
			loaded_icons += 1
	_check(loaded_icons == 12, "FpvIcons loads all 12 SVG icons (got %d)" % loaded_icons)

	var radio_files := [
		"res://Assets/Audio/radio/radio_01_bort_target_spotted.wav",
		"res://Assets/Audio/radio/radio_02_hq_cleared_hot.wav",
		"res://Assets/Audio/radio/radio_03_bort_direct_hit.wav",
		"res://Assets/Audio/radio/radio_04_hq_rtb.wav",
	]
	var loaded_wavs := 0
	for rpath in radio_files:
		if FileAccess.file_exists(rpath):
			var bytes := FileAccess.get_file_as_bytes(rpath)
			if bytes.size() > 44:
				loaded_wavs += 1
	_check(loaded_wavs == 4, "All 4 radio WAV files present and non-empty (got %d)" % loaded_wavs)

	var buses_ok := true
	for bname in ["Engine", "Wind", "Combat", "Radio", "Warning"]:
		if AudioServer.get_bus_index(bname) < 0:
			buses_ok = false
	_check(buses_ok, "AudioServer exposes Engine, Wind, Combat, Radio, Warning buses")

	var kill_cam := ReconKillCamScript.new()
	_check(kill_cam != null and is_equal_approx(ReconKillCamScript.SPEED_OF_SOUND, 343.0),
			"ReconKillCamDirector instantiates cleanly")
	if kill_cam != null:
		kill_cam.free()


func _verify_city_and_course() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.special_mission = 0

	var city_lvl := await _instantiate_level("res://sceneries/CityLevel.tscn", 0.5)
	if city_lvl != null:
		var city := city_lvl.get_node_or_null("City")
		var fp := float(city.get("target_footprint_m")) if city != null else 0.0
		_check(is_equal_approx(fp, 720.0), "CityLevel City.target_footprint_m == 720.0 (got %.1f)" % fp)
		var bd := city_lvl.get_node_or_null("CityHorizonBackdrop/DistantCityBlocks")
		_check(bd != null and _node_has_no_colliders(bd) and _node_is_shadowless(bd),
				"CityLevel CityHorizonBackdrop/DistantCityBlocks 0-col & shadowless")
		var gs := city_lvl.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
		_check(gs != null and gs.shape is BoxShape3D and is_equal_approx((gs.shape as BoxShape3D).size.x, 2400.0),
				"CityLevel Ground/CollisionShape3D == 2400m")
		await _free_level(city_lvl)

	var course_lvl := await _instantiate_level("res://sceneries/CourseLevel.tscn", 0.5)
	if course_lvl != null:
		var city := course_lvl.get_node_or_null("City")
		var fp := float(city.get("target_footprint_m")) if city != null else 0.0
		_check(is_equal_approx(fp, 240.0), "CourseLevel City.target_footprint_m == 240.0 (got %.1f)" % fp)
		var bd := course_lvl.get_node_or_null("CityHorizonBackdrop/DistantCityBlocks")
		_check(bd != null and _node_has_no_colliders(bd) and _node_is_shadowless(bd),
				"CourseLevel CityHorizonBackdrop/DistantCityBlocks 0-col & shadowless")
		var track := course_lvl.get_node_or_null("Track")
		var gates: Array = track.find_children("*", "Area3D", true, false) if track != null else []
		var gates_ok := gates.size() >= 7
		for g in gates:
			if g is Node3D and not _within_sq((g as Node3D).global_position, 125.0):
				gates_ok = false
		_check(gates_ok, "CourseLevel Track has >=7 gates within ±125m (got %d)" % gates.size())
		await _free_level(course_lvl)
