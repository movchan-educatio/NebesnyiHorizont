extends Node

## Consolidated release-readiness regression test covering all 4 milestone
## requirements on both desktop and MOBILE_UI=1:
##   1. Combat-only drone fleet (no training/Magura, no TAC-05 naval mission)
##   2. Infantry single-rifle integrity + forward-knee crouch without foot slip
##   3. UI/settings cleanup (no intro video, no Artificial Horizon, no font/video toggles)
##   4. iOS Haptics / Vibration API behavior & real Drone signal integration

const HapticsScript = preload("res://scripts/util/haptics.gd")
const MainMenuScript = preload("res://GUI/MainMenu.gd")
const OtherSettingsScript = preload("res://GUI/OtherSettingsScreen.gd")

var _fails := 0


func _check(cond: bool, label: String) -> void:
	print("[RELEASE-QA] ", "PASS " if cond else "FAIL ", label)
	if not cond:
		_fails += 1


func _collect_texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for child in root.find_children("*", "", true, false):
		var t = child.get("text")
		if t is String and not (t as String).is_empty():
			out.append(t as String)
		var tt = child.get("tooltip_text")
		if tt is String and not (tt as String).is_empty():
			out.append(tt as String)
	return out


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved_preset := int(Global.drone_preset)
	var saved_menu := Global.menu_settings.duplicate(true)
	var saved_records := Global.campaign_records.duplicate(true)
	var saved_hud := GameSettings.hud_config.duplicate(true)

	await _test_fleet_and_campaign()
	await _test_ui_and_settings()
	await _test_infantry_rig_and_crouch()
	await _test_haptics_api_and_drone()

	Global.drone_preset = saved_preset
	Global.menu_settings = saved_menu
	Global.campaign_records = saved_records
	GameSettings.hud_config = saved_hud

	print("[RELEASE-QA] mobile_ui=", MenuUI.is_mobile_ui(), " fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)


func _test_fleet_and_campaign() -> void:
	_check(DroneCatalog.count() == 10, "DroneCatalog has exactly 10 combat presets")
	var has_magura_id := false
	for i in range(DroneCatalog.count()):
		var p := DroneCatalog.preset(i)
		var dname := String(p.get("name", ""))
		var pid := String(p.get("id", "")).to_lower()
		if pid.contains("magura"):
			has_magura_id = true
		_check(DroneCatalog.is_combat(i), "preset %d (%s) is combat" % [i, dname])
		_check(not bool(p.get("is_naval", false)),
				"preset %d (%s) has no is_naval flag" % [i, dname])
		_check(not dname.to_lower().contains("магура")
				and not dname.to_lower().contains("magura"),
				"preset %d (%s) is not Magura" % [i, dname])
	_check(not has_magura_id, "magura preset id no longer exists")
	for fpv_idx in [7, 8, 9]:
		var fp := DroneCatalog.preset(fpv_idx)
		_check(bool(fp.get("fixed_wing", false))
				and int(fp.get("payload", 0)) >= 1
				and bool(fp.get("kamikaze", false)),
				"fixed-wing preset %d is armed combat strike drone" % fpv_idx)

	# Campaign size capped at 4 missions (TAC-01..TAC-04).
	Global.campaign_records = {}
	for m in [1, 2, 3]:
		Global.campaign_records["mission_%d" % m] = {"completed": true, "stars": 2}
	_check(Global.campaign_completed_count() == 3, "campaign count tracks 3 completed")
	_check(not Global.campaign_is_complete(), "campaign not complete at 3/4")
	Global.campaign_records["mission_4"] = {"completed": true, "stars": 3}
	Global.campaign_records["mission_5"] = {"completed": true, "stars": 3}
	_check(Global.campaign_completed_count() == 4, "campaign count ignores legacy mission 5")
	_check(Global.campaign_is_complete(), "campaign complete at 4/4")

	_check(MainMenuScript.BRIEFINGS.size() == 4
			and not MainMenuScript.BRIEFINGS.has(5),
			"MainMenu BRIEFINGS has 4 missions and drops TAC-05")
	_check(MainMenuScript.BRIEFINGS_EN.size() == 4
			and not MainMenuScript.BRIEFINGS_EN.has(5),
			"MainMenu BRIEFINGS_EN has 4 missions and drops TAC-05")

	await get_tree().process_frame


func _test_ui_and_settings() -> void:
	# 1. StartScreen: zero VideoStreamPlayer / video intro / TAC-05 text.
	var start_scene := load("res://GUI/StartScreen.tscn") as PackedScene
	var sstate := start_scene.get_state()
	var packed_has_video := false
	for idx_s in range(sstate.get_node_count()):
		if sstate.get_node_type(idx_s) == "VideoStreamPlayer":
			packed_has_video = true
	_check(not packed_has_video, "StartScreen packed scene has no VideoStreamPlayer")
	if not MenuUI.is_mobile_ui():
		var start_inst := start_scene.instantiate()
		add_child(start_inst)
		await get_tree().process_frame
		var video_nodes := start_inst.find_children("*", "VideoStreamPlayer", true, false)
		_check(video_nodes.is_empty(), "StartScreen has 0 VideoStreamPlayer nodes")
		_check(not ("_video" in start_inst), "StartScreen has no _video property")
		_check(not ("_sound_toggle" in start_inst), "StartScreen has no _sound_toggle property")
		start_inst.queue_free()
		await get_tree().process_frame

	# 2. HUDLadder & HUD & HUDConfig: zero HorizonLine / CheckHorizon.
	var ladder_scene := load("res://HUD/HUDLadder.tscn") as PackedScene
	var ladder := ladder_scene.instantiate()
	_check(ladder.find_child("HorizonLine", true, false) == null,
			"HUDLadder has no HorizonLine node")
	ladder.free()

	var hud_scene := load("res://HUD/HUD.tscn") as PackedScene
	var hud := hud_scene.instantiate()
	_check(hud.find_child("HorizonLine", true, false) == null,
			"HUD has no HorizonLine node")
	hud.free()

	var hud_cfg_scene := load("res://GUI/HUDConfig.tscn") as PackedScene
	var hud_cfg := hud_cfg_scene.instantiate()
	_check(hud_cfg.find_child("CheckHorizon", true, false) == null,
			"HUDConfig has no CheckHorizon node")
	hud_cfg.free()

	# 3. Config schemas exclude "horizon", "mobile_font_scale", "video_audio".
	_check(not GameSettings.hud_config.has("horizon"),
			"GameSettings.hud_config excludes horizon")
	_check(not GameSettings.hud_config.has("mobile_font_scale"),
			"GameSettings.hud_config excludes mobile_font_scale")
	_check(Global.menu_settings.has("haptics_enabled"),
			"Global.menu_settings exposes haptics_enabled")
	_check(not Global.menu_settings.has("video_audio"),
			"Global.menu_settings excludes video_audio")
	for toggle in OtherSettingsScript.HUD_TOGGLES:
		_check(String(toggle[0]) != "horizon",
				"OtherSettingsScreen HUD_TOGGLES excludes horizon (%s)" % str(toggle[0]))

	# 4. MainMenu, OtherSettingsScreen & MobileMenu UI exclude removed elements.
	var mm_scene := load("res://GUI/MainMenu.tscn") as PackedScene
	var mm := mm_scene.instantiate()
	add_child(mm)
	await get_tree().process_frame
	var mm_texts := " | ".join(_collect_texts(mm))
	_check(not mm_texts.contains("TAC-05") and not mm_texts.contains("МАГУРА-Х"),
			"MainMenu UI excludes TAC-05 and Magura")
	mm.queue_free()
	await get_tree().process_frame

	# 4. OtherSettingsScreen & MobileMenu UI contain none of the excluded controls.
	var other_scene := load("res://GUI/OtherSettingsScreen.tscn") as PackedScene
	var other := other_scene.instantiate()
	add_child(other)
	await get_tree().process_frame
	var other_texts := " | ".join(_collect_texts(other))
	_check(not other_texts.contains("Штучний горизонт")
			and not other_texts.contains("Розмір шрифту")
			and not other_texts.contains("Звук відео"),
			"OtherSettingsScreen excludes horizon, font slider and intro video sound")
	other.queue_free()
	await get_tree().process_frame

	var mobile_scene := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	var mobile := mobile_scene.instantiate()
	add_child(mobile)
	await get_tree().process_frame
	var mobile_texts := " | ".join(_collect_texts(mobile))
	_check(not mobile_texts.contains("Штучний горизонт")
			and not mobile_texts.contains("Розмір шрифту")
			and not mobile_texts.contains("Звук вступного відео")
			and not mobile_texts.contains("TAC-05")
			and not mobile_texts.contains("МАГУРА-Х"),
			"MobileMenu excludes horizon, font scale, TAC-05 and Magura")
	_check(mobile_texts.contains("Тактильний відгук"),
			"MobileMenu exposes haptics toggle")
	mobile.queue_free()
	await get_tree().process_frame

	# 5. FlightController.FlightMode.HORIZON flight mode stays intact.
	var mode_drone := (load("res://drone/drones/Drone1.tscn") as PackedScene).instantiate() as Drone
	add_child(mode_drone)
	await get_tree().process_frame
	GameSettings.hud_config["angle_mode"] = false
	GameSettings.hud_config["acro_mode"] = false
	var fc: FlightController = mode_drone.flight_controller
	fc.flight_mode = FlightController.FlightMode.RATE
	fc._on_cycle_flight_modes()
	_check(fc.flight_mode == FlightController.FlightMode.HORIZON,
			"FlightController.FlightMode.HORIZON still functions as flight mode")
	mode_drone.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_infantry_rig_and_crouch() -> void:
	# 1. DetailedSoldierRig: single rifle (0 baked Line01_028 vertices), procedural RiflePivot present.
	var rig := DetailedSoldierRig.new()
	add_child(rig)
	await get_tree().process_frame
	var rig_ok := rig.setup_rig(0)
	_check(rig_ok and rig.rifle_pivot != null and rig.get_node_or_null("RiflePivot") != null,
			"DetailedSoldierRig creates procedural RiflePivot")

	var w_bone := int(rig.call("_bone", DetailedSoldierRig.WEAPON_BONE_NAME))
	var remaining_weapon_verts := 0
	for n in rig.model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var arr := mi.mesh.surface_get_arrays(s)
			var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var bones := arr[Mesh.ARRAY_BONES] as PackedInt32Array
			var weights := arr[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array
			if verts != null and bones != null and weights != null and w_bone >= 0:
				var stride := bones.size() / maxi(verts.size(), 1)
				for v in range(verts.size()):
					var ws := 0.0
					for k in range(stride):
						if bones[v * stride + k] == w_bone:
							ws += weights[v * stride + k]
					if ws > 0.5:
						remaining_weapon_verts += 1
	_check(remaining_weapon_verts == 0,
			"DetailedSoldierRig strips baked weapon Line01_028 (verts=%d)" % remaining_weapon_verts)

	# 2. Crouch kinematics: constant foot height, forward knees, flat foot pitch.
	var sk := rig.skeleton
	var b_pel := int(rig.get("_b_pelvis"))
	var b_calf_l := int(rig.get("_b_calf_l"))
	var b_foot_l := int(rig.get("_b_foot_l"))
	var foot_y_by_crouch: Dictionary = {}
	for c in [0.0, 0.5, 1.0]:
		rig.set("_crouch_target", c)
		rig.set("_crouch_t", c)
		rig.set("_crouch", c * c * (3.0 - 2.0 * c))
		rig.call("_update_pose", 0.0)
		sk.force_update_all_bone_transforms()
		var to_rig := rig.global_transform.affine_inverse() * sk.global_transform
		var pel_p := to_rig * sk.get_bone_global_pose(b_pel).origin
		var knee_p := to_rig * sk.get_bone_global_pose(b_calf_l).origin
		var foot_p := to_rig * sk.get_bone_global_pose(b_foot_l).origin
		var foot_by := (to_rig.basis * sk.get_bone_global_pose(b_foot_l).basis.y).normalized()
		foot_y_by_crouch[c] = foot_p.y
		_check(absf(foot_p.y - float(foot_y_by_crouch[0.0])) <= 0.005,
				"crouch=%.1f keeps foot anchored vertically (y=%.3f vs %.3f)" % [
					c, foot_p.y, float(foot_y_by_crouch[0.0])])
		_check(foot_by.y > -0.25,
				"crouch=%.1f keeps foot level without ankle flip (by.y=%.3f)" % [c, foot_by.y])
		if c >= 0.9:
			_check(knee_p.z < pel_p.z,
					"crouch=%.1f bends knees forward (-Z: knee=%.3f < pel=%.3f)" % [
						c, knee_p.z, pel_p.z])

	# 3. Mobile LOD resume immediately snaps crouch blend to _crouch_target.
	rig.set_mobile_animation_lod(300.0)
	rig.set_crouch(false)
	rig.set_mobile_animation_lod(30.0)
	_check(is_zero_approx(rig.is_crouching_blend()),
			"LOD resume immediately syncs crouch pose without pop")
	rig.queue_free()
	await get_tree().process_frame

	# 4. EnemyRifleman and ChaosSoldier zero horizontal crouch-sliding.
	var arena := Node3D.new()
	add_child(arena)
	var fake_drone := (load("res://drone/drones/Drone1.tscn") as PackedScene).instantiate() as Drone
	fake_drone.name = "Drone"
	fake_drone.position = Vector3(12.0, 4.0, -25.0)
	arena.add_child(fake_drone)

	var enemy := EnemyRifleman.new()
	enemy.position = Vector3(0.0, 0.0, 0.0)
	arena.add_child(enemy)

	var target_node := Node3D.new()
	target_node.position = Vector3(15.0, 0.0, -45.0)
	arena.add_child(target_node)
	var chaos := ChaosSoldier.new()
	chaos.position = Vector3(5.0, 0.0, 0.0)
	chaos.target = target_node
	arena.add_child(chaos)
	await get_tree().physics_frame
	await get_tree().process_frame

	enemy.set("_drone", fake_drone)
	enemy.set("_crouching", true)
	chaos.set("_crouching", true)
	var erig = enemy.get("_detailed_rig")
	var crig = chaos.get("_detailed_rig")
	if erig != null:
		erig.set("_crouch_target", 1.0)
		erig.set("_crouch_t", 1.0)
		erig.set("_crouch", 1.0)
	if crig != null:
		crig.set("_crouch_target", 1.0)
		crig.set("_crouch_t", 1.0)
		crig.set("_crouch", 1.0)

	var enemy_start := enemy.global_position
	var chaos_start := chaos.global_position
	for i in range(18):
		enemy.set("_crouching", true)
		chaos.set("_crouching", true)
		enemy._physics_process(0.03)
		chaos._physics_process(0.03)
	var enemy_slide := Vector2(enemy.global_position.x - enemy_start.x,
			enemy.global_position.z - enemy_start.z).length()
	var chaos_slide := Vector2(chaos.global_position.x - chaos_start.x,
			chaos.global_position.z - chaos_start.z).length()
	_check(enemy_slide < 0.002,
			"EnemyRifleman does not slide horizontally while crouched (delta=%.4f m)" % enemy_slide)
	_check(chaos_slide < 0.002,
			"ChaosSoldier does not slide horizontally while crouched (delta=%.4f m)" % chaos_slide)

	arena.queue_free()
	await get_tree().process_frame


func _test_haptics_api_and_drone() -> void:
	Global.menu_settings["haptics_enabled"] = true
	HapticsScript.reset_stats()

	_check(not HapticsScript.trigger_collision(1.0),
			"Haptics ignores gentle impacts below threshold")
	_check(HapticsScript.trigger_collision(6.0),
			"Haptics fires medium collision impulse")
	var s1 := HapticsScript.get_stats()
	_check(not HapticsScript.trigger_collision(5.0),
			"Haptics debounces repeated collision within cooldown")
	_check(HapticsScript.trigger_collision(17.5),
			"Haptics allows stronger collision override")
	var s2 := HapticsScript.get_stats()
	_check(int(s2.get("last_duration_ms", 0)) > int(s1.get("last_duration_ms", 0))
			and float(s2.get("last_amplitude", 0.0)) > float(s1.get("last_amplitude", 0.0)),
			"Haptics scales duration and amplitude with impact speed")

	_check(HapticsScript.trigger_crash(), "Haptics fires crash pulse")
	_check(HapticsScript.trigger_explosion(1.1), "Haptics fires explosion pulse")
	_check(HapticsScript.trigger_arm_toggle(true), "Haptics fires arm pulse")
	_check(HapticsScript.trigger_arm_toggle(false), "Haptics fires disarm pulse")
	_check(HapticsScript.trigger_ui_tap(), "Haptics fires UI tactical tap")

	# Motor tick must be suppressed immediately after a strong event, then resume.
	var crash_t0 := Time.get_ticks_msec()
	_check(HapticsScript.trigger_crash(), "Haptics crash sets strong-event override")
	_check(not HapticsScript.update_motor_feedback(true, 0.9, 15000.0, 20000.0, 0.2),
			"Haptics suppresses motor tick during strong override window")
	while Time.get_ticks_msec() - crash_t0 < HapticsScript.STRONG_OVERRIDE_MS + 25:
		await get_tree().process_frame
	_check(HapticsScript.update_motor_feedback(true, 0.9, 15000.0, 20000.0, 0.25),
			"Haptics emits motor feedback when armed under throttle after override (dt_ms=%d)" % [
				Time.get_ticks_msec() - crash_t0])
	_check(not HapticsScript.update_motor_feedback(false, 0.9, 15000.0, 20000.0, 0.25),
			"Haptics stops motor feedback when disarmed")

	# Disabled setting blocks every pulse.
	Global.menu_settings["haptics_enabled"] = false
	var before_dis := int(HapticsScript.get_stats().get("total_pulses", 0))
	_check(not HapticsScript.trigger_collision(12.0)
			and not HapticsScript.trigger_crash()
			and not HapticsScript.trigger_explosion(1.0)
			and not HapticsScript.trigger_arm_toggle(true)
			and not HapticsScript.trigger_ui_tap()
			and not HapticsScript.update_motor_feedback(true, 1.0, 18000.0, 20000.0, 0.3),
			"Haptics emits zero pulses when haptics_enabled is false")
	var after_dis := int(HapticsScript.get_stats().get("total_pulses", 0))
	_check(before_dis == after_dis, "Disabled haptics leaves pulse counter unchanged")

	# Real Drone integration check.
	Global.menu_settings["haptics_enabled"] = true
	HapticsScript.reset_stats()
	var drone := (load("res://drone/drones/Drone1.tscn") as PackedScene).instantiate() as Drone
	add_child(drone)
	await get_tree().process_frame
	drone.flight_controller.state_armed = true
	drone.call("_on_armed_signal")
	drone.call("_trigger_crash", "QA_TEST")
	drone.flight_controller.state_armed = false
	drone.call("_on_disarmed_signal")
	var by_tag: Dictionary = HapticsScript.get_stats().get("by_tag", {})
	_check(int(by_tag.get("arm", 0)) >= 1
			and int(by_tag.get("disarm", 0)) >= 1
			and int(by_tag.get("crash", 0)) >= 1,
			"Drone signal wiring emits arm/disarm/crash haptics (%s)" % str(by_tag))
	drone.queue_free()
	await get_tree().process_frame
