extends Node

## QA: every named open-top tower must have an empty bore at the top.

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var path := OS.get_environment("QA_LEVEL")
	if path.is_empty():
		path = "res://sceneries/IndustrialLevel.tscn"
	var packed := load(path) as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(6.0).timeout
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var keys := ["HallChimney", "SiloShell", "WaterTowerTank", "WetlandsChimney",
			"FactoryChimneyTop", "IndustrialChimney", "IndustrialCoolingTower",
			"IndustrialSilo", "CoolingTower", "Smokestack"]
	var checked := 0
	var open_count := 0
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var nm := String(mi.name)
		var match_key := false
		for k in keys:
			if nm.begins_with(k):
				match_key = true
				break
		if not match_key:
			continue
		checked += 1
		var bb: AABB = mi.global_transform * mi.get_aabb()
		var c := bb.get_center()
		var top := bb.end.y
		var q := PhysicsRayQueryParameters3D.create(
				Vector3(c.x, top + 30.0, c.z), Vector3(c.x, top - 2.0, c.z))
		var hit: Dictionary = space.intersect_ray(q)
		var hit_y := 9999.0
		if not hit.is_empty():
			hit_y = (hit["position"] as Vector3).y
		var is_open := hit.is_empty() or hit_y < top - 1.0
		if is_open:
			open_count += 1
		print("[OPENQA] ", nm, " top=%.1f hit_y=%.1f open=%s" % [
			top, hit_y, is_open])
	print("[OPENQA] checked=", checked, " open=", open_count, " -> ",
			"PASS" if checked > 0 and open_count == checked else "FAIL")
	get_tree().quit(0 if (checked > 0 and open_count == checked) else 1)
