@tool
extends EditorScenePostImport

## Optional per-asset GLB/glTF import hook.
##
## Assign this file to an asset's Import panel → "Custom Script" (the
## `import_script/path` field in the .import file) when an inherited model
## still uses flat or unshaded placeholder materials.  The same helpers are
## applied at runtime by DroneCatalog/FrontlineAssets, so a model remains
## consistent even if its import settings predate this pipeline.

const MaterialUtils = preload("res://scripts/util/glb_material_utils.gd")


func _post_import(scene: Node) -> Object:
	if scene == null:
		return scene
	var changed := MaterialUtils.ensure_pbr(scene)
	print("[GLB-Import] PBR material pass: ", changed, " surface override(s) on ",
			scene.name)
	return scene
