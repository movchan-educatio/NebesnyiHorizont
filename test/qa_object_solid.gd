extends Node

## QA: roofs of authored cottages/barns and the hero hall must stop a
## downward ray (the player was falling through roofs in the video).

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(6.0).timeout
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var targets: Array = []
	for n in level.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.begins_with("cottage_") or nm.begins_with("barn_") or nm.begins_with("housecollision"):
			targets.append(n)
	targets.append(level.get_node_or_null("FrontlineTerrain/HeroHall_village"))
	var hc_roofs := level.get_node_or_null("FrontlineTerrain/Handcrafted_village_house/HandcraftedRoofSafety")
	if hc_roofs != null:
		for cs in hc_roofs.get_children():
			if cs is CollisionShape3D and (cs as CollisionShape3D).shape is BoxShape3D:
				var csn := cs as CollisionShape3D
				var bsz := (csn.shape as BoxShape3D).size
				csn.set_meta("roof_aabb", AABB(csn.global_position - Vector3(bsz.x * 0.5, csn.position.y, bsz.z * 0.5), Vector3(bsz.x, csn.position.y + 0.6, bsz.z)))
				targets.append(csn)
	var fails := 0
	var checked := 0
	for t in targets:
		if t == null:
			continue
		var box: AABB = AABB()
		var first := true
		if (t as Object).has_meta("roof_aabb"):
			box = (t as Object).get_meta("roof_aabb") as AABB
			first = false
		else:
			if t is MeshInstance3D:
				var self_mi := t as MeshInstance3D
				if self_mi.mesh != null and self_mi.visible:
					box = self_mi.global_transform * self_mi.get_aabb()
					first = false
			for mi_node in (t as Node).find_children("*", "MeshInstance3D", true, false):
				var mi := mi_node as MeshInstance3D
				if mi == null or mi.mesh == null or not mi.visible:
					continue
				var bb: AABB = mi.global_transform * mi.get_aabb()
				if first:
					box = bb
					first = false
				else:
					box = box.merge(bb)
		if first or box.size.y < 1.0:
			continue
		checked += 1
		var c := box.get_center()
		var q := PhysicsRayQueryParameters3D.create(
				Vector3(c.x, box.end.y + 30.0, c.z), Vector3(c.x, box.position.y - 5.0, c.z))
		var hit: Dictionary = space.intersect_ray(q)
		var ok := not hit.is_empty()
		if ok:
			var hy := (hit["position"] as Vector3).y
			ok = hy > box.position.y + 0.5
		if not ok:
			fails += 1
		print("[ROOFQA] ", (t as Node).name, " box=", box, " hit=",
				str(hit.get("position", Vector3.ZERO)), " ok=", ok)
	print("[ROOFQA] checked=", checked, " fails=", fails, " -> ",
			"PASS" if checked > 0 and fails == 0 else "FAIL")
	get_tree().quit(0 if (checked > 0 and fails == 0) else 1)
