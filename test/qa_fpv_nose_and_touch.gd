extends Node

## Windowed & headless QA verification for:
## 1. High-quality Blender 3D warhead on «КВАД-5» (menu preview + close-up + FPV + hidden in Freestyle)
## 2. Nose-visible FPV framing on «ФУРІЯ» A1-СМ, «ЛЕЛЕКА-100», «ЧАКЛУН JET», and «СОКІЛ» VTOL
## 3. Touch БЧ buttons visible on Combat sorties across all kamikaze airframes

const SHOT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/3e1fc674-fea9-4635-a574-57c85e14dad7/scratch/qa_shots"

var _fails := 0
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("[QA-FPV] FAIL: ", msg)
	else:
		print("[QA-FPV] PASS: ", msg)


func _save_shot(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_check(false, "Viewport image valid for " + filename)
		return
	var path := SHOT_DIR.path_join(filename)
	var err := img.save_png(path)
	_check(err == OK, "Saved screenshot " + filename)


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out


func _set_mobile_env(on: bool) -> void:
	if on:
		OS.set_environment("MOBILE_UI", "1")
		OS.set_environment("TOUCH_CONTROLS", "1")
	else:
		OS.unset_environment("MOBILE_UI")
		OS.unset_environment("TOUCH_CONTROLS")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280, 720)
	var saved_preset := Global.drone_preset
	var saved_mode := Global.play_mode
	var saved_special := Global.special_mission
	var saved_combat := Global.combat_mission
	var saved_diff := Global.difficulty
	var saved_training := Global.combat_training
	var saved_chain := Global.chain_briefing_pending
	var saved_map := str(Global.menu_settings.get("selected_map", "steppe"))
	var saved_settings := Global.menu_settings.duplicate(true)

	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	OS.set_environment("QA_NO_AIRFRAME_LIMIT", "1")
	_set_mobile_env(true)
	Global.menu_settings["selected_map"] = "steppe"
	Global.menu_settings["language"] = "uk"
	Global.chain_briefing_pending = false

	# 1. Close-up studio shot of quad5 Blender warhead
	await _capture_quad5_closeup()

	# 2. MobileMenu 3D preview of quad5 (preset 3)
	await _capture_quad5_menu_preview()

	# 3. Combat FPV + Touch БЧ buttons for all 6 airframes (Mobile UI)
	var combat_cases := [
		[3, "quad5_combat_fpv.png", true],
		[8, "furia_combat_fpv.png", false],
		[7, "leleka_combat_fpv.png", false],
		[9, "chaklun_combat_fpv.png", false],
		[4, "sokil_vtol_combat_fpv.png", false],
		[2, "strila8_combat_fpv.png", false],
	]
	for item in combat_cases:
		var idx := int(item[0])
		var shot_name := str(item[1])
		var spin_props := bool(item[2])
		await _test_level_fpv(idx, Global.PlayMode.COMBAT, false, true, spin_props, shot_name)

	# 4. quad5 dual-mode functional tests (Drop OR Detonate while hanging)
	await _test_quad5_dual_payload_actions()

	# 5. quad5 in pure Freestyle mode: warhead hidden, front props visible, БЧ buttons hidden
	await _test_level_fpv(3, Global.PlayMode.TRAINING, false, true, true, "quad5_freestyle_fpv.png")

	# 6. Desktop (non-_mobile.glb) sanity check for nose-visible presets
	_set_mobile_env(false)
	for idx in [3, 4, 7, 8, 9]:
		await _test_level_fpv(idx, Global.PlayMode.COMBAT, false, false, false, "")

	# Restore globals and saved settings file
	_set_mobile_env(false)
	Global.drone_preset = saved_preset
	Global.play_mode = saved_mode
	Global.special_mission = saved_special
	Global.combat_mission = saved_combat
	Global.difficulty = saved_diff
	Global.combat_training = saved_training
	Global.chain_briefing_pending = saved_chain
	Global.menu_settings = saved_settings
	Global.save_menu_settings()
	print("[QA-FPV] SUMMARY checks=", _checks, " fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _capture_quad5_closeup() -> void:
	var stage := Node3D.new()
	stage.name = "StudioStage"
	get_tree().root.add_child(stage)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.08, 0.10, 0.11, 1.0)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.45, 0.48, 0.50)
	we.ambient_light_energy = 0.85
	env.environment = we
	stage.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.4
	key.rotation_degrees = Vector3(-38.0, 35.0, 0.0)
	stage.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 1.0
	fill.rotation_degrees = Vector3(24.0, -135.0, 0.0)
	stage.add_child(fill)

	var holder := Node3D.new()
	stage.add_child(holder)
	var model := DroneCatalog.attach_model(holder, 3)
	_check(model != null, "quad5 studio model attached")

	var warhead_count := 0
	var provoloka_count := 0
	var styazka_count := 0
	if model != null:
		for mi in _find_meshes(model):
			var nm := String(mi.name).to_lower()
			if nm.contains("warhead"):
				warhead_count += 1
			if nm.contains("provoloka"):
				provoloka_count += 1
			if nm.contains("styazka"):
				styazka_count += 1
	_check(warhead_count >= 12 and provoloka_count == 2 and styazka_count >= 2,
			"quad5 Blender warhead parts present (warhead=%d, whiskers=%d, straps=%d)" % [
				warhead_count, provoloka_count, styazka_count])

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	stage.add_child(cam)
	cam.make_current()
	# Front-right-below 3/4 closeup highlighting underbody warhead, ogive, fuze & whiskers
	cam.look_at_from_position(Vector3(0.24, 0.02, -0.34), Vector3(0.0, -0.005, -0.055), Vector3.UP)
	await _save_shot("quad5_warhead_closeup.png")

	stage.queue_free()
	await get_tree().process_frame


func _capture_quad5_menu_preview() -> void:
	Global.menu_settings["selected_map"] = "industrial"
	Global.menu_settings["drone_preset"] = 3
	Global.drone_preset = 3
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_training = false
	var packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	_check(packed != null, "MobileMenu scene loaded")
	if packed == null:
		return
	var menu := packed.instantiate()
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	await get_tree().process_frame
	menu.set("_selected_map", "industrial")
	menu.set("_selected_mode", Global.PlayMode.COMBAT)
	DroneCatalog.apply(3)
	menu.call("_load_hero_model", 3)
	await get_tree().create_timer(1.2).timeout
	_check(Global.drone_preset == 3, "MobileMenu stayed on quad5 preset (got %d)" % Global.drone_preset)
	var model_node := menu.find_child("DroneModel", true, false) as Node3D
	_check(model_node != null, "MobileMenu shows quad5 model")
	await _save_shot("quad5_menu_preview.png")
	get_tree().current_scene = null
	menu.queue_free()
	await get_tree().process_frame
	Global.menu_settings["selected_map"] = "steppe"


func _test_level_fpv(preset_idx: int, play_mode: int, combat_training: bool,
		mobile_on: bool, spin_props: bool, shot_name: String) -> void:
	var preset := DroneCatalog.preset(preset_idx)
	var pname := str(preset.get("id", preset_idx))
	Global.drone_preset = preset_idx
	Global.play_mode = play_mode
	Global.combat_training = combat_training
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.difficulty = Global.Difficulty.RECRUIT
	Global.chain_briefing_pending = false

	var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	_check(packed != null, "%s SteppeLevel loaded" % pname)
	if packed == null:
		return
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level

	# Wait for deferred setup & TouchControls refresh
	await get_tree().create_timer(1.6).timeout
	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if fpv != null:
		fpv.current = true
	if level.has_method("_refresh_model_visibility"):
		level.call("_refresh_model_visibility")

	var model_root := level.get("_model_root") as Node3D
	_check(model_root != null and model_root.visible, "%s FPV _model_root visible (mobile=%s)" % [pname, mobile_on])

	var drone := level.get_node_or_null("Drone")
	if spin_props and drone != null and model_root != null:
		# Rotate props realistically to verify blur/blade framing in FPV screenshot
		var pivots := get_tree().get_nodes_in_group("drone_prop_pivot")
		for idx_p in range(pivots.size()):
			var pv := pivots[idx_p] as Node3D
			if pv != null and model_root.is_ancestor_of(pv):
				pv.rotation.y += 0.55 + float(idx_p) * 0.4

	# Check warhead visibility rules
	if model_root != null and pname == "quad5":
		var warhead_vis := 0
		var warhead_tot := 0
		for mi in _find_meshes(model_root):
			if String(mi.name).to_lower().contains("warhead"):
				warhead_tot += 1
				if mi.visible:
					warhead_vis += 1
		if play_mode == Global.PlayMode.COMBAT:
			_check(warhead_tot >= 12 and warhead_vis == warhead_tot,
					"quad5 Combat shows all warhead parts (%d/%d)" % [warhead_vis, warhead_tot])
		else:
			_check(warhead_tot >= 12 and warhead_vis == 0,
					"quad5 Freestyle hides all warhead parts (vis=%d/%d)" % [warhead_vis, warhead_tot])

	# Verify camera/gimbal obstructions hidden on recon wings
	if model_root != null and pname in ["leleka100", "furia", "chaklun_jet"]:
		var cam_vis := 0
		for mi in _find_meshes(model_root):
			var mn := String(mi.name).to_lower()
			if (mn.contains("cam") or mn.contains("gimbal") or mn.contains("irst") or mn.contains("thermal")) and mi.visible:
				cam_vis += 1
		_check(cam_vis == 0, "%s hides obstructing camera/gimbal parts (cam_vis=%d)" % [pname, cam_vis])

	# Check Touch БЧ button state on mobile runtime
	if mobile_on:
		var tc := get_node_or_null("/root/TouchControls")
		_check(tc != null, "%s TouchControls exists" % pname)
		if tc != null:
			var db := tc.get("_drop_button") as Button
			var dbr := tc.get("_drop_button_right") as Button
			if play_mode == Global.PlayMode.COMBAT:
				if pname == "quad5":
					_check(db != null and db.visible and db.text == "СКИД" \
							and dbr != null and dbr.visible and dbr.text == "БЧ",
							"quad5 Combat shows dual touch buttons (left=%s:'%s' right=%s:'%s')" % [
								str(db.visible if db else false), str(db.text if db else ""),
								str(dbr.visible if dbr else false), str(dbr.text if dbr else "")])
				else:
					_check(db != null and db.visible and dbr != null and dbr.visible and db.text == "БЧ",
							"%s Combat shows touch БЧ buttons (left=%s right=%s text=%s)" % [
								pname, str(db.visible if db else false),
								str(dbr.visible if dbr else false), str(db.text if db else "")])
			else:
				_check(db != null and not db.visible and dbr != null and not dbr.visible,
						"%s Freestyle hides touch БЧ buttons" % pname)

	if not shot_name.is_empty():
		await _save_shot(shot_name)

	get_tree().current_scene = null
	level.queue_free()
	await get_tree().process_frame


func _count_visible_warhead_meshes(model_root: Node3D) -> Vector2i:
	var vis := 0
	var tot := 0
	if model_root == null:
		return Vector2i.ZERO
	for mi in _find_meshes(model_root):
		var mn := String(mi.name).to_lower()
		if mn.contains("warhead") or mn.contains("detonator") \
				or mn.contains("provoloka") or mn.contains("styazka"):
			tot += 1
			if mi.visible:
				vis += 1
	return Vector2i(vis, tot)


func _test_quad5_dual_payload_actions() -> void:
	# --- Subtest A: Drop warhead in flight & verify visual removal + no empty detonation ---
	Global.drone_preset = 3
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_training = false
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.difficulty = Global.Difficulty.RECRUIT
	Global.chain_briefing_pending = false

	var packed := load("res://sceneries/SteppeLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(1.6).timeout

	var fpv := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if fpv != null:
		fpv.current = true
	var drone := level.get_node_or_null("Drone") as Drone
	var model_root := level.get("_model_root") as Node3D
	var cs := level.get_node_or_null("CombatSystem")
	var tc := get_node_or_null("/root/TouchControls")
	_check(drone != null and cs != null, "quad5 dual Subtest A ready")
	if drone != null and cs != null:
		var ground := float(level.call("_find_ground_y", drone.global_position.x, drone.global_position.z))
		drone.global_position = Vector3(drone.global_position.x, ground + 22.0, drone.global_position.z)
		drone.linear_velocity = Vector3(0.0, 0.0, -5.0)
		drone.angular_velocity = Vector3.ZERO
		if drone.flight_controller != null:
			drone.flight_controller.request_arm(true)
		await get_tree().physics_frame
		await get_tree().physics_frame

		var before_counts := _count_visible_warhead_meshes(model_root)
		_check(before_counts.y >= 17 and before_counts.x == before_counts.y and int(cs.get("ammo")) == 1,
				"quad5 Subtest A starts with hanging warhead (%d/%d) & ammo=1" % [before_counts.x, before_counts.y])

		# Trigger drop!
		level.call("_drop_fpv_payload")
		await get_tree().create_timer(0.15).timeout
		if tc != null:
			tc.call("_sync_payload_buttons")

		var dropped_bodies := 0
		for ch in level.get_children():
			if ch is Payload:
				dropped_bodies += 1
		var after_drop_counts := _count_visible_warhead_meshes(model_root)
		_check(dropped_bodies >= 1 and int(cs.get("ammo")) == 0,
				"quad5 Subtest A spawned dropped Payload (%d) and ammo=0" % dropped_bodies)
		_check(after_drop_counts.x == 0,
				"quad5 Subtest A hid all hanging warhead meshes immediately after drop (%d/%d)" % [
					after_drop_counts.x, after_drop_counts.y])
		if tc != null:
			var db := tc.get("_drop_button") as Button
			var dbr := tc.get("_drop_button_right") as Button
			_check(db != null and not db.visible and dbr != null and not dbr.visible,
					"quad5 Subtest A hid СКИД & БЧ buttons after single warhead dropped")
		await _save_shot("quad5_after_drop_fpv.png")

		# Wait past _reset_fpv_payload (0.75 s timer) to verify empty drone stays empty
		await get_tree().create_timer(0.85).timeout
		var persisted_counts := _count_visible_warhead_meshes(model_root)
		_check(persisted_counts.x == 0,
				"quad5 Subtest A keeps warhead hidden past reset timer (%d/%d)" % [
					persisted_counts.x, persisted_counts.y])
		level.call("_activate_fpv_payload")
		await get_tree().process_frame
		_check(drone.visible, "quad5 Subtest A cannot detonate on drone after warhead was dropped")

	get_tree().current_scene = null
	level.queue_free()
	await get_tree().process_frame

	# --- Subtest B: Detonate warhead while still hanging on the drone ---
	var level_b := packed.instantiate() as Node3D
	get_tree().root.add_child(level_b)
	get_tree().current_scene = level_b
	await get_tree().create_timer(1.6).timeout
	var drone_b := level_b.get_node_or_null("Drone") as Drone
	var cs_b := level_b.get_node_or_null("CombatSystem")
	var drops_before := int(level_b.get("_payload_drops"))
	level_b.call("_activate_fpv_payload")
	await get_tree().process_frame
	_check(int(level_b.get("_payload_drops")) == drops_before + 1 \
			and cs_b != null and int(cs_b.get("ammo")) == 0 \
			and drone_b != null and not drone_b.visible,
			"quad5 Subtest B detonated attached warhead while hanging on drone")

	get_tree().current_scene = null
	level_b.queue_free()
	await get_tree().process_frame
