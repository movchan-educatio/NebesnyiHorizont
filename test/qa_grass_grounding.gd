extends Node

## Regression test for the flight-school grass carpet.  On the legacy GLB map
## the old implementation placed every blade on one flat spawn-height plane,
## leaving clumps hanging in the air on the sloped lawn.  The fix raycasts the
## real collision and interpolates it, so each instance must sit on the ground.

const TEST_NAME := "GRASS_QA"
const LevelScene := preload("res://sceneries/BigLevel.tscn")

var _failures := 0
var _saved_mode := 0
var _saved_special := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	_saved_mode = Global.play_mode
	_saved_special = Global.special_mission
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.special_mission = 0
	var level := LevelScene.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(3.0).timeout

	var grass := level.get_node_or_null("FollowGrass") as MultiMeshInstance3D
	_check(grass != null, "tutorial level builds follow grass")
	if grass == null:
		_finish(level)
		return
	_check(bool(grass.get("_legacy_ground_ok")), "legacy collision height grid built")
	_check(int(grass.get("count")) > 0, "legacy map has grass instances")
	var grid: PackedFloat32Array = grass.get("_legacy_ground")
	var missing_cells := 0
	for v in grid:
		if float(v) <= -1000.0:
			missing_cells += 1
	print("[", TEST_NAME, "] grid_cells=", grid.size(), " missing=", missing_cells,
			" instances=", grass.get("count"))

	var space := level.get_world_3d().direct_space_state
	var checked := 0
	var missing := 0
	var offsets: Array[float] = []
	var worst := 0.0
	var worst_pos := Vector3.ZERO
	var nodes: Array = [grass]
	nodes.append_array(grass.find_children("*", "MultiMeshInstance3D", true, false))
	for node in nodes:
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null:
			continue
		var mm := mmi.multimesh
		var base := mmi.global_transform
		# Headless MultiMesh.get_instance_transform() returns identity for
		# buffers uploaded with set_buffer(), so decode the raw 12-float
		# row-major transform layout directly (origin at 3/7/11).
		var raw := mm.get_buffer()
		for i in range(mm.instance_count):
			var off := i * 12
			if off + 11 >= raw.size():
				break
			var local := Vector3(raw[off + 3], raw[off + 7], raw[off + 11])
			var p := base * local
			var query := PhysicsRayQueryParameters3D.create(
					Vector3(p.x, p.y + 18.0, p.z), Vector3(p.x, p.y - 24.0, p.z))
			query.collision_mask = 1
			query.collide_with_areas = false
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				missing += 1
				continue
			var normal: Vector3 = hit.get("normal", Vector3.UP)
			if normal.y < 0.65:
				continue
			var gy: float = (hit["position"] as Vector3).y
			var off_dist := absf(p.y - gy)
			offsets.append(off_dist)
			checked += 1
			if off_dist > worst:
				worst = off_dist
				worst_pos = p
	offsets.sort()
	var p95 := offsets[int(clampf(offsets.size() * 0.95, 0.0, float(offsets.size() - 1)))] \
			if not offsets.is_empty() else 99.0
	print("[", TEST_NAME, "] checked=", checked, " missing=", missing,
			" p95=%.3f worst=%.3f at %s" % [p95, worst, str(worst_pos)])
	_check(checked > 500, "enough grass instances sampled on collision ground")
	_check(missing <= 2, "grass skips void areas with no collision surface (%d)" % missing)
	_check(worst <= 0.65, "no grass clump floats/sinks more than 0.65 m (%.2f m)" % worst)
	_check(p95 <= 0.30, "95%% of blades sit within 0.30 m of the surface (%.2f m)" % p95)

	_finish(level)


func _finish(level: Node) -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
	Global.play_mode = _saved_mode
	Global.special_mission = _saved_special
	OS.unset_environment("DRONE_NO_RECORD")
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[", TEST_NAME, "] PASS ", label)
	else:
		_failures += 1
		push_error("[%s] FAIL %s" % [TEST_NAME, label])
