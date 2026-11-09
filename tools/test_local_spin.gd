@tool
extends SceneTree

func _init() -> void:
	var n := Node3D.new()
	n.rotation_degrees = Vector3(20.0, 0, 0)
	print("Initial rotation: ", n.rotation_degrees)
	
	var n_y := Node3D.new()
	n_y.rotation_degrees = Vector3(20.0, 0, 0)
	n_y.rotate_y(PI / 2.0)
	print("After rotate_y(90 deg):\n  rot=", n_y.rotation_degrees, "\n  basis.y=", n_y.basis.y)
	
	var n_local := Node3D.new()
	n_local.rotation_degrees = Vector3(20.0, 0, 0)
	n_local.rotate_object_local(Vector3.UP, PI / 2.0)
	print("After rotate_object_local(UP, 90 deg):\n  rot=", n_local.rotation_degrees, "\n  basis.y=", n_local.basis.y)
	quit()
