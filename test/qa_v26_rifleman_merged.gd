extends Node

## Mobile-only verification of the optimized skinned soldier used at runtime.
## The legacy rifleman_merged.glb is not the active combat model; the runtime
## asset is soldier_detailed_merged.glb (one skinned primitive).
const TEST_NAME := "qa_mobile_soldier_asset"
var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST_NAME, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var rig := DetailedSoldierRig.new()
	add_child(rig)
	var loaded := rig.setup_rig(-1)
	_check(loaded and rig.skeleton != null, "runtime detailed skinned soldier loads")
	if loaded and rig.model != null:
		var meshes := rig.model.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() == 1, "runtime soldier uses one merged body mesh")
		if meshes.size() == 1:
			var body := meshes[0] as MeshInstance3D
			_check(body.skin != null and body.get_node_or_null(body.skeleton) == rig.skeleton,
					"merged body has a skin bound to the soldier skeleton")
	var soldier := EnemyRifleman.new()
	add_child(soldier)
	await get_tree().process_frame
	_check(soldier.get("_detailed_rig") != null,
			"mobile combat infantry selects DetailedSoldierRig at runtime")
	print("[", TEST_NAME, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
