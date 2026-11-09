extends SceneTree

const FT := preload("res://scripts/util/frontline_terrain.gd")

func _init():
	for map_name in ["steppe", "industrial", "village", "wetlands"]:
		print("\n==========================================")
		print("  ANALYZING MAP: ", map_name)
		print("==========================================")
		var sc := load("res://sceneries/BigLevel.tscn") as PackedScene
		var level = sc.instantiate()
		level.frontline_map = map_name
		root.add_child(level)

		for i in range(15):
			await process_frame

		var workshops: Array[Dictionary] = []
		var site: Dictionary = FT.HALL_SITES.get(map_name, {})
		if not site.is_empty():
			workshops.append({"name": "HeroHall_" + map_name, "pos": site["center"], "radius": 85.0})
		if map_name == "industrial":
			workshops.append({"name": "factory_complex", "pos": Vector2(-200.0, -180.0), "radius": 110.0})
			workshops.append({"name": "secondary_hall", "pos": Vector2(-125.0, 80.0), "radius": 75.0})
		elif map_name == "steppe":
			workshops.append({"name": "farm_complex", "pos": Vector2(40.0, 146.0), "radius": 95.0})
		elif map_name == "village":
			workshops.append({"name": "village_house", "pos": Vector2(60.0, -110.0), "radius": 70.0})
		elif map_name == "wetlands":
			workshops.append({"name": "wetlands_dock", "pos": Vector2(-60.0, -140.0), "radius": 70.0})

		print("1. CHECKING STRUCTURES NEAR WORKSHOPS:")
		for node in level.find_children("*", "Node3D", true, false):
			if node.get_parent() != level and node.get_parent().name != "FrontlineTerrain" and node.get_parent().name != "BigLevel":
				continue
			var nm: String = node.name
			if nm.begins_with("HeroHall") or nm.begins_with("Handcrafted") or nm.begins_with("Clipmap") or nm.begins_with("Terrain") or nm.begins_with("Water") or nm.begins_with("Road") or nm.begins_with("Sun") or nm.begins_with("Env"):
				continue
			var npos3: Vector3 = (node as Node3D).global_position
			var npos2 := Vector2(npos3.x, npos3.z)
			for ws in workshops:
				var d: float = npos2.distance_to(ws["pos"])
				if d < float(ws["radius"]):
					print("  -> NEAR WORKSHOP [", ws["name"], "] (dist=", int(d), "m): ", nm, " at ", npos3)

		print("\n2. CHECKING POTENTIALLY FLOATING MESHES:")
		var floating_count := 0
		for c in level.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var nm: String = mi.name
			if nm.contains("Wire") or nm.contains("Cable") or nm.contains("Grass") or nm.contains("Leaf") or nm.contains("Foliage") or nm.contains("VFX") or nm.contains("Drone"):
				continue
			var aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if aabb.size.y < 0.8 or (aabb.size.x < 1.0 and aabb.size.z < 1.0):
				continue
			
			var min_terrain := 9999.0
			var max_terrain := -9999.0
			for ox: float in [-0.4, 0.0, 0.4]:
				for oz: float in [-0.4, 0.0, 0.4]:
					var tx: float = aabb.position.x + aabb.size.x * (0.5 + ox)
					var tz: float = aabb.position.z + aabb.size.z * (0.5 + oz)
					var ty: float = FT._height(map_name, tx, tz)
					min_terrain = minf(min_terrain, ty)
					max_terrain = maxf(max_terrain, ty)

			var gap: float = aabb.position.y - max_terrain
			if gap > 0.4:
				var min_gap: float = aabb.position.y - min_terrain
				var pnode: Node = mi.get_parent()
				var parent_name: String = pnode.name if pnode != null else ""
				# Only report if parent itself or this node is a standalone structure
				if not parent_name.contains("HeroHall") and not parent_name.contains("Handcrafted"):
					print("  FLOATING: ", nm, " (parent=", parent_name, ") pos.y=", aabb.position.y, " terrain=[", min_terrain, " .. ", max_terrain, "] gap=", gap, " min_gap=", min_gap, " at (", aabb.get_center().x, ", ", aabb.get_center().z, ")")
					floating_count += 1
					if floating_count > 30:
						print("  ... too many floating objects, stopping output for this map ...")
						break

		level.free()

	quit()
