extends Node

## QA: fly forward for ~25 s and report frame-time spikes plus grass rebuild
## timings.  Used to verify that the FollowGrass carpet no longer stutters.

var _level: Node
var _cam: Camera3D
var _started := false
var _last_usec := 0
var _times: Array[float] = []
var _spikes: Array[Dictionary] = []
var _elapsed := 0.0
var _tick := 0.0


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1280, 720)
		get_window().move_to_center()
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	Graphics.apply_quality_preset(Graphics.QualityPreset.MEDIUM)
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	_level = packed.instantiate()
	add_child(_level)
	await get_tree().create_timer(5.0).timeout
	_cam = Camera3D.new()
	_cam.name = "StutterCamera"
	_cam.fov = 90.0
	_cam.near = 0.05
	_cam.far = 4000.0
	_level.add_child(_cam)
	_cam.global_position = Vector3(50.0, 30.0, 260.0)
	_cam.look_at(Vector3(50.0, 25.0, -260.0), Vector3.UP)
	_cam.current = true
	_started = true
	_last_usec = Time.get_ticks_usec()
	print("[STUTTER] camera sweep start")


func _process(delta: float) -> void:
	if not _started:
		return
	_elapsed += delta
	_tick += delta
	# 22 m/s horizontal flight, fixed 30 m altitude: the grass carpet has to
	# rebuild while the camera travels, exactly like an FPV pass.
	_cam.global_position.z -= 22.0 * delta
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_usec) / 1000000.0
	_last_usec = now
	_times.append(dt)
	if dt > 0.05:
		_spikes.append({"t": _elapsed, "dt": dt, "pos": _cam.global_position})
	if _tick >= 25.0:
		_started = false
		_report()


func _report() -> void:
	var sorted := _times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var avg := float(n) / maxf(_elapsed, 0.001)
	var p50: float = sorted[int(n * 0.50)] if n > 0 else 0.0
	var p95: float = sorted[mini(int(n * 0.95), n - 1)] if n > 0 else 0.0
	var p99: float = sorted[mini(int(n * 0.99), n - 1)] if n > 0 else 0.0
	print("[STUTTER] frames=", n, " avg_fps=%.1f" % avg,
			" p50_ms=%.1f p95_ms=%.1f p99_ms=%.1f max_ms=%.1f" % [
				p50 * 1000.0, p95 * 1000.0, p99 * 1000.0,
				sorted[n - 1] * 1000.0 if n > 0 else 0.0])
	print("[STUTTER] spikes>50ms=", _spikes.size())
	for i in range(mini(_spikes.size(), 20)):
		var s: Dictionary = _spikes[i]
		print("[STUTTER] spike t=%.2f dt=%.1fms pos=%s" % [
			float(s["t"]), float(s["dt"]) * 1000.0, str(s["pos"])])
	get_tree().quit()
