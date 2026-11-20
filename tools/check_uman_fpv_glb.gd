extends SceneTree

## Headless QA for the Uman FPV drone pack: verifies each GLB imports and
## exposes the motor/propeller pivots expected by DronePropellerSystem.

func _initialize() -> void:
	var paths: Array[String] = [
		"res://Assets/UmanFPV/drones/Uman_Freestyle_3.glb",
		"res://Assets/UmanFPV/drones/Uman_Freestyle_5.glb",
		"res://Assets/UmanFPV/drones/Uman_Freestyle_7.glb",
	]
	var ok := true
	for path in paths:
		if not ResourceLoader.exists(path):
			print("[UMAN-FPV] FAIL missing resource: ", path)
			ok = false
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			print("[UMAN-FPV] FAIL not a PackedScene: ", path)
			ok = false
			continue
		var root := scene.instantiate() as Node3D
		var names: Array[String] = []
		_collect_names(root, names)
		var corners := ["FL", "FR", "BR", "BL"]
		var motors: Array[String] = []
		var props: Array[String] = []
		for c in corners:
			if names.has("motor_" + c):
				motors.append("motor_" + c)
			if names.has("propeller_" + c):
				props.append("propeller_" + c)
		var meshes := names.filter(func(n: String) -> bool: return n.ends_with("_bell") or n.ends_with("_blades"))
		print("[UMAN-FPV] ", path.get_file(), " | nodes=", names.size(),
			" motors=", motors, " props=", props, " mesh_instances=", meshes.size())
		if motors.size() != 4 or props.size() != 4:
			print("[UMAN-FPV] FAIL pivot count for ", path)
			ok = false
		root.free()
	print("[UMAN-FPV] RESULT=", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _collect_names(node: Node, out: Array[String]) -> void:
	out.append(node.name)
	for child in node.get_children():
		_collect_names(child, out)


func _aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
