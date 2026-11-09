extends Node

## QA: the tallest City building must have a real through-opening.
## One ray goes through the opening, one through the solid wall above it.


func _ready() -> void:
	var packed := load("res://sceneries/CityLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var city := level.get_node_or_null("City") as Node3D
	if city == null:
		print("[CITYTUN] no city")
		get_tree().quit(1)
		return
	var best_h := 0.0
	var best_cs: CollisionShape3D = null
	var best_mn := Vector3.ZERO
	var best_mx := Vector3.ZERO
	var shapes := 0
	for c in city.get_children():
		if not (c is StaticBody3D):
			continue
		for child in c.get_children():
			var cs := child as CollisionShape3D
			if cs == null or not (cs.shape is ConcavePolygonShape3D):
				continue
			var shape := cs.shape as ConcavePolygonShape3D
			var faces := shape.get_faces()
			if faces.size() < 3:
				continue
			shapes += 1
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := Vector3(-1e9, -1e9, -1e9)
			for p in faces:
				var w: Vector3 = cs.global_transform * p
				mn = mn.min(w)
				mx = mx.max(w)
			var h := mx.y - mn.y
			if h > best_h:
				best_h = h
				best_cs = cs
				best_mn = mn
				best_mx = mx
	print("[CITYTUN] trimeshes=", shapes, " tallest=", snappedf(best_h, 0.1))
	if best_cs == null:
		get_tree().quit(1)
		return
	var center := (best_mn + best_mx) * 0.5
	var sx := best_mx.x - best_mn.x
	var sz := best_mx.z - best_mn.z
	var space := level.get_world_3d().direct_space_state
	var ok := true
	for band in [["low", 0.12], ["mid", 0.45], ["high", 0.68]]:
		var y_open := best_mn.y + best_h * float(band[1])
		var from: Vector3
		var to: Vector3
		if sx < sz:
			from = Vector3(best_mn.x - 5.0, y_open, center.z)
			to = Vector3(best_mx.x + 5.0, y_open, center.z)
		else:
			from = Vector3(center.x, y_open, best_mn.z - 5.0)
			to = Vector3(center.x, y_open, best_mx.z + 5.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		var open_hit: Dictionary = space.intersect_ray(q)
		print("[CITYTUN] ", band[0], "_open_clear=", open_hit.is_empty())
		if not open_hit.is_empty():
			ok = false
	var y_wall := best_mn.y + best_h * 0.85
	var from2: Vector3
	var to2: Vector3
	if sx < sz:
		from2 = Vector3(best_mn.x - 5.0, y_wall, center.z)
		to2 = Vector3(best_mx.x + 5.0, y_wall, center.z)
	else:
		from2 = Vector3(center.x, y_wall, best_mn.z - 5.0)
		to2 = Vector3(center.x, y_wall, best_mx.z + 5.0)
	var q2 := PhysicsRayQueryParameters3D.create(from2, to2)
	q2.collision_mask = 1
	var wall_hit: Dictionary = space.intersect_ray(q2)
	print("[CITYTUN] wall_hit=", not wall_hit.is_empty())
	if wall_hit.is_empty():
		ok = false
	print("[CITYTUN] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
