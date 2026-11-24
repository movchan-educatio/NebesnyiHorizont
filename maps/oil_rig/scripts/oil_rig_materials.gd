@tool
extends Node3D
## Restores the shared atlas materials on imported GLB meshes.
## glTF modules are exported without embedded textures on purpose: all modules
## reuse the same 6 atlas images, which keeps mobile VRAM low.

const MAT_DIR := "res://maps/oil_rig/materials/"

func _ready() -> void:
	call_deferred("_apply")

func _apply() -> void:
	var shared := {
		"MAT_Structures": load(MAT_DIR + "structures.tres"),
		"MAT_Deck": load(MAT_DIR + "deck.tres"),
		"MAT_Emissive": load(MAT_DIR + "emissive.tres"),
		"MAT_FlameCore": load(MAT_DIR + "flame.tres"),
		"MAT_Light": load(MAT_DIR + "light.tres"),
	}
	for mi in find_children("*", "MeshInstance3D", true, false):
		var src: Material = mi.get_active_material(0)
		if src == null:
			continue
		var key := String(src.resource_name)
		if shared.has(key):
			mi.material_override = shared[key]
