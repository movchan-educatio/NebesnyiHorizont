extends Node

## QA: list all visible meshes near the old factory chimney position.

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var c := bb.get_center()
		if Vector2(c.x + 130.0, c.z + 146.0).length() > 45.0:
			continue
		if bb.size.y > 4.0:
			print("[NEAR2] pos=", bb.position, " size=", bb.size, " name=", mi.name,
					" path=", level.get_path_to(mi), " visible=", mi.visible)
	get_tree().quit()
