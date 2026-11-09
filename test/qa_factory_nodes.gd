extends Node

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var fac := level.get_node_or_null("FrontlineTerrain/Handcrafted_factory_complex")
	if fac == null:
		print("[FNODES] no factory")
		get_tree().quit()
		return
	for n in fac.find_children("*", "", true, false):
		var cls := n.get_class()
		if cls == "StaticBody3D" or cls == "CollisionShape3D" or cls == "MeshInstance3D":
			var p := Vector3.ZERO
			if n is Node3D:
				var bb: AABB = (n as Node3D).global_transform * ((n as MeshInstance3D).get_aabb() if n is MeshInstance3D and (n as MeshInstance3D).mesh != null else AABB())
				p = bb.get_center() if n is MeshInstance3D else ((n as Node3D).global_position)
			print("[FNODES] ", cls, " name=", n.name, " path=", fac.get_path_to(n),
					" pos=", p, " visible=", (n as Node3D).visible if n is Node3D else "-")
	get_tree().quit()
