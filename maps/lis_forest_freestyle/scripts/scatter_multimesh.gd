extends Node3D
## Rebuilds the Blender scatter as chunked MultiMeshInstance3D nodes.
## One draw per prototype per chunk keeps the iOS budget low.
## NOTE: scatter_transforms.json stores RAW BLENDER coordinates (Z-up).
## glTF/Godot is Y-up, so (bx,by,bz) -> (bx,bz,-by) is mandatory.

const SCATTER_JSON := "res://maps/lis_forest_freestyle/scatter_transforms.json"
const PROTO_DIR := "res://maps/lis_forest_freestyle/meshes/"
const CHUNK_SIZE: float = 600.0
const CONIFERS := ["pine_tall", "pine_mid", "pine_slim", "fir_dense"]

const VIS_RANGE := {
	"pine_tall": 520.0, "pine_mid": 460.0, "fir_dense": 420.0, "pine_slim": 460.0,
	"boulder_01": 320.0, "rock_07": 260.0, "rock_09": 260.0,
	"tree_stump_01": 180.0, "tree_stump_02": 180.0,
	"fern_02": 130.0, "shrub_01": 150.0, "shrub_02": 150.0,
	"shrub_03": 150.0, "shrub_04": 150.0,
	"grass_medium_01": 90.0, "grass_medium_02": 90.0,
	"dead_tree_trunk": 240.0, "dead_tree_trunk_02": 240.0,
	"pine_roots": 180.0, "rock_moss_set_01": 260.0, "rock_moss_set_02": 260.0,
}

## Nine scattered instances across seven edge coordinates on the 300 m terrain seam
## sample: five sat just above the seam, two grass clumps sat 2.5 m underground.
## Heights below are the measured surface at those exact XZ coordinates.
## Key = raw Blender (x, y, z) from scatter_transforms.json, rounded to 3 decimals.
const GROUND_FIX := {
	"-8.767,302.787,7.036": 7.14,
	"302.908,-201.860,5.064": 5.10,
	"-301.563,80.590,18.117": 18.21,
	"-300.130,-61.826,5.050": 5.12,
	"-1.439,430.920,-7.847": -5.30,
	"162.268,302.513,18.648": 18.36,
	"-126.488,-301.386,5.580": 5.62,
}

var _mesh_cache: Dictionary = {}
var _crown_offsets: Dictionary = {}
var chunk_count: int = 0
var instance_count: int = 0
var fixes_applied: int = 0


func _ready() -> void:
	var f := FileAccess.open(SCATTER_JSON, FileAccess.READ)
	if f == null:
		push_warning("[LIS] scatter_transforms.json missing — MultiMesh scatter skipped")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LIS] bad scatter JSON")
		return
	var groups: Dictionary = parsed.get("groups", {})
	for mid in groups.keys():
		var entries: Array = groups[mid]
		if entries.is_empty():
			continue
		var meshes: Array[Mesh] = _meshes_for(mid)
		if meshes.is_empty():
			push_warning("[LIS] no prototype mesh for " + str(mid))
			continue
		_build_chunks(str(mid), meshes, entries)
	print("[LIS] MultiMesh: %d chunks, %d instances, %d ground fixes" % [
			chunk_count, instance_count, fixes_applied])


func _meshes_for(mid: String) -> Array[Mesh]:
	if _mesh_cache.has(mid):
		return _mesh_cache[mid]
	var out: Array[Mesh] = []
	var path := PROTO_DIR + "proto_%s.glb" % mid
	if not ResourceLoader.exists(path):
		_mesh_cache[mid] = out
		return out
	var packed: PackedScene = load(path)
	if packed == null:
		_mesh_cache[mid] = out
		return out
	var inst: Node = packed.instantiate()
	var all: Array[Mesh] = []
	_collect_meshes(inst, all)
	inst.free()
	# Conifer prototypes are exported as two separate meshes: a ~700-face needle
	# crown and a ~730-face trunk.  Picking the largest one alone (the old code)
	# dropped the crown of pine_tall / pine_slim / fir_dense and left bare sticks.
	if CONIFERS.has(mid):
		# Keep both the needle crown (tree_foliage_*) and the bark trunk
		# (tree_trunk_*). Each conifer has ~725 crown faces + ~700 trunk faces
		# (~338k tris total across all 488 pines), matching the source previews.
		var crown: Mesh = null
		var trunk: Mesh = null
		for m in all:
			var nm := String(m.resource_name).to_lower()
			var has_needle := false
			for s in range(m.get_surface_count()):
				var mat := m.surface_get_material(s)
				if mat != null and mat.resource_name.to_lower().contains("needle"):
					has_needle = true
					break
			if has_needle or nm.contains("foliage"):
				if crown == null or m.get_faces().size() > crown.get_faces().size():
					crown = m
			elif nm.contains("trunk"):
				if trunk == null or m.get_faces().size() > trunk.get_faces().size():
					trunk = m
		if crown != null:
			out.push_back(crown)
		if trunk != null:
			out.push_back(trunk)
		if not out.is_empty():
			# Trunks start at y = 0; only shift orphan crowns without trunks.
			if trunk == null and crown != null:
				_crown_offsets[mid] = crown.get_aabb().position.y
			_mesh_cache[mid] = out
			return out
	# Other prototypes keep the single largest mesh (mobile draw-call budget).
	var best: Mesh = null
	for m in all:
		if best == null or m.get_faces().size() > best.get_faces().size():
			best = m
	if best:
		out.push_back(best)
	_mesh_cache[mid] = out
	return out


func _collect_meshes(node: Node, out: Array[Mesh]) -> void:
	if node is MeshInstance3D:
		var m := (node as MeshInstance3D).mesh
		if m and not out.has(m):
			out.push_back(m)
	for c in node.get_children():
		_collect_meshes(c, out)


func _build_chunks(mid: String, meshes: Array[Mesh], entries: Array) -> void:
	var buckets: Dictionary = {}
	for e in entries:
		if e.size() < 5:
			continue
		var bx: float = float(e[0])
		var by: float = float(e[1])
		var bz: float = float(e[2])
		var rz: float = float(e[3])
		var s: float = float(e[4])
		# Blender Z-up -> Godot Y-up.  Without this, Blender depth became
		# world height and whole tree bands floated or sank.
		var p := Vector3(bx, bz, -by)
		var ground_fix: Variant = GROUND_FIX.get("%.3f,%.3f,%.3f" % [bx, by, bz])
		if ground_fix != null:
			p.y = float(ground_fix)
			fixes_applied += 1
		p.y -= float(_crown_offsets.get(mid, 0.0)) * s
		var key := Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))
		if not buckets.has(key):
			buckets[key] = []
		var basis := Basis().rotated(Vector3.UP, -rz).scaled(Vector3(s, s, s))
		buckets[key].push_back(Transform3D(basis, p))

	var range_end: float = float(VIS_RANGE.get(mid, 300.0))
	for key in buckets.keys():
		var list: Array = buckets[key]
		if list.is_empty():
			continue
		for mi in range(meshes.size()):
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "mm_%s_c%d_%d_p%d" % [mid, key.x, key.y, mi]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = meshes[mi]
			mm.instance_count = list.size()
			for i in range(list.size()):
				# Authored transforms are already world-space; no offset.
				mm.set_instance_transform(i, list[i])
			mmi.multimesh = mm
			mmi.position = Vector3.ZERO
			var mesh_range := minf(range_end, 220.0) if (CONIFERS.has(mid) and mi > 0) else range_end
			mmi.visibility_range_end = mesh_range
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			add_child(mmi)
			chunk_count += 1
			instance_count += list.size()
