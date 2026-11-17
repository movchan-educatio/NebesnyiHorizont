extends Node

const FRONT_TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const OPEN_TOWER := preload("res://scripts/util/open_tower.gd")
const COMBAT_SFX := preload("res://combat/sfx.gd")
const RECON_KILL_CAM := preload("res://scripts/combat/recon_kill_cam.gd")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, item: String, detail: String = "") -> void:
	var tag := "PASS" if ok else "FAIL"
	if detail.is_empty():
		print("[QA20] ", tag, " ", item)
	else:
		print("[QA20] ", tag, " ", item, " :: ", detail)
	if not ok:
		_failures += 1


func _collect_strings(node: Node, out: Array[String]) -> void:
	if node == null:
		return
	if node is Button:
		out.append(String((node as Button).text))
	elif node is Label:
		out.append(String((node as Label).text))
	elif node is RichTextLabel:
		out.append(String((node as RichTextLabel).text))
	for child in node.get_children():
		_collect_strings(child, out)


func _run() -> void:
	var had_mobile := OS.has_environment("MOBILE_UI")
	var old_mobile := OS.get_environment("MOBILE_UI")
	var had_norec := OS.has_environment("DRONE_NO_RECORD")
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("DRONE_NO_RECORD", "1")
	await get_tree().process_frame

	# #1: HIGH graphics preset keeps 2D MSAA & FXAA off on mobile/iOS.
	var old_preset: int = int(Graphics.graphics_settings.get("quality_preset", 0))
	Graphics.apply_quality_preset(Graphics.QualityPreset.HIGH)
	await get_tree().process_frame
	var vp := get_viewport()
	_check(vp.msaa_2d == Viewport.MSAA_DISABLED and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED,
			"#1 HIGH preset keeps 2D MSAA/FXAA off on mobile",
			"msaa_2d=%d ssaa=%d" % [vp.msaa_2d, vp.screen_space_aa])
	var q_high: Dictionary = QualityManager.params()
	_check(int(q_high.get("msaa", -1)) == Viewport.MSAA_DISABLED and not bool(q_high.get("fxaa", true)),
			"#1 QualityManager HIGH mobile override disables msaa/fxaa")
	Graphics.apply_quality_preset(old_preset)

	# #3 & #6 (MobileMenu + MenuIcons + Touch settings UI):
	var menu := (load("res://GUI/mobile/MobileMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu_texts: Array[String] = []
	_collect_strings(menu, menu_texts)
	var has_bad_glyph := false
	for t in menu_texts:
		if t.contains("\u22EF") or t.contains("🏆"):
			has_bad_glyph = true
	var gc_top := menu.get_node_or_null("GcTopButton") as Button
	if gc_top == null:
		for b in menu.find_children("*", "Button", true, false):
			var btn := b as Button
			if btn.icon != null and (btn.text == "GC" or btn.text.contains("РЕКОРД")):
				gc_top = btn
				break
	_check(not has_bad_glyph and gc_top != null and gc_top.icon != null,
			"#3 MobileMenu uses procedural icons with no unsupported trophy/ellipsis glyphs")
	_check(menu.find_child("SettingsSimFloatToggle", true, false) != null \
			or Global.menu_settings.has("touch_floating_sticks"),
			"#6 Global & MobileMenu expose touch_floating_sticks/spring/sensitivity/expo")
	menu.queue_free()
	await get_tree().process_frame

	# #3 & #6 (TouchControls drawer & curves):
	TouchControls.begin(get_instance_id())
	TouchControls.refresh_touch_settings()
	await get_tree().process_frame
	var more_btn: Button = TouchControls.get("_more_button")
	var more_panel: Control = TouchControls.get("_more_panel")
	_check(more_btn != null and more_btn.icon != null and not more_btn.text.contains("\u22EF"),
			"#3 TouchControls More button renders procedural 3-dot icon")
	var has_drawer_controls := false
	if more_panel != null:
		var p_texts: Array[String] = []
		_collect_strings(more_panel, p_texts)
		var joined := "|".join(p_texts)
		has_drawer_controls = joined.contains("ПЛАВ") and joined.contains("ГАЗ:") \
				and (joined.contains("КАМЕРА") or joined.contains("PITCH")) \
				and (joined.contains("ANGLE") or joined.contains("РЕЖИМ"))
	_check(has_drawer_controls, "#6 TouchControls drawer exposes floating, spring, tilt, mode buttons")
	Global.menu_settings["touch_sensitivity"] = 1.25
	Global.menu_settings["touch_expo"] = 0.35
	TouchControls.refresh_touch_settings()
	var curved := float(TouchControls.call("_apply_axis_curve", 0.5, 0.02, true))
	_check(curved > 0.25 and curved < 0.70, "#6 TouchControls sensitivity/expo curve responds smoothly",
			"0.5->%.3f" % curved)
	Global.menu_settings["touch_sensitivity"] = 1.0
	Global.menu_settings["touch_expo"] = 0.2
	TouchControls.end(get_instance_id())

	# #4: MountainBackdrop vertices outside arena / HorizonRing >= 900m
	var m_root := Node3D.new()
	add_child(m_root)
	FRONT_TERRAIN._build_mountain_backdrop(m_root, "industrial")
	var min_r := 99999.0
	var v_count := 0
	for mi in m_root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m != null and m.get_surface_count() > 0:
			var arr := m.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in verts:
				v_count += 1
				var r := Vector2(v.x, v.z).length()
				min_r = minf(min_r, r)
	_check(v_count > 0 and min_r >= 900.0,
			"#4 MountainBackdrop keeps every vertex >= 900m outside arena",
			"verts=%d min_r=%.1fm" % [v_count, min_r])
	m_root.queue_free()

	# #5: OpenTower outward & inward winding matches Godot CW convention & safe material
	var prof: Array[Vector2] = [Vector2(8.0, 0.0), Vector2(6.5, 10.0), Vector2(7.0, 18.0)]
	var t_root := Node3D.new()
	add_child(t_root)
	var test_mat := StandardMaterial3D.new()
	test_mat.metallic = 0.9
	test_mat.roughness = 0.2
	var tower_mi := OPEN_TOWER.build_profile(t_root, Vector3.ZERO, prof, 0.6, test_mat, test_mat, {}, 16)
	var tower_mesh := tower_mi.mesh as ArrayMesh
	var box_mesh := BoxMesh.new()
	var b_arr := box_mesh.get_mesh_arrays()
	var bv: PackedVector3Array = b_arr[Mesh.ARRAY_VERTEX]
	var bn: PackedVector3Array = b_arr[Mesh.ARRAY_NORMAL]
	var bi: PackedInt32Array = b_arr[Mesh.ARRAY_INDEX]
	var box_sign := (bv[bi[1]] - bv[bi[0]]).cross(bv[bi[2]] - bv[bi[0]]).dot(bn[bi[0]])
	var wrong_tris := 0
	var total_tris := 0
	for s_idx in range(tower_mesh.get_surface_count()):
		var sarr := tower_mesh.surface_get_arrays(s_idx)
		var sv: PackedVector3Array = sarr[Mesh.ARRAY_VERTEX]
		var sn: PackedVector3Array = sarr[Mesh.ARRAY_NORMAL]
		var si: PackedInt32Array = sarr[Mesh.ARRAY_INDEX]
		for t in range(0, si.size(), 3):
			total_tris += 1
			var i0 := si[t]
			var i1 := si[t + 1]
			var i2 := si[t + 2]
			var face_sign := (sv[i1] - sv[i0]).cross(sv[i2] - sv[i0]).dot(sn[i0])
			if face_sign * box_sign <= 0.0:
				wrong_tris += 1
	var safe_mat: Material = OPEN_TOWER._safe_tower_material(test_mat)
	t_root.queue_free()
	_check(total_tris > 0 and wrong_tris == 0 and safe_mat is StandardMaterial3D \
			and (safe_mat as StandardMaterial3D).metallic <= 0.15 \
			and (safe_mat as StandardMaterial3D).roughness >= 0.72,
			"#5 OpenTower winding matches BoxMesh CW & matte material clamp",
			"tris=%d wrong=%d metal=%.2f rough=%.2f" % [
				total_tris, wrong_tris,
				(safe_mat as StandardMaterial3D).metallic,
				(safe_mat as StandardMaterial3D).roughness])

	# #7: Radio WAV durations/rate + CombatSfx fallback cadence
	var wav_ok := true
	var wav_detail := ""
	for rid in ["01", "02", "03", "04"]:
		var fname: String = String(Audio.RADIO_LINE_FILES[rid])
		var stream: AudioStreamWAV = Audio._load_pcm16_wav(Audio.RADIO_DIR + fname)
		if stream == null:
			wav_ok = false
			wav_detail += rid + ":null "
		else:
			var dur := stream.get_length()
			wav_detail += "%s:%.2fs@%dHz " % [rid, dur, stream.mix_rate]
			if stream.mix_rate != 22050 or dur < 6.0 or dur > 12.0:
				wav_ok = false
	var sfx_radio := COMBAT_SFX.radio_stream()
	wav_ok = wav_ok and sfx_radio.get_length() >= 4.0
	_check(wav_ok, "#7 Radio WAVs 22050Hz (6..12s) & slow fallback cadence", wav_detail.strip_edges())

	# #11: FlightController ANGLE stays LEVEL past 50deg tilt & across arm/disarm/reset
	GameSettings.hud_config["angle_mode"] = true
	var drone := (load("res://drone/drones/Drone1.tscn") as PackedScene).instantiate() as Drone
	add_child(drone)
	await get_tree().process_frame
	var fc: FlightController = drone.flight_controller
	fc.select_flight_mode(FlightController.FlightMode.LEVEL)
	fc.request_arm(true)
	fc.angles = Vector3(deg_to_rad(68.0), 0.0, deg_to_rad(65.0))
	fc.integrate_loop(0.016, Vector3(0, 20, 0), Basis.from_euler(fc.angles), Vector3.ZERO, Vector3.ZERO)
	var stayed_angle := fc.flight_mode == FlightController.FlightMode.LEVEL
	fc.request_disarm()
	stayed_angle = stayed_angle and fc.flight_mode == FlightController.FlightMode.LEVEL
	fc.change_flight_mode(FlightController.FlightMode.AUTO)
	fc.request_arm(true)
	stayed_angle = stayed_angle and fc.flight_mode == FlightController.FlightMode.LEVEL
	fc.change_flight_mode(FlightController.FlightMode.AUTO)
	fc.reset()
	stayed_angle = stayed_angle and fc.flight_mode == FlightController.FlightMode.LEVEL
	_check(stayed_angle, "#11 ANGLE (LEVEL) never drops into AUTO/RATE at >50deg tilt or arm/disarm/reset")

	# #2: FlightSchool non-pausing on mobile, close button & card above bottom controls
	var fs_script := load("res://scripts/util/flight_school.gd")
	var fs: Node = fs_script.new()
	add_child(fs)
	var dummy_level := Node3D.new()
	add_child(dummy_level)
	fs.call("initialize", dummy_level, drone, 0.0)
	var fs_hud := CanvasLayer.new()
	add_child(fs_hud)
	fs.call("setup_hud", fs_hud)
	await get_tree().process_frame
	var panel_card: Control = fs.get("panel_card")
	var help_overlay: Control = fs.get("_help_overlay")
	var close_btn: Node = null
	if help_overlay != null:
		close_btn = help_overlay.find_child("StartFlightCloseBtn", true, false)
	var mobile_unpaused := not get_tree().paused and not help_overlay.visible
	fs.call("open_help")
	var opened_ok := help_overlay.visible
	fs.call("close_help")
	var closed_ok := not help_overlay.visible and not get_tree().paused
	_check(mobile_unpaused and opened_ok and closed_ok and close_btn != null \
			and panel_card != null and panel_card.offset_bottom <= 300.0,
			"#2 FlightSchool unblocked on mobile with top InstructorCard & touch close button",
			"paused=%s card_bottom=%.1f close_btn=%s" % [
				str(get_tree().paused),
				panel_card.offset_bottom if panel_card else -1.0,
				str(close_btn != null)])
	fs_hud.queue_free()
	fs.queue_free()
	dummy_level.queue_free()
	drone.queue_free()

	# #10 & #17: Explosion ground clod snap (no floating squares) + wind drift in Explosion/DestructionFx
	var wind_host := Node3D.new()
	var wind_script := GDScript.new()
	wind_script.source_code = "extends Node3D\nvar _current_wind_vector := Vector3(8.0, 0.0, -4.0)\nfunc _find_ground_y(_x: float, _z: float) -> float:\n\treturn 0.0\n"
	wind_script.reload()
	wind_host.set_script(wind_script)
	get_tree().root.add_child(wind_host)
	var prev_scene := get_tree().current_scene
	get_tree().current_scene = wind_host
	var exp_node := Explosion.new()
	wind_host.add_child(exp_node)
	exp_node.global_position = Vector3(0.0, 14.0, 0.0)
	exp_node.call("_spawn_crater")
	exp_node.call("_spawn_smoke")
	await get_tree().process_frame
	var floating_clods := 0
	var wind_drifted := false
	for c in wind_host.get_children():
		if c.name == "CraterDecal" and c.get_child_count() > 0:
			floating_clods += c.get_child_count()
		elif c.name == "CraterClods":
			for clod in c.get_children():
				if (clod as Node3D).global_position.y > 0.8:
					floating_clods += 1
	for gp in exp_node.find_children("*", "GPUParticles3D", true, false):
		var pmat2 := (gp as GPUParticles3D).process_material as ParticleProcessMaterial
		if pmat2 != null and pmat2.gravity.x > 0.5 and pmat2.gravity.z < -0.2:
			wind_drifted = true
	_check(floating_clods == 0, "#10 Airburst explosion leaves ZERO floating crater squares",
			"floating=%d" % floating_clods)
	_check(wind_drifted, "#17 Explosion/smoke particles inherit downwind drift")
	get_tree().current_scene = prev_scene
	wind_host.queue_free()

	# #12 & #13: BombSight clean bottom-left + single CCIP marker (CombatSystem hides 3D marker)
	var sight := BombSight.new()
	add_child(sight)
	await get_tree().process_frame
	_check(sight.is_in_group("bomb_sight"), "#12/#13 BombSight joins bomb_sight group")
	var cs := CombatSystem.new()
	add_child(cs)
	cs.call("_build_impact_marker")
	await get_tree().process_frame
	var impact_m: Variant = cs.get("_impact_marker")
	_check(bool(cs.call("_has_bomb_sight")) and (impact_m == null or not (impact_m as Node3D).visible),
			"#13 CombatSystem suppresses duplicate 3D impact marker when BombSight active")
	cs.queue_free()
	sight.queue_free()

	# #15, #16 & #18: Tracers, SAM/APC silhouettes & Haptics
	var target_dummy := (load("res://drone/drones/Drone1.tscn") as PackedScene).instantiate() as Drone
	target_dummy.position = Vector3(0, 12, -25)
	add_child(target_dummy)
	var aa := AAGun.new()
	aa.position = Vector3(-12, 0, 0)
	add_child(aa)
	aa.set("_drone", target_dummy)
	aa.set("_distance", 28.0)
	aa.call("_fire")
	var c_aa := get_tree().get_nodes_in_group("aa_tracer").size()
	var soldier := EnemyRifleman.new()
	soldier.position = Vector3(12, 0, 0)
	add_child(soldier)
	soldier.set("_drone", target_dummy)
	soldier.set("_distance", 28.0)
	soldier.call("_fire")
	var c_both := get_tree().get_nodes_in_group("aa_tracer").size()
	var tracers := get_tree().get_nodes_in_group("aa_tracer")
	var bright_tracer := c_aa >= 1 and c_both >= 2
	for tr in tracers:
		if float(tr.get("tracer_width")) < 1.6:
			bright_tracer = false
		tr.queue_free()
	_check(bright_tracer, "#15 AAGun & EnemyRifleman spawn high-visibility aa_tracer bolts",
			"c_aa=%d c_both=%d muzzle=%s" % [c_aa, c_both, str(soldier.get("_muzzle") != null)])
	aa.queue_free()
	soldier.queue_free()
	target_dummy.queue_free()
	var apc := Vehicle.new()
	apc.kind = Vehicle.Kind.APC
	add_child(apc)
	var sam := Vehicle.new()
	sam.kind = Vehicle.Kind.SAM
	add_child(sam)
	await get_tree().process_frame
	_check(apc.find_child("*Wheel*", true, false) != null or apc.get_child_count() > 2,
			"#16 APC silhouette built")
	_check(sam.find_child("*Radar*", true, false) != null or sam.get_child_count() > 2,
			"#16 SAM radar mast silhouette built")
	Haptics.pulse(30, 0.4, "qa20_test")
	_check(int(Haptics._stats.get("total_pulses", 0)) >= 1,
			"#18 Haptics service records tactical pulses cleanly")
	var hm_stream := COMBAT_SFX.hitmarker_stream()
	_check(hm_stream != null and hm_stream.get_length() > 0.04,
			"#19 Hitmarker WAV stream synthesized cleanly")
	apc.queue_free()
	sam.queue_free()

	# #19: ReconKillCamDirector initial 150ms static signal loss phase
	var cam_host := Node3D.new()
	add_child(cam_host)
	var kcam := RECON_KILL_CAM.new()
	cam_host.add_child(kcam)
	kcam.call("trigger", cam_host, Vector3(10, 2, 10), Vector3(0, 15, 0))
	kcam.call("_build_hud")
	kcam.call("_process", 0.05)
	var loss_box: Control = kcam.get("_signal_loss_box")
	var entered_static := bool(kcam.get("_static_active")) and loss_box != null and loss_box.visible
	kcam.call("_process", 0.14)
	var exited_static := not bool(kcam.get("_static_active")) and not loss_box.visible
	_check(entered_static and exited_static,
			"#19 Kill-cam enters 0.15s white-noise VIDEO SIGNAL LOST phase then snaps live")
	kcam.call("cancel")
	kcam.queue_free()
	cam_host.queue_free()

	# #8, #9, #14, #20: BigLevel Combat Mission 1 primary infantry, radio respawn reset,
	# ObjectiveMarkers clamp, top radio subtitles & Results debriefing XP/Rank
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.special_mission = 0
	var lvl := (load("res://sceneries/BigLevel.tscn") as PackedScene).instantiate()
	add_child(lvl)
	await get_tree().create_timer(2.2).timeout
	get_tree().paused = false
	var prim_nodes := get_tree().get_nodes_in_group("primary_combat_target")
	_check(prim_nodes.size() == 6 and int(lvl.get("_mission_targets_total")) == 6,
			"#8 Combat Mission 1 spawns 6 primary infantry targets",
			"prim=%d total=%s" % [prim_nodes.size(), str(lvl.get("_mission_targets_total"))])
	var lvl_drone := lvl.get_node_or_null("Drone") as Drone
	if lvl_drone != null and lvl_drone.flight_controller != null:
		GameSettings.hud_config["angle_mode"] = true
		lvl_drone.flight_controller.select_flight_mode(FlightController.FlightMode.LEVEL)
		lvl_drone.flight_controller.change_flight_mode(FlightController.FlightMode.AUTO)
		lvl.call("_on_drone_armed", FlightController.FlightMode.AUTO)
		_check(lvl_drone.flight_controller.flight_mode == FlightController.FlightMode.LEVEL,
				"#11 BigLevel._on_drone_armed preserves ANGLE (LEVEL)")

	# Simulate radio beats triggered, test pre-mission reset AND mid-mission respawn silence
	lvl.set("_mission_started", false)
	lvl.set("_radio_beat_01_sent", true)
	lvl.set("_radio_beat_02_sent", true)
	lvl.set("_radio_cooldown", 12.0)
	lvl.call("_on_respawned")
	var clean_reset := not bool(lvl.get("_radio_beat_01_sent")) \
			and not bool(lvl.get("_radio_beat_02_sent")) \
			and float(lvl.get("_radio_cooldown")) <= 0.0
	lvl.set("_mission_started", true)
	lvl.set("_mission_phase", 1)
	lvl.call("_on_respawned")
	await get_tree().process_frame
	var sub_after_respawn := lvl.get("_radio_subtitle_panel") as Control
	var silent_mid := not bool(Audio._radio_player.playing) \
			and (sub_after_respawn == null or not sub_after_respawn.visible)
	_check(clean_reset and silent_mid,
			"#7/#9 Respawn resets pre-mission radio beats & keeps mid-mission respawn silent")

	var sub_panel := lvl.get("_radio_subtitle_panel") as Control
	var obj_markers := lvl.find_child("ObjectiveMarkers", true, false)
	lvl.call("_update_nav_marker")
	var nav_lbl := lvl.get("_nav_marker") as Label
	_check(sub_panel != null and sub_panel.anchor_top < 0.25 \
			and nav_lbl != null and not nav_lbl.text.is_empty() \
			and obj_markers != null and obj_markers.has_method("_safe_margins"),
			"#14 Radio subtitles anchored top & ObjectiveMarkers safe margins active")

	# Destroy primary infantry cleanly -> 1st kill in Phase 0 advances to Strike (1),
	# remaining kills reach 6/6 and advance to Extract (2) -> Results.
	lvl.call("_start_mission")
	lvl.set("_mission_phase", 0)
	lvl.set("_mission_phase_active", true)
	var killed_first := false
	for pi in prim_nodes:
		if is_instance_valid(pi) and pi.has_method("take_damage"):
			pi.call("take_damage", 999.0, (pi as Node3D).global_position)
			if not killed_first:
				killed_first = true
				_check(int(lvl.get("_mission_phase")) == 1,
						"#8 First primary kill during Phase 0 auto-advances to Strike (phase 1)",
						"phase=%s" % str(lvl.get("_mission_phase")))
	await get_tree().process_frame
	var extract_cleared := not bool(lvl.get("_mission_phase_active"))
	await get_tree().create_timer(1.0).timeout
	get_tree().paused = false
	var pinfo_done: Dictionary = lvl.call("get_mission_phase_info")
	_check(int(lvl.get("_mission_targets_destroyed")) == 6 and extract_cleared \
			and bool(lvl.get("_mission_finished")) and pinfo_done.is_empty(),
			"#8 Killing all 6 primary infantry completes mission directly with no Extract marker",
			"destroyed=%s finished=%s phase_active=%s" % [
				str(lvl.get("_mission_targets_destroyed")),
				str(lvl.get("_mission_finished")),
				str(lvl.get("_mission_phase_active"))])

	lvl.set("_payload_drops", 7)
	lvl.set("_payload_hits", 6)
	lvl.set("_armor_kills", 1)
	lvl.call("_show_results", "ТЕСТ ЗАВЕРШЕНО")
	var stats_lbl := lvl.get("_results_stats") as Label
	var career_lbl := lvl.get("_results_career_label") as Label
	var career_bar := lvl.get("_results_career_bar") as ProgressBar
	var stats_txt := stats_lbl.text if stats_lbl != null else ""
	_check((stats_txt.contains("УРАЖЕННЯ") or stats_txt.contains("KILLS")) \
			and (stats_txt.contains("ТОЧНІСТЬ") or stats_txt.contains("ACCURACY")) \
			and career_lbl != null and career_lbl.visible \
			and career_bar != null and career_bar.visible,
			"#20 Debriefing shows kills breakdown, accuracy %, XP & Pilot Rank progress bar")
	get_tree().paused = false
	lvl.queue_free()

	if had_mobile:
		OS.set_environment("MOBILE_UI", old_mobile)
	else:
		OS.unset_environment("MOBILE_UI")
	if not had_norec:
		OS.unset_environment("DRONE_NO_RECORD")

	print("[QA20] SUMMARY failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
