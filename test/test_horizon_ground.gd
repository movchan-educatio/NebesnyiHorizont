extends Node

## Verifies that the training-ring course (out to 900 m) stands on real ground:
## the horizon continuation must provide collision beyond the 1 km clipmap.
const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")

func _ready() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	var packed := load("res://sceneries/VillageLevel.tscn") as PackedScene
	var scene: Node = packed.instantiate()
	add_child(scene)
	for i in range(120):
		await get_tree().process_frame
	var rings: Array = scene.get("_training_rings")
	if rings.size() != 24:
		push_error("[HORIZON] expected 24 rings, got %d" % rings.size())
		get_tree().quit(1)
		return
	var worst := 0.0
	var beyond := 0
	for node in rings:
		var ring := node as Node3D
		if ring == null:
			push_error("[HORIZON] null ring")
			get_tree().quit(1)
			return
		var p: Vector3 = ring.global_position
		var ground: float = scene._find_ground_y(p.x, p.z)
		var analytic: float = TERRAIN.height_at("village", p.x, p.z)
		worst = maxf(worst, absf(ground - analytic))
		if Vector2(p.x, p.z).length() > 512.0:
			beyond += 1
	if worst > 2.0:
		push_error("[HORIZON] ground mismatch %.2f m" % worst)
		get_tree().quit(1)
		return
	print("[HORIZON] PASS - %d rings (%d beyond 512 m), worst ground delta %.2f m" % [
			rings.size(), beyond, worst])
	get_tree().quit(0)
