class_name LisFreestyleRings
extends RefCounted
## Authored 30-gate FPV freestyle loop for lis_forest_freestyle.
## Extracts the authored chamfered ring mesh from FreestyleGeometry/kit_ring_gate
## (zero procedural TorusMesh/CylinderMesh), builds 30 ordered Marker3D nodes
## under LisFreestyleMap/FPVGates (group "fpv_gates"), and clears interfering
## MultiMesh vegetation instances around each gate opening.

const GROUP_NAME := "fpv_gates"
const WATER_LEVEL := -12.0

## Ordered 30-gate course across all 8 map zones:
##   Z01 Basecamp -> Z02 Sawmill (w/ dive) -> Z03 River & Bridges (under & over)
##   -> Z05 Cableway -> Z06 Ruins (w/ dive) -> Z04 Watchtower (56m dive)
##   -> Z07 Treehouse -> Z08 Trestle -> River return -> Z01 Basecamp Finish.
## Format:
##   pos: [x, y_or_agl, z], abs_y: bool (true = world Y, false = AGL above max(ground, water)),
##   radius: float (m), zone: String, style: String, roll: float (deg), dir: [dx, dy, dz] optional
const GATES_DATA := [
	# Z01 Basecamp launch (ahead of DEFAULT_SPAWN (-176, 9, 205) facing NNW)
	{"pos": [-186.0, 7.5, 162.0], "abs_y": false, "radius": 5.0, "zone": "Z01", "style": "start", "roll": 0.0},
	{"pos": [-156.0, 9.0, 146.0], "abs_y": false, "radius": 4.6, "zone": "Z01", "style": "vertical", "roll": -8.0},
	# Z02 Sawmill Bando (clear perimeter + high roof dive + east exit)
	{"pos": [-116.0, 10.5, 76.0], "abs_y": false, "radius": 4.5, "zone": "Z02", "style": "banked", "roll": 14.0},
	{"pos": [-74.0, 34.0, 124.0], "abs_y": true, "radius": 4.8, "zone": "Z02", "style": "dive", "roll": 0.0, "dir": [0.75, -2.4, -0.55]},
	{"pos": [-38.0, 22.0, 84.0], "abs_y": true, "radius": 4.5, "zone": "Z02", "style": "banked", "roll": -12.0},
	# Z03 River S-curve & Bridges (skimming river, passing under then over z03_bridges_metal)
	{"pos": [-14.0, 6.5, 58.0], "abs_y": false, "radius": 4.4, "zone": "Z03", "style": "banked", "roll": -18.0},
	{"pos": [16.0, 6.0, 12.0], "abs_y": false, "radius": 4.3, "zone": "Z03", "style": "banked", "roll": 20.0},
	{"pos": [34.0, -8.2, -45.0], "abs_y": true, "radius": 3.8, "zone": "Z03", "style": "under_bridge", "roll": 0.0, "dir": [0.18, 0.04, -0.98]},
	{"pos": [52.0, 5.5, -108.0], "abs_y": false, "radius": 4.5, "zone": "Z03", "style": "banked", "roll": -16.0},
	{"pos": [20.0, 11.5, -45.0], "abs_y": true, "radius": 4.6, "zone": "Z03", "style": "over_bridge", "roll": 10.0, "dir": [-0.35, 0.08, -0.93]},
	# Z05 Cableway Corridor (canyon cross north-west along valley)
	{"pos": [18.0, 19.0, -135.0], "abs_y": true, "radius": 4.6, "zone": "Z05", "style": "vertical", "roll": 0.0},
	{"pos": [-28.0, 26.0, -182.0], "abs_y": true, "radius": 4.8, "zone": "Z05", "style": "banked", "roll": -14.0},
	{"pos": [-96.0, 32.0, -186.0], "abs_y": true, "radius": 4.6, "zone": "Z05", "style": "banked", "roll": 15.0},
	{"pos": [-166.0, 34.0, -162.0], "abs_y": true, "radius": 4.5, "zone": "Z05", "style": "vertical", "roll": 0.0},
	# Z06 Ruins (slope approach + horizontal dive + south ridge launch)
	{"pos": [-212.0, 46.0, -112.0], "abs_y": true, "radius": 4.6, "zone": "Z06", "style": "dive", "roll": 0.0, "dir": [0.45, -2.6, 0.65]},
	{"pos": [-185.0, 38.0, -44.0], "abs_y": true, "radius": 4.5, "zone": "Z06", "style": "banked", "roll": -12.0},
	{"pos": [-92.0, 22.0, -18.0], "abs_y": true, "radius": 4.8, "zone": "Z06", "style": "vertical", "roll": 0.0},
	# Climb east toward Z04 Watchtower ridge
	{"pos": [6.0, 36.0, -96.0], "abs_y": true, "radius": 5.0, "zone": "Z04", "style": "climb", "roll": 0.0},
	{"pos": [108.0, 62.0, -148.0], "abs_y": true, "radius": 5.0, "zone": "Z04", "style": "climb", "roll": 10.0},
	# Z04 Watchtower Hero Summit (near 58m AGL) & vertical dive along tower east flank
	{"pos": [214.0, 90.0, -162.0], "abs_y": true, "radius": 5.2, "zone": "Z04", "style": "dive", "roll": 0.0, "dir": [0.22, -3.2, 0.92]},
	{"pos": [216.0, 64.0, -124.0], "abs_y": true, "radius": 4.6, "zone": "Z04", "style": "dive", "roll": 0.0, "dir": [-0.25, -2.1, 0.95]},
	{"pos": [196.0, 14.0, -54.0], "abs_y": false, "radius": 4.6, "zone": "Z04", "style": "banked", "roll": -15.0},
	# Z07 Treehouse Canopy Slalom
	{"pos": [172.0, 16.0, 26.0], "abs_y": false, "radius": 4.5, "zone": "Z07", "style": "banked", "roll": 16.0},
	{"pos": [152.0, 44.0, 102.0], "abs_y": true, "radius": 4.6, "zone": "Z07", "style": "vertical", "roll": 0.0},
	{"pos": [188.0, 16.0, 168.0], "abs_y": false, "radius": 4.5, "zone": "Z07", "style": "banked", "roll": -14.0},
	# Z08 Trestle Flyover & River Valley Return
	{"pos": [156.0, 34.0, 235.0], "abs_y": true, "radius": 4.8, "zone": "Z08", "style": "over_trestle", "roll": 0.0, "dir": [-0.98, -0.08, -0.15]},
	{"pos": [76.0, 29.0, 235.0], "abs_y": true, "radius": 4.5, "zone": "Z08", "style": "over_trestle", "roll": 12.0, "dir": [-0.97, -0.18, -0.14]},
	{"pos": [14.0, 12.0, 212.0], "abs_y": false, "radius": 4.6, "zone": "Z08", "style": "banked", "roll": 18.0},
	{"pos": [-56.0, 6.5, 206.0], "abs_y": false, "radius": 4.6, "zone": "Z03", "style": "banked", "roll": -14.0},
	# Z01 Basecamp Finish
	{"pos": [-134.0, 8.5, 205.0], "abs_y": false, "radius": 5.2, "zone": "Z01", "style": "finish", "roll": 0.0},
]

static var _cached_ring_mesh: ArrayMesh = null
static var _ring_outer_radius: float = 1.0


static func get_ring_mesh(map_root: Node = null) -> ArrayMesh:
	if _cached_ring_mesh != null:
		return _cached_ring_mesh
	if map_root == null:
		return null
	var proto := map_root.find_child("kit_ring_gate", true, false) as MeshInstance3D
	if proto == null:
		proto = map_root.find_child("kit_ring_gate_v3", true, false) as MeshInstance3D
	if proto == null or proto.mesh == null:
		push_warning("[LIS-RINGS] kit_ring_gate prototype missing under map")
		return null
	var src_mesh: Mesh = proto.mesh
	var aabb: AABB = src_mesh.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	var outer_r := maxf(aabb.size.x * 0.5, aabb.size.y * 0.5)
	if outer_r < 0.1:
		outer_r = 4.52
	_ring_outer_radius = outer_r

	var out := ArrayMesh.new()
	out.resource_name = "LisAuthoredRingGateMesh"
	var inv_r := 1.0 / outer_r
	for s in range(src_mesh.get_surface_count()):
		var arrays := src_mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		if verts.is_empty():
			continue
		var shifted := PackedVector3Array()
		shifted.resize(verts.size())
		for vi in range(verts.size()):
			shifted[vi] = (verts[vi] - center) * inv_r
		arrays[Mesh.ARRAY_VERTEX] = shifted
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if out.get_surface_count() > 0:
		_cached_ring_mesh = out
		print("[LIS-RINGS] extracted authored kit_ring_gate (%d surfs, src_r=%.2fm -> unit mesh)" % [
			out.get_surface_count(), outer_r
		])
	return _cached_ring_mesh


static func build_markers(map_root: Node3D, ground_fn: Callable = Callable()) -> Node3D:
	if map_root == null:
		return null
	get_ring_mesh(map_root)
	var existing := map_root.get_node_or_null("FPVGates") as Node3D
	if existing != null:
		if not existing.is_in_group(GROUP_NAME):
			existing.add_to_group(GROUP_NAME)
		if existing.get_child_count() >= GATES_DATA.size():
			return existing
		for ch in existing.get_children():
			ch.queue_free()
	else:
		existing = Node3D.new()
		existing.name = "FPVGates"
		existing.add_to_group(GROUP_NAME)
		map_root.add_child(existing)

	var positions: Array[Vector3] = []
	for i in range(GATES_DATA.size()):
		var entry: Dictionary = GATES_DATA[i]
		var rp: Array = entry["pos"]
		var gx := float(rp[0])
		var gz := float(rp[2])
		var gy := WATER_LEVEL
		if ground_fn.is_valid():
			gy = float(ground_fn.call(gx, gz))
		else:
			gy = _sample_terrain_mesh_y(map_root, gx, gz)
		var base_y := maxf(gy, WATER_LEVEL)
		var r := float(entry["radius"])
		var world_y := float(rp[1]) if bool(entry["abs_y"]) else (base_y + float(rp[1]))
		if bool(entry["abs_y"]) and String(entry["style"]) != "under_bridge":
			world_y = maxf(world_y, base_y + r + 1.4)
		positions.append(Vector3(gx, world_y, gz))

	for i in range(GATES_DATA.size()):
		var entry: Dictionary = GATES_DATA[i]
		var pos: Vector3 = positions[i]
		var dir: Vector3
		if entry.has("dir"):
			var dv: Array = entry["dir"]
			dir = Vector3(float(dv[0]), float(dv[1]), float(dv[2])).normalized()
		else:
			var next_pos: Vector3 = positions[(i + 1) % positions.size()]
			var prev_pos: Vector3 = positions[(i - 1 + positions.size()) % positions.size()]
			if i == 0:
				dir = next_pos - pos
			elif i == positions.size() - 1:
				dir = pos - prev_pos
			else:
				dir = (next_pos - pos).normalized() + (pos - prev_pos).normalized()
			dir.y = clampf(dir.y, -0.35, 0.35)
			if dir.length_squared() < 0.001:
				dir = Vector3.FORWARD
			dir = dir.normalized()

		var up := Vector3.UP
		if absf(dir.dot(Vector3.UP)) > 0.96:
			up = Vector3.FORWARD
		var basis := Basis.looking_at(dir, up)
		var roll_deg := float(entry.get("roll", 0.0))
		if absf(roll_deg) > 0.01:
			basis = basis.rotated(dir, deg_to_rad(roll_deg))

		var marker := Marker3D.new()
		marker.name = "Gate_%02d" % (i + 1)
		marker.add_to_group(GROUP_NAME)
		marker.transform = Transform3D(basis, pos)
		marker.set_meta("gate_index", i)
		marker.set_meta("radius", float(entry["radius"]))
		marker.set_meta("zone", String(entry["zone"]))
		marker.set_meta("style", String(entry["style"]))
		existing.add_child(marker)
	print("[LIS-RINGS] FPVGates ready: %d authored Marker3D gates" % existing.get_child_count())
	return existing


static func clear_scatter_near_gates(scatter_node: Node3D, gates_node: Node3D,
		clear_radius: float = 8.5) -> int:
	if scatter_node == null or gates_node == null:
		return 0
	var gate_list: Array[Dictionary] = []
	for ch in gates_node.get_children():
		if ch is Marker3D:
			var m := ch as Marker3D
			var r := float(m.get_meta("radius", 4.6))
			gate_list.append({
				"pos": m.global_position,
				"xz": Vector2(m.global_position.x, m.global_position.z),
				"r_clear": maxf(clear_radius, r + 3.8),
				"r_gate": r,
			})
	if gate_list.is_empty():
		return 0

	var zero_xf := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3(0.0, -500.0, 0.0))
	var cleared := 0
	for mmi in scatter_node.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi_node := mmi as MultiMeshInstance3D
		var mm := mmi_node.multimesh
		if mm == null or mm.instance_count <= 0:
			continue
		var is_tree := String(mmi_node.name).contains("pine") or String(mmi_node.name).contains("fir") \
				or String(mmi_node.name).contains("trunk")
		var tree_h := 17.0 if is_tree else 4.0
		var mmi_xf := mmi_node.global_transform
		var cached_meta: Variant = mmi_node.get_meta("instance_transforms", null)
		var cached_list: Array = cached_meta if cached_meta is Array else []
		var meta_dirty := false
		for idx in range(mm.instance_count):
			var inst_xf: Transform3D = cached_list[idx] if idx < cached_list.size() else mm.get_instance_transform(idx)
			if inst_xf.basis.x.length_squared() < 0.0001:
				continue
			var wpos := mmi_xf * inst_xf.origin
			var wxz := Vector2(wpos.x, wpos.z)
			for g in gate_list:
				var gpos: Vector3 = g["pos"]
				var gr: float = float(g["r_gate"])
				if wxz.distance_to(g["xz"] as Vector2) < float(g["r_clear"]):
					# Clear ground props near gate and conifers whose trunk/crown overlaps gate elevation
					if gpos.y - gr - 3.5 <= wpos.y + tree_h and wpos.y <= gpos.y + gr + 2.5:
						mm.set_instance_transform(idx, zero_xf)
						if idx < cached_list.size():
							cached_list[idx] = zero_xf
							meta_dirty = true
						cleared += 1
						break
		if meta_dirty:
			mmi_node.set_meta("instance_transforms", cached_list)
	if cleared > 0:
		print("[LIS-RINGS] cleared %d interfering scatter instances near gates" % cleared)
	return cleared


static func _sample_terrain_mesh_y(map_root: Node3D, x: float, z: float) -> float:
	var tp := map_root.find_child("terrain_playable", true, false) as MeshInstance3D
	if tp == null or tp.mesh == null or tp.mesh.get_surface_count() == 0:
		return 8.0
	var arr := tp.mesh.surface_get_arrays(0)
	if arr.is_empty():
		return 8.0
	var verts := arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
	if verts.is_empty():
		return 8.0
	var xf := tp.global_transform
	var best_d2 := 1e12
	var best_y := 8.0
	var target := Vector2(x, z)
	# terrain_playable has ~40k vertices in a 201x201 grid; stride 1 gives exact height quickly
	for vi in range(0, verts.size(), 1):
		var v := xf * verts[vi]
		var d2 := (v.x - target.x) * (v.x - target.x) + (v.z - target.y) * (v.z - target.y)
		if d2 < best_d2:
			best_d2 = d2
			best_y = v.y
			if d2 < 2.5:
				break
	return best_y
