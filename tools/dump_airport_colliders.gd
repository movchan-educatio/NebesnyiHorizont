extends Node

## QA helper: instantiate the airport level and list every static collider so
## route planning can distinguish terrain from real obstacles.
##   Godot --headless --path . res://tools/dump_airport_colliders.tscn

func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("QA_NO_AMBIENT", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 2
	Global.combat_mission = 1
	Global.chain_briefing_pending = false
	var level: Node = (load("res://sceneries/AirportLevel.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.0).timeout
	var bodies: Array[StaticBody3D] = []
	_collect(level, bodies)
	print("[AIRPORT-QA] static bodies: ", bodies.size())
	var counts := {}
	for b in bodies:
		var key := b.name.substr(0, 14)
		counts[key] = int(counts.get(key, 0)) + 1
	for key in counts.keys():
		print("[AIRPORT-QA] prefix ", key, " = ", counts[key])
	for b in bodies:
		if b.name.begins_with("Collision_"):
			var aabb := _body_aabb(b)
			print("[AIRPORT-QA] ", b.name, " center=", aabb.get_center(), " size=", aabb.size)
	convoy_info(level)
	get_tree().quit(0)


func convoy_info(level: Node) -> void:
	var convoy = level.get("_special_convoy")
	if convoy == null:
		print("[AIRPORT-QA] no convoy")
		return
	var wps: PackedVector3Array = convoy.get("_waypoints")
	print("[AIRPORT-QA] convoy pos=", convoy.global_position,
			" dest=", level.get("_special_convoy_dest"), " waypoints=", wps.size())


func _collect(node: Node, out: Array[StaticBody3D]) -> void:
	if node is StaticBody3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _body_aabb(body: StaticBody3D) -> AABB:
	var out := AABB()
	var first := true
	for c in body.get_children():
		if c is not CollisionShape3D:
			continue
		var shape: Shape3D = (c as CollisionShape3D).shape
		if shape == null:
			continue
		var local := AABB()
		if shape is ConcavePolygonShape3D:
			local = AABB()
			var faces := (shape as ConcavePolygonShape3D).get_faces()
			for v in faces:
				local = local.merge(AABB(v, Vector3.ZERO))
		elif shape is BoxShape3D:
			var hs := (shape as BoxShape3D).size * 0.5
			local = AABB(-hs, hs * 2.0)
		elif shape is CylinderShape3D:
			var r := (shape as CylinderShape3D).radius
			var h := (shape as CylinderShape3D).height
			local = AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
		else:
			local = AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
		var world := body.global_transform * (c as CollisionShape3D).transform * local
		if first:
			out = world
			first = false
		else:
			out = out.merge(world)
	return out
