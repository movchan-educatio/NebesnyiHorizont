## Procedurally generated combat audio. Keeps the project asset-free:
## the explosion is synthesised once and cached, then reused by every boom.
class_name CombatSfx


const MAX_LOW_VOICES := 16
static var _active_3d_voices := 0

static var _boom_stream: AudioStreamWAV = null
static var _shot_stream: AudioStreamWAV = null
static var _rifle_stream: AudioStreamWAV = null
static var _radio_stream: AudioStreamWAV = null
static var _hitmarker_stream: AudioStreamWAV = null


static func _can_spawn_3d_voice(priority: bool = false) -> bool:
	if QualityManager.get_active_level() == QualityManager.Level.LOW:
		var cap := MAX_LOW_VOICES + (4 if priority else 0)
		return _active_3d_voices < cap
	return true


static func _track_3d_voice(player: AudioStreamPlayer3D) -> void:
	_active_3d_voices += 1
	player.tree_exiting.connect(func(): _active_3d_voices = maxi(_active_3d_voices - 1, 0), CONNECT_ONE_SHOT)


static func boom_stream() -> AudioStreamWAV:
	if _boom_stream != null:
		return _boom_stream
	var rate := 22050
	var length := 1.15
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 4.6)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.14)
		lp2 = lerpf(lp2, lp, 0.08)
		var thump: float = sin(TAU * 52.0 * t) * exp(-t * 7.0)
		var crack := 0.0
		if t < 0.06:
			crack = randf_range(-0.7, 0.7) * (1.0 - t / 0.06)
		var s: float = (lp2 * 2.6 + thump * 0.85 + crack) * env
		s = clampf(s, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	_boom_stream = AudioStreamWAV.new()
	_boom_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_boom_stream.mix_rate = rate
	_boom_stream.stereo = false
	_boom_stream.data = data
	return _boom_stream


static func play_boom(parent: Node, world_position: Vector3, volume_db: float = 4.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(true):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = boom_stream()
	player.volume_db = volume_db
	player.bus = "Combat"
	player.unit_size = 26.0
	player.max_distance = 500.0
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	player.finished.connect(player.queue_free)


## Short, dry AA cannon crack. Cached once and reused for every tracer.
static func shot_stream() -> AudioStreamWAV:
	if _shot_stream != null:
		return _shot_stream
	var rate := 22050
	var length := 0.17
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 24.0)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.32)
		var crack: float = lp * 1.5 + randf_range(-0.35, 0.35)
		var thump: float = sin(TAU * 95.0 * t) * exp(-t * 28.0)
		var s: float = clampf((crack + thump * 0.7) * env, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32767.0))
	_shot_stream = AudioStreamWAV.new()
	_shot_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_shot_stream.mix_rate = rate
	_shot_stream.stereo = false
	_shot_stream.data = data
	return _shot_stream


static func play_shot(parent: Node, world_position: Vector3, volume_db: float = -6.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(false):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = shot_stream()
	player.volume_db = volume_db
	player.bus = "Combat"
	player.unit_size = 14.0
	player.max_distance = 260.0
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	player.finished.connect(player.queue_free)


## Short, sharp rifle crack for the enemy infantry.  Quieter and higher pitched
## than the AA cannon so a squad reads as small-arms fire.
static func rifle_stream() -> AudioStreamWAV:
	if _rifle_stream != null:
		return _rifle_stream
	var rate := 22050
	var length := 0.26
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 38.0)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.55)
		lp2 = lerpf(lp2, lp, 0.10)
		var crack: float = lp * 1.8 + randf_range(-0.28, 0.28)
		var thump: float = sin(TAU * 145.0 * t) * exp(-t * 42.0)
		var s: float = (crack + thump * 0.45) * env
		# A short slap-back tail makes a lone rifle read across the valley
		# instead of sounding like a dry click.
		if t > 0.13:
			s += lp2 * exp(-(t - 0.13) * 9.0) * 0.32
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	_rifle_stream = AudioStreamWAV.new()
	_rifle_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_rifle_stream.mix_rate = rate
	_rifle_stream.stereo = false
	_rifle_stream.data = data
	return _rifle_stream


static func play_rifle(parent: Node, world_position: Vector3, volume_db: float = -9.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(false):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = rifle_stream()
	player.volume_db = volume_db
	player.bus = "Combat"
	player.unit_size = 9.0
	player.max_distance = 180.0
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	player.finished.connect(player.queue_free)


# ---------------------------------------------------------------------------
#  Heavy weapons, tracks, burning wrecks and distant artillery
# ---------------------------------------------------------------------------
static var _cannon_stream: AudioStreamWAV = null
static var _autocannon_stream: AudioStreamWAV = null
static var _track_stream: AudioStreamWAV = null
static var _fire_stream: AudioStreamWAV = null
static var _artillery_stream: AudioStreamWAV = null
static var _servo_stream: AudioStreamWAV = null


## Tank main gun: a deep 42 Hz thump, a broadband muzzle blast and a long tail.
## The AA/rifle crack was never meant to carry a 125 mm cannon.
static func cannon_stream() -> AudioStreamWAV:
	if _cannon_stream != null:
		return _cannon_stream
	var rate := 22050
	var count := int(rate * 1.05)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 3.0)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.22)
		lp2 = lerpf(lp2, lp, 0.06)
		var thump: float = sin(TAU * 42.0 * t) * exp(-t * 4.2) * 0.95
		var crack: float = noise * exp(-t * 34.0) * 0.55
		var blast: float = lp2 * 2.1
		var s: float = (thump + crack + blast) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	_cannon_stream = _make_stream(rate, data, false)
	return _cannon_stream


## Autocannon / heavy machine gun: shorter and harder than the rifle, with a
## mechanical low thump so BMP/APC bursts read as cannon fire.
static func autocannon_stream() -> AudioStreamWAV:
	if _autocannon_stream != null:
		return _autocannon_stream
	var rate := 22050
	var count := int(rate * 0.16)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 20.0)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.38)
		var crack: float = lp * 1.5 + randf_range(-0.3, 0.3)
		var thump: float = sin(TAU * 78.0 * t) * exp(-t * 26.0) * 0.9
		var s: float = (crack + thump) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	_autocannon_stream = _make_stream(rate, data, false)
	return _autocannon_stream


## Track clatter: 9 clanks per second plus a low rumble, looped seamlessly.
## Played as a second layer whose volume/pitch follows the vehicle speed.
static func track_clatter_stream() -> AudioStreamWAV:
	if _track_stream != null:
		return _track_stream
	var rate := 22050
	var count := rate
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.18)
		# Rhythmic track pin impacts at ~14 Hz with metallic ringing
		var pin_cycle := fmod(t * 14.0, 1.0)
		var pin_click := exp(-pin_cycle * 24.0) * sin(TAU * 440.0 * t) * 0.42
		# Low diesel track guide rumble + road wheel squeak
		var s := sin(TAU * 38.0 * t) * 0.28 + sin(TAU * 76.0 * t) * 0.16
		s += sin(TAU * 1150.0 * t) * 0.07 * (sin(TAU * 3.5 * t) * 0.5 + 0.5)
		s += lp * 0.22 + pin_click
		values[i] = clampf(s * 0.95, -1.0, 1.0)
	_track_stream = _finalise_loop(values, rate)
	return _track_stream


## Burning wreck: filtered roar with random pops; looped for the fire lifetime.
static func fire_stream() -> AudioStreamWAV:
	if _fire_stream != null:
		return _fire_stream
	var rate := 22050
	var count := int(rate * 2.0)
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.05)
		var s := lp * 1.5 + sin(TAU * 73.0 * t) * 0.05
		if randf() < 0.0025:
			s += randf_range(-0.8, 0.8)
		values[i] = clampf(s, -1.0, 1.0)
	_fire_stream = _finalise_loop(values, rate)
	return _fire_stream


## Distant artillery rumble: a long, low boom with no muzzle crack.
static func artillery_stream() -> AudioStreamWAV:
	if _artillery_stream != null:
		return _artillery_stream
	var rate := 22050
	var count := int(rate * 2.6)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 1.25)
		var noise := randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.07)
		lp2 = lerpf(lp2, lp, 0.03)
		var thump: float = sin(TAU * 33.0 * t) * exp(-t * 1.8) * 0.8
		var s: float = (thump + lp2 * 2.4) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	_artillery_stream = _make_stream(rate, data, false)
	return _artillery_stream


static func _play_3d(parent: Node, stream: AudioStream, world_position: Vector3,
		volume_db: float, unit_size: float, max_distance: float,
		pitch: float = 1.0, bus: String = "Combat", priority: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(priority):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.bus = bus
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.pitch_scale = pitch
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	if not (stream is AudioStreamWAV) \
			or (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		player.finished.connect(player.queue_free)


static func play_cannon(parent: Node, world_position: Vector3,
		volume_db: float = -4.0) -> void:
	_play_3d(parent, cannon_stream(), world_position, volume_db, 34.0, 900.0, 1.0, "Combat", true)


static func play_autocannon(parent: Node, world_position: Vector3,
		volume_db: float = -7.0) -> void:
	_play_3d(parent, autocannon_stream(), world_position, volume_db, 17.0, 420.0)


## Low, pitch-down exhaust pop for a truck/tank under load.
static func play_backfire(parent: Node, world_position: Vector3,
		volume_db: float = -16.0) -> void:
	_play_3d(parent, autocannon_stream(), world_position, volume_db, 12.0, 140.0, 0.62)


## Short electric motor whine for a tank/SAM turret traversing.
static func servo_stream() -> AudioStreamWAV:
	if _servo_stream != null:
		return _servo_stream
	var rate := 22050
	var count := int(rate * 0.34)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 7.0) * smoothstep(0.0, 0.02, t)
		var sweep: float = 520.0 - 230.0 * (t / 0.34)
		var s: float = (sin(TAU * sweep * t) * 0.34
				+ sin(TAU * sweep * 2.0 * t) * 0.11
				+ randf_range(-0.05, 0.05)) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	_servo_stream = _make_stream(rate, data, false)
	return _servo_stream


static func play_servo(parent: Node, world_position: Vector3,
		volume_db: float = -18.0) -> void:
	_play_3d(parent, servo_stream(), world_position, volume_db, 8.0, 110.0)


static func play_artillery(parent: Node, world_position: Vector3,
		volume_db: float = -10.0) -> void:
	_play_3d(parent, artillery_stream(), world_position, volume_db, 55.0, 1500.0)


## Starts a burning-wreck loop and schedules a few secondary pops.  The player
## frees itself after `duration`.
static func start_burning(parent: Node, world_position: Vector3,
		duration: float = 26.0) -> void:
	if DisplayServer.get_name() == "headless" or parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(false):
		return
	var fire := AudioStreamPlayer3D.new()
	fire.stream = fire_stream()
	fire.volume_db = -13.0
	fire.bus = "Combat"
	fire.unit_size = 11.0
	fire.max_distance = 220.0
	_track_3d_voice(fire)
	parent.add_child(fire)
	fire.global_position = world_position
	fire.play()
	var timer := Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	fire.add_child(timer)
	timer.timeout.connect(fire.queue_free)
	timer.start()
	# Secondary ammunition pops at random moments (skipped on LOW voice budget).
	if QualityManager.get_active_level() != QualityManager.Level.LOW:
		var pop_timer := Timer.new()
		pop_timer.one_shot = true
		pop_timer.wait_time = randf_range(1.6, 4.2)
		fire.add_child(pop_timer)
		pop_timer.timeout.connect(func():
			if not is_instance_valid(fire) or not is_instance_valid(parent) or not parent.is_inside_tree():
				return
			play_autocannon(parent, world_position + Vector3(
					randf_range(-1.2, 1.2), randf_range(0.2, 1.2),
					randf_range(-1.2, 1.2)), -17.0)
			pop_timer.wait_time = randf_range(1.6, 4.2)
			pop_timer.start()
		)
		pop_timer.start()


static var _engine_stream: AudioStreamWAV = null
static var _wind_stream: AudioStreamWAV = null
static var _beeper_stream: AudioStreamWAV = null
static var _drop_stream: AudioStreamWAV = null
static var _music_stream: AudioStreamWAV = null
static var _combat_music: AudioStreamWAV = null
static var _footstep_stream: AudioStreamWAV = null
static var _soldier_death_stream: AudioStreamWAV = null
static var _drone_impact_stream: AudioStreamWAV = null
static var _fpv_stream: AudioStreamWAV = null
static var _tank_stream: AudioStreamWAV = null
static var _bmp_stream: AudioStreamWAV = null
static var _apc_stream: AudioStreamWAV = null
static var _truck_stream: AudioStreamWAV = null
static var _heli_stream: AudioStreamWAV = null
static var _shahed_stream: AudioStreamWAV = null
static var _motor_5in_stream: AudioStreamWAV = null
static var _motor_8in_stream: AudioStreamWAV = null
static var _motor_usv_stream: AudioStreamWAV = null
static var _motor_pusher_stream: AudioStreamWAV = null
static var _motor_jet_stream: AudioStreamWAV = null
static var _motor_hexa_stream: AudioStreamWAV = null
static var _motor_7in_stream: AudioStreamWAV = null
static var _thunder_stream: AudioStreamWAV = null


static func _make_stream(rate: int, samples: PackedByteArray,
		loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = samples
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size() / 2
	return stream


static func engine_stream() -> AudioStreamWAV:
	if _engine_stream != null:
		return _engine_stream
	var rate := 22050
	var count := int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(rate)
		var s := sin(TAU * 88.0 * t) * 0.5 + sin(TAU * 176.0 * t) * 0.22 \
			+ sin(TAU * 44.0 * t) * 0.2
		s += randf_range(-0.06, 0.06)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	_engine_stream = _make_stream(rate, data, true)
	return _engine_stream


## Diesel rumble used for the T-72. Low fundamental, a hard second harmonic
## and filtered clatter read as a tracked vehicle rather than a car engine.
static func tank_engine_stream() -> AudioStreamWAV:
	if _tank_stream != null:
		return _tank_stream
	_tank_stream = _engine_loop(22050, 1.0, 43.0, 4, 0.22, 0.0, 0.0, 7.0, 0.25)
	return _tank_stream


## BMP-2: faster, harder diesel than the tank, with a small turbo whine.
static func bmp_engine_stream() -> AudioStreamWAV:
	if _bmp_stream != null:
		return _bmp_stream
	_bmp_stream = _engine_loop(22050, 1.0, 68.0, 4, 0.17, 620.0, 0.035, 9.0, 0.18)
	return _bmp_stream


## BTR-90: wheeled APC, a little smoother and higher than the BMP.
static func apc_engine_stream() -> AudioStreamWAV:
	if _apc_stream != null:
		return _apc_stream
	_apc_stream = _engine_loop(22050, 1.0, 78.0, 3, 0.14, 480.0, 0.025, 0.0, 0.0)
	return _apc_stream


## Light truck / Tigr: busy petrol engine with a valvetrain rattle.
static func truck_engine_stream() -> AudioStreamWAV:
	if _truck_stream != null:
		return _truck_stream
	_truck_stream = _engine_loop(22050, 1.0, 96.0, 5, 0.12, 950.0, 0.02, 12.0, 0.15)
	return _truck_stream


## Helicopter: 13 Hz blade slap + turbine whine. The amplitude modulation is
## what makes it unmistakably a rotor aircraft.
static func heli_rotor_stream() -> AudioStreamWAV:
	if _heli_stream != null:
		return _heli_stream
	var rate := 22050
	var count := rate
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.09)
		var slap: float = pow(maxf(0.0, sin(TAU * 13.0 * t)), 3.0)
		var s := lp * (0.30 + 0.80 * slap)
		s += sin(TAU * 55.0 * t) * 0.16
		s += sin(TAU * 104.0 * t) * 0.07 * (0.5 + 0.5 * slap)
		s += sin(TAU * 880.0 * t) * 0.035
		values[i] = clampf(s * 0.9, -1.0, 1.0)
	_heli_stream = _finalise_loop(values, rate)
	return _heli_stream


## Shahed-136: angry two-stroke pusher buzz, much higher and sharper than the
## ground vehicles.
static func shahed_engine_stream() -> AudioStreamWAV:
	if _shahed_stream != null:
		return _shahed_stream
	var rate := 22050
	var count := rate
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.20)
		var s := sin(TAU * 112.0 * t) * 0.30
		s += sin(TAU * 224.0 * t) * 0.22
		s += sin(TAU * 336.0 * t) * 0.13
		s += sin(TAU * 448.0 * t) * 0.07
		s += lp * 0.16
		s *= 0.82 + 0.18 * sin(TAU * 14.0 * t)
		values[i] = clampf(s, -1.0, 1.0)
	_shahed_stream = _finalise_loop(values, rate)
	return _shahed_stream


## Shared diesel synthesiser: a harmonic stack plus filtered noise and an
## optional turbo whine. Frequencies are whole numbers so the 1 s loop is
## musically seamless; a short crossfade hides the noise seam.
static func _engine_loop(rate: int, length: float, base: float, harmonics: int,
		noise_mix: float, whine_hz: float, whine_mix: float,
		pulse_hz: float, pulse_mix: float) -> AudioStreamWAV:
	var count := int(rate * length)
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var s := 0.0
		for h in range(1, harmonics + 1):
			s += sin(TAU * base * float(h) * t) * (0.55 / float(h))
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.11)
		s += lp * noise_mix
		if whine_hz > 0.0:
			s += sin(TAU * whine_hz * t) * whine_mix
		if pulse_hz > 0.0:
			var p_mix := minf(pulse_mix, 0.04)
			s *= 1.0 - p_mix * 0.5 + p_mix * 0.5 * sin(TAU * pulse_hz * t)
		values[i] = clampf(s * 0.72, -1.0, 1.0)
	return _finalise_loop(values, rate)


static func _finalise_loop(values: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var count := values.size()
	var fade := mini(int(rate * 0.05), count / 6)
	var out_count := count - fade
	for i in range(fade):
		var w := float(i) / float(maxi(fade, 1))
		values[i] = lerpf(values[out_count + i], values[i], w)
	var data := PackedByteArray()
	data.resize(out_count * 2)
	for i in range(out_count):
		data.encode_s16(i * 2, int(clampf(values[i], -1.0, 1.0) * 30000.0))
	return _make_stream(rate, data, true)


static func wind_stream() -> AudioStreamWAV:
	if _wind_stream != null:
		return _wind_stream
	var rate := 22050
	var count := int(rate * 1.1)
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	for i in range(count):
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.04)
		values[i] = clampf(lp * 1.5, -1.0, 1.0)
	_wind_stream = _finalise_loop(values, rate)
	return _wind_stream


## Classic two-beep low-voltage warning.  One 0.42 s buffer contains both
## pulses, so the OSD only has to call play() on the chosen cadence.
static func beeper_stream() -> AudioStreamWAV:
	if _beeper_stream != null:
		return _beeper_stream
	var rate := 22050
	var count := int(rate * 0.42)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(rate)
		var beep := 0.0
		if t < 0.09:
			beep = t / 0.09
		elif t >= 0.15 and t < 0.24:
			beep = (t - 0.15) / 0.09
		var env := clampf(sin(beep * PI), 0.0, 1.0) if beep > 0.0 else 0.0
		var s := (sin(TAU * 2600.0 * t) + sin(TAU * 5200.0 * t) * 0.25) * env * 0.55
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	_beeper_stream = _make_stream(rate, data, false)
	return _beeper_stream


static var _alert_streams := {}
static var _ew_crackle_stream: AudioStreamWAV = null


## Short cockpit alert tones.  Keeping them synthesised avoids shipping voice
## assets and lets the warning bus duck the engine/wind bed cleanly.
static func alert_stream(kind: String) -> AudioStreamWAV:
	if _alert_streams.has(kind):
		return _alert_streams[kind] as AudioStreamWAV
	var rate := 22050
	var length := 0.45
	match kind:
		"ew_enter":
			length = 0.50
		"ew_exit":
			length = 0.36
		"lq_critical":
			length = 0.55
		"sam_lock":
			length = 0.40
		"kamikaze":
			length = 0.44
		"incoming":
			length = 0.16
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := 1.0
		var s := 0.0
		match kind:
			"ew_enter":
				if t < 0.16:
					env = sin(clampf(t / 0.16, 0.0, 1.0) * PI)
				elif t >= 0.26 and t < 0.46:
					env = sin(clampf((t - 0.26) / 0.20, 0.0, 1.0) * PI)
				else:
					env = 0.0
				s = (sin(TAU * 180.0 * t) + sin(TAU * 360.0 * t) * 0.45) * env * 0.5
			"ew_exit":
				env = sin(clampf(t / length, 0.0, 1.0) * PI)
				s = sin(TAU * (520.0 + 900.0 * (t / length)) * t) * env * 0.45
			"lq_critical":
				var gate := 1.0 if fmod(t, 0.18) < 0.10 else 0.0
				s = (sin(TAU * 1250.0 * t) * 0.5 + rng.randf_range(-0.35, 0.35)) * gate * 0.62
			"sam_lock":
				env = exp(-t * 9.0)
				s = sin(TAU * (1500.0 - 600.0 * t / length) * t) * env * 0.55
			"kamikaze":
				env = 1.0 if (t < 0.08 or (t >= 0.16 and t < 0.24) or (t >= 0.30 and t < 0.38)) else 0.0
				s = (sin(TAU * 920.0 * t) + sin(TAU * 1840.0 * t) * 0.3) * env * 0.45
			"incoming":
				lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.55)
				env = exp(-t * 24.0)
				s = (rng.randf_range(-1.0, 1.0) - lp) * env * 0.55
			_:
				env = sin(clampf(t / length, 0.0, 1.0) * PI)
				s = sin(TAU * 880.0 * t) * env * 0.4
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 30000.0))
	var stream := _make_stream(rate, data, false)
	_alert_streams[kind] = stream
	return stream


## Looping REB crackle: filtered static with occasional pops.  This is the
## audio counterpart to the analog video interference.
static func ew_crackle_stream() -> AudioStreamWAV:
	if _ew_crackle_stream != null:
		return _ew_crackle_stream
	var rate := 22050
	var count := int(rate * 1.4)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	var lp := 0.0
	for i in range(count):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.12)
		var pop := 0.0
		if rng.randf() < 0.004:
			pop = rng.randf_range(-0.8, 0.8)
		var s := (lp - rng.randf_range(-1.0, 1.0) * 0.35) * 0.55 + pop
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26000.0))
	_ew_crackle_stream = _make_stream(rate, data, true)
	return _ew_crackle_stream


static func play_alert_3d(parent: Node, world_position: Vector3, kind: String,
		volume_db: float = -8.0, unit_size: float = 22.0,
		max_distance: float = 650.0) -> void:
	_play_3d(parent, alert_stream(kind), world_position, volume_db,
			unit_size, max_distance, 1.0, "Warning", true)


static func drop_stream() -> AudioStreamWAV:
	if _drop_stream != null:
		return _drop_stream
	var rate := 22050
	var count := int(rate * 0.5)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env: float = exp(-t * 5.0)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.25)
		var tone: float = sin(TAU * (300.0 - 200.0 * t) * t) * 0.3
		var s: float = (lp * 1.6 + tone) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 24000.0))
	_drop_stream = _make_stream(rate, data, false)
	return _drop_stream


static func music_stream() -> AudioStreamWAV:
	if _music_stream != null:
		return _music_stream
	var rate := 22050
	var notes := [220.0, 277.0, 330.0, 277.0, 220.0, 330.0, 440.0, 330.0]
	var total := int(rate * 0.32 * notes.size())
	var data := PackedByteArray()
	data.resize(total * 2)
	for n in range(notes.size()):
		var start := int(rate * 0.32 * n)
		var span := int(rate * 0.32)
		for i in range(span):
			var t := float(i) / float(rate)
			var env: float = exp(-t * 6.0)
			var s := sin(TAU * notes[n] * t) * 0.35
			s += sin(TAU * notes[n] * 2.0 * t) * 0.12
			var idx := start + i
			if idx < total:
				data.encode_s16(idx * 2, int(clampf(s, -1.0, 1.0) * env * 22000.0))
	_music_stream = _make_stream(rate, data, true)
	return _music_stream


## Long-form combat ambience: low drone, slow minor pad and a heartbeat pulse.
## 24 s seamless loop, generated once and cached.
static func combat_music_stream() -> AudioStreamWAV:
	if _combat_music != null:
		return _combat_music
	var rate := 22050
	var length := 24.0
	var total := int(rate * length)
	var data := PackedByteArray()
	data.resize(total * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	var roots := [110.0, 98.0, 87.31, 98.0]
	for i in range(total):
		var t := float(i) / float(rate)
		var s := sin(TAU * 55.0 * t) * 0.10 + sin(TAU * 55.4 * t) * 0.08
		var chord: float = roots[int(t / 6.0) % roots.size()]
		s += sin(TAU * chord * t) * 0.05
		s += sin(TAU * chord * 1.5 * t) * 0.03
		s += sin(TAU * chord * 2.0 * t) * 0.02
		s += rng.randf_range(-1.0, 1.0) * 0.005
		var edge := minf(1.0, minf(t, length - t) / 1.5)
		data.encode_s16(i * 2, int(clampf(s * edge, -1.0, 1.0) * 22000.0))
	_combat_music = _make_stream(rate, data, true)
	return _combat_music


## Short boot-on-gravel footstep for AI infantry.
static func footstep_stream() -> AudioStreamWAV:
	if _footstep_stream != null:
		return _footstep_stream
	var rate := 22050
	var count := int(rate * 0.16)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := exp(-t * 34.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.35)
		var s := lp * 0.55 * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 18000.0))
	_footstep_stream = _make_stream(rate, data, false)
	return _footstep_stream


## Short shout + body-fall thud when an infantryman is killed.
static func soldier_death_stream() -> AudioStreamWAV:
	if _soldier_death_stream != null:
		return _soldier_death_stream
	var rate := 22050
	var length := 0.75
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := exp(-t * 4.2)
		var f := 175.0 - 55.0 * t
		var s := sin(TAU * f * t) * 0.32 + sin(TAU * f * 2.0 * t) * 0.10
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.20)
		s += lp * 0.30 * exp(-t * 10.0)
		if t > 0.34:
			var tt := t - 0.34
			s += sin(TAU * 52.0 * tt) * exp(-tt * 20.0) * 0.55
			s += rng.randf_range(-1.0, 1.0) * exp(-tt * 30.0) * 0.18
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 22000.0))
	_soldier_death_stream = _make_stream(rate, data, false)
	return _soldier_death_stream


## Carbon frame + ground impact for a crashing drone.
static func drone_impact_stream() -> AudioStreamWAV:
	if _drone_impact_stream != null:
		return _drone_impact_stream
	var rate := 22050
	var length := 0.9
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9911
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := exp(-t * 5.5)
		var s := sin(TAU * 62.0 * t) * exp(-t * 9.0) * 0.45
		s += sin(TAU * 34.0 * t) * exp(-t * 6.0) * 0.30
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.45)
		s += lp * exp(-t * 7.0) * 0.55
		# fractured blade / carbon snap
		if t < 0.08:
			s += rng.randf_range(-1.0, 1.0) * exp(-t * 60.0) * 0.9
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 24000.0))
	_drone_impact_stream = _make_stream(rate, data, false)
	return _drone_impact_stream


static func play_footstep(parent: Node, world_position: Vector3,
		volume_db: float = -16.0) -> void:
	_play_3d(parent, footstep_stream(), world_position, volume_db,
			0.8, 34.0, randf_range(0.92, 1.12))


static func play_soldier_death(parent: Node, world_position: Vector3,
		volume_db: float = -5.0) -> void:
	_play_3d(parent, soldier_death_stream(), world_position, volume_db,
			1.0, 55.0, randf_range(0.94, 1.06))


static func play_drone_impact(parent: Node, world_position: Vector3,
		volume_db: float = 0.0) -> void:
	_play_3d(parent, drone_impact_stream(), world_position, volume_db,
			1.3, 120.0, randf_range(0.9, 1.1), "Combat", true)


static func make_looping_player(stream: AudioStreamWAV, volume_db: float,
		unit_size: float, max_distance: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.bus = "Engine"
	return player


static func play_drop(parent: Node, world_position: Vector3, volume_db: float = -4.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(true):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = drop_stream()
	player.volume_db = volume_db
	player.bus = "Combat"
	player.unit_size = 10.0
	player.max_distance = 120.0
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	player.finished.connect(player.queue_free)


## FPV Drone Motor Sound Synthesis (BLDC motors, multi-rotor beating & prop wash)
## kind: 0 = 5-inch freestyle/racing, 1 = 7-8 inch heavy combat, 2 = USV naval,
##       3 = fixed-wing pusher, 4 = jet turbine, 5 = heavy hexa bomber,
##       6 = 7-inch long-range.
static func drone_motor_stream(kind: int = 0) -> AudioStreamWAV:
	match kind:
		1:
			if _motor_8in_stream != null:
				return _motor_8in_stream
			# 7-8" heavy drone: lower fundamental (142 Hz), 8 harmonics, throaty blade flutter
			_motor_8in_stream = _synth_quad_motor(22050, 1.0, 142.0, 8, 0.18, 568.0, 0.14, 28.0, 0.22)
			return _motor_8in_stream
		2:
			if _motor_usv_stream != null:
				return _motor_usv_stream
			# USV Naval Magura-X: marine diesel & waterjet turbine cavitation
			_motor_usv_stream = _synth_quad_motor(22050, 1.0, 58.0, 5, 0.25, 1200.0, 0.08, 12.0, 0.30)
			return _motor_usv_stream
		3:
			if _motor_pusher_stream != null:
				return _motor_pusher_stream
			# Fixed-wing pusher (Leleka/Furia): slower 2-blade prop, narrow buzz.
			_motor_pusher_stream = _synth_quad_motor(22050, 1.0, 96.0, 4, 0.10, 390.0, 0.07, 16.0, 0.10)
			return _motor_pusher_stream
		4:
			if _motor_jet_stream != null:
				return _motor_jet_stream
			# Chaklun jet: turbine whine + compressor wash, no prop beat.
			_motor_jet_stream = _synth_quad_motor(22050, 1.0, 430.0, 3, 0.34, 1680.0, 0.30, 7.0, 0.06)
			return _motor_jet_stream
		5:
			if _motor_hexa_stream != null:
				return _motor_hexa_stream
			# Baba Yaga 6-rotor heavy bomber: deep 22" blades.
			_motor_hexa_stream = _synth_quad_motor(22050, 1.0, 74.0, 10, 0.22, 260.0, 0.12, 9.0, 0.26)
			return _motor_hexa_stream
		6:
			if _motor_7in_stream != null:
				return _motor_7in_stream
			# 7" long-range / strike quad.
			_motor_7in_stream = _synth_quad_motor(22050, 1.0, 118.0, 6, 0.16, 520.0, 0.11, 22.0, 0.18)
			return _motor_7in_stream
		_:
			if _motor_5in_stream != null:
				return _motor_5in_stream
			# 5" Freestyle: screaming high-rev BLDC whine (245 Hz), sharp blade harmonics, prop wash
			_motor_5in_stream = _synth_quad_motor(22050, 1.0, 245.0, 7, 0.14, 980.0, 0.20, 48.0, 0.15)
			return _motor_5in_stream


static func _synth_quad_motor(rate: int, length: float, base_hz: float, harmonics: int,
		wash_mix: float, whistle_hz: float, whistle_mix: float,
		beat_hz: float, beat_mix: float) -> AudioStreamWAV:
	var count := int(rate * (length + 0.05))
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	# One coherent stack: detuned copies at 140/142/144/146 Hz beat at 2-6 Hz,
	# which is the audible "tuk-tuk-tuk" pulsing in flight.
	var detunes := [1.0]
	for i in range(count):
		var t := float(i) / float(rate)
		var s := 0.0
		# Harmonic stack of 4 motors using integer frequencies so there is no rhythmic beat
		for d in detunes:
			for h in range(1, harmonics + 1):
				var h_amp: float = 0.55 / float(h)
				var hz := roundf(base_hz * d * float(h))
				s += sin(TAU * hz * t) * h_amp * 0.6
		# Aerodynamic propeller wash (filtered noise)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)
		s += lp * wash_mix
		# Propeller blade tip whistle
		if whistle_hz > 0.0:
			s += sin(TAU * roundf(whistle_hz) * t) * whistle_mix
		values[i] = clampf(s * 0.75, -1.0, 1.0)
	return _finalise_loop(values, rate)


## Distant and near thunderclap for thunderstorms and storm operations.
static func thunder_stream() -> AudioStreamWAV:
	if _thunder_stream != null:
		return _thunder_stream
	var rate := 22050
	var length := 3.2
	var count := int(rate * length)
	var values := PackedFloat32Array()
	values.resize(count)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		# Leading lightning whip crack at t < 0.08
		var crack := 0.0
		if t < 0.08:
			crack = randf_range(-0.9, 0.9) * (1.0 - t / 0.08)
		# Low rolling rumble (35 - 75 Hz)
		var n := randf_range(-1.0, 1.0)
		lp1 = lerpf(lp1, n, 0.07)
		lp2 = lerpf(lp2, lp1, 0.04)
		var rumble: float = sin(TAU * 48.0 * t) * 0.5 + sin(TAU * 72.0 * t) * 0.35 + sin(TAU * 34.0 * t) * 0.4
		var env := exp(-t * 1.2) * (0.8 + 0.2 * sin(TAU * 2.5 * t))
		var s: float = (crack * 0.6 + lp2 * 2.8 + rumble * 0.4) * env
		values[i] = clampf(s * 0.95, -1.0, 1.0)

	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		data.encode_s16(i * 2, int(clampf(values[i], -1.0, 1.0) * 31000.0))
	_thunder_stream = _make_stream(rate, data, false)
	return _thunder_stream


static func play_thunder(parent: Node, world_position: Vector3, volume_db: float = 6.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	if not _can_spawn_3d_voice(true):
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = thunder_stream()
	player.volume_db = volume_db
	player.bus = "Combat"
	player.unit_size = 45.0
	player.max_distance = 1800.0
	_track_3d_voice(player)
	parent.add_child(player)
	player.global_position = world_position
	player.play()
	player.finished.connect(player.queue_free)


## Squelch + clipped formant chatter.  This is intentionally non-verbal: it
## reads as a military radio net without shipping voice assets, and it sits on
## top of the HUD callout ("STRIKE, STRIKE", "EXTRACT").
static func radio_stream() -> AudioStreamWAV:
	if _radio_stream != null:
		return _radio_stream
	var rate := 22050
	var length := 4.8
	var count := int(rate * length)
	var values := PackedFloat32Array()
	values.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44117
	var lp := 0.0
	var phase1 := 0.0
	var phase2 := 0.0
	var phase3 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := 0.0
		if t < 0.08:
			env = 1.0 - t / 0.08
		elif t > 0.16 and t < 4.60:
			# Natural radio cadence: ~2.1 Hz syllables (~0.48 s) with inter-word gaps.
			var local := t - 0.16
			var syllable := fmod(local, 0.48)
			var phrase_gate := 1.0 if fmod(local, 1.48) < 1.16 else 0.16
			env = sin(clampf(syllable / 0.48, 0.0, 1.0) * PI) * 0.8 * phrase_gate
			env *= 0.75 + 0.25 * sin(TAU * 2.1 * local)
		elif t >= 4.60:
			env = maxf(0.0, 1.0 - (t - 4.60) / 0.18)
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.22)
		phase1 += TAU * 320.0 / rate
		phase2 += TAU * 880.0 / rate
		phase3 += TAU * 1760.0 / rate
		var voice := sin(phase1) * 0.45 + sin(phase2) * 0.25 + sin(phase3) * 0.12
		var hiss := (lp - noise * 0.55) * 0.55
		values[i] = clampf((voice * 0.65 + hiss) * env, -1.0, 1.0)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		data.encode_s16(i * 2, int(clampf(values[i], -1.0, 1.0) * 30000.0))
	_radio_stream = _make_stream(rate, data, false)
	return _radio_stream


static func play_radio(parent: Node, _text: String = "", volume_db: float = -7.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = radio_stream()
	player.volume_db = volume_db
	player.bus = "Radio"
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


## Crisp 2D tactile hitmarker confirmation click for combat hits/kills.
static func hitmarker_stream() -> AudioStreamWAV:
	if _hitmarker_stream != null:
		return _hitmarker_stream
	var rate := 22050
	var length := 0.085
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182
	for i in range(count):
		var t := float(i) / float(rate)
		var p1 := exp(-t * 68.0) * (sin(TAU * 1720.0 * t) * 0.60 + sin(TAU * 2880.0 * t) * 0.35)
		var p2 := 0.0
		if t >= 0.026:
			var dt := t - 0.026
			p2 = exp(-dt * 58.0) * (sin(TAU * 2240.0 * dt) * 0.55 + rng.randf_range(-0.15, 0.15) * exp(-dt * 120.0))
		var s := clampf((p1 + p2) * 0.85, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 28000.0))
	_hitmarker_stream = _make_stream(rate, data, false)
	return _hitmarker_stream


static func play_hitmarker(parent: Node, is_kill: bool = false,
		volume_db: float = -4.5) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if parent == null or not parent.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = hitmarker_stream()
	player.pitch_scale = 1.22 if is_kill else 1.0
	player.volume_db = volume_db
	player.bus = &"Combat"
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


static func prewarm() -> void:
	boom_stream()
	shot_stream()
	rifle_stream()
	cannon_stream()
	hitmarker_stream()
	drop_stream()
	drone_impact_stream()
	soldier_death_stream()


static func clear_caches() -> void:
	_boom_stream = null
	_shot_stream = null
	_rifle_stream = null
	_radio_stream = null
	_hitmarker_stream = null
	_cannon_stream = null
	_autocannon_stream = null
	_track_stream = null
	_fire_stream = null
	_artillery_stream = null
	_servo_stream = null
	_engine_stream = null
	_wind_stream = null
	_beeper_stream = null
	_drop_stream = null
	_music_stream = null
	_combat_music = null
	_footstep_stream = null
	_soldier_death_stream = null
	_drone_impact_stream = null
	_fpv_stream = null
	_tank_stream = null
	_bmp_stream = null
	_apc_stream = null
	_truck_stream = null
	_heli_stream = null
	_shahed_stream = null
	_motor_5in_stream = null
	_motor_8in_stream = null
	_motor_usv_stream = null
	_motor_pusher_stream = null
	_motor_jet_stream = null
	_motor_hexa_stream = null
	_motor_7in_stream = null
	_thunder_stream = null
	_alert_streams.clear()
	_ew_crackle_stream = null
	_active_3d_voices = 0
