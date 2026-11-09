class_name PropAssets
extends RefCounted

## Loads the 20 Blender-authored frontline props from a single GLB library and
## exposes their meshes keyed by prop name.  Every prop is a one-surface,
## vertex-coloured mesh, so a MultiMesh per prop type stays one draw call.

const LIB := "res://Assets/frontline/props/props_library.glb"

static var _meshes: Dictionary = {}
static var _ready := false


static func meshes() -> Dictionary:
	if _ready:
		return _meshes
	_ready = true
	if not ResourceLoader.exists(LIB):
		return _meshes
	var packed := load(LIB) as PackedScene
	if packed == null:
		return _meshes
	var scene := packed.instantiate()
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var key := String(mi.name)
		if not key.begins_with("prop_"):
			continue
		# glTF may append a numeric suffix on duplicates.
		key = key.split(".")[0]
		_meshes[key] = mi.mesh
	scene.free()
	return _meshes


## Approximate solid bounds used for the concave prop-collision mesh.  The
## values are half-extents in metres (x, height, z).
static func half_extents(prop_name: String) -> Vector3:
	match prop_name:
		"prop_crate":
			return Vector3(0.47, 0.47, 0.47)
		"prop_barrel", "prop_oil_drum":
			return Vector3(0.34, 0.46, 0.34)
		"prop_sandbags":
			return Vector3(0.85, 0.50, 0.25)
		"prop_barrier":
			return Vector3(1.05, 0.55, 0.32)
		"prop_pipe":
			return Vector3(1.25, 0.55, 0.60)
		"prop_pallet":
			return Vector3(0.62, 0.20, 0.62)
		"prop_tires":
			return Vector3(0.44, 0.62, 0.44)
		"prop_ammo":
			return Vector3(0.46, 0.30, 0.26)
		"prop_camo_net":
			return Vector3(1.75, 1.10, 1.35)
		"prop_hay":
			return Vector3(0.70, 0.62, 0.65)
		"prop_car_wreck":
			return Vector3(1.90, 0.70, 0.85)
		"prop_apc":
			return Vector3(2.40, 1.10, 1.30)
		"prop_fence":
			return Vector3(2.30, 0.85, 0.10)
		"prop_antenna":
			return Vector3(0.55, 2.40, 0.55)
		"prop_generator":
			return Vector3(0.80, 0.60, 0.50)
		"prop_tent":
			return Vector3(1.75, 1.00, 1.40)
		"prop_logs":
			return Vector3(0.70, 0.60, 1.25)
		"prop_sign":
			return Vector3(0.48, 1.20, 0.08)
		"prop_fuel_tank":
			return Vector3(1.35, 0.75, 0.60)
		_:
			return Vector3(0.5, 0.5, 0.5)
