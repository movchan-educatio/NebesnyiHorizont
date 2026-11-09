extends Node

## QA-only draw-call / triangle breakdown for a frontline map.
## Runs the real level scene, then groups every visible geometry instance by
## category, so the next optimisation pass targets what actually issues draws.

const LEVEL_PATH := "res://sceneries/SteppeLevel.tscn"


func _ready() -> void:
	var level_path := OS.get_environment("PERF_LEVEL")
	if level_path.is_empty():
		level_path = LEVEL_PATH
	var packed := load(level_path) as PackedScene
	if packed == null:
		print("[PERF] cannot load ", level_path)
		get_tree().quit()
		return
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(4.0).timeout
	var groups := {}
	var misc_detail := {}
	_walk(level, level, groups, misc_detail)
	var rows: Array = []
	var total_draws := 0
	var total_tris := 0
	var total_nodes := 0
	for key in groups:
		var g: Dictionary = groups[key]
		rows.append([int(g["draws"]), int(g["tris"]), int(g["nodes"]), key])
		total_draws += int(g["draws"])
		total_tris += int(g["tris"])
		total_nodes += int(g["nodes"])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[PERF] total draws=%d tris=%d nodes=%d groups=%d" % [
			total_draws, total_tris, total_nodes, rows.size()])
	for i in range(mini(rows.size(), 50)):
		var r: Array = rows[i]
		print("[PERF] %6d draws %9d tris %5d nodes  %s" % [r[0], r[1], r[2], r[3]])
	var misc_rows: Array = []
	for key in misc_detail:
		misc_rows.append([int(misc_detail[key]), key])
	misc_rows.sort_custom(func(a, b): return a[0] > b[0])
	for i in range(mini(misc_rows.size(), 30)):
		print("[PERF] misc %5d draws  %s" % [misc_rows[i][0], misc_rows[i][1]])
	var inf := get_tree().get_nodes_in_group("enemy_infantry")
	var inf_meshes := 0
	var inf_surfaces := 0
	for unit in inf:
		for node in unit.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				inf_meshes += 1
				inf_surfaces += mi.mesh.get_surface_count()
	print("[PERF] infantry units=%d visible_meshes=%d surfaces=%d" % [
			inf.size(), inf_meshes, inf_surfaces])
	get_tree().quit()


func _walk(node: Node, level: Node, groups: Dictionary, misc_detail: Dictionary) -> void:
	if node is GeometryInstance3D and not (node as GeometryInstance3D).is_visible_in_tree():
		return
	var key := _group_key(node, level)
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		var draws := 0
		var tris := 0
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			draws = mmi.multimesh.mesh.get_surface_count()
			tris = _mesh_tris(mmi.multimesh.mesh) * mmi.multimesh.instance_count
		_add(groups, key, draws, tris)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var draws := 0
		var tris := 0
		if mi.mesh != null:
			draws = mi.mesh.get_surface_count()
			tris = _mesh_tris(mi.mesh)
		_add(groups, key, draws, tris)
		if key == "terrain/misc":
			var detail := _misc_name(node, level)
			misc_detail[detail] = int(misc_detail.get(detail, 0)) + draws
	elif node is GPUParticles3D or node is CPUParticles3D:
		_add(groups, key, 1, 0)
	for child in node.get_children():
		_walk(child, level, groups, misc_detail)


func _add(groups: Dictionary, key: String, draws: int, tris: int) -> void:
	if draws == 0 and tris == 0:
		return
	if not groups.has(key):
		groups[key] = {"draws": 0, "tris": 0, "nodes": 0}
	var g: Dictionary = groups[key]
	g["draws"] = int(g["draws"]) + draws
	g["tris"] = int(g["tris"]) + tris
	g["nodes"] = int(g["nodes"]) + 1


func _group_key(node: Node, level: Node) -> String:
	var chain: Array[Node] = []
	var cur := node
	while cur != null and cur != level:
		chain.push_front(cur)
		cur = cur.get_parent()
	if chain.is_empty():
		return "level"
	var top := String(chain[0].name)
	if top != "FrontlineTerrain":
		if top.begins_with("MissionInfantry"):
			return "infantry"
		if top.begins_with("Destructible") or top.begins_with("@Node3D"):
			return "destructibles"
		return top
	for i in range(1, chain.size()):
		var raw := String(chain[i].name).to_lower()
		if raw.contains("batchedprops"):
			return "terrain/batched props"
		if raw.contains("herohall") or raw.contains("halllights") or raw.contains("hallfog"):
			return "terrain/hall"
		if raw.contains("trunk") or raw.contains("leaves") or raw.contains("canopy") \
				or raw.contains("treeline"):
			return "terrain/trees"
		if raw.contains("grass") or raw.contains("tuft") or raw.contains("reed") \
				or raw.contains("flower") or raw.contains("scrub") or raw.contains("stone"):
			return "terrain/ground detail"
		if raw.begins_with("prop_"):
			return "terrain/props"
		if raw.begins_with("treecollision"):
			return "terrain/tree collision"
		if raw.begins_with("frontlineterrain"):
			continue
		if raw.begins_with("@"):
			continue
		if raw.contains("batched"):
			return "terrain/batched props"
		if raw.contains("cottage") or raw.contains("barn") or raw.contains("hospital") \
				or raw.contains("admin") or raw.contains("factory") or raw.contains("bridge") \
				or raw.contains("bunker") or raw.contains("checkpoint") or raw.contains("arch") \
				or raw.contains("observation") or raw.contains("pylon") or raw.contains("rock") \
				or raw.contains("hedgehog") or raw.contains("sandbag"):
			return "terrain/landmarks"
		if raw.contains("crop") or raw.contains("field") or raw.contains("orchard"):
			return "terrain/fields"
		if raw.contains("rubble") or raw.contains("ruin") or raw.contains("wreck") \
				or raw.contains("debris"):
			return "terrain/debris"
		if raw.contains("shrub") or raw.contains("bush") or raw.contains("oak") \
				or raw.contains("pine") or raw.contains("tree"):
			return "terrain/vegetation"
	return "terrain/misc"


func _misc_name(node: Node, level: Node) -> String:
	var ft := level.get_node_or_null("FrontlineTerrain")
	if ft == null:
		return "no terrain"
	var cur := node
	while cur != null and cur.get_parent() != ft:
		cur = cur.get_parent()
	if cur == null:
		return "outside"
	var raw := String(cur.name)
	if raw.begins_with("@"):
		raw = "procedural"
	raw = raw.split(".")[0]
	for suffix in ["_0", "_1", "_2", "_3", "_4", "_5", "_6", "_7", "_8", "_9"]:
		if raw.ends_with(suffix):
			raw = raw.substr(0, raw.length() - suffix.length())
			break
	return raw


func _mesh_tris(mesh: Mesh) -> int:
	var total := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.size() <= Mesh.ARRAY_INDEX or arrays[Mesh.ARRAY_INDEX] == null:
			var verts = arrays[Mesh.ARRAY_VERTEX]
			if verts != null:
				total += int(verts.size()) / 3
		else:
			total += int((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()) / 3
	return total
