extends Node

## Regression test suite for all Build #41 user-reported issues + asset integrity.
const TEST_NAME := "BUILD41_FIXES"
const BombSightScript = preload("res://combat/bomb_sight.gd")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var saved_preset: int = Global.drone_preset
	var saved_mode: int = Global.play_mode
	var saved_cm: int = Global.combat_mission
	var saved_sp: int = Global.special_mission
	var saved_menu: Dictionary = Global.menu_settings.duplicate(true)
	var saved_hud: Dictionary = GameSettings.hud_config.duplicate(true)
	var saved_mobile_src: String = str(MobileInput.get("source_override"))

	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("DRONE_KILLCAM_TEST", "1")
	GameSettings.hud_config["fpv_rig"] = true
	GameSettings.save_hud_config()
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.special_mission = 0
	Global.drone_preset = 0
	Global.chain_briefing_pending = false

	# 1. Verify bomb_sight source has no green drop_line connector between center and reticle.
	var bs_src := FileAccess.get_file_as_string("res://combat/bomb_sight.gd")
	_check(not bs_src.contains("drop_line"), "bomb_sight removes unexplained green drop_line")

	# 2. Verify MobileMenu loads cleanly with zero syntax/null child errors.
	var mm_packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	var mm_inst := mm_packed.instantiate() if mm_packed != null else null
	_check(mm_inst != null, "MobileMenu instantiates cleanly")
	if mm_inst != null:
		mm_inst.free()

	# 3. Load BigLevel and inspect camera, FPVRig, Airflow, HUD layout, KillCam, mission completion.
	var level_packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	_check(level_packed != null, "BigLevel.tscn loads cleanly")
	if level_packed != null:
		var lvl := level_packed.instantiate() as Node3D
		get_tree().root.add_child(lvl)
		get_tree().current_scene = lvl
		await get_tree().create_timer(2.5).timeout

		# Bug #6: Airflow particles completely removed.
		var cam := lvl.get_node_or_null("Drone/FPVCamera") as Camera3D
		_check(cam != null and cam.get_node_or_null("AirflowParticles") == null,
				"AirflowParticles removed from FPVCamera")

		# Bug #7: Authentic per-drone GLB FPVRig (_fpv_rig == _model_root, no procedural FPVRig) toggleable via fpv_rig.
		var model_root := lvl.get("_model_root") as Node3D
		var fpv_rig := lvl.get("_fpv_rig") as Node3D
		_check(cam != null and cam.get_node_or_null("FPVRig") == null,
				"No procedural FPVRig node on FPVCamera")
		_check(model_root != null and fpv_rig == model_root and model_root.visible,
				"Authentic GLB DroneModel used as _fpv_rig and visible when fpv_rig=true")
		GameSettings.hud_config["fpv_rig"] = false
		GameSettings.hud_config_updated.emit()
		await get_tree().process_frame
		_check(model_root != null and not model_root.visible, "DroneModel obvis hides when fpv_rig=false")
		GameSettings.hud_config["fpv_rig"] = true
		GameSettings.hud_config_updated.emit()
		await get_tree().process_frame
		_check(model_root != null and model_root.visible, "DroneModel obvis shows again when fpv_rig=true")

		# Bug #2: TouchControls Menu button sits cleanly below HUD text (TelemetryLeftRow / MissionBadgeRow).
		TouchControls.set_enabled(true)
		await get_tree().process_frame
		var pause_btn := TouchControls.get("_pause_button") as Control
		var mission_row := lvl.get_node_or_null("CanvasLayer/MissionBadgeRow")
		if mission_row == null:
			var hud_layer = lvl.get("_hud")
			if hud_layer != null:
				mission_row = hud_layer.get_node_or_null("MissionBadgeRow")
		var mr_bottom: float = 120.0
		if mission_row is Control:
			mr_bottom = (mission_row as Control).position.y + maxf((mission_row as Control).size.y, 20.0)
		_check(pause_btn != null and pause_btn.position.y >= mr_bottom + 12.0,
				"TouchControls Menu button y=%.1f clears MissionBadgeRow bottom %.1f" % [
					pause_btn.position.y if pause_btn != null else -1.0, mr_bottom])

		# Bug #3: Controller lock + ELRS active never turns sticks on via Menu press or next-mission transition.
		TouchControls.call("set_controller_only", true)
		await get_tree().process_frame
		_check(not bool(TouchControls.get("touch_mode")),
				"set_controller_only(true) turns touch sticks OFF")
		# Simulate touching pause button / scene transition reload while controller locked.
		var ev_touch := InputEventScreenTouch.new()
		ev_touch.index = 0
		ev_touch.pressed = true
		ev_touch.position = pause_btn.position + Vector2(12.0, 12.0) if pause_btn != null else Vector2(40, 200)
		TouchControls._input(ev_touch)
		TouchControls.set_enabled(false)
		TouchControls.set_enabled(true)
		await get_tree().process_frame
		_check(not bool(TouchControls.get("touch_mode")),
				"touch_mode stays OFF across Menu touch & scene enable when controller-locked")

		# Simulate active ELRS in 'auto' mode across mission load / screen touches.
		TouchControls.call("set_controller_only", false)
		ElrsWifiInput.valid = true
		ElrsWifiInput.set("_last_frame_ms", Time.get_ticks_msec())
		TouchControls.set_enabled(false)
		TouchControls.set_enabled(true)
		var mid_touch := InputEventScreenTouch.new()
		mid_touch.index = 1
		mid_touch.pressed = true
		mid_touch.position = Vector2(300.0, 500.0)
		TouchControls._input(mid_touch)
		await get_tree().process_frame
		_check(not bool(TouchControls.get("touch_mode")),
				"touch_mode stays OFF across scene enable & accidental tap while ELRS is active")
		ElrsWifiInput.valid = false
		ElrsWifiInput.set("_last_frame_ms", -60000)
		ElrsWifiInput.set("_last_valid_ms", -60000)
		TouchControls.set_enabled(true)
		await get_tree().process_frame

		# PauseMenu ButtonTouchSticks toggles cleanly between ON and OFF.
		var pause_menu: Variant = lvl.get("pause_menu")
		if pause_menu == null:
			pause_menu = lvl.find_child("PauseMenu", true, false)
		_check(pause_menu != null and pause_menu.has_method("_on_touch_sticks_toggled") \
				and pause_menu.get("btn_touch_sticks") != null,
				"PauseMenu exposes ButtonTouchSticks toggle")
		if pause_menu != null and pause_menu.has_method("show_menu"):
			pause_menu.call("show_menu", true)
			pause_menu.call("_on_touch_sticks_toggled")
			_check(bool(TouchControls.call("is_controller_locked")) and not bool(TouchControls.get("touch_mode")),
					"PauseMenu toggle disables touch sticks when previously ON")
			pause_menu.call("_on_touch_sticks_toggled")
			_check(not bool(TouchControls.call("is_controller_locked")) and bool(TouchControls.get("touch_mode")),
					"PauseMenu toggle re-enables touch sticks when pressed again")
			pause_menu.call("_on_resume_pressed")
		get_tree().paused = false

		# Bug #4: Continuous deadzone curve + square gimbal travel + LEVEL sub-hover ground safety.
		TouchControls.call("set_menu_preview", true)
		MobileInput.call("set_source", "touch")
		await get_tree().process_frame
		var tiny_curve: float = float(TouchControls.call("_apply_axis_curve", 0.025, 0.02, true))
		_check(tiny_curve > 0.0 and tiny_curve < 0.03,
				"Touch deadzone transition is continuous (no step jump): %.4f" % tiny_curve)
		var left_c: Vector2 = TouchControls.get("_left_center")
		var rad: float = float(TouchControls.get("_radius"))
		TouchControls.call("_handle_touch", 0, left_c, true)
		TouchControls.call("_handle_touch", 0, left_c + Vector2(rad, -rad), true)
		await get_tree().process_frame
		_check(absf(float(TouchControls.get("yaw"))) > 0.95 and float(TouchControls.get("throttle")) > 0.95,
				"Square gimbal travel allows full Yaw+Throttle corner (yaw=%.2f thr=%.2f)" % [
					float(TouchControls.get("yaw")), float(TouchControls.get("throttle"))])
		TouchControls.call("_handle_touch", 0, left_c, false)
		TouchControls.call("set_menu_preview", false)

		# Bug #1: KillCam triggers reliably on consecutive primary targets (e.g. BMP then TRUCK).
		var kc: Variant = lvl.get("_kill_cam")
		var v_bmp: Variant = (lvl.get("_vehicles") as Array)[0] if (lvl.get("_vehicles") as Array).size() > 0 else null
		lvl.call("_on_vehicle_destroyed", 150, Vehicle.Kind.BMP, v_bmp)
		_check(kc != null and bool(kc.call("is_active")),
				"KillCam triggers on first non-tank primary vehicle destruction")
		if kc != null and bool(kc.call("is_active")):
			kc.call("cancel")
		lvl.set("_kill_cam_last_ms", -10000)
		var v_truck: Variant = (lvl.get("_vehicles") as Array)[1] if (lvl.get("_vehicles") as Array).size() > 1 else null
		lvl.call("_on_vehicle_destroyed", 100, Vehicle.Kind.TRUCK, v_truck)
		_check(kc != null and bool(kc.call("is_active")),
				"KillCam triggers again on subsequent target destruction")
		if kc != null and bool(kc.call("is_active")):
			kc.call("cancel")

		# Bug #8: Destroying all remaining targets finishes mission directly with zero exit marker.
		var total_t := int(lvl.get("_mission_targets_total"))
		lvl.set("_mission_targets_destroyed", total_t)
		lvl.call("_check_combat_mission_complete")
		await get_tree().create_timer(1.0).timeout
		get_tree().paused = false
		var pinfo: Dictionary = lvl.call("get_mission_phase_info")
		_check(bool(lvl.get("_mission_finished")) and pinfo.is_empty(),
				"Mission completes with zero lingering exit marker")

		TouchControls.set_enabled(false)
		lvl.queue_free()
		await get_tree().process_frame

	# Bug #10: Hangar & Hero hide newly attached giant models until fit_preview_model scales them.
	if mm_packed != null:
		var mm := mm_packed.instantiate()
		get_tree().root.add_child(mm)
		mm.call("show_drone")
		var leleka_idx := -1
		for i in range(DroneCatalog.count()):
			if str(DroneCatalog.preset(i).get("id", "")) == "leleka100":
				leleka_idx = i
				break
		if leleka_idx >= 0:
			mm.set("_hangar_preview_idx", leleka_idx)
			mm.call("_load_hangar_model", leleka_idx)
			var hangar_holder := mm.get("_hangar_holder") as Node3D
			var model_attached_hidden := false
			var saw_unscaled_visible := false
			for _f in range(90):
				await get_tree().process_frame
				if hangar_holder != null and hangar_holder.get_child_count() > 0:
					var m := hangar_holder.get_child(0) as Node3D
					if m != null:
						if not m.visible:
							model_attached_hidden = true
						else:
							var box: AABB = mm.call("_combined_bounds", hangar_holder)
							var max_d := maxf(box.size.x, maxf(box.size.y, box.size.z))
							if max_d > 0.70:
								saw_unscaled_visible = true
							else:
								break
			_check(model_attached_hidden or not saw_unscaled_visible,
					"Leleka-100 never appears unscaled (>0.70m) in Hangar")
			var final_box: AABB = mm.call("_combined_bounds", hangar_holder)
			var final_max := maxf(final_box.size.x, maxf(final_box.size.y, final_box.size.z))
			_check(final_max > 0.20 and final_max <= 0.70,
					"Hangar Leleka-100 scaled cleanly to pedestal size (max_dim=%.3f)" % final_max)
		mm.queue_free()
		await get_tree().process_frame

	# Bug #9: Real per-drone GLB rigs load across presets; verify all kept drone preset models & level scenes load cleanly.
	# AND verify none of their transitive ResourceLoader dependencies match export_presets.cfg exclude_filter.
	var models_ok := true
	var check_roots: Array[String] = [
		"res://GUI/mobile/MobileMenu.tscn",
		"res://sceneries/BigLevel.tscn",
		"res://sceneries/VillageLevel.tscn",
		"res://sceneries/SteppeLevel.tscn",
		"res://sceneries/IndustrialLevel.tscn",
		"res://sceneries/WetlandsLevel.tscn",
		"res://sceneries/CityLevel.tscn",
		"res://sceneries/CourseLevel.tscn",
		"res://Assets/combat/soldier_detailed_merged.glb",
		"res://Assets/combat/rifleman.glb",
		"res://Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
		"res://Assets/vehicles/low-poly_bmp-2m.glb",
		"res://Assets/vehicles/btr-90_ussr.glb",
		"res://Assets/vehicles/gaz_tigr_low_poly.glb",
		"res://Assets/vehicles/apache_hecu_half-life.glb",
		"res://Assets/vehicles/apache_hecu_half-life_mobile.glb",
		"res://Assets/Drones/shahed-136.glb",
		"res://Assets/Drones/ua_norm/radiomaster_tx12.glb",
		"res://Assets/Drones/ua_norm/radiomaster_tx12_rig.glb",
		"res://Assets/handcrafted/factory_complex.glb",
		"res://Assets/handcrafted/farm_complex.glb",
		"res://Assets/handcrafted/freight_train.glb",
		"res://Assets/handcrafted/village_house.glb",
		"res://Assets/handcrafted/wetlands_dock.glb",
	]
	for i in range(DroneCatalog.PRESETS.size()):
		var p := DroneCatalog.preset(i)
		var mpath := str(p.get("model", ""))
		if not mpath.is_empty():
			if load(mpath) == null:
				models_ok = false
				print("[", TEST_NAME, "] FAIL missing preset model: ", mpath)
			check_roots.append(mpath)
			var mob_path := mpath.trim_suffix(".glb") + "_mobile.glb"
			if ResourceLoader.exists(mob_path):
				check_roots.append(mob_path)
	_check(models_ok, "All DroneCatalog preset GLB models load cleanly")
	_verify_export_dependencies(check_roots)

	for spath in [
		"res://sceneries/BigLevel.tscn",
		"res://sceneries/VillageLevel.tscn",
		"res://sceneries/SteppeLevel.tscn",
		"res://sceneries/IndustrialLevel.tscn",
		"res://sceneries/WetlandsLevel.tscn",
		"res://sceneries/CityLevel.tscn",
		"res://sceneries/CourseLevel.tscn",
	]:
		_check(ResourceLoader.exists(spath), "Level scene exists: " + spath)

	OS.set_environment("DRONE_KILLCAM_TEST", "")
	MobileInput.call("set_source", saved_mobile_src)
	Global.menu_settings = saved_menu
	Global.save_menu_settings()
	GameSettings.hud_config = saved_hud
	GameSettings.save_hud_config()
	Global.drone_preset = saved_preset
	Global.play_mode = saved_mode
	Global.combat_mission = saved_cm
	Global.special_mission = saved_sp
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _verify_export_dependencies(roots: Array[String]) -> void:
	var raw_cfg := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var has_bom := false
	if raw_cfg != null:
		has_bom = raw_cfg.get_8() == 0xEF and raw_cfg.get_8() == 0xBB and raw_cfg.get_8() == 0xBF
		raw_cfg.close()
	_check(not has_bom, "export_presets.cfg has no UTF-8 BOM")
	var cfg := ConfigFile.new()
	var err := cfg.load("res://export_presets.cfg")
	_check(err == OK, "export_presets.cfg parses as ConfigFile")
	if err != OK:
		return
	var exclude_raw := str(cfg.get_value("preset.0", "exclude_filter", ""))
	var pats := PackedStringArray()
	for tok in exclude_raw.split(","):
		var t := tok.strip_edges()
		if t != "":
			pats.append(t)

	var visited: Dictionary = {}
	var queue: Array[String] = roots.duplicate()
	while queue.size() > 0:
		var cur: String = queue.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		if ResourceLoader.exists(cur):
			for dep in ResourceLoader.get_dependencies(cur):
				var parts := String(dep).split("::::")
				var dp := parts[-1]
				if dp.begins_with("res://") and not visited.has(dp):
					queue.append(dp)

	var excluded_deps: Array[String] = []
	for p in visited.keys():
		var s := String(p)
		if not s.begins_with("res://Assets/"):
			continue
		var rel := s.trim_prefix("res://")
		for pat in pats:
			if rel.matchn(pat) or (pat.ends_with("/**") and rel.begins_with(pat.trim_suffix("/**") + "/")) or (pat.ends_with("/*") and rel.begins_with(pat.trim_suffix("/*") + "/")):
				excluded_deps.append(rel + " <- " + pat)
				break
	if excluded_deps.size() > 0:
		print("[", TEST_NAME, "] EXCLUDED_DEPS sample: ", excluded_deps.slice(0, 10))
	_check(excluded_deps.is_empty(),
			"Zero transitive Assets/ dependencies excluded by export_presets.cfg (found=%d)" % excluded_deps.size())
