extends Node

## QA: list tall thin meshes near the factory (pylons, masts, chimneys).

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
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var bb: AABB = mi.global_transform * mi.get_aabb()
		if bb.size.y < 9.0 or bb.size.x > 14.0 or bb.size.z > 14.0:
			continue
		var c := bb.get_center()
		if Vector2(c.x + 138.0, c.z + 146.0).length() > 320.0:
			continue
		print("[TALL] bottom=%.1f top=%.1f size=%s pos=%s name=%s path=%s parent=%s" % [
			bb.position.y, bb.end.y, str(bb.size), str(c), mi.name,
			String(level.get_path_to(mi)),
			String(mi.get_parent().name) if mi.get_parent() != null else "?"])
	print("[TALL] done")
	get_tree().quit()
