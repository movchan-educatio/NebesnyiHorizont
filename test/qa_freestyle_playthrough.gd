extends Node

const SCENES := {
	"uman": "res://sceneries/UmanLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"airport": "res://sceneries/AirportLevel.tscn",
}

var _fails := 0
var _shot_dir := ""
var _shot_count := 0
var _prev_alt_err := 0.0
var _alt_integral := 0.0


func _check(ok: bool, msg: String) -> void:
	if ok:
		print("[FREESTYLE-QA] PASS ", msg)
	else:
		_fails += 1
		print("[FREESTYLE-QA] FAIL ", msg)


func _ready() -> void:
	await get_tree().process_frame
	_shot_dir = OS.get_environment("FREESTYLE_SHOT_DIR").strip_edges()
	var is_headless := DisplayServer.get_name() == "headless"
	Engine.max_physics_steps_per_frame = 24
	Engine.time_scale = 4.0 if is_headless else 1.4

	Global.menu_settings["language"] = "uk"
	Global.menu_settings["sound_enabled"] = false

	# Ensure default flight/touch settings don't fight direct stick inputs.
	var prev_touch := false
	if TouchControls != null:
		prev_touch = bool(TouchControls.enabled)
		if TouchControls.has_method("set_enabled"):
			TouchControls.set_enabled(false)
		else:
			TouchControls.enabled = false

	var map_filter := OS.get_environment("FREESTYLE_MAP").strip_edges().to_lower()
	var maps := ["uman", "industrial", "wetlands", "airport"]
	if not map_filter.is_empty() and SCENES.has(map_filter):
		maps = [map_filter]

	for map_id in maps:
		await _run_map_playthrough(map_id)

	if OS.get_environment("FREESTYLE_SCAN_ONLY") != "1" and (map_filter.is_empty() or map_filter == "uman"):
		for preset_idx in [10, 11, 12]:
			await _run_uman_preset_smoke(preset_idx)

	if TouchControls != null:
		if TouchControls.has_method("set_enabled"):
			TouchControls.set_enabled(prev_touch)
		else:
			TouchControls.enabled = prev_touch
	Engine.time_scale = 1.0
	Engine.max_physics_steps_per_frame = 8
	print("[FREESTYLE-QA] SUMMARY fails=", _fails, " shots=", _shot_count)
	get_tree().quit(1 if _fails > 0 else 0)


func _capture_shot(filename: String) -> void:
	if _shot_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	var dir := DirAccess.open(_shot_dir)
	if dir == null:
		DirAccess.make_dir_recursive_absolute(_shot_dir)
	var saved_scale := Engine.time_scale
	Engine.time_scale = 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	var tex := get_viewport().get_texture()
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_empty():
			var out_path := _shot_dir.path_join(filename)
			if img.save_png(out_path) == OK:
				_shot_count += 1
				print("[FREESTYLE-QA] SHOT ", out_path)
	Engine.time_scale = saved_scale


func _load_level(map_id: String, preset_idx: int) -> Node:
	get_tree().paused = false
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.special_mission = 0
	Global.menu_settings["selected_map"] = map_id
	Global.drone_preset = preset_idx
	Global.menu_settings["drone_preset"] = preset_idx
	var packed := load(SCENES[map_id]) as PackedScene
	if packed == null:
		return null
	var level := packed.instantiate()
	get_tree().root.add_child(level)
	for _i in range(6):
		await get_tree().physics_frame
	var rings: Array = level.get("_training_rings") if level.get("_training_rings") is Array else []
	for _w in range(45):
		rings = level.get("_training_rings") if level.get("_training_rings") is Array else []
		if rings.size() >= 24:
			break
		await get_tree().physics_frame
	var mobile_ui := OS.get_environment("MOBILE_UI") == "1"
	if TouchControls != null:
		if TouchControls.has_method("set_enabled"):
			TouchControls.set_enabled(mobile_ui)
		else:
			TouchControls.enabled = mobile_ui
			TouchControls.visible = mobile_ui
		TouchControls.touch_mode = mobile_ui
	if DisplayServer.get_name() != "headless":
		# Warm up Vulkan shader pipelines while drone is safely frozen before arming.
		for _pf in range(6):
			await get_tree().process_frame
	return level


func _cleanup_level(level: Node) -> void:
	get_tree().paused = false
	if level != null and is_instance_valid(level):
		level.queue_free()
	for _i in range(6):
		await get_tree().physics_frame


func _steer_towards(drone: Drone, radio: Node, target_pos: Vector3, next_pos: Vector3,
		hover_est: float, dist_to_gate: float, dt: float, max_speed: float = 22.0) -> void:
	var cur := drone.global_position
	var vel := drone.linear_velocity
	var cur_xz := Vector2(cur.x, cur.z)
	var tgt_xz := Vector2(target_pos.x, target_pos.z)
	var to_tgt_xz := tgt_xz - cur_xz
	var d_xz := to_tgt_xz.length()

	var fwd3 := -drone.global_basis.z
	var right3 := drone.global_basis.x
	var fwd_xz := Vector2(fwd3.x, fwd3.z)
	if fwd_xz.length_squared() < 0.0001:
		fwd_xz = Vector2(0.0, -1.0)
	else:
		fwd_xz = fwd_xz.normalized()
	var right_xz := Vector2(right3.x, right3.z)
	if right_xz.length_squared() < 0.0001:
		right_xz = Vector2(1.0, 0.0)
	else:
		right_xz = right_xz.normalized()

	var dir_xz := to_tgt_xz.normalized() if d_xz > 0.25 else fwd_xz
	# Blend gently toward exit leg when very close to gate center so transitions feel organic.
	if dist_to_gate < 7.0 and next_pos != target_pos:
		var nxt_xz := Vector2(next_pos.x - cur.x, next_pos.z - cur.z)
		if nxt_xz.length_squared() > 1.0:
			dir_xz = dir_xz.lerp(nxt_xz.normalized(), 0.28).normalized()

	var heading_err := atan2(fwd_xz.x * dir_xz.y - fwd_xz.y * dir_xz.x, fwd_xz.dot(dir_xz))
	var ang_y := drone.angular_velocity.y
	# Positive yaw stick turns clockwise (+X right when facing -Z, negative ang_vel.y).
	var yaw_cmd := clampf(heading_err * 0.45 + ang_y * 0.12, -0.45, 0.45)

	var vel_xz := Vector2(vel.x, vel.z)
	var cur_v_fwd := vel_xz.dot(fwd_xz)
	var cur_v_right := vel_xz.dot(right_xz)

	var alt_err := target_pos.y - cur.y
	var d_alt := (alt_err - _prev_alt_err) / maxf(dt, 0.001)
	_prev_alt_err = alt_err
	_alt_integral = clampf(_alt_integral + alt_err * dt * 0.18, -0.15, 0.25)
	var des_vy := clampf(alt_err * 1.6 + clampf(d_alt, -5.0, 5.0) * 0.12, -6.0, 10.0)
	var vy_err := des_vy - vel.y
	var up_cos := clampf(drone.global_basis.y.y, 0.48, 1.0)
	var base_thr := clampf((hover_est + _alt_integral) / up_cos, 0.28, 0.82)
	var thr_cmd := clampf(base_thr + vy_err * 0.11, 0.24, 0.94)

	# Keep pitch/roll strictly inside [-0.50, 0.50] so HORIZON stays pure self-leveling angle mode.
	var low_climb := alt_err > 1.8 and vel.y < 1.2
	var turn_slow := clampf(1.0 - absf(heading_err) / 1.35, 0.28, 1.0)
	var target_speed := clampf(d_xz * 1.15, 6.5, max_speed) * turn_slow
	if low_climb:
		target_speed = minf(target_speed, 7.0)
	elif dist_to_gate < 9.0:
		target_speed = minf(target_speed, 16.5)

	var des_v_xz := dir_xz * target_speed
	var des_v_fwd := des_v_xz.dot(fwd_xz)
	var des_v_right := des_v_xz.dot(right_xz)

	var fwd_err := des_v_fwd - cur_v_fwd
	var right_err := des_v_right - cur_v_right

	var tilt_cap := 0.28 if low_climb else 0.50
	var pitch_cmd := clampf(-fwd_err * 0.075, -tilt_cap, minf(0.42, tilt_cap))
	var roll_cmd := clampf(right_err * 0.065, -tilt_cap, tilt_cap)

	radio.set("test_throttle", thr_cmd)
	radio.set("test_yaw", yaw_cmd)
	radio.set("test_pitch", pitch_cmd)
	radio.set("test_roll", roll_cmd)


func _fly_gates(level: Node, target_gate_count: int, max_sim_sec: float,
		shot_prefix: String = "") -> Dictionary:
	var drone := level.get_node_or_null("Drone") as Drone
	var radio := level.get_node_or_null("RadioController")
	var fc := drone.flight_controller if drone != null else null
	var rings: Array = level.get("_training_rings") if level.get("_training_rings") is Array else []
	var hover_est := float(fc.throttle_hover_point) if fc != null else 0.48
	if hover_est <= 0.15 or hover_est >= 0.85:
		hover_est = 0.48
	print("[FREESTYLE-QA] flight start hover_est=", snappedf(hover_est, 0.01),
			" drone_pos=", drone.global_position if drone != null else Vector3.ZERO)
	_prev_alt_err = 0.0
	_alt_integral = 0.0

	if fc == null or radio == null or drone == null or rings.is_empty():
		return {"passed": 0, "nav_changed": false, "finished": false, "failed": true, "score": 0, "time": 0.0}

	if not shot_prefix.is_empty():
		# Capture clean initial launch framing before dynamic chase tilt, then fly.
		await _capture_shot("01_%s_start.png" % shot_prefix)

	fc.select_flight_mode(FlightController.FlightMode.HORIZON)
	radio.set("test_throttle", hover_est)
	radio.set("test_yaw", 0.0)
	radio.set("test_pitch", 0.0)
	radio.set("test_roll", 0.0)
	fc.set_armed(true)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var max_steps := int(max_sim_sec / dt)
	var nav_seen_next := false
	var mid_shot_taken := false
	var last_passed := 0
	var stuck_steps := 0

	for step in range(max_steps):
		if bool(level.get("_mission_finished")):
			break
		var passed := int(level.get("_rings_passed"))
		if passed >= target_gate_count:
			break
		if passed != last_passed:
			print("[FREESTYLE-QA] gate %d/%d passed t=%.1fs pos=%s" % [
				passed, rings.size(), float(level.get("_mission_time")), str(drone.global_position)])
			last_passed = passed
			stuck_steps = 0
		else:
			stuck_steps += 1
		if stuck_steps > int(28.0 / dt):
			print("[FREESTYLE-QA] STUCK at gate %d/%d pos=%s" % [
				passed + 1, rings.size(), str(drone.global_position)])
			break

		var nav := level.get("_nav_marker") as Label
		if passed >= 1 and nav != null and not nav.text.contains(" 1/"):
			nav_seen_next = true

		var cur_ring := rings[passed] as Area3D
		var nxt_ring := rings[mini(passed + 1, rings.size() - 1)] as Area3D
		var tgt := cur_ring.global_position if cur_ring != null else drone.global_position
		var nxt_pos := nxt_ring.global_position if nxt_ring != null else tgt
		var dist := drone.global_position.distance_to(tgt)
		var cruise_max := 26.0 if level.get("frontline_map") == "airport" else 22.0
		_steer_towards(drone, radio, tgt, nxt_pos, hover_est, dist, dt, cruise_max)

		if not shot_prefix.is_empty() and not mid_shot_taken and passed >= 5 and dist < 24.0:
			mid_shot_taken = true
			await _capture_shot("02_%s_midflight.png" % shot_prefix)

		if stuck_steps == int(12.0 / dt):
			print("[FREESTYLE-QA] STALL-DIAG gate=%d/%d pos=%s tgt=%s vel=%s euler=%s in=%s" % [
				passed + 1, rings.size(), str(drone.global_position), str(tgt),
				str(drone.linear_velocity), str(drone.global_basis.get_euler()), str(fc.input)])

		await get_tree().physics_frame

	if not shot_prefix.is_empty() and bool(level.get("_mission_finished")):
		await get_tree().process_frame
		await _capture_shot("03_%s_debrief.png" % shot_prefix)

	return {
		"passed": int(level.get("_rings_passed")),
		"nav_changed": nav_seen_next,
		"finished": bool(level.get("_mission_finished")),
		"failed": bool(level.get("_mission_failed")),
		"score": int(level.get("_score")),
		"time": float(level.get("_mission_time")),
	}


func _scan_course_corridors(level: Node, map_id: String, rings: Array) -> void:
	var drone := level.get_node_or_null("Drone") as CollisionObject3D
	var world: World3D = (level as Node3D).get_world_3d() if level is Node3D else null
	if world == null or rings.is_empty():
		return
	var space := world.direct_space_state
	if space == null:
		return
	var excludes: Array[RID] = []
	if drone != null:
		excludes.append(drone.get_rid())
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	for i in range(rings.size()):
		var a_node := rings[i] as Area3D
		if a_node == null:
			continue
		var p0: Vector3 = drone.global_position if (i == 0 and drone != null) else (rings[i - 1] as Area3D).global_position
		var p1: Vector3 = a_node.global_position
		var dist := p0.distance_to(p1)
		var steps := maxi(int(ceil(dist / 5.0)), 2)
		for s in range(1, steps):
			var pt := p0.lerp(p1, float(s) / float(steps))
			var gy := float(level.call("_find_ground_y", pt.x, pt.z))
			if pt.y < gy + 1.5:
				print("[CORRIDOR] %s leg %d->%d LOW_GROUND pt=%s gy=%.2f" % [map_id, i, i + 1, str(pt), gy])
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = sphere
			q.transform = Transform3D(Basis.IDENTITY, pt)
			q.collision_mask = 1
			q.collide_with_bodies = true
			q.collide_with_areas = false
			q.exclude = excludes
			var hits := space.intersect_shape(q, 4)
			for h in hits:
				var col = h.get("collider")
				var nm := str(col.name) if col is Node else str(col)
				if nm in ["UmanSafetyGround", "FrontlineGround", "Ground", "GroundBody", "Terrain", "AirportGround"] or nm.begins_with("UmanGround"):
					continue
				print("[CORRIDOR] %s leg %d->%d HIT=%s at pt=%s (gate=%s)" % [map_id, i, i + 1, nm, str(pt), str(p1)])
				break


func _run_map_playthrough(map_id: String) -> void:
	print("[FREESTYLE-QA] === MAP: ", map_id, " ===")
	var ghost_path := "user://ghost_training_%s.rpl" % map_id
	var old_ghost := ""
	if FileAccess.file_exists(ghost_path):
		old_ghost = FileAccess.get_file_as_string(ghost_path)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ghost_path))

	var preset_idx := DroneCatalog.first_for_map(map_id)
	var level := await _load_level(map_id, preset_idx)
	_check(level != null, "%s: level instantiated" % map_id)
	if level == null:
		return

	var rings: Array = level.get("_training_rings") if level.get("_training_rings") is Array else []
	_check(rings.size() == 24, "%s: 24 gates spawned (%d)" % [map_id, rings.size()])

	var blocked_gates := 0
	var vis_gates := 0
	var active_mon := 0
	var grounded_arches := 0
	var aerial_gates := 0
	var floating_arches := 0
	var bad_aerial_feet := 0
	for r in rings:
		var a := r as Area3D
		if a == null or not is_instance_valid(a):
			continue
		if a.visible:
			vis_gates += 1
		if a.monitoring:
			active_mon += 1
		var rad := float(a.get_meta("ring_radius", 4.5)) * 0.7 + 0.8
		if not bool(level.call("_freestyle_gate_clear", a.global_position, rad)):
			blocked_gates += 1
		var shp := int(a.get_meta("ring_shape", -1))
		var r_sz := float(a.get_meta("ring_radius", 4.6))
		var fl := a.get_node_or_null("FootLeft") as MeshInstance3D
		var fr := a.get_node_or_null("FootRight") as MeshInstance3D
		if shp == 1:
			grounded_arches += 1
			var g_here := float(level.call("_find_ground_y", a.global_position.x, a.global_position.z))
			var agl_here := a.global_position.y - g_here
			var legs_ok := bool(a.get_meta("arch_grounded", false)) and fl != null and fr != null \
					and agl_here <= r_sz * 1.50
			if legs_ok:
				var gl := float(level.call("_find_ground_y", fl.global_position.x, fl.global_position.z))
				var gr := float(level.call("_find_ground_y", fr.global_position.x, fr.global_position.z))
				if absf(fl.global_position.y - (gl + 0.12)) >= 0.45 \
						or absf(fr.global_position.y - (gr + 0.12)) >= 0.45:
					legs_ok = false
			if not legs_ok:
				floating_arches += 1
		else:
			aerial_gates += 1
			if fl != null or fr != null:
				bad_aerial_feet += 1
	print("[FREESTYLE-QA] %s shapes: grounded_arches=%d aerial=%d floating_arches=%d bad_aerial_feet=%d" % [
		map_id, grounded_arches, aerial_gates, floating_arches, bad_aerial_feet])
	_check(vis_gates == 24 and active_mon == 1, "%s: 24 visible, 1 monitoring (%d/%d)" % [map_id, vis_gates, active_mon])
	_check(blocked_gates == 0, "%s: 0 blocked gates (%d)" % [map_id, blocked_gates])
	_check(floating_arches == 0 and bad_aerial_feet == 0, "%s: arches grounded, aerial clean (%d/%d)" % [map_id, floating_arches, bad_aerial_feet])
	if OS.get_environment("FREESTYLE_SCAN_ONLY") == "1":
		_scan_course_corridors(level, map_id, rings)
		await _cleanup_level(level)
		return

	var reb := level.get_node_or_null("RebSystem")
	_check(reb != null, "%s: RebSystem exists" % map_id)
	if reb != null:
		_check(bool(reb.get("unlimited_freestyle")), "%s: RebSystem unlimited_freestyle=true" % map_id)
		var domes: Array = reb.get("ew_domes") if reb.get("ew_domes") is Array else []
		_check(domes.is_empty(), "%s: 0 EW domes in Freestyle (%d)" % [map_id, domes.size()])

	var res := await _fly_gates(level, 24, 220.0, map_id)
	print("[FREESTYLE-QA] %s flight result=%s" % [map_id, str(res)])
	_check(int(res["passed"]) == 24, "%s: completed 24/24 gates (%d/24)" % [map_id, int(res["passed"])])
	_check(bool(res["nav_changed"]), "%s: HUD nav marker updated past gate 1" % map_id)
	_check(bool(res["finished"]) and not bool(res["failed"]), "%s: mission finished cleanly" % map_id)
	_check(int(res["score"]) > 0 and float(res["time"]) > 5.0, "%s: valid score/time (%d / %.1fs)" % [map_id, int(res["score"]), float(res["time"])])
	var res_panel = level.get("_results")
	_check(res_panel != null and bool(res_panel.visible), "%s: debrief results visible" % map_id)
	_check(FileAccess.file_exists(ghost_path), "%s: ghost replay file created" % map_id)

	# Respawn reset test
	level.call("request_respawn")
	for _k in range(10):
		await get_tree().physics_frame
	_check(int(level.get("_rings_passed")) == 0 and int(level.get("_score")) == 0,
			"%s: respawn resets gates and score cleanly" % map_id)

	await _cleanup_level(level)

	# Second load: verify Ghost loads & plays with live meshes without script errors
	if map_id in ["uman", "airport"]:
		var level2 := await _load_level(map_id, preset_idx)
		if level2 != null:
			var g := level2.get("_ghost_node") as Ghost
			_check(g != null, "%s: ghost reloaded on second sortie" % map_id)
			if g != null:
				_check(g.replay.size() > 10, "%s: ghost has %d samples" % [map_id, g.replay.size()])
				_check(g.get_child_count() > 0, "%s: ghost 3D mesh loaded (%d children)" % [map_id, g.get_child_count()])
				var d2 := level2.get_node_or_null("Drone") as Drone
				var r2 := level2.get_node_or_null("RadioController")
				if d2 != null and d2.flight_controller != null:
					d2.flight_controller.select_flight_mode(FlightController.FlightMode.HORIZON)
					if r2 != null:
						var h2 := float(d2.flight_controller.throttle_hover_point)
						r2.set("test_throttle", h2 if h2 > 0.2 else 0.45)
						r2.set("test_yaw", 0.0)
						r2.set("test_pitch", 0.0)
						r2.set("test_roll", 0.0)
					d2.flight_controller.set_armed(true)
					for _f in range(36):
						await get_tree().physics_frame
					_check(g.frame > 0 and g.state == Ghost.State.PLAYING,
							"%s: ghost playback advancing (frame=%d)" % [map_id, g.frame])
			await _cleanup_level(level2)

	if not old_ghost.is_empty():
		var wf := FileAccess.open(ghost_path, FileAccess.WRITE)
		if wf != null:
			wf.store_string(old_ghost)
			wf.close()
	elif FileAccess.file_exists(ghost_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ghost_path))


func _run_uman_preset_smoke(preset_idx: int) -> void:
	var p := DroneCatalog.preset(preset_idx)
	var pname := str(p.get("name", str(preset_idx)))
	var level := await _load_level("uman", preset_idx)
	_check(level != null, "Uman preset %s: loaded" % pname)
	if level == null:
		return
	var res := await _fly_gates(level, 4, 35.0, "")
	_check(int(res["passed"]) >= 4, "Uman preset %s: flew smoothly through 4 gates (%d/4)" % [pname, int(res["passed"])])
	await _cleanup_level(level)
