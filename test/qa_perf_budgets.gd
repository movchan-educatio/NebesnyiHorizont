extends Node

## P0 Mobile/LOW performance budget & parity QA suite:
##   1. CCIP / BombBallistics solve p95 < 2.0 ms + Airport flat ground_at parity
##   2. GroundRoutePlanner < 1500 ms + expired deadline < 50 ms fallback
##   3. Airport LOW draw calls <= 1200, triangles <= 350000, MultiMesh trees batched
##   4. Explosion dispatch p95 < 1.0 ms & DestructionFx LOW active particle cap <= 40 + 0 leak
##   5. PerformanceGovernor 60 FPS cap recovery

const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")
const BallisticsScript = preload("res://combat/ballistics.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const DestructionFxScript = preload("res://combat/destruction_fx.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const PerfGovernorScript = preload("res://scripts/util/performance_governor.gd")

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[PERF_QA] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _percentile(sorted_vals: Array[float], q: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx := clampi(int(ceil(float(sorted_vals.size()) * q)) - 1, 0, sorted_vals.size() - 1)
	return sorted_vals[idx]


func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in range(mesh.get_surface_count()):
		var prim: Mesh.PrimitiveType = (mesh as ArrayMesh).surface_get_primitive_type(s) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		var arr := mesh.surface_get_arrays(s)
		if arr.is_empty():
			continue
		var idx = arr[Mesh.ARRAY_INDEX]
		var verts = arr[Mesh.ARRAY_VERTEX]
		var count := 0
		if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
			count = (idx as PackedInt32Array).size()
		elif verts is PackedVector3Array:
			count = (verts as PackedVector3Array).size()
		if prim == Mesh.PRIMITIVE_TRIANGLES:
			total += count / 3
		elif prim == Mesh.PRIMITIVE_TRIANGLE_STRIP and count >= 3:
			total += count - 2
	return total


func _count_scene_geometry(root: Node, stats: Dictionary) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root is Node3D and not (root as Node3D).is_visible_in_tree():
		return
	if root is MultiMeshInstance3D:
		var mmi := root as MultiMeshInstance3D
		if mmi.name.begins_with("AirportOak_MM_") or mmi.name.begins_with("AirportPine_MM_"):
			stats["mm_trees"] = int(stats["mm_trees"]) + 1
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var mm := mmi.multimesh
			var inst_cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			if inst_cnt > 0:
				stats["mm_surfaces"] = int(stats["mm_surfaces"]) + mm.mesh.get_surface_count()
				stats["tris"] = int(stats["tris"]) + _mesh_tris(mm.mesh) * inst_cnt
	elif root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.name.begins_with("AirportTree"):
			stats["loose_trees"] = int(stats["loose_trees"]) + 1
		if mi.mesh != null:
			stats["mesh_surfaces"] = int(stats["mesh_surfaces"]) + mi.mesh.get_surface_count()
			stats["tris"] = int(stats["tris"]) + _mesh_tris(mi.mesh)
	for child in root.get_children():
		_count_scene_geometry(child, stats)


func _run() -> void:
	var had_no_record := OS.has_environment("DRONE_NO_RECORD")
	var saved_no_record := OS.get_environment("DRONE_NO_RECORD")
	var had_no_ambient := OS.has_environment("QA_NO_AMBIENT")
	var saved_no_ambient := OS.get_environment("QA_NO_AMBIENT")
	var had_quality := OS.has_environment("DRONE_QUALITY")
	var saved_quality := OS.get_environment("DRONE_QUALITY")
	var saved_max_fps := Engine.max_fps

	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	OS.set_environment("DRONE_QUALITY", "low")

	var saved_mode := int(Global.play_mode)
	var saved_special := int(Global.special_mission)
	var saved_combat := int(Global.combat_mission)
	var saved_briefing := bool(Global.chain_briefing_pending)

	Global.play_mode = Global.PlayMode.COMBAT
	Global.chain_briefing_pending = false
	var airport_packed := load("res://sceneries/AirportLevel.tscn") as PackedScene

	# 2. GroundRoutePlanner < 1500 ms (clean Special 2 escort world) + expired deadline < 50 ms fallback
	Global.special_mission = 2
	Global.combat_mission = 1
	var escort_level := airport_packed.instantiate() as Node3D
	get_tree().root.add_child(escort_level)
	get_tree().current_scene = escort_level
	get_tree().paused = false
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = false
	var reserved: Array = escort_level.get("_reserved_ground_route")
	var from_pt: Vector3 = reserved[0] if reserved.size() >= 2 else Vector3(-330.0, 0.12, 255.0)
	var to_pt: Vector3 = reserved[reserved.size() - 1] if reserved.size() >= 2 else Vector3(330.0, 0.12, 255.0)
	var rt0 := Time.get_ticks_usec()
	var route := GroundRoutePlanner.plan(escort_level, from_pt, to_pt, 10.0, 418.0)
	var route_ms := float(Time.get_ticks_usec() - rt0) / 1000.0
	print("[PERF_QA] ground_route_ms=%.2f reserved_wps=%d replanned_wps=%d" % [
		route_ms, reserved.size(), route.size()])
	_check(route_ms < 1500.0 and reserved.size() >= 2 and route.size() >= 2,
			"GroundRoutePlanner completed in %.2f ms (< 1500 ms, %d wps)" % [route_ms, route.size()])

	var planner := GroundRoutePlanner.new()
	planner._setup(escort_level, 10.0, 418.0)
	planner._deadline = Time.get_ticks_usec() - 1
	var dl0 := Time.get_ticks_usec()
	var aborted := planner._astar(0, planner._size * planner._size - 1)
	var dl_ms := float(Time.get_ticks_usec() - dl0) / 1000.0
	_check(aborted.is_empty() and dl_ms < 50.0,
			"GroundRoutePlanner expired deadline aborted in %.3f ms (< 50 ms)" % dl_ms)

	if is_instance_valid(escort_level):
		if get_tree().current_scene == escort_level:
			get_tree().current_scene = null
		escort_level.queue_free()
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout

	Global.special_mission = 0
	Global.combat_mission = 1
	var airport_level := airport_packed.instantiate() as Node3D
	get_tree().root.add_child(airport_level)
	get_tree().current_scene = airport_level
	get_tree().paused = false
	await get_tree().create_timer(1.2).timeout
	get_tree().paused = false

	# 1. CCIP / Ballistics p95 < 2.0 ms & Airport ground_at parity
	var _warmup := BallisticsScript.simulate(
			airport_level, "airport", Vector3(20.0, 48.0, 15.0),
			Vector3(12.0, -2.0, -8.0), Vector3(3.0, 0.0, 1.5), "82mm", 0.05)
	var ccip_times: Array[float] = []
	for mname in ["steppe", "village", "airport"]:
		for kind in ["vog", "82mm", "120mm", "tm62"]:
			for _i in range(60):
				var t0 := Time.get_ticks_usec()
				var _sol := BallisticsScript.simulate(
						airport_level, mname, Vector3(20.0, 48.0, 15.0),
						Vector3(12.0, -2.0, -8.0), Vector3(3.0, 0.0, 1.5), kind, 0.05)
				ccip_times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	ccip_times.sort()
	var ccip_p50 := _percentile(ccip_times, 0.50)
	var ccip_p95 := _percentile(ccip_times, 0.95)
	var ccip_max := ccip_times[ccip_times.size() - 1]
	print("[PERF_QA] ccip_ms p50=%.4f p95=%.4f max=%.4f samples=%d" % [
		ccip_p50, ccip_p95, ccip_max, ccip_times.size()])
	_check(ccip_p95 < 2.0, "CCIP/Ballistics p95 %.4f ms < 2.0 ms" % ccip_p95)
	var apt_g := BallisticsScript.ground_at(airport_level, "airport", 0.0, 0.0)
	var apt_t := FrontlineTerrainScript.height_at("airport", 80.0, -60.0)
	_check(absf(apt_g - 0.12) < 0.05 and absf(apt_t - 0.12) < 0.05,
			"Airport flat ground parity (ballistics=%.2f terrain=%.2f)" % [apt_g, apt_t])

	# 3. Airport LOW draw calls <= 1200, triangles <= 350000, MultiMesh trees
	var geo := {"mesh_surfaces": 0, "mm_surfaces": 0, "tris": 0, "mm_trees": 0, "loose_trees": 0}
	_count_scene_geometry(airport_level, geo)
	var total_draws := int(geo["mesh_surfaces"]) + int(geo["mm_surfaces"])
	var total_tris := int(geo["tris"])
	print("[PERF_QA] airport_low mesh_surf=%d mm_surf=%d total_draws=%d total_tris=%d mm_trees=%d loose_trees=%d" % [
		geo["mesh_surfaces"], geo["mm_surfaces"], total_draws, total_tris, geo["mm_trees"], geo["loose_trees"]])
	_check(total_draws <= 1200, "Airport LOW draws %d <= 1200" % total_draws)
	_check(total_tris <= 350000, "Airport LOW triangles %d <= 350000" % total_tris)
	_check(int(geo["mm_trees"]) >= 2 and int(geo["loose_trees"]) == 0,
			"Airport trees batched via MultiMesh (%d MM, %d loose)" % [geo["mm_trees"], geo["loose_trees"]])

	# 4. Weapon fire / explosion dispatch < 1.0 ms p95 & LOW particle cap <= 40 + 0 leak
	var fx_holder := Node3D.new()
	fx_holder.name = "PerfFxHolder"
	airport_level.add_child(fx_holder)
	CombatSfxScript.boom_stream()
	var warm_exp := ExplosionScript.spawn(fx_holder, Vector3(0.0, 2.0, 0.0), 8.0, 0.0)
	var warm_fx := DestructionFxScript.spawn_multiphase_explosion(fx_holder, Vector3(2.0, 2.0, 0.0), 1.0, 0.12, false)
	await get_tree().process_frame
	if is_instance_valid(warm_exp):
		warm_exp.queue_free()
	if is_instance_valid(warm_fx):
		warm_fx.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var exp_times: Array[float] = []
	for i in range(20):
		var pos := Vector3(float(i) * 3.0, 1.5, -20.0)
		var et0 := Time.get_ticks_usec()
		var _ex := ExplosionScript.spawn(fx_holder, pos, 8.0, 0.0)
		exp_times.append(float(Time.get_ticks_usec() - et0) / 1000.0)
	exp_times.sort()
	var exp_p95 := _percentile(exp_times, 0.95)
	print("[PERF_QA] explosion_dispatch_ms p95=%.4f max=%.4f" % [exp_p95, exp_times[exp_times.size() - 1]])
	_check(exp_p95 < 1.0, "Explosion dispatch p95 %.4f ms < 1.0 ms" % exp_p95)

	for i in range(12):
		var pos := Vector3(-40.0 + float(i) * 5.0, 0.5, 40.0)
		DestructionFxScript.spawn_multiphase_explosion(fx_holder, pos, 1.0, 0.12, false)
	for i in range(4):
		var wreck := Node3D.new()
		wreck.position = Vector3(-15.0 + float(i) * 10.0, 0.12, 55.0)
		fx_holder.add_child(wreck)
		DestructionFxScript.burn(wreck, wreck.global_position, "vehicle", 6.0, 0.12)
	var active_ps := DestructionFxScript._active_particle_systems
	print("[PERF_QA] low_active_particle_systems=%d (cap=40)" % active_ps)
	_check(active_ps <= 40, "DestructionFx LOW active particle systems %d <= 40" % active_ps)

	fx_holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var leaked_ps := DestructionFxScript._active_particle_systems
	_check(leaked_ps == 0, "DestructionFx active particle systems released cleanly (%d == 0)" % leaked_ps)

	# 5. PerformanceGovernor 60 FPS cap recovery
	Engine.max_fps = 60
	var gov := PerfGovernorScript.new()
	add_child(gov)
	gov.configure({
		"target_fps": 60.0,
		"scale_3d": 0.80,
		"min_scale": 0.55,
		"max_scale": 0.85,
		"adaptive": true,
		"mobile_profile": true,
	})
	gov.set("_warmup", 0.0)
	for _i in range(90):
		gov._process(1.0 / 45.0)
	var dropped_scale := gov.current_scale()
	for _i in range(400):
		gov._process(1.0 / 59.5)
	var recovered_scale := gov.current_scale()
	print("[PERF_QA] perf_gov dropped=%.2f recovered=%.2f" % [dropped_scale, recovered_scale])
	_check(dropped_scale < 0.80 and recovered_scale > dropped_scale,
			"PerformanceGovernor drops on 45 FPS (%.2f) and recovers at 59.5 FPS (%.2f)" % [
				dropped_scale, recovered_scale])
	gov.queue_free()

	if is_instance_valid(airport_level):
		if get_tree().current_scene == airport_level:
			get_tree().current_scene = null
		airport_level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	Engine.max_fps = saved_max_fps
	Global.play_mode = saved_mode
	Global.special_mission = saved_special
	Global.combat_mission = saved_combat
	Global.chain_briefing_pending = saved_briefing
	_restore_env("DRONE_NO_RECORD", had_no_record, saved_no_record)
	_restore_env("QA_NO_AMBIENT", had_no_ambient, saved_no_ambient)
	_restore_env("DRONE_QUALITY", had_quality, saved_quality)

	print("[PERF_QA] failures=%d" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _restore_env(key: String, existed: bool, value: String) -> void:
	if existed:
		OS.set_environment(key, value)
	else:
		OS.unset_environment(key)
