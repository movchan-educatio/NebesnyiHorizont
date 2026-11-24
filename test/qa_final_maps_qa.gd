extends Node
## Comprehensive headless QA suite verifying Stage 4-7 iOS map optimizations,
## 30/30 unobstructed gates on both Lis Forest and Oil Rig, PBR ORM/Normal
## materials, animated flare shaders, LOD ranges, batched rocks, and MobileMenu.

var _fails := 0
var _checks := 0


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("[FINAL-QA] PASS ", label)
	else:
		_fails += 1
		print("[FINAL-QA] FAIL ", label)


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_QUALITY", "low")
	OS.set_environment("DRONE_NO_RECORD", "1")
	await _test_lis_forest()
	await _test_lis_night_env()
	await _test_oilrig()
	await _test_mobile_menu_cards()
	print("[FINAL-QA] SUMMARY checks=%d failures=%d" % [_checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_lis_forest() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Global.difficulty = Global.Difficulty.OPERATOR
	DroneCatalog.apply(0)

	var packed := load("res://sceneries/LisLevel.tscn") as PackedScene
	_check(packed != null, "LisLevel.tscn завантажується")
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	for _i in range(24):
		await get_tree().physics_frame

	var lis := level.find_child("LisFreestyleMap", true, false) as Node3D
	_check(lis != null, "LisFreestyleMap присутній")
	if lis == null:
		level.queue_free()
		return

	# 1. 30 FPVGates in group fpv_gates
	var fg := lis.get_node_or_null("FPVGates") as Node3D
	_check(fg != null and fg.is_in_group("fpv_gates"), "Lis FPVGates у групі fpv_gates")
	_check(fg != null and fg.get_child_count() == 30, "Lis FPVGates має рівно 30 воріт (%d)" % (fg.get_child_count() if fg != null else -1))
	_check(int(level.get("_rings_total")) == 30, "Lis _rings_total == 30 (%d)" % int(level.get("_rings_total")))

	var ring_cols := 0
	var rings_arr: Array = level.get("_training_rings")
	for r in rings_arr:
		if r is Node:
			ring_cols += (r as Node).find_children("*", "StaticBody3D", true, false).size()
	_check(ring_cols == 0, "Lis кільця мають 0 StaticBody3D (%d)" % ring_cols)

	# 2. 30/30 unobstructed physics sweep
	var drone := level.get_node_or_null("Drone")
	var space: PhysicsDirectSpaceState3D = (level as Node3D).get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 2.6
	var exclude: Array[RID] = []
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())
	var blocked := 0
	if fg != null:
		for ch in fg.get_children():
			if not (ch is Marker3D):
				continue
			var m := ch as Marker3D
			var fwd := -m.global_transform.basis.z.normalized()
			var p0 := m.global_position
			for off in [-10.0, 0.0, 10.0]:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = sphere
				q.collision_mask = 1
				q.exclude = exclude
				q.transform = Transform3D(Basis.IDENTITY, p0 + fwd * off)
				var res: Array = space.intersect_shape(q, 2)
				if not res.is_empty():
					blocked += 1
					print("[FINAL-QA]   Lis blocked ", m.name, " off=", off, " col=", res[0].get("collider"))
					break
	_check(blocked == 0, "Lis 30/30 воріт без перешкод у прольоті (blocked=%d)" % blocked)

	# 3. Sequential gate order & LapTimer check
	if drone != null and rings_arr.size() == 30:
		level.call("_on_ring_entered", drone, rings_arr[1])
		_check(int(level.get("_rings_passed")) == 0, "Lis пропуск першого кільця заблокований")
		for i in range(30):
			level.set("_mission_time", float(i + 1) * 3.0)
			level.call("_on_ring_entered", drone, rings_arr[i])
		_check(int(level.get("_rings_passed")) == 30, "Lis послідовний фініш 30/30 спрацював")
		_check(bool(level.get("_mission_finished")), "Lis _mission_finished після 30 воріт")
		_check(float(level.get("_mission_time")) > 0.0, "Lis LapTimer _mission_time > 0")

	# 4. Grass LOD 18-24m, scatter >1500, 0 floating >0.5m
	var sc := lis.find_child("ScatterMultiMesh", true, false) as Node3D
	var active_scatter := 0
	var grass_ok := true
	var grass_seen := 0
	var floating := 0
	if sc != null:
		for mmi in sc.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (mmi as MultiMeshInstance3D).multimesh
			if mm == null:
				continue
			var nm := String(mmi.name)
			if nm.contains("grass_medium"):
				grass_seen += 1
				var vr := (mmi as MultiMeshInstance3D).visibility_range_end
				if vr < 18.0 or vr > 24.0:
					grass_ok = false
			var mmi_xf := (mmi as MultiMeshInstance3D).global_transform
			var cached_meta: Variant = mmi.get_meta("instance_transforms", null)
			var cached_list: Array = cached_meta if cached_meta is Array else []
			for k in range(mm.instance_count):
				var xf: Transform3D = cached_list[k] if k < cached_list.size() else mm.get_instance_transform(k)
				if xf.basis.x.length_squared() < 0.0001:
					continue
				active_scatter += 1
				var wpos := mmi_xf * xf.origin
				if absf(wpos.x) <= 295.0 and absf(wpos.z) <= 295.0 and sc.has_method("_sample_terrain_grid"):
					var ty := float(sc.call("_sample_terrain_grid", wpos.x, wpos.z))
					if ty > -900.0 and wpos.y - ty > 0.5:
						floating += 1
	_check(grass_seen >= 2 and grass_ok, "Lis трава visibility_range_end у межах 18-24м (chunks=%d)" % grass_seen)
	_check(active_scatter > 1500, "Lis активних інстансів рослинності > 1500 (%d)" % active_scatter)
	_check(floating == 0, "Lis 0 завислих дерев/рослинності > 0.5м над рельєфом (floating=%d)" % floating)

	# 5. 0 visible kit_* and batched bank rocks
	var vis_kit := 0
	for ch in lis.find_children("kit_*", "Node3D", true, false):
		if not ch.is_queued_for_deletion() and (ch as Node3D).visible:
			vis_kit += 1
	_check(vis_kit == 0, "Lis 0 видимих прототипів kit_* біля (0,0,0) (%d)" % vis_kit)

	var batched := lis.find_child("BankRocksBatched", true, false) as MultiMeshInstance3D
	_check(batched != null and batched.multimesh != null and batched.multimesh.instance_count == 97,
			"Lis BankRocksBatched об'єднав 97 каменів (%d)" % (batched.multimesh.instance_count if batched and batched.multimesh else -1))
	var unbatched_rocks := 0
	for ch in lis.find_children("bank_rock_*", "MeshInstance3D", true, false):
		if not ch.is_queued_for_deletion() and (ch as MeshInstance3D).visible:
			unbatched_rocks += 1
	_check(unbatched_rocks == 0, "Lis 0 незгрупованих видимих bank_rock_* (%d)" % unbatched_rocks)

	# 6. No volumetric fog / SSR / SDFGI / SSAO / glow
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env := we.environment if we != null else null
	_check(env != null and not env.volumetric_fog_enabled and env.volumetric_fog_density <= 0.00001, "Lis без volumetric fog")
	_check(env != null and env.fog_height_density <= 0.00001, "Lis без height fog")
	_check(env != null and not env.ssr_enabled and not env.sdfgi_enabled and not env.ssao_enabled and not env.glow_enabled,
			"Lis без SSR/SDFGI/SSAO/glow")

	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame


func _test_lis_night_env() -> void:
	Global.menu_settings["selected_map"] = "lis_forest_freestyle"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 12
	Global.difficulty = Global.Difficulty.OPERATOR
	DroneCatalog.apply(0)
	var level := (load("res://sceneries/LisLevel.tscn") as PackedScene).instantiate()
	add_child(level)
	for _i in range(12):
		await get_tree().physics_frame
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env := we.environment if we != null else null
	_check(int(level.get("_weather")) == 3 and env != null and not env.volumetric_fog_enabled and not env.ssr_enabled,
			"Lis нічна спецоперація 12 зберігає _weather=3 без volumetric/SSR")
	Global.special_mission = 0
	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame


func _test_oilrig() -> void:
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	DroneCatalog.apply(0)

	var packed := load("res://sceneries/OilRigLevel.tscn") as PackedScene
	_check(packed != null, "OilRigLevel.tscn завантажується")
	if packed == null:
		return
	var level := packed.instantiate()
	add_child(level)
	for _i in range(24):
		await get_tree().physics_frame

	var rig := level.find_child("OilRigMap", true, false) as Node3D
	_check(rig != null, "OilRigMap присутній")
	if rig == null:
		level.queue_free()
		return

	# 1. 49 fpv_gates markers + 30 VisibleGateRings
	var fg := rig.get_node_or_null("FPVGates") as Node3D
	var gate_cnt := fg.get_child_count() if fg != null else 0
	var grp_ok := true
	if fg != null:
		for ch in fg.get_children():
			if not ch.is_in_group("fpv_gates"):
				grp_ok = false
				break
	_check(gate_cnt == 49 and grp_ok, "OilRig 49 маркерів у групі fpv_gates (%d)" % gate_cnt)

	var vr := rig.find_child("VisibleGateRings", true, false) as MultiMeshInstance3D
	_check(vr != null and vr.multimesh != null and vr.multimesh.instance_count == 30,
			"OilRig VisibleGateRings = 30 (%d)" % (vr.multimesh.instance_count if vr and vr.multimesh else -1))
	_check(vr != null and vr.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"OilRig VisibleGateRings не кидають тіней")
	_check(vr != null and vr.find_children("*", "StaticBody3D", true, false).is_empty(),
			"OilRig кільця не мають колайдерів")

	# 2. 30/30 unobstructed sweep against MapColliders
	var drone := level.get_node_or_null("Drone")
	var space: PhysicsDirectSpaceState3D = (level as Node3D).get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 2.6
	var exclude: Array[RID] = []
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())
	var indices: Variant = rig.get("SELECTED_GATE_INDICES")
	var blocked := 0
	if indices is Array and fg != null:
		for idx in indices:
			var m := fg.get_node_or_null("Gate_%02d" % int(idx)) as Marker3D
			if m == null:
				blocked += 1
				continue
			var nrm := m.global_transform.basis.y.normalized()
			var p0 := m.global_position
			for off in [-10.0, 0.0, 10.0]:
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = sphere
				q.collision_mask = 1
				q.exclude = exclude
				q.transform = Transform3D(Basis.IDENTITY, p0 + nrm * off)
				var res: Array = space.intersect_shape(q, 2)
				if not res.is_empty():
					blocked += 1
					break
	_check(blocked == 0, "OilRig 30/30 обраних воріт вільні для прольоту (blocked=%d)" % blocked)

	# 3. Checkpoint triggers + _rings_total == 0
	var rig_trigs: Array = level.get("_rig_gate_triggers")
	_check(int(level.get("_rings_total")) == 0 and rig_trigs.size() == 30,
			"OilRig 30 Area3D чекпоінтів активні при _rings_total == 0 (trigs=%d)" % rig_trigs.size())
	if drone != null:
		level.call("_on_oilrig_gate_entered", drone, 0)
		_check((level.get("_rig_gates_passed") as Dictionary).size() == 1 and int(level.get("_rings_total")) == 0,
				"OilRig чекпоінт оновлює лічильник воріт без порушення _rings_total == 0")

	# 4. Colliders, Spawns, WaterKillZone, RailPosts
	var mc := rig.get_node_or_null("MapColliders")
	_check(mc != null and mc.get_child_count() == 937,
			"OilRig MapColliders == 937 (%d)" % (mc.get_child_count() if mc != null else -1))
	var sp := rig.get_node_or_null("SpawnPoints")
	var sp_cnt := sp.get_child_count() if sp != null else 0
	var sp_grp := get_tree().get_nodes_in_group("map_spawn_points").size()
	_check(sp_cnt == 5 and sp_grp >= 5, "OilRig 5 map_spawn_points (%d / %d)" % [sp_cnt, sp_grp])
	_check(rig.get_node_or_null("WaterKillZone") is Area3D, "OilRig WaterKillZone присутній")
	var rp := rig.find_child("RailPosts", true, false) as MultiMeshInstance3D
	_check(rp != null and rp.multimesh != null and rp.multimesh.instance_count >= 375,
			"OilRig RailPosts >= 375 (%d)" % (rp.multimesh.instance_count if rp and rp.multimesh else -1))

	# 5. PBR ORM/Normal + animated flares + 0 OmniLights + no volumetric/SSR/SDFGI
	var s_mat := load("res://maps/oil_rig/materials/structures.tres") as StandardMaterial3D
	var d_mat := load("res://maps/oil_rig/materials/deck.tres") as StandardMaterial3D
	_check(s_mat != null and s_mat.normal_enabled and s_mat.ao_enabled and s_mat.metallic_texture != null and s_mat.roughness_texture != null,
			"OilRig structures.tres має валідні NormalGL/ORM канали")
	_check(d_mat != null and d_mat.normal_enabled and d_mat.ao_enabled and d_mat.metallic_texture != null and d_mat.roughness_texture != null,
			"OilRig deck.tres має валідні NormalGL/ORM канали")

	var fe := rig.find_child("MS_flare_emissive", true, false) as MeshInstance3D
	var ff := rig.find_child("MS_flare_flame", true, false) as MeshInstance3D
	_check(fe != null and fe.get_active_material(0) is ShaderMaterial, "OilRig MS_flare_emissive використовує ShaderMaterial")
	_check(ff != null and ff.get_active_material(0) is ShaderMaterial, "OilRig MS_flare_flame використовує ShaderMaterial")
	_check(rig.find_children("*", "OmniLight3D", true, false).is_empty(), "OilRig 0 OmniLight3D на факелах")

	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env := we.environment if we != null else null
	_check(env != null and not env.volumetric_fog_enabled and not env.ssr_enabled and not env.sdfgi_enabled and not env.ssao_enabled and not env.glow_enabled,
			"OilRig без volumetric/SSR/SDFGI/SSAO/glow")

	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame


func _test_mobile_menu_cards() -> void:
	var menu_packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	_check(menu_packed != null, "MobileMenu.tscn завантажується")
	if menu_packed == null:
		return
	var menu := menu_packed.instantiate()
	add_child(menu)
	for _i in range(6):
		await get_tree().process_frame
	if menu.has_method("_show"):
		menu.call("_show", "play")
	if menu.has_method("_select_map"):
		menu.call("_select_map", "lis_forest_freestyle")
		menu.call("_select_map", "oilrig")
	_check(str(Global.menu_settings.get("selected_map", "")) == "oilrig" or str(menu.get("_selected_map")) == "oilrig",
			"MobileMenu перемикання карт працює")

	var tex_lis := load("res://Assets/Branding/mobile_map_lis_forest_freestyle.png") as Texture2D
	var tex_rig := load("res://Assets/Branding/mobile_map_oilrig.png") as Texture2D
	_check(tex_lis != null and tex_lis.get_size() == Vector2(1920, 1080),
			"mobile_map_lis_forest_freestyle.png == 1920x1080 (%s)" % [str(tex_lis.get_size()) if tex_lis != null else "null"])
	_check(tex_rig != null and tex_rig.get_size() == Vector2(1920, 1080),
			"mobile_map_oilrig.png == 1920x1080 (%s)" % [str(tex_rig.get_size()) if tex_rig != null else "null"])

	menu.queue_free()
	for _f in range(3):
		await get_tree().process_frame
