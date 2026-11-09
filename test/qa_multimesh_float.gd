extends Node

## QA: scan MultiMesh instance transforms for instances floating above terrain.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	var level_path := OS.get_environment("QA_FLOAT_LEVEL")
	if level_path.is_empty():
		level_path = "res://sceneries/VillageLevel.tscn"
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load(level_path) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var map_name: String = str(level.get("frontline_map"))
	if map_name.is_empty():
		map_name = "village" if level_path.contains("Village") else "industrial"
	print("[MMF] level=", level_path, " map=", map_name)
	for node in level.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var nm := String(mmi.name).to_lower()
		if nm.contains("tree") or nm.contains("leaf") or nm.contains("grass") \
				or nm.contains("tuft") or nm.contains("reed") or nm.contains("flower") \
				or nm.contains("scrub") or nm.contains("crop") or nm.contains("canopy") \
				or nm.contains("impostor"):
			continue
		var mm := mmi.multimesh
		var base := mmi.global_transform
		var found := 0
		var first := Vector3.ZERO
		var first_i := -1
		for i in range(mm.instance_count):
			var xf := base * mm.get_instance_transform(i)
			var p := xf.origin
			if p.y > TERRAIN.height_at(map_name, p.x, p.z) + 4.0:
				found += 1
				if first_i < 0:
					first_i = i
					first = p
		if found > 0:
			print("[MMF] ", level.get_path_to(mmi), " instances=", mm.instance_count,
					" floating=", found, " first=", first, " index=", first_i,
					" mesh=", mm.mesh.resource_path if mm.mesh != null else "null")
	get_tree().quit()
