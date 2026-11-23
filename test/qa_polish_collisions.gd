extends Node

## Phase 2B collision polish regression.
##
## Every named fly-through opening is probed twice: a physics ray along the
## centre line and a 0.25 m sphere (5" FPV drone) stepped along the same line.
## Solid members are probed with a ray that MUST hit.  Afterwards all four main
## level scenes are instantiated one by one in the real world and checked.

const R := 0.25

var _failures: Array[String] = []
var _checks := 0
var _sphere := SphereShape3D.new()
var _space: PhysicsDirectSpaceState3D
var _sub: SubViewport
var _arena: Node3D


func _ready() -> void:
	_sphere.radius = R
	call_deferred("_run")


func _settle(n: int = 3) -> void:
	for _i in range(n):
		await get_tree().physics_frame


func _force_tree(node: Node) -> void:
	if node == null:
		return
	if node is Node3D and node.is_inside_tree():
		(node as Node3D).force_update_transform()
	for c in node.get_children():
		_force_tree(c)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(label)
	print("[QA_POLISH_COLLISIONS] ", "ok   " if ok else "FAIL ", label)


## Ray + stepped-sphere sweep.  Both must be completely clear.
func _sweep_clear(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		label: String, verbose: bool = true) -> bool:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	rq.collision_mask = 1
	var rh := space.intersect_ray(rq)
	if not rh.is_empty():
		if verbose:
			_check(false, label + " ray hit " + str(rh.get("position")))
		return false
	var dist := from.distance_to(to)
	var steps := maxi(2, ceili(dist / (R * 1.5)))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.collision_mask = 1
	for i in range(steps + 1):
		q.transform = Transform3D(Basis(), from.lerp(to, float(i) / float(steps)))
		if not space.intersect_shape(q, 4).is_empty():
			if verbose:
				_check(false, label + " sphere hit @t=" + str(float(i) / float(steps)))
			return false
	if verbose:
		_check(true, label)
	return true


func _solid_hit(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3,
		label: String) -> void:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	rq.collision_mask = 1
	var hit := space.intersect_ray(rq)
	_check(not hit.is_empty(), label)


## The frontline props_library prop_pipe is authored with solid, vertex-coloured
## end caps / reinforcement rings: its *visible* mesh is closed, so an axial
## ray is expected to touch that mesh.  What must never happen is an invisible
## ConvexPolygonShape3D "plug" (the old generic convex hull) covering the bore.
func _sweep_no_convex_plug(space: PhysicsDirectSpaceState3D, from: Vector3,
		to: Vector3, label: String) -> bool:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	rq.collision_mask = 1
	if _hit_is_convex(space.intersect_ray(rq)):
		_check(false, label + " convex plug on ray")
		return false
	var dist := from.distance_to(to)
	var steps := maxi(2, ceili(dist / (R * 1.5)))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.collision_mask = 1
	for i in range(steps + 1):
		q.transform = Transform3D(Basis(), from.lerp(to, float(i) / float(steps)))
		for hit in space.intersect_shape(q, 8):
			if _hit_is_convex(hit):
				_check(false, label + " convex plug at t=" + str(float(i) / float(steps)))
				return false
	_check(true, label)
	return true


func _hit_is_convex(hit: Dictionary) -> bool:
	if hit.is_empty():
		return false
	var col := hit.get("collider") as Node
	if col == null:
		return false
	for found in col.find_children("*", "CollisionShape3D", true, false):
		if (found as CollisionShape3D).shape is ConvexPolygonShape3D:
			return true
	return false


func _mesh_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	for found in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(found as MeshInstance3D)
	for mi in meshes:
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var b := mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB()


func _longest_axis(box: AABB) -> Vector3:
	return Vector3.RIGHT if box.size.x >= box.size.z else Vector3.FORWARD


func _axis_half(box: AABB, axis: Vector3) -> float:
	return (box.size.x if axis == Vector3.RIGHT else box.size.z) * 0.5


func _run() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.combat_mission = 0
	Global.special_mission = 0
	Global.drone_preset = 6
	OS.set_environment("DRONE_NO_RECORD", "1")

	_sub = SubViewport.new()
	_sub.name = "QaPhysicsWorld"
	_sub.world_3d = World3D.new()
	add_child(_sub)
	_arena = Node3D.new()
	_arena.name = "QaArena"
	_sub.add_child(_arena)
	_space = _sub.world_3d.direct_space_state
	await _settle(2)

	await _test_structures()
	_test_prop_pipe()
	await _test_levels()

	print("[QA_POLISH_COLLISIONS] checks=", _checks, " failures=", _failures.size())
	if _failures.is_empty():
		print("[QA_POLISH_COLLISIONS] PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("[QA_POLISH_COLLISIONS] FAIL ", f)
		get_tree().quit(1)


func _test_structures() -> void:
	var base := Vector3.ZERO
	var step := Vector3(600.0, 0.0, 0.0)

	# 1. Three concrete culverts: bore clear, wall solid.
	var n := MilitaryStructures.build_concrete_pipe_culvert_course(
			_arena, base, 0.0)
	_force_tree(n)
	var pipes: Array[Node3D] = []
	for c in n.get_children():
		if c is Node3D:
			pipes.append(c as Node3D)
	_check(pipes.size() == 3, "culvert course has 3 barrels")
	for i in range(pipes.size()):
		var xf := pipes[i].global_transform
		_sweep_clear(_space, xf * Vector3(0, 0, -5.5), xf * Vector3(0, 0, 5.5),
				"culvert %d centre bore" % i)
		_solid_hit(_space, xf * Vector3(0, 0, 0), xf * Vector3(5.5, 0, 0),
				"culvert %d wall solid" % i)

	# 2. True hollow pipe.
	base += step
	n = MilitaryStructures.build_hollow_pipe(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 0, -7), base + Vector3(0, 0, 7),
			"hollow pipe centre bore")
	_solid_hit(_space, base, base + Vector3(4.5, 0, 0), "hollow pipe wall solid")

	# 3. Cooling tower: vertical funnel + N/S base breaches.
	base += step
	n = MilitaryStructures.build_cooling_tower_dive_funnel(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 36, 0), base + Vector3(0, 6, 0),
			"cooling tower vertical dive funnel")
	_sweep_clear(_space, base + Vector3(0, 2.5, -12), base + Vector3(0, 2.5, 12),
			"cooling tower N/S base breaches")
	_solid_hit(_space, base + Vector3(0, 15, 0), base + Vector3(12, 15, 0),
			"cooling tower wall solid")

	# 4. Damaged hangar: lengthwise centre + skylight dive.
	base += step
	n = MilitaryStructures.build_damaged_hangar_arch(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 5.0, -20), base + Vector3(0, 5.0, 20),
			"damaged hangar lengthwise centre y=5")
	_sweep_clear(_space, base + Vector3(0, 20, 2), base + Vector3(0, 1, 2),
			"damaged hangar skylight dive")
	_solid_hit(_space, base + Vector3(-16, 2, 0), base + Vector3(0, 2, 0),
			"damaged hangar side pillar solid")

	# 5. Radar relay: top ring bore + mast leg.
	base += step
	n = MilitaryStructures.build_radar_relay_station(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 21, -5), base + Vector3(0, 21, 5),
			"radar relay top ring bore")
	_solid_hit(_space, base + Vector3(0, 10, 1.5), base + Vector3(4, 10, 1.5),
			"radar relay mast leg solid")

	# 6. Bailey bridge / helipad hangar / military arch / artillery bunker /
	#    scaffolding cube: one open path and one solid member each.
	base += step
	n = MilitaryStructures.build_bailey_truss_bridge(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 3, -11), base + Vector3(0, 3, 11),
			"bailey bridge under-deck span")
	_solid_hit(_space, base + Vector3(0, 3, -20), base + Vector3(0, 3, -12),
			"bailey bridge abutment solid")

	base += step
	n = MilitaryStructures.build_fortified_helipad_hangar(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 3, -20), base + Vector3(0, 3, 20),
			"helipad hangar open ends")
	_sweep_clear(_space, base + Vector3(6, 16, 2), base + Vector3(6, 1, 2),
			"helipad hangar skylight dive")
	_solid_hit(_space, base, base + Vector3(14, 0, 0),
			"helipad hangar side wall solid")

	base += step
	n = MilitaryStructures.build_military_arch_portal(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(-5.75, 5, -8), base + Vector3(-5.75, 5, 8),
			"military arch portal opening")
	_solid_hit(_space, base + Vector3(0, 5, -8), base + Vector3(0, 5, 8),
			"military arch portal pier solid")

	base += step
	n = MilitaryStructures.build_artillery_bunker_complex(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(0, 2.5, -10), base + Vector3(0, 2.5, 10),
			"artillery bunker central corridor")
	_solid_hit(_space, base + Vector3(0, 2.5, 0), base + Vector3(10, 2.5, 0),
			"artillery bunker casemate solid")

	base += step
	n = MilitaryStructures.build_scaffolding_freestyle_cube(_arena, base, 0.0)
	_force_tree(n)
	_sweep_clear(_space, base + Vector3(-12, 7, 4), base + Vector3(12, 7, 4),
			"scaffolding cube open tier")
	_solid_hit(_space, base + Vector3(-12, 2, -8), base + Vector3(-6, 2, -8),
			"scaffolding cube post solid")


func _test_prop_pipe() -> void:
	var base := Vector3(4000.0, 0.0, 0.0)
	var inst := FrontlineAssets.spawn_prop(_arena, "prop_pipe", base, 0.0, 1.0)
	if inst == null:
		_check(false, "FrontlineAssets.spawn_prop(prop_pipe) returned null")
		return
	_force_tree(inst)
	var box := _mesh_aabb(inst)
	if box.size.length() < 0.1:
		_check(false, "prop_pipe has no visible mesh")
		return
	var axis := _longest_axis(box)
	var c := box.get_center()
	var half := _axis_half(box, axis)
	_sweep_no_convex_plug(_space, c - axis * (half + 2.0),
			c + axis * (half + 2.0), "prop_pipe axial sweep has no convex plug")
	var other := Vector3.FORWARD if axis == Vector3.RIGHT else Vector3.RIGHT
	_solid_hit(_space, c, c + other * (_axis_half(box, other) + 2.0),
			"prop_pipe wall solid")


func _test_levels() -> void:
	var paths := [
		"res://sceneries/IndustrialLevel.tscn",
		"res://sceneries/WetlandsLevel.tscn",
		"res://sceneries/AirportLevel.tscn",
		"res://sceneries/UmanLevel.tscn",
	]
	for path in paths:
		await _test_one_level(path)


func _test_one_level(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_check(false, path + " failed to load")
		return
	var level := packed.instantiate() as Node3D
	if level == null:
		_check(false, path + " failed to instantiate")
		return
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _settle(3)
	await get_tree().create_timer(0.35).timeout
	_force_tree(level)
	var space := level.get_world_3d().direct_space_state
	var tag := path.get_file().get_basename()
	_check(level.get_node_or_null("Drone") != null, tag + " spawned Drone (no script errors)")
	_check(space != null, tag + " has a physics space")

	if tag == "AirportLevel":
		await _check_airport(level, space, tag)
	else:
		_check_level_pipe(level, space, tag)

	level.queue_free()
	get_tree().current_scene = self
	await get_tree().process_frame
	await _settle(1)


func _check_airport(level: Node3D, space: PhysicsDirectSpaceState3D,
		tag: String) -> void:
	var wrecks := level.get_node_or_null("AirportLandmark_HangarAircraftWrecks") as Node3D
	if wrecks == null:
		_check(false, tag + " hangar landmark missing")
	else:
		var hm := wrecks.find_child("RuinedHangarFrame", true, false) as MeshInstance3D
		if hm == null or hm.mesh == null:
			_check(false, tag + " RuinedHangarFrame mesh missing")
		else:
			var bb := hm.global_transform * hm.get_aabb()
			var axis := _longest_axis(bb)
			var c := bb.get_center()
			c.y = wrecks.global_position.y + 7.5
			var half := _axis_half(bb, axis)
			_sweep_clear(space, c - axis * (half + 3.0), c + axis * (half + 3.0),
					tag + " hangar interior bay y=7.5")

	var depot := level.get_node_or_null("AirportLandmark_FuelDepot") as Node3D
	if depot == null:
		_check(false, tag + " fuel depot landmark missing")
		return
	var dm := depot.find_child("FuelDepotCisterns", true, false) as MeshInstance3D
	if dm == null or dm.mesh == null:
		_check(false, tag + " FuelDepotCisterns mesh missing")
		return
	var box := dm.global_transform * dm.get_aabb()
	var axis2 := _longest_axis(box)
	var c2 := box.get_center()
	c2.y = box.end.y + 2.0
	_sweep_clear(space, c2 - axis2 * (_axis_half(box, axis2) + 3.0),
			c2 + axis2 * (_axis_half(box, axis2) + 3.0),
			tag + " fuel depot overhead gap")

	# Between-tank gap: at least one vertical column through the footprint has
	# to be clear from above down to ground level.  The old 24x5x16 box sealed
	# every one of these columns.
	var gap_ok := false
	for gx in range(1, 7):
		for gz in range(1, 7):
			var px := box.position.x + box.size.x * float(gx) / 7.0
			var pz := box.position.z + box.size.z * float(gz) / 7.0
			var top := Vector3(px, box.end.y + 1.5, pz)
			var bottom := Vector3(px, box.position.y + 0.8, pz)
			if _sweep_clear(space, top, bottom, "", false):
				gap_ok = true
				break
		if gap_ok:
			break
	if not gap_ok:
		# Horizontal probe through the cistern row at a few low heights.
		for hy in [2.5, 3.5, 5.0]:
			for ax in [Vector3.RIGHT, Vector3.FORWARD]:
				var p := box.get_center()
				p.y = float(hy)
				var h2 := _axis_half(box, ax)
				if _sweep_clear(space, p - ax * (h2 + 2.0), p + ax * (h2 + 2.0),
						"", false):
					gap_ok = true
					break
			if gap_ok:
				break
	_check(gap_ok, tag + " fuel depot between-tank gaps passable")


func _check_level_pipe(level: Node3D, space: PhysicsDirectSpaceState3D,
		tag: String) -> void:
	var course := level.find_child("ConcretePipeCulvertCourse", true, false) as Node3D
	if course == null:
		var prop_col := level.find_child("PropPipeCollision", true, false) as Node3D
		if prop_col != null:
			var pbox := _body_aabb(prop_col)
			if pbox.size.length() > 0.1:
				var paxis := _longest_axis(pbox)
				var pc := pbox.get_center()
				var ph := _axis_half(pbox, paxis)
				_sweep_clear(space, pc - paxis * (ph + 2.0),
						pc + paxis * (ph + 2.0), tag + " PropPipeCollision bore")
				return
		# No authored pipe in this layout: spawn a fresh course in the same
		# world, far away from the map terrain.
		course = MilitaryStructures.build_concrete_pipe_culvert_course(level,
				Vector3(6000.0, 0.0, 6000.0), 0.0)
		_force_tree(course)
	var pipes: Array[Node3D] = []
	for c in course.get_children():
		if c is Node3D:
			pipes.append(c as Node3D)
	var cleared := 0
	for i in range(pipes.size()):
		var xf := pipes[i].global_transform
		if _sweep_clear(space, xf * Vector3(0, 0, -5.5), xf * Vector3(0, 0, 5.5),
				"", false):
			cleared += 1
	_check(pipes.size() > 0 and cleared == pipes.size(),
			tag + " culvert centre bores clear (%d/%d)" % [cleared, pipes.size()])


func _body_aabb(node: Node) -> AABB:
	var a := _mesh_aabb(node)
	if a.size.length() > 0.1:
		return a
	var box := AABB()
	var first := true
	for found in node.find_children("*", "CollisionShape3D", true, false):
		var cs := found as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var local := AABB()
		if cs.shape is BoxShape3D:
			var sz := (cs.shape as BoxShape3D).size
			local = AABB(-sz * 0.5, sz)
		elif cs.shape is ConcavePolygonShape3D:
			var pts := (cs.shape as ConcavePolygonShape3D).get_faces()
			var f := true
			for p in pts:
				if f:
					local = AABB(p, Vector3.ZERO)
					f = false
				else:
					local = local.expand(p)
		else:
			continue
		var b := cs.global_transform * local
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB()
