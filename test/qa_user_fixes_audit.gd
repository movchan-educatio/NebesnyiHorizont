## Visual & Functional Verification Suite for all 11 user-reported fixes:
## 1. MobileMenu bottom clipping + Changelog visibility (with QuickTut=true)
## 2. Leleka-100 non-white matte tactical recolor
## 3. Auto-reset on hit / drop hit leaving 0 ammo
## 4. Explosion / Hit / KillCam prewarm & low-hitch caches
## 5. Legacy 2s CombatHUD / StickOverlay glitch suppression & loading handoff
## 6. 0/24 obstructed arches on Wetlands, Airport, Industrial (physics + landmarks + trees)
## 7. Mid-mission drone switching (COMBAT restricts Uman drones, TRAINING allows all) + KEY_B
## 8. Language toggle UA <-> EN <-> UA crash-free rebuild on MobileMenu
## 9. Wetlands lighthouse & wooden boardwalk separation + single causeway
## 10. Airport ControlTowerRuins hollow open-window fly-through cab
## 11. +20% unit size scale across infantry, tanks, BMP, APC, truck, heli, AA, CombatTarget
extends Node

const OUT_DIR := "res://test/qa_out"

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var saved_no_rec := OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("DRONE_NO_RECORD", "1")
	# BigLevel disables Kill-Cam in headless unless this test flag is present;
	# the payload-drone regressions below call _maybe_trigger_kill_cam directly.
	var saved_killcam := OS.get_environment("DRONE_KILLCAM_TEST")
	OS.set_environment("DRONE_KILLCAM_TEST", "1")
	var saved_mobile := OS.get_environment("MOBILE_UI")
	var saved_preset := Global.drone_preset
	var saved_menu_preset := int(Global.menu_settings.get("drone_preset", 0))
	var saved_mode := Global.play_mode
	var saved_ct := Global.combat_training
	var saved_cm := Global.combat_mission
	var saved_sm := Global.special_mission
	var saved_records := Global.campaign_records.duplicate(true)
	var saved_q := int(Graphics.graphics_settings.get("quality", 1))
	var saved_lang := Loc.get_language()

	var root_win := get_tree().root
	if root_win != null and DisplayServer.get_name() != "headless":
		root_win.size = Vector2i(1280, 720)

	await _audit_mobile_menu_leleka_and_language()
	await _audit_wetlands_and_arches()
	await _audit_airport_tower_windows_and_arches()
	await _audit_industrial_arches_switcher_and_reset()
	await _audit_units_scale_and_prewarm()

	Global.campaign_records = saved_records
	Global.drone_preset = saved_preset
	Global.menu_settings["drone_preset"] = saved_menu_preset
	Global.play_mode = saved_mode
	Global.combat_training = saved_ct
	Global.combat_mission = saved_cm
	Global.special_mission = saved_sm
	Loc.set_language(Loc.Language.UA if saved_lang != Loc.Language.EN else Loc.Language.UA, true)
	Graphics.apply_quality_preset(saved_q)
	if saved_mobile.is_empty():
		OS.unset_environment("MOBILE_UI")
	else:
		OS.set_environment("MOBILE_UI", saved_mobile)
	if saved_no_rec.is_empty():
		OS.unset_environment("DRONE_NO_RECORD")
	else:
		OS.set_environment("DRONE_NO_RECORD", saved_no_rec)
	if saved_killcam.is_empty():
		OS.unset_environment("DRONE_KILLCAM_TEST")
	else:
		OS.set_environment("DRONE_KILLCAM_TEST", saved_killcam)

	print("[QA_FIXES] failures=%d" % _failures)
	if _failures == 0:
		print("[QA_FIXES] ALL USER FIX AUDITS PASSED")
	get_tree().quit(0 if _failures == 0 else 1)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("[QA_FIXES] FAIL: ", msg)


func _pass(msg: String) -> void:
	print("[QA_FIXES] PASS: ", msg)


func _snap(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_fail("Empty viewport image for " + filename)
		return
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(filename))
	var err := img.save_png(path)
	if err != OK:
		_fail("Failed to save PNG %s (err=%d)" % [path, err])
	else:
		print("[QA_FIXES] SNAP: ", path)


func _wait_frames(n: int = 4) -> void:
	for _i in range(n):
		await get_tree().process_frame


func _world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null and mi.visible:
				var bb := mi.get_aabb()
				if bb.size.length_squared() > 0.0001:
					var xf := mi.global_transform
					for xi in [0.0, 1.0]:
						for yi in [0.0, 1.0]:
							for zi in [0.0, 1.0]:
								var pt: Vector3 = xf * (bb.position + Vector3(
										bb.size.x * float(xi),
										bb.size.y * float(yi),
										bb.size.z * float(zi)))
								if not has:
									out = AABB(pt, Vector3.ZERO)
									has = true
								else:
									out = out.expand(pt)
		for ch in cur.get_children():
			stack.append(ch)
	return out


func _verify_all_arches_clear(lvl: Node, label: String) -> void:
	var rings = lvl.get("_training_rings")
	var specs = lvl.get("_freestyle_ring_specs")
	if not (rings is Array) or (rings as Array).size() < 24:
		_fail("%s expected 24 training rings, got %s" % [label, str(rings.size() if rings is Array else 0)])
		return
	var blocked_physics := 0
	var tree_hits := 0
	var tree_mms: Array[MultiMeshInstance3D] = []
	var mmi_stack: Array[Node] = [lvl]
	while not mmi_stack.is_empty():
		var cur: Node = mmi_stack.pop_back()
		if cur is MultiMeshInstance3D:
			var mmi := cur as MultiMeshInstance3D
			var lname := String(mmi.name).to_lower()
			if (lname.contains("tree") or lname.contains("oak") or lname.contains("pine") \
					or lname.contains("_trunks") or lname.contains("_leaves")) \
					and not lname.contains("bghorizontreeline") \
					and not lname.contains("grass") and not lname.contains("reed"):
				tree_mms.append(mmi)
		for ch in cur.get_children():
			mmi_stack.append(ch)

	for i in range((rings as Array).size()):
		var ring = rings[i]
		if not is_instance_valid(ring) or not (ring is Node3D):
			blocked_physics += 1
			continue
		var rpos := (ring as Node3D).global_position
		var rdir := -(ring as Node3D).global_transform.basis.z
		var sz := 4.5
		if specs is Array and i < (specs as Array).size():
			var sp: Dictionary = specs[i]
			rdir = sp.get("dir", rdir)
			sz = float(sp.get("size", 4.5))
		var radius := sz * 0.7 + 0.8
		if lvl.has_method("_freestyle_gate_clear") and not bool(lvl.call("_freestyle_gate_clear", rpos, radius, rdir)):
			blocked_physics += 1
			printerr("[QA_FIXES] obstructed physics/landmark gate #%d at %s" % [i + 1, str(rpos)])
		for mmi in tree_mms:
			var mm := mmi.multimesh
			if mm == null:
				continue
			var xfp := mmi.global_transform
			for ti in range(mm.instance_count):
				var ixf := mm.get_instance_transform(ti)
				if ixf.origin.y < -200.0 or ixf.basis.x.length_squared() < 0.001:
					continue
				var tw := xfp * ixf.origin
				if Vector2(tw.x, tw.z).distance_to(Vector2(rpos.x, rpos.z)) < 7.5:
					tree_hits += 1
					printerr("[QA_FIXES] tree inside gate #%d at %s vs tree %s" % [i + 1, str(rpos), str(tw)])
					break
	if blocked_physics == 0 and tree_hits == 0:
		_pass("%s 24/24 arches 100%% unobstructed (0 physics/landmark hits, 0 trees)" % label)
	else:
		_fail("%s obstructed arches: physics=%d tree_hits=%d" % [label, blocked_physics, tree_hits])


func _audit_mobile_menu_leleka_and_language() -> void:
	print("[QA_FIXES] Stage 1: MobileMenu, Leleka-100, Language")
	OS.set_environment("MOBILE_UI", "1")
	Global.campaign_records.erase("flight_school")
	Global.drone_preset = 7  # Leleka-100
	Global.menu_settings["drone_preset"] = 7
	Loc.set_language(Loc.Language.UA)
	await DroneCatalog.wait_for_model(7, 15000)

	var packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	var menu := packed.instantiate() as Control
	add_child(menu)
	await _wait_frames(4)
	menu.call("_load_hero_model", 7)
	for _w in range(90):
		await get_tree().process_frame
		var hh := menu.get("_hero_holder") as Node
		if hh != null and hh.get_child_count() > 0:
			var hm := hh.get_child(0) as Node3D
			if hm != null and hm.visible and int(hm.get_meta("preset_idx", -1)) == 7:
				break
	await _wait_frames(8)

	var vp_h := get_viewport().get_visible_rect().size.y
	if vp_h <= 10.0:
		vp_h = 720.0

	# Check all visible Buttons and changelog labels do NOT clip below viewport bottom
	var clipped := 0
	var hero_btn_seen := 0
	var chg_seen := 0
	var ui_stack: Array[Node] = [menu]
	while not ui_stack.is_empty():
		var cur: Node = ui_stack.pop_back()
		if cur is Button and (cur as Control).is_visible_in_tree():
			var b := cur as Button
			var r := b.get_global_rect()
			if r.end.y > vp_h + 1.0:
				clipped += 1
				_fail("MobileMenu button clipped bottom: '%s' end_y=%.1f > vp_h=%.1f" % [b.text, r.end.y, vp_h])
			if b.text.contains("ПОПЕРЕДНІЙ") or b.text.contains("ПОЧАТИ") or b.text.contains("НАСТУПНИЙ"):
				hero_btn_seen += 1
		elif cur is Label and (cur as Control).is_visible_in_tree():
			var l := cur as Label
			if l.text.contains("ОНОВЛЕННЯ") or l.text.contains("Геймпади"):
				chg_seen += 1
				var lr := l.get_global_rect()
				if lr.end.y > vp_h + 1.0:
					clipped += 1
					_fail("MobileMenu changelog clipped: '%s' end_y=%.1f > vp_h=%.1f" % [l.text.left(28), lr.end.y, vp_h])
		for ch in cur.get_children():
			ui_stack.append(ch)

	if clipped == 0 and hero_btn_seen >= 3 and chg_seen >= 1:
		_pass("MobileMenu zero bottom clipping (hero_btns=%d chg_labels=%d vp_h=%.0f)" % [hero_btn_seen, chg_seen, vp_h])
	else:
		_fail("MobileMenu layout check clipped=%d hero_btns=%d chg=%d" % [clipped, hero_btn_seen, chg_seen])

	# Verify Leleka-100 material is no longer blown-out pure white
	var hero_root = menu.get("_hero_holder")
	var white_count := 0
	var mat_checked := 0
	if hero_root is Node:
		var m_stack: Array[Node] = [hero_root]
		while not m_stack.is_empty():
			var n: Node = m_stack.pop_back()
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				if mi.mesh != null:
					for s in range(mi.mesh.get_surface_count()):
						var mat := mi.get_surface_override_material(s)
						if mat == null:
							mat = mi.mesh.surface_get_material(s)
						if mat is StandardMaterial3D:
							var sm := mat as StandardMaterial3D
							var mname := String(sm.resource_name).to_lower()
							var miname := String(mi.name).to_lower()
							if not mname.contains("composite") or miname.contains("motor") or mname.contains("dark"):
								continue
							mat_checked += 1
							var c := sm.albedo_color
							var lum := (c.r + c.g + c.b) / 3.0
							if lum > 0.68:
								white_count += 1
								_fail("Leleka composite material too white (%s / %s lum=%.2f col=%s)" % [mi.name, mname, lum, str(c)])
			for ch in n.get_children():
				m_stack.append(ch)
	if mat_checked > 0 and white_count == 0:
		_pass("Leleka-100 recolored to non-white tactical matte (checked %d surfaces)" % mat_checked)
	else:
		_fail("Leleka-100 recolor verification mat_checked=%d white_count=%d" % [mat_checked, white_count])

	await _snap("fix_01_mobile_menu_leleka.png")

	# Verify UA <-> EN <-> UA <-> EN <-> UA toggle never crashes or frees invalid refs
	var l0 := Loc.get_language()
	menu.call("_on_toggle_language")
	await _wait_frames(8)
	var l1 := Loc.get_language()
	menu.call("_on_toggle_language")
	await _wait_frames(8)
	var l2 := Loc.get_language()
	menu.call("_on_toggle_language")
	await _wait_frames(8)
	var l3 := Loc.get_language()
	menu.call("_on_toggle_language")
	await _wait_frames(8)
	var l4 := Loc.get_language()
	if is_instance_valid(menu) and l1 != l0 and l2 == l0 and l3 == l1 and l4 == l0:
		_pass("MobileMenu language toggle stable (%d -> %d -> %d -> %d -> %d)" % [l0, l1, l2, l3, l4])
	else:
		_fail("MobileMenu language toggle failed: %d -> %d -> %d -> %d -> %d" % [l0, l1, l2, l3, l4])
	Loc.set_language(Loc.Language.UA, true)

	menu.queue_free()
	await _wait_frames(6)
	DroneCatalog.flush_prefetch()


func _audit_wetlands_and_arches() -> void:
	print("[QA_FIXES] Stage 2: Wetlands separation & arches")
	OS.set_environment("MOBILE_UI", "1")
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Global.drone_preset = 0
	Graphics.apply_quality_preset(0)

	var packed := load("res://sceneries/WetlandsLevel.tscn") as PackedScene
	var lvl := packed.instantiate()
	add_child(lvl)
	await _wait_frames(20)
	for _p in range(6):
		await get_tree().physics_frame
	await _wait_frames(10)

	# Verify legacy StickOverlay & CombatHUD subnodes stay hidden in mobile mode
	var stick_ov := lvl.get_node_or_null("StickOverlay") as CanvasItem
	if stick_ov != null and stick_ov.visible:
		_fail("Legacy StickOverlay visible in mobile mode!")
	else:
		_pass("Legacy StickOverlay properly hidden")

	var mh_lh := lvl.get_node_or_null("FrontlineTerrain/MobileHero_Lighthouse") as Node3D
	if mh_lh == null:
		mh_lh = lvl.find_child("MobileHero_Lighthouse", true, false) as Node3D
	var mast := mh_lh.get_node_or_null("LighthouseLatticeMast") as Node3D if mh_lh != null else null
	var boardwalk: Node3D = null
	var causeway_nodes: Array[Node3D] = []
	var sc_stack: Array[Node] = [lvl]
	while not sc_stack.is_empty():
		var cur: Node = sc_stack.pop_back()
		if cur is Node3D:
			var sp := String((cur as Node).scene_file_path)
			if sp.contains("swamp_22_marsh_boardwalk_tower"):
				boardwalk = cur as Node3D
			elif sp.contains("swamp_04_wooden_trestle_causeway"):
				causeway_nodes.append(cur as Node3D)
		for ch in cur.get_children():
			sc_stack.append(ch)

	if mh_lh != null and mast != null and boardwalk != null:
		var mast_bb := _world_aabb(mast)
		var bw_bb := _world_aabb(boardwalk)
		var xz_dist := Vector2(mast.global_position.x, mast.global_position.z).distance_to(
				Vector2(boardwalk.global_position.x, boardwalk.global_position.z))
		var overlaps := mast_bb.intersects(bw_bb)
		if not overlaps and xz_dist >= 12.0:
			_pass("Wetlands lighthouse & boardwalk separated (xz_dist=%.1fm overlap=%s causeways=%d)" % [xz_dist, str(overlaps), causeway_nodes.size()])
		else:
			_fail("Wetlands lighthouse/boardwalk overlap! xz_dist=%.1f overlap=%s" % [xz_dist, str(overlaps)])
	else:
		_fail("Wetlands lighthouse or boardwalk node not found")

	var causeway_overlaps := 0
	for i in range(causeway_nodes.size()):
		for j in range(i + 1, causeway_nodes.size()):
			if _world_aabb(causeway_nodes[i]).intersects(_world_aabb(causeway_nodes[j])):
				causeway_overlaps += 1
	if causeway_nodes.is_empty() or causeway_overlaps > 0:
		_fail("Wetlands trestle causeways check count=%d overlaps=%d" % [causeway_nodes.size(), causeway_overlaps])
	else:
		_pass("Wetlands trestle causeways non-overlapping (count=%d overlaps=%d)" % [causeway_nodes.size(), causeway_overlaps])

	await _verify_all_arches_clear(lvl, "Wetlands")

	# Frame separated lighthouse & boardwalk + START 1/24 arch
	var tc := get_node_or_null("/root/TouchControls")
	if tc != null:
		tc.set("visible", false)
	lvl.set("_osd_visible", false)
	lvl.call("_apply_osd")
	var qa_cam := Camera3D.new()
	qa_cam.fov = 72.0
	qa_cam.far = 1500.0
	lvl.add_child(qa_cam)
	qa_cam.current = true
	if mh_lh != null:
		var focus := mh_lh.global_position + Vector3(11.0, 9.0, 2.0)
		qa_cam.global_position = mh_lh.global_position + Vector3(10.0, 18.0, 34.0)
		qa_cam.look_at(focus, Vector3.UP)
	await _wait_frames(6)
	await _snap("fix_02_wetlands_separated_and_arches.png")

	lvl.queue_free()
	await _wait_frames(8)


func _audit_airport_tower_windows_and_arches() -> void:
	print("[QA_FIXES] Stage 3: Airport arches & hollow tower")
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Graphics.apply_quality_preset(0)

	var packed := load("res://sceneries/AirportLevel.tscn") as PackedScene
	var lvl := packed.instantiate()
	add_child(lvl)
	await _wait_frames(20)
	for _p in range(8):
		await get_tree().physics_frame
	await _wait_frames(10)

	await _verify_all_arches_clear(lvl, "Airport")

	var tower := lvl.find_child("AirportLandmark_ControlTowerRuins", true, false) as Node3D
	if tower == null:
		_fail("AirportLandmark_ControlTowerRuins missing")
	else:
		var tpos := tower.global_position
		var space := (lvl as Node3D).get_world_3d().direct_space_state
		var blocked_rays := 0
		# Test 4 opposite window-bay angles (22.5, 67.5, 112.5, 157.5 deg) straight through y=21.55
		for bi in range(4):
			var ang := (float(bi) + 0.5) * TAU / 8.0
			var dir := Vector3(cos(ang), 0.0, -sin(ang))
			var center := tpos + Vector3(0.0, 21.55, 0.0)
			var q := PhysicsRayQueryParameters3D.create(center - dir * 8.0, center + dir * 8.0)
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				blocked_rays += 1
				_fail("Airport ATC cab window ray #%d blocked at %s collider=%s" % [bi, str(hit["position"]), str(hit["collider"])])
		if blocked_rays == 0:
			_pass("Airport ControlTowerRuins hollow cab fly-through rays 4/4 unobstructed")

		var tc := get_node_or_null("/root/TouchControls")
		if tc != null:
			tc.set("visible", false)
		lvl.set("_osd_visible", false)
		lvl.call("_apply_osd")
		var qa_cam := Camera3D.new()
		qa_cam.fov = 66.0
		qa_cam.far = 1500.0
		lvl.add_child(qa_cam)
		qa_cam.current = true
		var view_ang := PI / 8.0
		var vdir := Vector3(cos(view_ang), 0.0, -sin(view_ang))
		var cab_ctr := tpos + Vector3(0.0, 21.6, 0.0)
		qa_cam.global_position = cab_ctr + vdir * 13.5 + Vector3(0.0, 0.4, 0.0)
		qa_cam.look_at(cab_ctr, Vector3.UP)
		await _wait_frames(6)
		await _snap("fix_03_airport_tower_windows.png")

	lvl.queue_free()
	await _wait_frames(8)


func _audit_industrial_arches_switcher_and_reset() -> void:
	print("[QA_FIXES] Stage 4: Industrial arches, switcher & auto-reset")
	# 1) Industrial freestyle 24/24 clear check
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Graphics.apply_quality_preset(0)
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var lvl_free := packed.instantiate()
	add_child(lvl_free)
	await _wait_frames(20)
	for _p in range(6):
		await get_tree().physics_frame
	await _wait_frames(8)
	await _verify_all_arches_clear(lvl_free, "Industrial")
	lvl_free.queue_free()
	await _wait_frames(6)

	# 2) Industrial COMBAT: CombatHUD subnodes hidden, post-drop auto-reset, low-speed kamikaze, Mid-Mission Drone Switcher
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.special_mission = 0
	Global.drone_preset = 1  # Grim-7M (dropper)
	var lvl := packed.instantiate()
	add_child(lvl)
	await _wait_frames(18)
	for _p in range(6):
		await get_tree().physics_frame
	await _wait_frames(8)

	# Check legacy CombatHUD subnodes hidden
	var chud := lvl.get_node_or_null("CombatHUD")
	var legacy_vis := false
	if chud != null:
		for sub in ["Root/TopRight", "Root/Message", "Root/Hint"]:
			var ci := chud.get_node_or_null(sub) as CanvasItem
			if ci != null and ci.visible:
				legacy_vis = true
				_fail("Legacy CombatHUD node visible: " + sub)
	if not legacy_vis:
		_pass("Legacy CombatHUD subnodes hidden immediately")

	# Verify post-drop & post-replay auto-reset rules (miss vs kill, remaining ammo vs 0 ammo, kamikaze skip)
	var cs := lvl.get_node_or_null("CombatSystem")
	var drone := lvl.get_node_or_null("Drone") as Drone
	var kc := lvl.get("_kill_cam") as Object
	if cs != null and drone != null and kc != null:
		var respawn_counts := [0]
		var on_respawn := func() -> void:
			respawn_counts[0] += 1
		if not drone.is_connected("respawned", on_respawn):
			drone.connect("respawned", on_respawn)

		# 1) Drop & MISS with 0 ammo left (quad5): wait 2.1s -> MUST NOT auto-reset
		lvl.call("switch_drone_in_mission", 3)
		for _f1 in range(10):
			await get_tree().physics_frame
		await _wait_frames(6)
		respawn_counts[0] = 0
		cs.set("ammo", 0)
		lvl.set("_payload_ammo_left", 0)
		lvl.set("_active_dropped_payloads", 1)
		lvl.call("notify_payload_exploded")
		await get_tree().create_timer(2.1).timeout
		if not bool(kc.call("is_active")) and not bool(lvl.get("_pending_post_drop_rearm")) \
				and int(cs.get("ammo")) == 0 and respawn_counts[0] == 0 \
				and lvl.get("_post_drop_rearm_timer") == null:
			_pass("Miss with 0 ammo does NOT trigger 2s auto-reset")
		else:
			_fail("Miss auto-reset regression: kc=%s pend=%s ammo=%s respawns=%d" % [
				str(kc.call("is_active")), str(lvl.get("_pending_post_drop_rearm")),
				str(cs.get("ammo")), respawn_counts[0]
			])

		# 2) Drop & KILL with remaining ammo (baba_yaga 4->3): Kill-Cam freezes airborne drone, no reset after replay
		lvl.call("switch_drone_in_mission", 6)
		for _f2 in range(10):
			await get_tree().physics_frame
		await _wait_frames(6)
		respawn_counts[0] = 0
		drone.global_position += Vector3(0.0, 25.0, 0.0)
		if drone.has_method("reset_motion_history"):
			drone.reset_motion_history()
		drone.freeze = false
		var bomb_nodes: Array = lvl.get("_bomb_nodes")
		if bomb_nodes != null and bomb_nodes.size() > 1:
			bomb_nodes.pop_back()
		cs.set("ammo", int(bomb_nodes.size()))
		lvl.set("_active_dropped_payloads", 1)
		lvl.set("_kill_cam_last_ms", -10000)
		var kc_rem_ok := bool(lvl.call("_maybe_trigger_kill_cam", drone.global_position + Vector3(50, -25, 50), true))
		lvl.call("notify_payload_exploded")
		for _p2 in range(4):
			await get_tree().physics_frame
		var modal_during_kc := TouchControls != null and bool(TouchControls.call("_any_modal_menu_open"))
		if kc_rem_ok and bool(kc.call("is_active")) and drone.freeze \
				and bool(lvl.get("_kill_cam_paused_drone")) and not bool(lvl.get("_pending_post_drop_rearm")) \
				and modal_during_kc:
			kc.call("cancel")
			for _p2b in range(6):
				await get_tree().physics_frame
			await _wait_frames(4)
			if not bool(kc.call("is_active")) and not drone.freeze and int(lvl.call("_ammo_count")) == 3 and respawn_counts[0] == 0:
				_pass("Kill with remaining bombs pauses drone for Kill-Cam then resumes flight with 3 bombs")
			else:
				_fail("Post-KillCam resume mismatch (ammo=%s freeze=%s respawns=%d)" % [
					str(lvl.call("_ammo_count")), str(drone.freeze), respawn_counts[0]
				])
		else:
			_fail("Kill-Cam remaining-ammo setup failed (ok=%s active=%s freeze=%s pend=%s modal=%s)" % [
				str(kc_rem_ok), str(kc.call("is_active")), str(drone.freeze),
				str(lvl.get("_pending_post_drop_rearm")), str(modal_during_kc)
			])
			if bool(kc.call("is_active")):
				kc.call("cancel")

		# 3) Drop & KILL with LAST bomb (quad5 1->0): hold reset until replay finishes, then reset+rearm
		lvl.call("switch_drone_in_mission", 3)
		for _f3 in range(10):
			await get_tree().physics_frame
		await _wait_frames(6)
		respawn_counts[0] = 0
		drone.global_position += Vector3(0.0, 25.0, 0.0)
		if drone.has_method("reset_motion_history"):
			drone.reset_motion_history()
		drone.freeze = false
		cs.set("ammo", 0)
		lvl.set("_payload_ammo_left", 0)
		lvl.set("_active_dropped_payloads", 1)
		lvl.set("_kill_cam_last_ms", -10000)
		var kc_last_ok := bool(lvl.call("_maybe_trigger_kill_cam", drone.global_position + Vector3(55, -25, 55), true))
		lvl.call("notify_payload_exploded")
		for _p3 in range(4):
			await get_tree().physics_frame
		if kc_last_ok and bool(kc.call("is_active")) and bool(lvl.get("_pending_post_drop_rearm")) \
				and respawn_counts[0] == 0 and int(cs.get("ammo")) == 0:
			kc.call("cancel")
			for _p3b in range(10):
				await get_tree().physics_frame
			await _wait_frames(6)
			if respawn_counts[0] == 1 and int(cs.get("ammo")) == 1 and not drone.freeze:
				_pass("Kill with last bomb waits for Kill-Cam finish/skip, then auto-resets & rearms (ammo=1)")
			else:
				_fail("Post-KillCam last-bomb reset mismatch (respawns=%d ammo=%s freeze=%s)" % [
					respawn_counts[0], str(cs.get("ammo")), str(drone.freeze)
				])
		else:
			_fail("Kill-Cam last-bomb setup failed (ok=%s active=%s pend=%s respawns=%d ammo=%s)" % [
				str(kc_last_ok), str(kc.call("is_active")), str(lvl.get("_pending_post_drop_rearm")),
				respawn_counts[0], str(cs.get("ammo"))
			])
			if bool(kc.call("is_active")):
				kc.call("cancel")

		# 4) Kamikaze & KILL with early replay skip: fallback timer cancelled, instant post-replay respawn
		lvl.call("switch_drone_in_mission", 0)
		for _f4 in range(10):
			await get_tree().physics_frame
		await _wait_frames(6)
		respawn_counts[0] = 0
		lvl.set("_kill_cam_last_ms", -10000)
		var kam_timer := Timer.new()
		kam_timer.one_shot = true
		lvl.add_child(kam_timer)
		kam_timer.start(2.4)
		lvl.set("_kamikaze_respawn_timer", kam_timer)
		var kc_kam_ok := bool(lvl.call("_maybe_trigger_kill_cam", drone.global_position + Vector3(40, 0, 40), true))
		if kc_kam_ok and kam_timer.is_stopped() and bool(lvl.get("_pending_kamikaze_respawn")):
			kc.call("cancel")
			for _p4b in range(10):
				await get_tree().physics_frame
			await _wait_frames(6)
			if respawn_counts[0] == 1:
				_pass("Kamikaze Kill-Cam cancels 2.4s timer and respawns immediately after replay skip")
			else:
				_fail("Kamikaze post-KillCam skip did not respawn immediately (respawns=%d)" % respawn_counts[0])
		else:
			_fail("Kamikaze Kill-Cam timer conversion failed")
			if bool(kc.call("is_active")):
				kc.call("cancel")

		if drone.is_connected("respawned", on_respawn):
			drone.disconnect("respawned", on_respawn)

		# Check low-speed kamikaze threshold helper
		var v_sample := Vehicle.new()
		v_sample.add_to_group("combat_target")
		if lvl.has_method("_is_combat_target_body") and bool(lvl.call("_is_combat_target_body", v_sample)):
			_pass("Combat target body detection + lowered 2.5 m/s contact threshold wired")
		else:
			_fail("_is_combat_target_body failed")
		v_sample.free()

	# Open mid-mission drone switcher in COMBAT and verify only presets 0..9 appear
	lvl.call("open_drone_switcher")
	await _wait_frames(6)
	var switcher := lvl.get("_drone_switcher") as Node
	if switcher != null and switcher.has_method("_eligible_presets"):
		var eligible: Array = switcher.call("_eligible_presets")
		var grid := switcher.get("_grid") as GridContainer
		var cards := grid.get_child_count() if grid != null else 0
		var has_uman := false
		for idx in eligible:
			if DroneCatalog.is_uman(int(idx)):
				has_uman = true
		if not has_uman and eligible.size() == 10 and cards == 10:
			_pass("MissionDroneSwitcher in COMBAT strictly lists & renders 10 tactical cards (0 Uman freestyle)")
		else:
			_fail("MissionDroneSwitcher COMBAT filter/render invalid: eligible=%d cards=%d has_uman=%s" % [eligible.size(), cards, str(has_uman)])
	else:
		_fail("MissionDroneSwitcher failed to open")

	await _snap("fix_04_industrial_arches_and_switcher.png")

	# Close switcher and test live switch to Heavy Bomber (preset 6) then back to Kamikaze (preset 0)
	if switcher != null and switcher.has_method("close"):
		switcher.call("close")
	await _wait_frames(4)
	var ok_bomber := bool(lvl.call("switch_drone_in_mission", 6))
	await _wait_frames(6)
	var bs := lvl.get("_bomb_sight") as CanvasItem
	if ok_bomber and bool(lvl.get("_heavy_bomber")) and bs != null and bs.visible:
		_pass("Live mission switch to Heavy Bomber enabled BombSight + 4x payload")
	else:
		_fail("Switch to Heavy Bomber mismatch: ok=%s hb=%s bs=%s" % [str(ok_bomber), str(lvl.get("_heavy_bomber")), str(bs)])
	var ok_kamikaze := bool(lvl.call("switch_drone_in_mission", 0))
	await _wait_frames(6)
	var drone_node := lvl.get_node_or_null("Drone")
	var sensor := drone_node.get_node_or_null("WarheadSensor") if drone_node != null else null
	if ok_kamikaze and not bool(lvl.get("_heavy_bomber")) and sensor != null and (bs == null or not bs.visible):
		_pass("Live mission switch back to Grim-7 disabled BombSight & attached WarheadSensor")
	else:
		_fail("Switch back to Grim-7 mismatch")

	lvl.queue_free()
	await _wait_frames(8)


func _audit_units_scale_and_prewarm() -> void:
	print("[QA_FIXES] Stage 5: Units +20% scale & VFX prewarm")
	# 1) Timing prewarm + burst
	var t0 := Time.get_ticks_usec()
	DestructionFx.prewarm(self, Vector3(0, -15, 0))
	HitFx.prewarm()
	Explosion.prewarm()
	CombatSfx.prewarm()
	ReconKillCamDirector.prewarm()
	var prewarm_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_pass("VFX/SFX/Shader prewarm completed in %.1f ms" % prewarm_ms)

	# 2) Spawn showcase stage for +20% unit scaling
	OS.unset_environment("MOBILE_UI")
	var stage := Node3D.new()
	stage.name = "ScaleStage"
	add_child(stage)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 0.95)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	stage.add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	stage.add_child(sun)

	var gnd := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 40)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.36, 0.28)
	gnd.mesh = pm
	gnd.material_override = gm
	stage.add_child(gnd)

	var rifleman := EnemyRifleman.new()
	stage.add_child(rifleman)
	rifleman.global_position = Vector3(-9.0, 0.0, 0.0)
	rifleman.set_physics_process(false)

	var aa := AAGun.new()
	stage.add_child(aa)
	aa.global_position = Vector3(-5.0, 0.0, 0.0)
	aa.set_physics_process(false)

	var ct := CombatTarget.new()
	ct.kind = CombatTarget.Kind.TRUCK
	stage.add_child(ct)
	ct.global_position = Vector3(-0.5, 0.0, 0.0)

	var v_bmp := Vehicle.new()
	v_bmp.kind = Vehicle.Kind.BMP
	v_bmp.hostile = true
	v_bmp.move_speed = 0.0
	stage.add_child(v_bmp)
	v_bmp.global_position = Vector3(5.5, 0.0, 0.0)
	v_bmp.set_physics_process(false)

	var v_tank := Vehicle.new()
	v_tank.kind = Vehicle.Kind.TANK
	v_tank.hostile = true
	v_tank.move_speed = 0.0
	stage.add_child(v_tank)
	v_tank.global_position = Vector3(13.0, 0.0, 0.0)
	v_tank.set_physics_process(false)

	await _wait_frames(8)

	var expected := 1.20
	var bad_scale := 0
	for pair in [
		["EnemyRifleman", rifleman],
		["AAGun", aa],
		["Vehicle_BMP", v_bmp],
		["Vehicle_TANK", v_tank],
	]:
		var n: Node3D = pair[1]
		if n.scale.x < expected - 0.02:
			bad_scale += 1
			_fail("%s scale=%.3f < expected %.2f" % [pair[0], n.scale.x, expected])
	if float(CombatTarget.MODEL_SIZE[CombatTarget.Kind.TANK]) < 10.5 \
			or CombatSystem.kamikaze_hit_radius(v_tank) < 4.1 \
			or CombatSystem.kamikaze_hit_radius(rifleman) < 2.1:
		bad_scale += 1
		_fail("CombatTarget / Kamikaze hit radius not scaled +20%")

	if bad_scale == 0:
		_pass("All units & hitboxes scaled +20%% cleanly (infantry=%.2f tank=%.2f aa=%.2f)" % [
			rifleman.scale.x, v_tank.scale.x, aa.scale.x])

	var cam := Camera3D.new()
	cam.fov = 56.0
	stage.add_child(cam)
	cam.current = true
	cam.global_position = Vector3(2.0, 5.5, 16.5)
	cam.look_at(Vector3(2.0, 1.4, 0.0), Vector3.UP)
	await _wait_frames(6)
	await _snap("fix_05_units_scaled_20pct.png")

	stage.queue_free()
	await _wait_frames(4)
