extends Node

## QA: the factory chimney must be a hollow open-top tower with a large base
## arch (fly in top, out bottom) and solid mid/upper walls.

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
	var space: PhysicsDirectSpaceState3D = level.get_world_3d().direct_space_state
	var ground: float = TERRAIN.height_at("industrial", -90.0, -146.0)
	var top_guess := ground + 32.0
	var top_open := true
	var top_hit := Vector3.ZERO
	var q_top := PhysicsRayQueryParameters3D.create(
			Vector3(-90.0, 80.0, -146.0), Vector3(-90.0, ground - 1.0, -146.0))
	var h_top: Dictionary = space.intersect_ray(q_top)
	if not h_top.is_empty():
		top_hit = h_top["position"]
		if top_hit.y > top_guess - 1.0:
			top_open = false
	print("[FTUNNEL] ground=%.1f top=%.1f top_ray_hit=%s open=%s" % [
		ground, top_guess, str(top_hit), top_open])
	var base_open := false
	var base_origin := Vector3(-90.0, ground + 3.0, -146.0)
	var q_base := PhysicsRayQueryParameters3D.create(
			base_origin, base_origin + Vector3(8.0, 0.0, 0.0))
	var h_base: Dictionary = space.intersect_ray(q_base)
	base_open = h_base.is_empty() or (h_base["position"] as Vector3).distance_to(
			base_origin) > 5.0
	var upper_solid := true
	for y in [15.0, 28.0, 31.0]:
		var origin := Vector3(-90.0, ground + y, -146.0)
		var q := PhysicsRayQueryParameters3D.create(
				origin, origin + Vector3(8.0, 0.0, 0.0))
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(origin) > 5.0:
			upper_solid = false
	print("[FTUNNEL] base_open=", base_open, " upper_solid=", upper_solid,
			" -> ", "PASS" if (top_open and base_open and upper_solid) else "FAIL")
	get_tree().quit(0 if (top_open and base_open and upper_solid) else 1)
