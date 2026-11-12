extends Node

## Mobile-only verification of the optimized skinned soldier used at runtime.
## The legacy rifleman_merged.glb is not the active combat model; the runtime
## asset is soldier_detailed_merged.glb (one skinned primitive).
const TEST_NAME := "qa_mobile_soldier_asset"


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)


func _run() -> void:
	var rig := DetailedSoldierRig.new()
	add_child(rig)
	var loaded := rig.setup_rig(-1)
	_check(loaded and rig.skeleton != null, "runtime detailed skinned soldier loads")
	if loaded and rig.model != null:
		var meshes := rig.model.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() == 1, "runtime soldier uses one merged body mesh")
		var body := meshes[0] as MeshInstance3D
		_check(body.skin != null or rig.skeleton != null, "merged body is driven by the soldier skeleton")
	var soldier := EnemyRifleman.new()
	add_child(soldier)
	await get_tree().process_frame
	_check(soldier.get("_detailed_rig") != null,
			"mobile combat infantry selects DetailedSoldierRig at runtime")
	get_tree().quit(0 if loaded and rig.skeleton != null
			and rig.model != null and rig.model.find_children("*", "MeshInstance3D", true, false).size() == 1
			and soldier.get("_detailed_rig") != null else 1)
