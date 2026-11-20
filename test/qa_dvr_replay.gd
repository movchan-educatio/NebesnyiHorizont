extends Node

## Regression for the strike DVR replay.  The old button re-opened the live
## gameplay scene with a REC overlay, so it looked like footage but was just the
## frozen world.  A replay with captured viewport frames must show those exact
## frames; without captured frames it must fall back to the camera path (or an
## explicit "NO RECORDING" state) and always restore the debrief.

const LevelScene := preload("res://sceneries/BigLevel.tscn")
const TEST := "DVR_QA"

var _failures := 0
var _had_no_record := false
var _saved_no_record := ""
var _level: Node3D = null


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _run() -> void:
	_had_no_record = OS.has_environment("DRONE_NO_RECORD")
	_saved_no_record = OS.get_environment("DRONE_NO_RECORD")
	OS.set_environment("DRONE_NO_RECORD", "1")
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.drone_preset = 0
	var level := LevelScene.instantiate() as Node3D
	_level = level
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(6.0).timeout
	if not is_instance_valid(level):
		_check(false, "combat level loaded")
		_finish()
		return
	var results: Control = level.get("_results")
	_check(results != null, "debrief screen exists before the replay")
	if results == null:
		_finish()
		return
	_check(level.get("_dvr_overlay") == null, "DVR overlay is created on demand")

	# Inject six distinctive "recorded" frames.  If playback ever drew the live
	# scene instead of these textures the identity check below fails.
	var frames: Array[Texture2D] = []
	var colors := [Color(0.85, 0.10, 0.10), Color(0.10, 0.85, 0.10),
			Color(0.10, 0.10, 0.85), Color(0.85, 0.85, 0.10),
			Color(0.85, 0.10, 0.85), Color(0.10, 0.85, 0.85)]
	for i in range(colors.size()):
		var img := Image.create(32, 18, false, Image.FORMAT_RGB8)
		img.fill(colors[i])
		frames.append(ImageTexture.create_from_image(img))
	level.set("_dvr_frames", frames)
	results.visible = true
	level.call("_on_dvr_replay_pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(level.get("_dvr_replaying")), "DVR replay starts")
	_check(get_tree().paused, "world is frozen during DVR playback")
	var overlay: CanvasLayer = level.get("_dvr_overlay")
	_check(overlay != null and is_instance_valid(overlay) and overlay.visible,
			"DVR overlay is visible during playback")
	_check(overlay != null and overlay.layer == 300,
			"DVR overlay renders above the mobile HUD")
	var rect: TextureRect = level.get("_dvr_overlay_rect")
	_check(rect != null and rect.texture != null and frames.has(rect.texture),
			"playback shows a captured viewport frame, not the live scene")
	var stamp: Label = level.get("_dvr_overlay_stamp")
	_check(stamp != null and stamp.text.contains("REC"),
			"recorded footage carries the REC stamp")
	var timecode: Label = level.get("_dvr_overlay_time")
	_check(timecode != null and timecode.text.contains("PLAY"),
			"playback shows a running timecode")

	var started := Time.get_ticks_msec()
	while bool(level.get("_dvr_replaying")) and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
	_check(not bool(level.get("_dvr_replaying")), "frame playback finishes on its own")
	await get_tree().process_frame
	_check(not get_tree().paused, "world resumes after DVR playback")
	_check(results.visible, "debrief is restored after DVR playback")
	_check(overlay != null and not overlay.visible, "DVR overlay is hidden after playback")

	# No captured frames and no camera samples: the fallback must say so
	# explicitly instead of pretending the live world is archive footage.
	level.set("_dvr_frames", [] as Array[Texture2D])
	level.set("_dvr_samples", [])
	results.visible = true
	level.call("_on_dvr_replay_pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(bool(level.get("_dvr_replaying")), "fallback replay starts without frames")
	var fallback_time: Label = level.get("_dvr_overlay_time")
	_check(fallback_time != null
			and (fallback_time.text.contains("NO RECORDING")
					or fallback_time.text.contains("ВІДСУТНІЙ")),
			"missing recording shows an explicit no-recording state")
	started = Time.get_ticks_msec()
	while bool(level.get("_dvr_replaying")) and Time.get_ticks_msec() - started < 8000:
		await get_tree().process_frame
	_check(not bool(level.get("_dvr_replaying")) and not get_tree().paused,
			"fallback replay restores the game state")
	_check(results.visible, "fallback replay returns to the debrief")

	_finish()


func _finish() -> void:
	if _level != null and is_instance_valid(_level):
		if get_tree().current_scene == _level:
			get_tree().current_scene = null
		get_tree().paused = false
		_level.queue_free()
		_level = null
		await get_tree().process_frame
	if _had_no_record:
		OS.set_environment("DRONE_NO_RECORD", _saved_no_record)
	else:
		OS.unset_environment("DRONE_NO_RECORD")
	print("[", TEST, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
