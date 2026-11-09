@tool
extends SceneTree

func _init() -> void:
	var path := "res://Assets/Drones/ua_norm/falcon_x.glb"
	var scn := load(path) as PackedScene
	if scn == null:
		print("Failed to load ", path)
		quit()
		return
	var inst := scn.instantiate()
	print("Loaded ", path)
	for child in inst.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var m: Mesh = mi.mesh
			if m == null:
				continue
			var aabb := mi.get_aabb()
			print("Mesh: ", mi.name, " aabb_pos: ", aabb.position, " aabb_size: ", aabb.size)
			# Find vertices around the 4 motor locations: X around +-0.1
			var arrays = m.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var fl_verts: Array[Vector3] = []
			var bl_verts: Array[Vector3] = []
			for v in verts:
				# Check FL: X < -0.08, Z > 0.03
				if v.x < -0.07 and v.z > 0.03:
					fl_verts.append(v)
				# Check BL: X < -0.07, Z < -0.02
				if v.x < -0.07 and v.z < -0.02:
					bl_verts.append(v)
			if fl_verts.size() > 0:
				var min_y := 999.0
				var max_y := -999.0
				var avg_y := 0.0
				for v in fl_verts:
					min_y = minf(min_y, v.y)
					max_y = maxf(max_y, v.y)
					avg_y += v.y
				avg_y /= fl_verts.size()
				print("  -> ", mi.name, " FL candidate verts count=", fl_verts.size(), " Y min=", min_y, " max=", max_y, " avg=", avg_y)
			if bl_verts.size() > 0:
				var min_y := 999.0
				var max_y := -999.0
				var avg_y := 0.0
				for v in bl_verts:
					min_y = minf(min_y, v.y)
					max_y = maxf(max_y, v.y)
					avg_y += v.y
				avg_y /= bl_verts.size()
				print("  -> ", mi.name, " BL candidate verts count=", bl_verts.size(), " Y min=", min_y, " max=", max_y, " avg=", avg_y)
	quit()
