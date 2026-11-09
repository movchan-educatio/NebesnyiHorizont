extends SceneTree

func _init():
	var glb = load("res://Assets/Drones/ua_norm/falcon_x.glb")
	var inst = glb.instantiate()
	var frame = inst.find_child("Object_28", true, false) as MeshInstance3D
	var mesh = frame.mesh
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	print("Object_28 vertex count = ", mdt.get_vertex_count())
	var vs_fl = []
	var vs_bl = []
	for i in range(mdt.get_vertex_count()):
		var v = mdt.get_vertex(i)
		if v.x < -0.06 and v.z > 0.02:
			vs_fl.append(v)
		elif v.x < -0.06 and v.z < -0.02:
			vs_bl.append(v)
	if vs_fl.size() > 0:
		var sum_v = Vector3.ZERO
		for v in vs_fl: sum_v += v
		var avg = sum_v / vs_fl.size()
		print("FL arm in Godot mesh: count=", vs_fl.size(), " avg=", avg)
	if vs_bl.size() > 0:
		var sum_v = Vector3.ZERO
		for v in vs_bl: sum_v += v
		var avg = sum_v / vs_bl.size()
		print("BL arm in Godot mesh: count=", vs_bl.size(), " avg=", avg)
	var m_fl = inst.find_child("motor_FL", true, false)
	var m_bl = inst.find_child("motor_BL", true, false)
	print("motor_FL in Godot: ", m_fl.position if m_fl else "none")
	print("motor_BL in Godot: ", m_bl.position if m_bl else "none")
	quit()
