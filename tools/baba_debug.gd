## QA: print Baba Yaga FPV camera and bomb-bay geometry.
extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("DRONE_COMBAT_MISSION", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.combat_mission = 1
	Global.drone_preset = 12
	var level := (load("res://sceneries/BigLevel.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(2.0).timeout
	var cam := level.get_node_or_null("Drone/FPVCamera") as Camera3D
	print("[BABADBG] cam pos=", cam.global_position, " rot=", cam.global_rotation_degrees,
			" fov=", cam.fov, " cull_mask=", cam.cull_mask)
	var barrel := level.get_node_or_null("TacticalLaunchBarrel")
	if barrel != null:
		for mi in barrel.find_children("*", "MeshInstance3D", true, false):
			print("[BABADBG] barrel ", mi.name, " layers=", (mi as MeshInstance3D).layers,
					" visible=", (mi as MeshInstance3D).visible,
					" parent_visible=", (mi as MeshInstance3D).get_parent().visible,
					" aabb=", (mi as MeshInstance3D).get_aabb().size)
	var bays := level.find_children("BombBay", "", true, false)
	for b in bays:
		var n3 := b as Node3D
		print("[BABADBG] BombBay pos=", n3.global_position)
		for c in n3.get_children():
			var n3c := c as Node3D
			var aabb := AABB()
			var first := true
			for mi in c.find_children("*", "MeshInstance3D", true, false):
				var b2: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
				aabb = b2 if first else aabb.merge(b2)
				first = false
			print("[BABADBG]  ", c.name, " pos=", n3c.global_position,
					" aabb=", aabb.position, " size=", aabb.size,
					" visible=", n3c.visible)
	var model_root := level.get_node_or_null("Drone/DroneModel")
	if model_root != null:
		print("[BABADBG] --- visible model meshes ---")
		for n in model_root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.visible:
				var b: AABB = mi.global_transform * mi.get_aabb()
				print("[BABADBG] MODEL ", mi.name, " path=", mi.get_path(),
						" pos=", mi.global_position, " size=", b.size)
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.visible:
			var b: AABB = mi.global_transform * mi.get_aabb()
			if b.size.length() > 0.15:
				print("[BABADBG] visible ", mi.name, " path=", mi.get_path(),
						" parent=", mi.get_parent().name,
						" pos=", mi.global_position,
						" size=", b.size, " aabb=", b.position)
	get_tree().quit(0)
