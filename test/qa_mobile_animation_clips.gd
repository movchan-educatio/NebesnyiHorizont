extends Node3D

## QA for the exported soldier animation clips: every .tres exists, has tracks
## and length, and plays on the runtime skeleton without errors.
var _failures := 0


func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[MOBILE_ANIM_CLIPS] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	var names := ["Idle", "Walk", "Run", "Aim", "Fire", "Reload", "Hit", "Death"]
	var clips := {}
	for clip_name in names:
		var path := "res://Assets/combat/animations/soldier_%s.tres" % clip_name
		var clip := load(path) as Animation
		_check(clip != null and clip.get_track_count() > 0 and clip.length > 0.0,
				"%s clip loads with tracks and length" % clip_name)
		if clip != null:
			clips[clip_name] = clip
	var rig := DetailedSoldierRig.new()
	add_child(rig)
	var loaded := rig.setup_rig(-1)
	_check(loaded and rig.clip_player != null, "runtime rig hosts the clip preview player")
	if loaded and rig.clip_player != null:
		var all_play := true
		for clip_name in names:
			if not rig.preview_clip(clip_name, 1.0):
				all_play = false
				break
			await get_tree().process_frame
			if not rig.clip_player.is_playing():
				all_play = false
				break
			rig.stop_preview()
		_check(all_play, "all eight clips play on the skeleton without errors")
		var library := rig.clip_player.get_animation_library("soldier")
		_check(library != null and library.get_animation_list().size() == 8,
				"preview library contains all eight clips")
	print("[MOBILE_ANIM_CLIPS] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
