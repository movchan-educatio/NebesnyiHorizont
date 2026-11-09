extends SceneTree

func _init() -> void:
	var ps := load("res://Assets/Drones/ua_norm/pisun_vtol.glb") as PackedScene
	var inst := ps.instantiate()
	root.add_child(inst)
	_dump(inst, 0)
	for n in ["motor_FL","propeller_FL","motor_BL","propeller_BL"]:
		var x := inst.find_child(n, true, false) as Node3D
		if x:
			print(n, " global=", x.global_position, " local=", x.position, " rot=", x.rotation_degrees, " scale=", x.scale)
	quit()

func _dump(n: Node, d: int) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		if d <= 2 or "motor" in n.name or "propeller" in n.name:
			print("  ".repeat(d), n.name, " g=", n3.global_position, " l=", n3.position, " r=", n3.rotation_degrees)
	for c in n.get_children():
		_dump(c, d+1)
