extends Node

## QA: find the large flat green surface visible at the City spawn and report
## which node/material it is so the texture pass can target it.

func _ready() -> void:
	var packed := load("res://sceneries/CityLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(6.0).timeout
	var city := level.get_node_or_null("City")
	if city == null:
		print("[GREEN] no city")
		get_tree().quit()
		return
	var rows: Array = []
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = mi.mesh.surface_get_material(0) as StandardMaterial3D
		if mat == null:
			continue
		var c := mat.albedo_color
		if c.g > c.r * 1.25 and c.g > c.b * 1.15 and c.g > 0.08:
			var box: AABB = mi.global_transform * mi.get_aabb()
			rows.append("%s | path=%s | col=%s | tex=%s | size=%.1f | y=%.1f" % [
				String(mi.name), String(level.get_path_to(mi)), c.to_html(),
				"yes" if mat.albedo_texture != null else "no",
				maxf(box.size.x, maxf(box.size.y, box.size.z)), mi.global_position.y])
	rows.sort()
	print("[GREEN] count=", rows.size())
	for r in rows:
		print("[GREEN] ", r)
	get_tree().quit()
