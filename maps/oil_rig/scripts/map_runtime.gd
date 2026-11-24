extends Node3D
## Fills the repeated-prop MultiMesh pool at runtime. Godot does not serialise
## per-instance transforms in .tscn files. Neon gate rings were removed;
## FPVGates keeps only invisible Marker3D nodes for gameplay logic.
##
## The source package also ships scripts/oil_rig_materials.gd, but the authored
## .tscn never attaches it: the GLBs are exported WITHOUT embedded textures, so
## a plain instance is white. Restore the six authored atlas materials here on
## the same root node that the scene already uses (a Node can have one script).
## OilRigLevel.gd applies the same overrides; setting them twice is idempotent.

const MAT_DIR := "res://maps/oil_rig/materials/"

@onready var posts_mm: MultiMeshInstance3D = $InstancedDetails/RailPosts

func _ready() -> void:
	_restore_atlas_materials()
	call_deferred("_populate")

func _restore_atlas_materials() -> void:
	var shared := {
		"MAT_Structures": load(MAT_DIR + "structures.tres"),
		"MAT_Deck": load(MAT_DIR + "deck.tres"),
		"MAT_Emissive": load(MAT_DIR + "emissive.tres"),
		"MAT_FlameCore": load(MAT_DIR + "flame.tres"),
		"MAT_Light": load(MAT_DIR + "light.tres"),
	}
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for surface in range(mi.mesh.get_surface_count()):
			var src: Material = mi.get_surface_override_material(surface)
			if src == null:
				src = mi.mesh.surface_get_material(surface)
			if src == null:
				continue
			var key := String(src.resource_name)
			if shared.has(key):
				mi.set_surface_override_material(surface, shared[key])

func _populate() -> void:
	_populate_posts()

func _populate_posts() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://maps/oil_rig/scripts/instancing_data.json"))
	if data == null or not data.has("posts"):
		push_warning("OilRigMap: instancing_data.json missing")
		return
	var mm := posts_mm.multimesh
	var pts: Array = data["posts"]
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		var p: Array = pts[i]
		mm.set_instance_transform(i,
			Transform3D(Basis.IDENTITY, Vector3(p[0], p[1], p[2])))
