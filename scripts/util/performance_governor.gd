class_name PerformanceGovernor
extends Node

## Adaptive internal-resolution governor.
##
## The sim targets 120 FPS on Intel-class integrated GPUs.  Instead of shipping
## one fixed 3D scale that either stutters or looks soft on every machine, this
## node watches the real frame time and nudges the viewport's FSR scale between
## a per-preset floor and ceiling.  HUD/OSD are canvas items, so they stay at
## native resolution and razor sharp while only the 3D world adapts.
##
## It also respects VSync / Engine.max_fps: capping at 60 Hz must not be
## mistaken for a performance problem that should blur the image further.

const SAMPLE_TIME := 0.45
const DOWN_STEP := 0.04
const UP_STEP := 0.04
const WARMUP_TIME := 4.0
const BAD_SAMPLES_BEFORE_DOWN := 3

var target_fps := 118.0
var min_scale := 0.55
var max_scale := 0.9
var adaptive := true
var fsr_sharpness := 0.3
var _sample_time := SAMPLE_TIME
var _down_step := DOWN_STEP
var _up_step := UP_STEP
var _bad_samples_before_down := BAD_SAMPLES_BEFORE_DOWN
var _down_cooldown := 0.9

var _scale := 0.8
var _acc_time := 0.0
var _acc_frames := 0
var _cooldown := 0.0
var _good_samples := 0
var _bad_samples := 0
var _warmup := WARMUP_TIME


func configure(preset: Dictionary) -> void:
	target_fps = float(preset.get("target_fps", 118.0))
	min_scale = float(preset.get("min_scale", preset.get("scale_3d", 1.0)))
	max_scale = float(preset.get("max_scale", preset.get("scale_3d", 1.0)))
	adaptive = bool(preset.get("adaptive", false))
	fsr_sharpness = float(preset.get("fsr_sharpness", 0.3))
	var mobile_profile := bool(preset.get("mobile_profile", false))
	_sample_time = 0.40 if mobile_profile else SAMPLE_TIME
	_down_step = 0.06 if mobile_profile else DOWN_STEP
	_up_step = 0.03 if mobile_profile else UP_STEP
	_bad_samples_before_down = 2 if mobile_profile else BAD_SAMPLES_BEFORE_DOWN
	_down_cooldown = 0.65 if mobile_profile else 0.9
	_scale = clampf(float(preset.get("scale_3d", max_scale)), min_scale, max_scale)
	var forced := OS.get_environment("QA_FORCE_SCALE")
	if not forced.is_empty():
		# Static-scale QA mode: isolate the upscaler's cost from the adaptive
		# governor's resolution changes.
		adaptive = false
		_scale = clampf(float(forced), 0.25, 1.0)
	_apply_scale()
	_acc_time = 0.0
	_acc_frames = 0
	_cooldown = 0.0
	_good_samples = 0
	_bad_samples = 0
	_warmup = WARMUP_TIME
	set_process(adaptive)


func _process(delta: float) -> void:
	if not adaptive:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_warmup = maxf(0.0, _warmup - delta)
	_acc_time += delta
	_acc_frames += 1
	if _acc_time < _sample_time:
		return

	var fps := float(_acc_frames) / maxf(_acc_time, 0.0001)
	_acc_time = 0.0
	_acc_frames = 0
	# Loading, shader compilation and the first terrain frame produce 4 FPS
	# spikes.  Never let those transient frames collapse the internal scale.
	if _warmup > 0.0 or _cooldown > 0.0:
		return

	var goal := _effective_target()
	if fps < goal * 0.93:
		_good_samples = 0
		_bad_samples += 1
		if _bad_samples >= _bad_samples_before_down and _scale > min_scale + 0.001:
			_set_scale(maxf(min_scale, _scale - _down_step))
			_cooldown = _down_cooldown
			_bad_samples = 0
	elif fps > goal * 1.02:
		_bad_samples = 0
		_good_samples += 1
		if _good_samples >= 2 and _scale < max_scale - 0.001:
			_set_scale(minf(max_scale, _scale + _up_step))
			_cooldown = 1.0
			_good_samples = 0
	else:
		_good_samples = 0
		_bad_samples = 0


func current_scale() -> float:
	return _scale


func _set_scale(value: float) -> void:
	_scale = clampf(value, min_scale, max_scale)
	_apply_scale()
	print("[PerfGovernor] scale3d=", "%.2f" % _scale, " target=", int(_effective_target()),
			" fps=", Engine.get_frames_per_second())


func _apply_scale() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	if _scale < 0.999:
		vp.scaling_3d_mode = QualityManager.scaling_mode()
		vp.scaling_3d_scale = _scale
		vp.fsr_sharpness = fsr_sharpness
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0


## The frame-rate we can actually reach: a 60 Hz VSync panel or the user's FPS
## cap must never trigger endless downscaling.
func _effective_target() -> float:
	var goal := target_fps
	if Engine.max_fps > 0:
		goal = minf(goal, float(Engine.max_fps) - 1.0)
	# A 60 Hz panel cannot show 120 FPS.  Even with VSync disabled the governor
	# must not chase an unreachable target and blur the 3D image down to the
	# minimum scale.  Always respect the physical refresh rate.
	var refresh := DisplayServer.screen_get_refresh_rate()
	if refresh > 1.0:
		goal = minf(goal, refresh - 1.0)
	return maxf(goal, 30.0)
