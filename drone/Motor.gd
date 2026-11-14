@tool
extends Node3D
class_name Motor


@onready var propeller := get_children().back() as Propeller

@export var clockwise := true: set = set_clockwise
@export var MAX_TORQUE := 1000.0 # (float, 0.0, 10000.0)
@export var MAX_RPM := 10000.0 # (float, 0.0, 30000.0)
@export var RPM_ACCELERATION := 16000.0 # (float, 0, 1000000)
## DShot/ESC active braking multiplier for spool-down.  A real ESC brakes the
## motor harder than it accelerates it, which is what gives a quad its crisp
## throttle chops; 1.0 would coast down like a free-spinning propeller.
@export var ESC_BRAKING := 1.0 # (float, 1.0, 4.0)
@export var MIN_POWER := 1 # (int, 0, 100)
@export var kv := 2000 # (int, 100, 20000)
@export var motor_size := 2207 # (int, 101, 9999)

var torque := 0.0: get = get_torque, set = set_torque
var rpm := 0.0: get = get_rpm, set = set_rpm
var rpm_target := 0.0: get = get_rpm_target, set = set_rpm_target
var max_rpm_change := 0.0
var powered := false

@onready var rotor := $Motor_Rotor

var sounds := []
var sound1: AudioStreamPlayer = null
var sound2: AudioStreamPlayer = null
var sound_selector := -1
## Overall gain of the recorded rotor loops. They are already normalised; a
## small negative offset keeps four motors from clipping when they all sum.
const SOUND_GAIN_DB := -2.0
## Audio crossfades only need ~30 updates per second.  The old code walked all
## eight rotor loops for all four motors on every 120 Hz physics tick.
var _sound_tick := 0.0
var _sound_accum := 0.0


func _ready() -> void:
	set_clockwise(clockwise)
	
	if Engine.is_editor_hint():
		return
	
	MAX_TORQUE = MAX_TORQUE / 1000.0
	max_rpm_change = MAX_TORQUE * RPM_ACCELERATION
	
	var paths := [
		"res://Assets/Audio/SFX/Propellers/looped/idle_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor1_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor2_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor3_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor4_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor5_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor6_loop.wav",
		"res://Assets/Audio/SFX/Propellers/looped/motor7_loop.wav",
	]
	# Four identical engine loops per drone beat against each other and sound
	# like a pulsing siren.  Only the first motor owns the audio; the other
	# three stay silent but keep their physics.
	var emit_sound := true
	var owner_node := get_parent()
	while owner_node != null and not (owner_node is Drone):
		owner_node = owner_node.get_parent()
	if owner_node is Drone:
		if owner_node.has_meta("engine_sound_source"):
			emit_sound = false
		else:
			owner_node.set_meta("engine_sound_source", self)
	if emit_sound:
		for path in paths:
			var player := AudioStreamPlayer.new()
			player.stream = load(path)
			player.volume_db = -80.0
			player.bus = "Engine"
			add_child(player)
			# The recorded loops are imported without a loop flag. Without this a
			# motor sample simply ends after 2-7 seconds and the drone goes silent.
			_make_looping(player.stream)
			sounds.append(player)
		sound1 = sounds[0]
		sound2 = sounds[1]


func _make_looping(stream: AudioStream) -> void:
	var wav := stream as AudioStreamWAV
	if wav == null:
		return
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = maxi(1, int(wav.get_length() * float(wav.mix_rate)))


func _exit_tree() -> void:
	for p in sounds:
		if p is AudioStreamPlayer and is_instance_valid(p):
			(p as AudioStreamPlayer).stop()
			(p as AudioStreamPlayer).stream = null
	sounds.clear()
	sound1 = null
	sound2 = null


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	var rot := rpm * PI / 30.0
	if clockwise:
		rot = -rot
	rotor.rotate_object_local(Vector3.UP, rot * delta)
	propeller.rotate_object_local(Vector3.UP, rot * delta)
	
	rotor.transform = rotor.transform.orthonormalized()
	propeller.transform = propeller.transform.orthonormalized()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_sound_tick -= delta
	_sound_accum += delta
	if _sound_tick > 0.0:
		return
	_sound_tick = 1.0 / 30.0
	var abs_rpm: float = absf(rpm)
	update_sound(abs_rpm, _sound_accum)
	_sound_accum = 0.0


func update_thrust(delta: float) -> void:
	var rate := max_rpm_change * delta
	if powered:
		# Active braking on throttle chops; acceleration uses the normal torque
		# limit.  move_toward keeps the spool monotonic and frame-rate safe.
		if absf(rpm_target) < absf(rpm):
			rate *= ESC_BRAKING
		set_rpm(move_toward(rpm, rpm_target, rate))
		set_torque(rpm / (MAX_RPM as float) * MAX_TORQUE)
	else:
		rate *= ESC_BRAKING * clampf(absf(rpm) / 10000.0, 0.05, 1.0)
		set_rpm(move_toward(rpm, 0.0, rate))
		set_torque(0.0)


func set_clockwise(cw: bool) -> void:
	clockwise = cw
	if propeller:
		propeller.set_clockwise(clockwise)


func set_torque(x: float) -> void:
	torque = x


func get_torque() -> float:
	if clockwise:
		return torque
	else:
		return -torque


func set_pwm(p: float) -> void:
	set_rpm_target(p * MAX_RPM)


func set_rpm_target(x: float) -> void:
	rpm_target = x


func get_rpm_target() -> float:
	return rpm_target


func set_rpm(x: float) -> void:
	rpm = clamp(x, -MAX_RPM, MAX_RPM)
	propeller.rpm = rpm


func get_rpm() -> float:
	return rpm


func _on_armed(_mode) -> void:
	if sounds.is_empty():
		return
	sound_selector = -1
	sound1 = sounds[0]
	sound2 = sounds[1]
	# Start every recorded stage once. They loop for the whole flight; volume
	# crossfades pick the audible pair, so stage changes can never fall silent.
	for player in sounds:
		player.volume_db = -80.0
		if not player.playing:
			player.play()


## Chooses one of the recorded motor stages and crossfades between the two
## samples around the current RPM. Every sample keeps playing, so switching
## stages is instant and cannot leave the drone without engine noise.
func update_sound(abs_rpm: float = 0.0, delta: float = 0.016) -> void:
	if sounds.is_empty():
		return
	var rpm_ratio: float = clampf(abs_rpm / maxf(MAX_RPM, 1.0), 0.0, 1.0)
	var stage := 1
	var level_start := 0.0
	var level_end := 0.15
	var volume_low := 0.05
	var volume_high := 0.10
	var pitch_low1 := 1.0
	var pitch_high1 := 1.0
	var pitch_low2 := 0.85
	var pitch_high2 := 1.0

	if abs_rpm < 10.0:
		stage = 0
	elif rpm_ratio < 0.15:
		stage = 1
		level_start = 0.0
		level_end = 0.15
		volume_low = 0.05
		volume_high = 0.10
		pitch_low1 = 1.0
		pitch_high1 = 1.0
		pitch_low2 = 0.85
		pitch_high2 = 1.0
	elif rpm_ratio < 0.3:
		stage = 2
		level_start = 0.15
		level_end = 0.3
		volume_low = 0.2
		volume_high = 0.3
		pitch_low1 = 1.0
		pitch_high1 = 1.15
		pitch_low2 = 0.73
		pitch_high2 = 1.0
	elif rpm_ratio < 0.45:
		stage = 3
		level_start = 0.3
		level_end = 0.45
		volume_low = 0.35
		volume_high = 0.45
		pitch_low1 = 1.0
		pitch_high1 = 1.25
		pitch_low2 = 0.8
		pitch_high2 = 1.0
	elif rpm_ratio < 0.6:
		stage = 4
		level_start = 0.45
		level_end = 0.6
		volume_low = 0.5
		volume_high = 0.55
		pitch_low1 = 1.0
		pitch_high1 = 1.22
		pitch_low2 = 0.81
		pitch_high2 = 1.0
	elif rpm_ratio < 0.75:
		stage = 5
		level_start = 0.6
		level_end = 0.75
		volume_low = 0.65
		volume_high = 0.7
		pitch_low1 = 1.0
		pitch_high1 = 1.23
		pitch_low2 = 0.8
		pitch_high2 = 1.0
	elif rpm_ratio < 0.9:
		stage = 6
		level_start = 0.75
		level_end = 0.9
		volume_low = 0.8
		volume_high = 0.9
		pitch_low1 = 1.0
		pitch_high1 = 1.22
		pitch_low2 = 0.82
		pitch_high2 = 1.0
	else:
		stage = 7
		level_start = 0.9
		level_end = 1.0
		volume_low = 0.9
		volume_high = 0.95
		pitch_low1 = 1.0
		pitch_high1 = 1.1
		pitch_low2 = 0.91
		pitch_high2 = 1.0

	# Keep every stage looping while the rotors are turning.
	if powered or abs_rpm > 1.0:
		for player in sounds:
			if not player.playing:
				player.play()

	if stage == 0:
		for i in range(sounds.size()):
			var target := -18.0 if (i == 0 and powered) else -80.0
			sounds[i].volume_db = move_toward(sounds[i].volume_db, target,
					absf(delta) * 220.0)
		if powered:
			sounds[0].pitch_scale = 1.0
		return

	sound_selector = stage
	var index1: int = stage - 1
	var index2: int = stage
	sound1 = sounds[index1]
	sound2 = sounds[index2]
	var span := maxf(level_end - level_start, 0.0001)
	var blend := clampf((rpm_ratio - level_start) / span, 0.0, 1.0)
	sound1.pitch_scale = lerpf(pitch_low1, pitch_high1, blend)
	sound2.pitch_scale = lerpf(pitch_low2, pitch_high2, blend)

	var levels := [0.0, -80.0]
	if rpm_ratio <= volume_low:
		levels = [0.0, -80.0]
	elif rpm_ratio >= volume_high:
		levels = [-80.0, 0.0]
	else:
		var interp := clampf((rpm_ratio - volume_low) / maxf(volume_high - volume_low, 0.0001),
				0.0, 1.0)
		levels[0] = get_interpolated_sound_level(0.0, -80.0, interp, "expo")
		levels[1] = get_interpolated_sound_level(0.0, -80.0, 1.0 - interp, "expo")

	for i in range(sounds.size()):
		var target := -80.0
		if i == index1:
			target = float(levels[0]) + SOUND_GAIN_DB
		elif i == index2:
			target = float(levels[1]) + SOUND_GAIN_DB
		sounds[i].volume_db = move_toward(sounds[i].volume_db, target,
				absf(delta) * 320.0)


## Kept for compatibility with the old motor scenes/tests.
func update_sound_source(source: int = 0) -> void:
	sound_selector = source


func adjust_sound_level(b: float, e: float, v: float) -> void:
	var levels := [0.0, -80.0]
	if v <= b:
		levels = [0.0, -80.0]
	elif v >= e:
		levels = [-80.0, 0.0]
	else:
		var interp := (v - b) / maxf(e - b, 0.0001)
		levels[0] = get_interpolated_sound_level(0.0, -80.0, interp, "expo")
		levels[1] = get_interpolated_sound_level(0.0, -80.0, 1.0 - interp, "expo")
	if sound1 != null:
		sound1.volume_db = float(levels[0])
	if sound2 != null:
		sound2.volume_db = float(levels[1])


func get_interpolated_sound_level(b: float, e: float, v: float, transition: String = "expo") -> float:
	var result := 0.0
	match transition:
		"expo":
			result = e * pow(2, 10 * (v - 1)) + b - e * 0.001
		"linear":
			result = b + v * (e - b)
	return result


func get_rpm_ratio_range(start: float = 0, end: float = 1) -> Array:
	return [start, end]


func get_pitch_range(start1: float = 1, end1: float = 1, start2: float = 1, end2: float = 1) -> Array:
	return [start1, end1, start2, end2]
