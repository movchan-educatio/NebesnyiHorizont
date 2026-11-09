extends SceneTree

func _init() -> void:
	var p := PrismMesh.new()
	p.size = Vector3(10.0, 4.0, 8.0)
	var arrays := p.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var seen := {}
	for v in verts:
		var key := Vector3(snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001))
		seen[key] = true
	print("PRISM verts=", seen.keys())
	var shape := p.create_convex_shape()
	print("CONVEX points=", shape.points)
	quit()
