extends Node

## QA: inside-out rays from the tower bore must hit the inner wall at the
## expected radius; this catches one-sided/missing collision.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var cx := 310.0
	var cz := 80.0
	var base: float = TERRAIN.height_at("village", cx, cz)
	var bad := 0
	for h in [5.0, 10.0, 15.0]:
		for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0),
				Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var origin := Vector3(cx, base + h, cz)
			var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 6.0)
			var hit: Dictionary = space.intersect_ray(q)
			var dist := 999.0
			if not hit.is_empty():
				dist = origin.distance_to(hit["position"])
			var ok := dist > 1.1 and dist < 2.4
			if not ok:
				bad += 1
			print("[INSIDEQA] h=%.0f dir=%s dist=%.2f ok=%s" % [
				h, str(dir), dist, ok])
	print("[INSIDEQA] bad=", bad, " -> ", "FAIL" if bad > 0 else "PASS")
	get_tree().quit(0 if bad == 0 else 1)
