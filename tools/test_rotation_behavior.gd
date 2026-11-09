@tool
extends SceneTree

func _init() -> void:
	var parent := Node3D.new()
	var child := Node3D.new()
	parent.add_child(child)
	
	parent.rotation_degrees.x = -90.0
	print("Parent rot: ", parent.rotation_degrees)
	print("Child basis before rotate_y:\n", child.basis)
	child.rotate_y(PI / 4.0)
	print("Child basis after rotate_y:\n", child.basis)
	print("Child global_transform.basis:\n", child.global_transform.basis)
	
	var child2 := Node3D.new()
	parent.add_child(child2)
	child2.rotate_object_local(Vector3.UP, PI / 4.0)
	print("Child2 after rotate_object_local UP:\n", child2.basis)
	quit()
