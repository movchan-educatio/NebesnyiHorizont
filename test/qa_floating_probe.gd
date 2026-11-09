extends Node

## QA: dump every large mesh/multimesh AABB above the industrial terrain and
## the material texture, to tell roofs from intentional overhead wires.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var level_path := OS.get_environment("QA_FLOAT_LEVEL")
	if level_path.is_empty():
		level_path = "res://sceneries/IndustrialLevel.tscn"
	var packed := load(level_path) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var map_name: String = str(level.get("frontline_map"))
	if map_name.is_empty():
		map_name = "village" if level_path.contains("Village") else "industrial"
	var rows: Array = []
	_walk(level, level, map_name, rows)
	rows.sort_custom(func(a, b): return float(a["bottom"]) > float(b["bottom"]))
	print("[FLOAT2] suspicious=", rows.size())
	for i in range(mini(rows.size(), 120)):
		var r: Dictionary = rows[i]
		print("[FLOAT2] bottom=%.1f top=%.1f size=%s name=%s tex=%s path=%s" % [
			float(r["bottom"]), float(r["top"]), str(r["size"]), str(r["name"]),
			str(r["tex"]), str(r["path"])])
	# Also list all factory-complex children for a ground-truth comparison.
	var fc := level.get_node_or_null("FrontlineTerrain/Handcrafted_factory_complex")
	if fc != null:
		print("[FLOAT2] factory children:")
		for c in fc.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var bb: AABB = mi.global_transform * mi.get_aabb()
			print("[FLOAT2]   %s bottom=%.1f top=%.1f size=%s" % [
				mi.name, bb.position.y, bb.end.y, str(bb.size)])
	# Also list tower-like nodes and positions.
	for n in level.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("tower") or nm.contains("chim") or nm.contains("silo"):
			print("[FLOAT2] TOWER ", level.get_path_to(n), " pos=", (n as Node3D).global_position)
	# List all house/cottage/farm-like meshes with their world AABBs.
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi2 := n as MeshInstance3D
		if mi2 == null or mi2.mesh == null:
			continue
		var nm2 := String(mi2.name).to_lower()
		var path2 := String(level.get_path_to(mi2)).to_lower()
		if nm2.contains("house") or nm2.contains("cottage") or nm2.contains("barn") \
				or nm2.contains("farm") or path2.contains("handcrafted"):
			var bb2: AABB = mi2.global_transform * mi2.get_aabb()
			print("[FLOAT2] HOUSE ", level.get_path_to(mi2), " pos=", bb2.position,
					" size=", bb2.size, " visible=", mi2.is_visible_in_tree())
	var ct := level.get_node_or_null("FrontlineTerrain/CoolingTower") as MeshInstance3D
	if ct != null:
		var idx = ct.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		print("[FLOAT2] COOL visible=", ct.is_visible_in_tree(), " xf=", ct.global_transform,
				" aabb=", ct.get_aabb(), " surfaces=", ct.mesh.get_surface_count(),
				" indices=", 0 if idx == null else (idx as PackedInt32Array).size(),
				" layers=", ct.layers, " range=", ct.visibility_range_end,
				" parent_vis=",
				(ct.get_parent() as Node3D).visible if ct.get_parent() is Node3D else "?")
	get_tree().quit()


func _walk(node: Node, level: Node, map_name: String, rows: Array) -> void:
	if node is GeometryInstance3D and not (node as GeometryInstance3D).is_visible_in_tree():
		return
	var mi := node as MeshInstance3D
	var mmi := node as MultiMeshInstance3D
	if (mi != null and mi.mesh != null) or (mmi != null and mmi.multimesh != null):
		var nm := String(node.name).to_lower()
		var skip := nm.contains("ring") or nm.contains("cloud") or nm.contains("mountain") \
				or nm.contains("sky") or nm.contains("horizon") or nm.contains("water") \
				or nm.contains("grass") or nm.contains("tree") or nm.contains("leaf") \
				or nm.contains("canopy") or nm.contains("bird") or nm.contains("smoke") \
				or nm.contains("hud") or nm.contains("drone") or nm.contains("marker") \
				or nm.contains("beam") or nm.contains("moon") or nm.contains("sun") \
				or nm.contains("decal") or nm.contains("shadow") or nm.contains("impostor")
		if not skip:
			var aabb: AABB
			if mmi != null:
				aabb = mmi.global_transform * mmi.get_aabb()
			else:
				aabb = mi.global_transform * mi.get_aabb()
			if aabb.size.x > 1.0 and aabb.size.z > 1.0 and aabb.size.y > 0.4 \
					and aabb.position.y < 400.0:
				var cx := aabb.get_center().x
				var cz := aabb.get_center().z
				var ground := TERRAIN.height_at(map_name, cx, cz)
				if aabb.position.y > ground + 4.0:
					var tex := _tex_of(mi, mmi)
					rows.append({"bottom": aabb.position.y, "top": aabb.end.y,
							"size": aabb.size, "name": node.name, "tex": tex,
							"path": String(level.get_path_to(node))})
	for child in node.get_children():
		if child == level.get_node_or_null("Drone"):
			continue
		_walk(child, level, map_name, rows)


func _tex_of(mi: MeshInstance3D, mmi: MultiMeshInstance3D) -> String:
	var mat: Material = null
	if mmi != null:
		mat = mmi.material_override
		if mat == null and mmi.multimesh.mesh != null:
			mat = mmi.multimesh.mesh.surface_get_material(0)
	elif mi != null:
		mat = mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
	var sm := mat as StandardMaterial3D
	if sm != null and sm.albedo_texture != null:
		return sm.albedo_texture.resource_path.get_file()
	return "none"
