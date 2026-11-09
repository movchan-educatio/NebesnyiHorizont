extends Node

## QA: list every small mesh whose AABB floats high above the terrain.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")


func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var count := 0
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		if bb.size.length() > 30.0 or bb.size.y > 30.0:
			continue
		var c := bb.get_center()
		var g := TERRAIN.height_at("industrial", c.x, c.z)
		if bb.position.y > g + 12.0 and bb.size.x < 12.0 and bb.size.z < 12.0:
			count += 1
			print("[SMALLFLOAT] bottom=%.1f top=%.1f size=%s pos=%s name=%s path=%s" % [
				bb.position.y, bb.end.y, str(bb.size), str(c), mi.name,
				String(level.get_path_to(mi))])
	print("[SMALLFLOAT] count=", count)
	get_tree().quit()
