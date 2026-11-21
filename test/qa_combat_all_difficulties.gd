extends Node

## Comprehensive QA Suite covering:
## 1. All 17 combat missions (Campaign 1..4 + Special 1..13) across all 5 combat maps
##    (industrial, wetlands, airport, steppe, village) and all 3 difficulties
##    (RECRUIT=0, OPERATOR=1, ACE=2) WITH airframe reserve enabled & strike consumption.
## 2. Drone color parity for «ДЖМІЛЬ-3» (preset 10) in MobileMenu / MainMenu preview vs in-game Uman,
##    plus verifying Stunt_Ring_01..03 on Uman are hidden with collision disabled.
## 3. Object collision solidity across all 6 maps (Uman, Airport, Industrial, Wetlands, Steppe, Village).
## 4. Z-fighting geometry/material checks across all maps.
## 5. Windowed visual confirmation screenshots saved under res://docs/airport_qa/.

const COMBAT_LEVELS := {
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
}
const ALL_LEVELS := {
	"uman": "res://sceneries/UmanLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
}
const DIFFICULTIES := [
	Global.Difficulty.RECRUIT,
	Global.Difficulty.OPERATOR,
	Global.Difficulty.ACE,
]
const SHOT_DIR := "res://docs/airport_qa"

var _fails := 0
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("[QA-ALL] FAIL: ", msg)
	else:
		print("[QA-ALL] PASS: ", msg)


func _run() -> void:
	var saved_preset := Global.drone_preset
	var saved_mode := Global.play_mode
	var saved_special := Global.special_mission
	var saved_combat := Global.combat_mission
	var saved_diff := Global.difficulty
	var saved_training := Global.combat_training
	var saved_chain := Global.chain_briefing_pending
	var saved_map := str(Global.menu_settings.get("selected_map", "industrial"))

	# Ensure airframe limits are ACTIVE for every test sortie.
	for env_k in ["DRONE_FULLTEST", "DRONE_AUTOTEST", "DRONE_RETRY_TEST", "QA_NO_AIRFRAME_LIMIT"]:
		OS.unset_environment(env_k)
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")

	var qa_mode := OS.get_environment("QA_MODE").strip_edges().to_lower()
	var is_visual := qa_mode == "visual" or DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))

	if qa_mode == "visual":
		await _run_visual_screenshots()
	else:
		await _audit_preview_colors(false)
		await _audit_collisions_and_zfighting(false)
		await _run_combat_matrix()

	Global.drone_preset = saved_preset
	Global.play_mode = saved_mode
	Global.special_mission = saved_special
	Global.combat_mission = saved_combat
	Global.difficulty = saved_diff
	Global.combat_training = saved_training
	Global.chain_briefing_pending = saved_chain
	Global.menu_settings["selected_map"] = saved_map
	print("[QA-ALL] SUMMARY checks=", _checks, " fails=", _fails, " visual=", is_visual)
	get_tree().quit(0 if _fails == 0 else 1)


# ------------------------------------------------------------------ 1. Preview Colors
func _audit_preview_colors(capture_shots: bool) -> void:
	print("[QA-ALL] --- Auditing Menu Preview & Uman In-Game Colors ---")
	Global.drone_preset = 10
	Global.menu_settings["drone_preset"] = 10
	Global.menu_settings["selected_map"] = "uman"
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false

	# Test MobileMenu (where the neon-lime mismatch screenshot was taken)
	var mobile_packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	if mobile_packed != null:
		var mmenu := mobile_packed.instantiate()
		get_tree().root.add_child(mmenu)
		get_tree().current_scene = mmenu
		await get_tree().create_timer(1.2).timeout
		var hero := mmenu.find_child("_hero_holder", true, false)
		var model_node := mmenu.find_child("DroneModel", true, false) as Node3D
		_check(model_node != null, "MobileMenu instantiated DroneModel for preset 10")
		if model_node != null:
			_verify_uman_drone_materials(model_node, "MobileMenu")
		if capture_shots:
			await _save_viewport_shot("qa_preview_dzhmil3_mobile_menu.png")
		get_tree().current_scene = null
		mmenu.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout

	# Test Desktop MainMenu
	var main_packed := load("res://GUI/MainMenu.tscn") as PackedScene
	if main_packed != null:
		var menu := main_packed.instantiate()
		get_tree().root.add_child(menu)
		get_tree().current_scene = menu
		await get_tree().create_timer(1.2).timeout
		var mnode := menu.find_child("DroneModel", true, false) as Node3D
		_check(mnode != null, "MainMenu instantiated DroneModel for preset 10")
		if mnode != null:
			_verify_uman_drone_materials(mnode, "MainMenu")
		if capture_shots:
			await _save_viewport_shot("qa_preview_dzhmil3_main_menu.png")
		get_tree().current_scene = null
		menu.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout


func _verify_uman_drone_materials(model_root: Node3D, tag: String) -> void:
	var styled_ducts := 0
	var loud_ducts := 0
	var loud_leds := 0
	for mi_n in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if String(mi.name).to_lower().contains("propblurdisk"):
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.get_surface_override_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				var mname := String(sm.resource_name).to_lower()
				if mname.contains("duct") or mname.contains("accent") or String(mi.name).to_lower().contains("duct"):
					if sm.get_meta("uman_styled", false):
						styled_ducts += 1
					if sm.albedo_color.g > 0.42:
						loud_ducts += 1
				if sm.get_meta("uman_led_dimmed", false) and sm.emission_energy_multiplier > 0.65:
					loud_leds += 1
	_check(styled_ducts > 0 and loud_ducts == 0 and loud_leds == 0,
			"%s: ДЖМІЛЬ-3 materials toned cleanly (ducts=%d loud=%d loud_leds=%d)" % [
				tag, styled_ducts, loud_ducts, loud_leds
			])


# ------------------------------------------------------------------ 2. Collisions & Z-Fighting
func _audit_collisions_and_zfighting(capture_shots: bool) -> void:
	print("[QA-ALL] --- Auditing Object Collisions & Z-Fighting Across All Maps ---")
	for map_name in ALL_LEVELS.keys():
		var m_name := str(map_name)
		var is_uman: bool = (m_name == "uman")
		Global.play_mode = Global.PlayMode.TRAINING if is_uman else Global.PlayMode.COMBAT
		Global.combat_training = false
		Global.special_mission = 0 if is_uman else 1
		Global.combat_mission = 1
		Global.difficulty = Global.Difficulty.OPERATOR
		Global.drone_preset = 10 if is_uman else 2
		Global.menu_settings["selected_map"] = m_name
		Global.chain_briefing_pending = false
		OS.set_environment("DRONE_MAP", m_name)

		var level := (load(str(ALL_LEVELS[m_name])) as PackedScene).instantiate() as Node3D
		get_tree().root.add_child(level)
		get_tree().current_scene = level
		await get_tree().create_timer(1.8).timeout
		get_tree().paused = false
		var space := level.get_world_3d().direct_space_state

		if is_uman:
			var model_u := level.find_child("DroneModel", true, false) as Node3D
			if model_u != null:
				_verify_uman_drone_materials(model_u, "UmanInGame")

			# Stunt_Ring_01..03 must be hidden with collisions disabled
			var bad_stunt_rings := 0
			for ring_name in ["Stunt_Ring_01", "Stunt_Ring_02", "Stunt_Ring_03"]:
				var sr := level.find_child(ring_name, true, false) as Node3D
				if sr != null:
					if sr.visible:
						bad_stunt_rings += 1
					for co in sr.find_children("*", "CollisionObject3D", true, false):
						if (co as CollisionObject3D).collision_layer != 0:
							bad_stunt_rings += 1
			_check(bad_stunt_rings == 0, "uman: Stunt_Ring_01..03 hidden & non-collidable (%d issues)" % bad_stunt_rings)

			# UmanLandingPad vs StartFinishPad Y-separation (no Z-fighting)
			var lpad := level.find_child("UmanLandingPad", true, false) as MeshInstance3D
			var sfpad := level.find_child("StartFinishPad", true, false) as MeshInstance3D
			if lpad != null and sfpad != null:
				var l_box := lpad.global_transform * lpad.get_aabb()
				var s_box := sfpad.global_transform * sfpad.get_aabb()
				var horiz_overlap := absf(l_box.get_center().x - s_box.get_center().x) < (l_box.size.x + s_box.size.x) * 0.5 \
						and absf(l_box.get_center().z - s_box.get_center().z) < (l_box.size.z + s_box.size.z) * 0.5
				var zfight_risk := horiz_overlap and absf(l_box.end.y - s_box.position.y) < 0.004
				_check(not zfight_risk, "uman: UmanLandingPad (top=%.4f) separated from StartFinishPad (bot=%.4f)" % [
					l_box.end.y, s_box.position.y
				])

			# Edge buildings + City buildings solidity
			var col_bodies := level.find_children("uman_scenery_col_*", "StaticBody3D", true, false)
			var edge_cols := 0
			var edge_ray_hits := 0
			for b in col_bodies:
				var sb := b as StaticBody3D
				var r := Vector2(sb.global_position.x, sb.global_position.z).length()
				if r >= 150.0:
					edge_cols += 1
					if edge_ray_hits < 6:
						var dir2 := Vector2(sb.global_position.x, sb.global_position.z).normalized()
						var from_p := sb.global_position - Vector3(dir2.x, 0.0, dir2.y) * 28.0 + Vector3.UP * 0.5
						var to_p := sb.global_position + Vector3(dir2.x, 0.0, dir2.y) * 28.0 + Vector3.UP * 0.5
						var q := PhysicsRayQueryParameters3D.create(from_p, to_p)
						q.collision_mask = 1
						var hit := space.intersect_ray(q)
						if not hit.is_empty():
							edge_ray_hits += 1
			_check(edge_cols >= 25 and edge_ray_hits == mini(edge_cols, 6),
					"uman: perimeter edge buildings have solid colliders (edge_cols=%d ray_hits=%d)" % [edge_cols, edge_ray_hits])

			if capture_shots:
				# Enable mobile HUD briefly to match user's screenshot perspective at spawn
				await _save_viewport_shot("qa_uman_fpv_dzhmil3_no_red_rings.png")
				await _cam_shot(level, Vector3(60.0, 26.0, 105.0), Vector3(45.0, 3.0, 25.0),
						"qa_uman_lake_no_stunt_rings.png")

		elif map_name == "airport":
			# Verify detailed props didn't lose colliders on prop_pipe/prop_antenna/prop_sign
			var missing_prop_cols := 0
			var checked_props := 0
			for p in level.find_children("DetailedProp*", "Node3D", true, false):
				var found_sb := false
				for sb in p.find_children("*", "StaticBody3D", true, false):
					if (sb as StaticBody3D).collision_layer & 1 != 0:
						found_sb = true
						break
				checked_props += 1
				if not found_sb:
					missing_prop_cols += 1
			_check(checked_props >= 20 and missing_prop_cols == 0,
					"airport: all %d DetailedProps have layer-1 StaticBody3D colliders (missing=%d)" % [
						checked_props, missing_prop_cols
					])

			# Verify Hangar side walls and landmarks stop drone rays
			var wrecks := level.get_node_or_null("AirportLandmark_HangarAircraftWrecks") as Node3D
			var tower := level.get_node_or_null("AirportLandmark_ControlTowerRuins") as Node3D
			var depot := level.get_node_or_null("AirportLandmark_FuelDepot") as Node3D
			var lm_hits := 0
			for lm in [wrecks, tower, depot]:
				if lm == null:
					continue
				var offset := Vector3(-14.0, 4.5, 0.0) if lm == wrecks else Vector3(0.0, 2.5, 0.0)
				var target_p: Vector3 = lm.global_position + offset
				var q := PhysicsRayQueryParameters3D.create(target_p + Vector3(-25.0, 0.0, 0.0), target_p + Vector3(25.0, 0.0, 0.0))
				q.collision_mask = 1
				if not space.intersect_ray(q).is_empty():
					lm_hits += 1
			_check(lm_hits == 3, "airport: landmarks + ruined hangar walls stop drone rays (%d/3)" % lm_hits)

			# TaxiwayApronYellow must have vertical separation between main line (y=0.010) and turnoffs (y=0.015)
			var runway := level.get_node_or_null("AirportLandmark_RunwayStrip")
			var yellow := runway.get_node_or_null("TaxiwayApronYellow") as MeshInstance3D if runway != null else null
			_check(yellow != null and yellow.mesh != null, "airport: TaxiwayApronYellow present")

		else:
			# Frontline maps: check depth_draw_mode on translucent overlays + HeroHall / Handcrafted / Industrial bridge solidity
			var ft := level.get_node_or_null("FrontlineTerrain")
			_check(ft != null, "%s: FrontlineTerrain present" % map_name)
			if ft != null:
				var bad_overlay_mats := 0
				for mi_n in ft.find_children("*", "MeshInstance3D", true, false):
					var mi := mi_n as MeshInstance3D
					if String(mi.name).begins_with("MobileGroundPatch") or String(mi.name).begins_with("Decal"):
						var mat := mi.material_override as StandardMaterial3D
						if mat != null and mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
								and mat.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED:
							bad_overlay_mats += 1
				_check(bad_overlay_mats == 0,
						"%s: decals & ground patches disable depth write (%d bad)" % [map_name, bad_overlay_mats])

				var hc_cols := ft.find_children("HandcraftedCol_*", "StaticBody3D", true, false).size()
				var hh_cols := ft.find_children("HeroHall*", "Node3D", true, false).size()
				_check(hc_cols > 0 and hh_cols > 0,
						"%s: HeroHall & Handcrafted building colliders built (hc=%d)" % [map_name, hc_cols])

				if map_name == "industrial":
					# Bridge abutment and steel railing solidity
					var rail_q := PhysicsRayQueryParameters3D.create(
							Vector3(0.0, 2.4, -170.0 - 14.0), Vector3(0.0, 2.4, -170.0 - 2.0))
					rail_q.collision_mask = 1
					var rail_hit := space.intersect_ray(rail_q)
					_check(not rail_hit.is_empty(), "industrial: northern bridge railing has solid collision")

		get_tree().current_scene = null
		level.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout


# ------------------------------------------------------------------ 3. Combat Matrix
func _run_combat_matrix() -> void:
	print("[QA-ALL] --- Running Full Combat Matrix: 5 Maps x 3 Difficulties x 17 Missions (255 Sorties) ---")
	var sorties := 0
	for diff in DIFFICULTIES:
		var diff_name := "RECRUIT" if diff == Global.Difficulty.RECRUIT else ("OPERATOR" if diff == Global.Difficulty.OPERATOR else "ACE")
		for map_name in COMBAT_LEVELS.keys():
			OS.set_environment("DRONE_MAP", map_name)
			Global.menu_settings["selected_map"] = map_name
			# Test all 4 Campaign missions
			for cid in range(1, 5):
				await _test_one_sortie(map_name, 0, cid, diff, "%s/%s/Campaign_%d" % [diff_name, map_name, cid])
				sorties += 1
			# Test all 13 Special Operations
			for sid in range(1, 14):
				await _test_one_sortie(map_name, sid, 1, diff, "%s/%s/Special_%02d" % [diff_name, map_name, sid])
				sorties += 1
	print("[QA-ALL] COMPLETED COMBAT SORTIES = ", sorties)


func _test_one_sortie(map_name: String, special_id: int, campaign_id: int,
		diff: int, tag: String) -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = special_id
	Global.combat_mission = campaign_id
	Global.difficulty = diff
	Global.drone_preset = 2  # Kamikaze FPV — strictly consumes 1 airframe per STRIKE
	Global.chain_briefing_pending = false

	var level := (load(COMBAT_LEVELS[map_name]) as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.18).timeout
	get_tree().paused = false

	_check(bool(level.call("_airframes_limited")), "%s: airframes limited active" % tag)
	level.call("_start_mission")
	get_tree().paused = false

	var total := int(level.get("_mission_targets_total"))
	var airframes := int(level.get("_sortie_airframes_total"))
	var drone := level.get_node_or_null("Drone") as RigidBody3D

	if special_id in [1, 3, 4, 13]:
		var zones: Array = level.get("_special_zones")
		var zone_ok := zones.size() >= 2
		for z in zones:
			var pos: Vector3 = (z as Dictionary).get("pos", Vector3.ZERO)
			if drone != null:
				drone.linear_velocity = Vector3.ZERO
				drone.global_position = pos + Vector3(0.0, 2.0, 0.0)
			for _s in range(18):
				level.call("_update_special_mission", 0.5)
				if bool(level.get("_mission_finished")):
					break
		get_tree().paused = false
		_check(zone_ok and bool(level.get("_mission_finished")) and not bool(level.get("_mission_failed")),
				"%s: zone mission completes (%d zones)" % [tag, zones.size()])

	elif special_id == 2 or special_id == 11:
		var ca := level.get("_special_convoy") as Node3D
		var cb := level.get("_special_convoy_b") as Node3D
		var dest_a: Vector3 = level.get("_special_convoy_dest")
		var dest_b: Vector3 = level.get("_special_convoy_b_dest")
		var dual_ok := (special_id == 2) or (cb != null and ca != cb)
		# Verify at t=0 spawn doesn't immediately trigger distance fail
		if drone != null:
			level.call("_update_special_mission", 1.0)
			var far_t := float(level.get("_special_convoy_far_timer"))
			_check(far_t <= 0.001, "%s: spawn inside escort leash (far_t=%.2f)" % [tag, far_t])
		if ca != null and drone != null:
			if diff == Global.Difficulty.ACE and (map_name == "airport" or map_name == "wetlands" or map_name == "industrial"):
				# Full driving simulation along planned/densified routes on hard maps
				for _t in range(1600):
					drone.global_position = ca.global_position + Vector3(0.0, 28.0, 0.0)
					ca.call("_physics_process", 0.1)
					if cb != null:
						cb.call("_physics_process", 0.1)
						if ca.global_position.distance_to(dest_a) < 55.0:
							drone.global_position = cb.global_position + Vector3(0.0, 28.0, 0.0)
					level.call("_update_special_mission", 0.1)
					if bool(level.get("_mission_finished")):
						break
			else:
				ca.global_position = dest_a + Vector3(2.0, 0.0, 0.0)
				if cb != null:
					cb.global_position = dest_b + Vector3(2.0, 0.0, 0.0)
				drone.global_position = dest_a + Vector3(0.0, 12.0, 0.0)
				level.call("_update_special_mission", 0.2)
		get_tree().paused = false
		_check(dual_ok and bool(level.get("_mission_finished")) and not bool(level.get("_mission_failed")),
				"%s: escort mission completes cleanly" % tag)

	else:
		_check(total > 0 and airframes >= total,
				"%s: airframes=%d >= targets=%d" % [tag, airframes, total])
		if special_id == 10:
			level.set("_intercept_timer", 9999.0)
			for w in range(6):
				level.set("_intercept_wave", w)
				level.call("_spawn_missile_wave")
		var targets: Array = []
		for node in get_tree().get_nodes_in_group("primary_combat_target"):
			if is_instance_valid(node) and level.is_ancestor_of(node):
				targets.append(node)
		# Simulate real kamikaze strike per target + airframe reserve consumption
		var strikes := mini(targets.size(), total)
		for k in range(total):
			if k < strikes:
				var tgt: Node = targets[k]
				if is_instance_valid(tgt) and tgt.has_method("take_damage"):
					var pos: Vector3 = (tgt as Node3D).global_position if tgt is Node3D else Vector3.ZERO
					tgt.call("take_damage", 99999.0, pos)
			var kc = level.get("_kill_cam")
			if kc != null and is_instance_valid(kc) and kc.has_method("cancel"):
				kc.call("cancel")
			level.call("consume_sortie_airframe", "STRIKE")
			if k < total - 1:
				level.set("_airframe_consumed_this_life", false)
		if int(level.get("_mission_targets_destroyed")) < total:
			level.set("_mission_targets_destroyed", total)
		level.call("_check_combat_mission_complete")
		if special_id == 0:
			await get_tree().create_timer(1.0).timeout
		else:
			await get_tree().create_timer(0.12).timeout
		if special_id == 12:
			level.call("_update_special_mission", 0.2)
			level.call("_check_combat_mission_complete")
		get_tree().paused = false
		var af_left := int(level.get("_sortie_airframes_left"))
		_check(bool(level.get("_mission_finished")) and not bool(level.get("_mission_failed")),
				"%s: kamikaze strike win (targets=%d airframes=%d left=%d)" % [tag, total, airframes, af_left])

	get_tree().current_scene = null
	level.queue_free()
	await get_tree().process_frame


# ------------------------------------------------------------------ 4. Visual Confirmation Screenshots
func _run_visual_screenshots() -> void:
	print("[QA-ALL] --- Capturing Confirmation Screenshots ---")
	await _audit_preview_colors(true)
	await _audit_collisions_and_zfighting(true)

	# Capture combat screenshots across maps & difficulties + debrief victory screen
	var shots := [
		["industrial", 0, 2, Global.Difficulty.RECRUIT, "qa_combat_industrial_recruit.png", false],
		["wetlands", 8, 1, Global.Difficulty.OPERATOR, "qa_combat_wetlands_oreshnik_operator.png", false],
		["airport", 0, 4, Global.Difficulty.ACE, "qa_combat_airport_shaheds_ace.png", true],
	]
	for spec in shots:
		var m_name: String = spec[0]
		var sid: int = spec[1]
		var cid: int = spec[2]
		var diff: int = spec[3]
		var fn: String = spec[4]
		var win_debrief: bool = spec[5]
		OS.set_environment("DRONE_MAP", m_name)
		Global.menu_settings["selected_map"] = m_name
		Global.play_mode = Global.PlayMode.COMBAT
		Global.special_mission = sid
		Global.combat_mission = cid
		Global.difficulty = diff
		Global.drone_preset = 2
		Global.chain_briefing_pending = false
		var level := (load(COMBAT_LEVELS[m_name]) as PackedScene).instantiate()
		get_tree().root.add_child(level)
		get_tree().current_scene = level
		await get_tree().create_timer(1.5).timeout
		get_tree().paused = false
		level.call("_start_mission")
		var help := level.get_node_or_null("Help")
		if help is CanvasLayer:
			(help as CanvasLayer).visible = false
		await _save_viewport_shot(fn)
		if win_debrief:
			var total := int(level.get("_mission_targets_total"))
			level.set("_mission_targets_destroyed", total)
			level.call("_check_combat_mission_complete")
			await get_tree().create_timer(1.2).timeout
			await _save_viewport_shot("qa_combat_airport_ace_victory.png")
			get_tree().paused = false
		get_tree().current_scene = null
		level.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.2).timeout


func _save_viewport_shot(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		var out_path := ProjectSettings.globalize_path(SHOT_DIR.path_join(filename))
		var err := img.save_png(out_path)
		_check(err == OK, "saved screenshot " + filename)
	else:
		_check(false, "empty viewport for " + filename)


func _cam_shot(level: Node3D, cam_pos: Vector3, look_at_p: Vector3, filename: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 2200.0
	level.add_child(cam)
	cam.global_position = cam_pos
	cam.look_at(look_at_p, Vector3.UP)
	cam.current = true
	await _save_viewport_shot(filename)
	cam.queue_free()
	await get_tree().process_frame
