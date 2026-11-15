class_name QaFloatingScanner
extends RefCounted

## Pipeline QA: detects props whose visible bottom floats above the rendered
## terrain.  It runs *before* the static batching pass, while individual
## MeshInstance3D nodes still exist, and also walks MultiMesh instance
## transforms.  Results and source transforms are stored on the terrain root so
## a post-batch audit can still report the original spawn positions.
##
## This is deliberately non-destructive: production loads log a summary, while
## QA_STRICT promotes findings to push_error().  It never changes transforms;
## grounding itself is done by FrontlineAssets / the prop placement helpers.


static func scan(root: Node3D, map_name: String, strict: bool = false) -> Dictionary:
	var result := {
		"map": map_name,
		"checked": 0,
		"floating": 0,
		"multimesh_checked": 0,
		"multimesh_floating": 0,
		"issues": [],
		"source_transforms": [],
	}
	if root == null or map_name.is_empty():
		return result
	if OS.has_environment("QA_NO_FLOAT_SCAN"):
		return result
	var terrain = load("res://scripts/util/frontline_terrain.gd")
	var assets = load("res://scripts/util/frontline_assets.gd")
	if terrain == null or assets == null:
		return result
	var hall: Dictionary = terrain.HALL_SITES.get(map_name, {})
	var tree := root.get_tree()
	if tree == null:
		return result
	var sources: Array = result["source_transforms"]
	var issues: Array = result["issues"]

	# ------------------------------------------------ individual prop instances
	for node in tree.get_nodes_in_group("frontline_asset"):
		var n := node as Node3D
		if n == null or not is_instance_valid(n) or not root.is_ancestor_of(n):
			continue
		var nm := String(n.name).to_lower()
		if nm.contains("bridge") or nm.contains("barge") or nm.contains("boat") \
				or nm.contains("water") or nm.contains("dock"):
			continue
		var bb: AABB = assets.visual_aabb(n)
		if bb.size.y < 0.05:
			continue
		result["checked"] = int(result["checked"]) + 1
		sources.append(n.global_transform)
		var p := Vector2(n.global_position.x, n.global_position.z)
		var support := _support_height(terrain, map_name, hall, p,
				maxf(bb.size.x, 0.5), maxf(bb.size.z, 0.5), n.global_rotation.y)
		var gap := bb.position.y - support
		if gap > 0.65:
			result["floating"] = int(result["floating"]) + 1
			if issues.size() < 30:
				issues.append({
					"kind": "mesh", "name": String(n.name),
					"position": n.global_position, "bottom": bb.position.y,
					"ground": support, "gap": gap,
				})

	# ------------------------------------------------------- MultiMesh instances
	# The dummy/headless renderer does not retain per-instance MultiMesh
	# transforms, so every instance reads as identity there.  Scan only in a
	# real display context; the automatic pipeline otherwise reports false
	# positives at y=0.
	if DisplayServer.get_name() == "headless":
		result["multimesh_skipped_headless"] = true
		root.set_meta("qa_float_result", result)
		root.set_meta("qa_source_transforms", sources)
		_print_summary(result, strict)
		return result
	var stride := 1
	if not strict and not OS.has_environment("DRONE_FLOAT_AUDIT"):
		stride = 3
	for node in root.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := node as MultiMeshInstance3D
		if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
			continue
		var name_l := String(mmi.name).to_lower()
		# Unnamed MultiMesh nodes are generated decoration/merge leftovers;
		# their support semantics are unknown.  Named nodes are audited.
		if name_l.begins_with("@") or name_l == "multimeshinstance3d":
			continue
		if _skip_multimesh(name_l):
			continue
		var mm := mmi.multimesh
		var local_aabb := mm.mesh.get_aabb()
		var count := mm.instance_count
		if OS.has_environment("QA_FLOAT_DEBUG") and count > 0:
			print("[QA-FLOAT] MM ", mmi.name, " count=", count,
					" tf0=", mm.get_instance_transform(0),
					" aabb=", local_aabb)
		var step := maxi(stride, int(ceil(float(count) / 700.0)))
		for i in range(0, count, step):
			var xf := mm.get_instance_transform(i)
			var world_xf := mmi.global_transform * xf
			var ibox: AABB = world_xf * local_aabb
			var origin := world_xf.origin
			var p2 := Vector2(origin.x, origin.z)
			var support2 := _support_height(terrain, map_name, hall, p2,
					maxf(ibox.size.x, 0.25), maxf(ibox.size.z, 0.25), 0.0)
			result["multimesh_checked"] = int(result["multimesh_checked"]) + 1
			sources.append(world_xf)
			var gap2 := ibox.position.y - support2
			if gap2 > 0.85:
				result["multimesh_floating"] = int(result["multimesh_floating"]) + 1
				if issues.size() < 30:
					issues.append({
						"kind": "multimesh", "name": String(mmi.name),
						"index": i, "position": origin,
						"bottom": ibox.position.y, "ground": support2,
						"gap": gap2,
					})

	root.set_meta("qa_float_result", result)
	root.set_meta("qa_source_transforms", sources)
	_print_summary(result, strict)
	return result


static func _support_height(terrain, map_name: String, hall: Dictionary,
		p: Vector2, width: float, depth: float, yaw: float) -> float:
	if not hall.is_empty():
		var c: Vector2 = hall["center"]
		var half: Vector2 = hall["half"]
		if absf(p.x - c.x) <= half.x and absf(p.y - c.y) <= half.y:
			# Props inside a hall stand on its authored finished deck, which is
			# above the terrain pan by 0.10 m.
			var sink := float(hall.get("sink", 0.0))
			return float(terrain.height_at(map_name, c.x, c.y)) + 0.10 - sink
	return float(terrain.footprint_surface_height(map_name, p,
			clampf(width, 0.5, 24.0), clampf(depth, 0.5, 24.0), yaw))


static func _skip_multimesh(name_l: String) -> bool:
	for w in ["grass", "leaf", "leaves", "foliage", "bush", "scrub", "canopy",
			"impostor", "reed", "flower", "tuft", "weeds", "crop", "pebble",
			"rubble", "debris", "smoke", "plume", "mist", "roof", "blade", "cloud",
			"batch", "hud", "sprite", "glass", "water", "train", "rail"]:
		if name_l.contains(w):
			return true
	return false


static func _print_summary(result: Dictionary, strict: bool) -> void:
	var floating := int(result["floating"]) + int(result["multimesh_floating"])
	var checked := int(result["checked"]) + int(result["multimesh_checked"])
	if floating > 0 or OS.has_environment("DRONE_FLOAT_AUDIT") \
			or OS.has_environment("QA_STRICT") or strict:
		print("[QA-FLOAT] map=", result["map"], " checked=", checked,
				" floating=", floating)
		for issue in result["issues"]:
			print("[QA-FLOAT]   ", issue)
	if strict and floating > 0:
		push_error("[QA-FLOAT] %d floating object(s) detected on %s" % [
			floating, result["map"]])
