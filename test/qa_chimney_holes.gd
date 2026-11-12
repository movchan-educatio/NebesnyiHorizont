extends Node

## QA: The flooded pump-station stack on Wetlands (22,60) must be solid except
## for its intended base arch and open top.  Any horizontal ray that passes
## through the shell above the arch is a geometry hole.  (The old Village yard
## chimney builder is no longer called, so the probe now targets the live
## WetlandsChimney built by world_detail._dress_wetlands.)

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/WetlandsLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var cx := 22.0
	var cz := 60.0
	var base: float = TERRAIN.height_at("wetlands", cx, cz)
	print("[CHQA] base=", base)
	var bad := 0
	for h in [4.5, 6.0, 8.0, 10.0, 12.0, 14.0, 16.0]:
		for axis in ["x", "z"]:
			var from: Vector3
			var to: Vector3
			if axis == "x":
				from = Vector3(cx - 8.0, base + h, cz)
				to = Vector3(cx + 8.0, base + h, cz)
			else:
				from = Vector3(cx, base + h, cz - 8.0)
				to = Vector3(cx, base + h, cz + 8.0)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			var hit: Dictionary = space.intersect_ray(q)
			var dist := 999.0
			if not hit.is_empty():
				dist = from.distance_to(hit["position"])
			var through := dist > 7.0
			if through:
				bad += 1
			print("[CHQA] h=%.1f axis=%s hit=%s dist=%.1f through=%s" % [
				h, axis, str(hit.get("position", Vector3.ZERO)), dist, through])
	print("[CHQA] holes=", bad, " -> ", "FAIL" if bad > 0 else "PASS")
	get_tree().quit(0 if bad == 0 else 1)
