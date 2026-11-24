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
static var _kamikaze_engines: Dictionary = {}
static var _kamikaze_warning_stream: AudioStreamWAV = null
static var _kamikaze_fall_stream: AudioStreamWAV = null


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
	# Three distinct weapon voices + a small pitch jitter stop a whole squad
	# from sounding like one sample repeated on a timer.
	player.stream = rifle_variant_stream(randi() % 3)
	player.pitch_scale = randf_range(0.93, 1.08)
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
#  Infantry detail: footsteps, reloads, suppressive bursts and squad barks.
#  Every stream is cached procedurally; the play helpers are headless-safe.
# ---------------------------------------------------------------------------
static var _footstep_variants := {}
static var _rifle_variants := {}
static var _callout_variants := {}
static var _reload_stream_cached: AudioStreamWAV = null
static var _mg_burst_stream_cached: AudioStreamWAV = null
static var _bullet_whiz_stream_cached: AudioStreamWAV = null
static var _infantry_hit_stream_cached: AudioStreamWAV = null


## 0 = gravel crunch, 1 = boot thump, 2 = dry grass / dirt scuff.
static func footstep_stream(variant: int = 0) -> AudioStreamWAV:
	var slot := clampi(variant, 0, 2)
	if _footstep_variants.has(slot):
		return _footstep_variants[slot] as AudioStreamWAV
	var rate := 22050
	var length := 0.22 if slot == 2 else 0.16
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4200 + slot * 977
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := exp(-t * (30.0 if slot == 1 else 20.0))
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.34 if slot == 0 else 0.14)
		lp2 = lerpf(lp2, lp, 0.28)
		var s := 0.0
		match slot:
			0:  # sharp gravel crunch with a few discrete stone clicks
				s = lp * 0.95 + lp2 * 0.40 \
						+ rng.randf_range(-0.45, 0.45) * exp(-t * 55.0)
			1:  # heavy boot on packed earth
				s = sin(TAU * 96.0 * t) * exp(-t * 32.0) * 0.95 + lp * 0.42
			2:  # dry grass / loose dirt scuff (softer, longer)
				s = (lp2 - lp) * 1.9 + lp * 0.85
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 28000.0))
	var stream := _make_stream(rate, data, false)
	_footstep_variants[slot] = stream
	return stream


## Metallic magazine slap followed by a two-click bolt rack (~0.35 s).
static func reload_stream() -> AudioStreamWAV:
	if _reload_stream_cached != null:
		return _reload_stream_cached
	var rate := 22050
	var count := int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33117
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var s := 0.0
		# Magazine snap.
		if t < 0.075:
			s += rng.randf_range(-1.0, 1.0) * exp(-t * 62.0) * 0.75
			s += sin(TAU * 630.0 * t) * exp(-t * 48.0) * 0.35
		# Bolt pulled back then driven home.
		if t >= 0.16 and t < 0.29:
			var dt := t - 0.16
			s += sin(TAU * (1500.0 - 850.0 * dt) * dt) * exp(-dt * 42.0) * 0.55
			s += rng.randf_range(-1.0, 1.0) * exp(-dt * 78.0) * 0.30
		if t >= 0.21 and t < 0.31:
			var dt2 := t - 0.21
			s += sin(TAU * 1980.0 * dt2) * exp(-dt2 * 55.0) * 0.38
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.20)
		s += lp * 0.10
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 27000.0))
	_reload_stream_cached = _make_stream(rate, data, false)
	return _reload_stream_cached


## Four rapid rounds with a short ringing tail (~0.42 s).
static func mg_burst_stream() -> AudioStreamWAV:
	if _mg_burst_stream_cached != null:
		return _mg_burst_stream_cached
	var rate := 22050
	var count := int(rate * 0.42)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51503
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var s := 0.0
		for k in range(4):
			var dt := t - 0.11 * float(k)
			if dt >= 0.0 and dt < 0.17:
				s += sin(TAU * (1180.0 - 460.0 * dt) * dt) * exp(-dt * 40.0) * 0.40
				s += rng.randf_range(-1.0, 1.0) * exp(-dt * 60.0) * 0.50
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.30)
		s += lp * 0.20 * exp(-t * 6.0)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 29000.0))
	_mg_burst_stream_cached = _make_stream(rate, data, false)
	return _mg_burst_stream_cached


## 0 = sharp AK-74 crack, 1 = punchy AKM, 2 = suppressed / distant thud.
static func rifle_variant_stream(variant: int = 0) -> AudioStreamWAV:
	var slot := clampi(variant, 0, 2)
	if _rifle_variants.has(slot):
		return _rifle_variants[slot] as AudioStreamWAV
	var rate := 22050
	var length := 0.30 if slot == 2 else 0.26
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100 + slot * 313
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var decay := 34.0 if slot == 2 else (38.0 if slot == 0 else 30.0)
		var env := exp(-t * decay)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.24 if slot == 2 else 0.55)
		lp2 = lerpf(lp2, lp, 0.12)
		var s := 0.0
		match slot:
			0:  # AK-74: bright, thin, sharp
				s = lp * 1.70 + n * 0.28 + sin(TAU * 165.0 * t) * exp(-t * 44.0) * 0.35
			1:  # AKM: heavier low-end punch
				s = lp * 1.25 + n * 0.20 + sin(TAU * 118.0 * t) * exp(-t * 30.0) * 0.85
			2:  # suppressed / far: dull thud, little high crack
				s = lp2 * 1.55 + sin(TAU * 74.0 * t) * exp(-t * 22.0) * 0.65
		if t > 0.11:
			s += lp2 * exp(-(t - 0.11) * 11.0) * 0.30
		data.encode_s16(i * 2, int(clampf(s * env, -1.0, 1.0) * 28500.0))
	var stream := _make_stream(rate, data, false)
	_rifle_variants[slot] = stream
	return stream


## Supersonic crack + descending zip as the round passes the listener (~0.16 s).
static func bullet_whiz_stream() -> AudioStreamWAV:
	if _bullet_whiz_stream_cached != null:
		return _bullet_whiz_stream_cached
	var rate := 22050
	var count := int(rate * 0.16)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61133
	var lp := 0.0
	var phase := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var frac := t / 0.16
		var hz := 900.0 - 6600.0 * frac
		phase += TAU * maxf(hz, 120.0) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.45)
		var s := sin(phase) * 0.50 * exp(-t * 16.0)
		s += (n - lp) * 0.55 * exp(-t * 34.0)
		s += sin(TAU * 2100.0 * t) * exp(-t * 70.0) * 0.30
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 29000.0))
	_bullet_whiz_stream_cached = _make_stream(rate, data, false)
	return _bullet_whiz_stream_cached


## Webbing / kevlar impact: muffled body thud plus a small metal click (~0.12 s).
static func infantry_hit_stream() -> AudioStreamWAV:
	if _infantry_hit_stream_cached != null:
		return _infantry_hit_stream_cached
	var rate := 22050
	var count := int(rate * 0.12)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77123
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.18)
		var s := sin(TAU * 132.0 * t) * exp(-t * 30.0) * 0.80
		s += lp * 0.65 * exp(-t * 38.0)
		if t < 0.025:
			s += n * exp(-t * 150.0) * 0.55
			s += sin(TAU * 720.0 * t) * exp(-t * 110.0) * 0.35
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 27500.0))
	_infantry_hit_stream_cached = _make_stream(rate, data, false)
	return _infantry_hit_stream_cached


## Three terse, non-verbal squad alerts: squelch + clipped formant barks.
static func infantry_callout_stream(variant: int = 0) -> AudioStreamWAV:
	var slot := clampi(variant, 0, 2)
	if _callout_variants.has(slot):
		return _callout_variants[slot] as AudioStreamWAV
	var rate := 22050
	var count := int(rate * 0.26)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99100 + slot * 719
	var lp := 0.0
	var roots := [410.0, 540.0, 330.0]
	var formant := float(roots[slot])
	for i in range(count):
		var t := float(i) / float(rate)
		var env := sin(clampf(t / 0.26, 0.0, 1.0) * PI)
		# Gate into two short barks inside the 0.26 s window.
		var gate := 0.12 if fmod(t, 0.13) > 0.085 else 1.0
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.22)
		var voice := sin(TAU * formant * t) * 0.55 \
				+ sin(TAU * formant * 2.4 * t) * 0.24 \
				+ sin(TAU * formant * 4.1 * t) * 0.11
		var s := (voice * 0.62 + (n - lp) * 0.40) * env * gate
		if t < 0.02:
			s += n * (1.0 - t / 0.02) * 0.45  # radio squelch onset
		if t > 0.22:
			s += n * ((t - 0.22) / 0.04) * 0.20  # release hiss
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 27000.0))
	var stream := _make_stream(rate, data, false)
	_callout_variants[slot] = stream
	return stream


static func play_reload(parent: Node, world_position: Vector3,
		volume_db: float = -14.0) -> void:
	_play_3d(parent, reload_stream(), world_position, volume_db,
			2.0, 60.0, randf_range(0.95, 1.05))


static func play_mg_burst(parent: Node, world_position: Vector3,
		volume_db: float = -7.0) -> void:
	_play_3d(parent, mg_burst_stream(), world_position, volume_db,
			9.0, 200.0, randf_range(0.93, 1.07))


static func play_bullet_whiz(parent: Node, world_position: Vector3,
		volume_db: float = -9.0) -> void:
	_play_3d(parent, bullet_whiz_stream(), world_position, volume_db,
			2.5, 55.0, randf_range(0.92, 1.10))


static func play_infantry_hit(parent: Node, world_position: Vector3,
		volume_db: float = -11.0) -> void:
	_play_3d(parent, infantry_hit_stream(), world_position, volume_db,
			1.6, 45.0, randf_range(0.94, 1.06))


## `variant < 0` picks a random voice; callers may request a specific one.
static func play_infantry_callout(parent: Node, world_position: Vector3,
		volume_db: float = -12.0, variant: int = -1) -> void:
	var slot := randi() % 3 if variant < 0 else clampi(variant, 0, 2)
	_play_3d(parent, infantry_callout_stream(slot), world_position, volume_db,
			4.0, 110.0, randf_range(0.94, 1.06))


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


# ---------------------------------------------------------------------------
#  Wheeled-vehicle detail: tire roll, air brakes, armor hits and cook-offs
# ---------------------------------------------------------------------------
static var _wheel_roll_cached: AudioStreamWAV = null
static var _air_brake_cached: AudioStreamWAV = null
static var _armor_hit_cache := {}
static var _cookoff_cached: AudioStreamWAV = null


## Seamless gravel/tire roll, pitched by vehicle speed in vehicle.gd.
static func wheel_roll_stream() -> AudioStreamWAV:
	if _wheel_roll_cached != null:
		return _wheel_roll_cached
	var rate := 22050
	var count := int(rate * 1.0)
	var values := PackedFloat32Array()
	values.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13801
	var lp := 0.0
	var lp2 := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.12)
		lp2 = lerpf(lp2, lp, 0.40)
		# Regular tread clumps over loose gravel plus a low rolling rumble.
		var tread := pow(maxf(0.0, sin(TAU * 17.0 * t)), 4.0)
		var s := lp2 * 1.45 + lp * 0.35 + sin(TAU * 48.0 * t) * 0.14
		s *= 0.82 + 0.18 * tread
		values[i] = clampf(s, -1.0, 1.0)
	_wheel_roll_cached = _finalise_loop(values, rate)
	return _wheel_roll_cached


## Pneumatic brake hiss with a short mechanical latch clank.
static func air_brake_stream() -> AudioStreamWAV:
	if _air_brake_cached != null:
		return _air_brake_cached
	var rate := 22050
	var count := int(rate * 0.34)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 24601
	var hp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		hp = lerpf(hp, n, 0.55)
		var hiss := (n - hp) * 0.70 * exp(-t * 6.0) * smoothstep(0.0, 0.025, t)
		var clank := 0.0
		if t >= 0.03 and t < 0.11:
			clank = sin(TAU * 480.0 * (t - 0.03)) * exp(-(t - 0.03) * 48.0) * 0.45
		data.encode_s16(i * 2, int(clampf(hiss + clank, -1.0, 1.0) * 27000.0))
	_air_brake_cached = _make_stream(rate, data, false)
	return _air_brake_cached


## Metallic armor clang + spark crunch. Heavy armor gets a deeper ring.
static func armor_hit_stream(heavy: bool = true) -> AudioStreamWAV:
	var slot := 1 if heavy else 0
	if _armor_hit_cache.has(slot):
		return _armor_hit_cache[slot] as AudioStreamWAV
	var rate := 22050
	var count := int(rate * 0.22)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 30601 + slot * 811
	var base := 390.0 if heavy else 720.0
	for i in range(count):
		var t := float(i) / float(rate)
		var env := exp(-t * (16.0 if heavy else 24.0))
		var ring := sin(TAU * base * t) * 0.55 \
				+ sin(TAU * base * 1.63 * t) * 0.30 \
				+ sin(TAU * base * 2.71 * t) * 0.15
		var crunch := rng.randf_range(-1.0, 1.0) * exp(-t * 70.0) * 0.65
		var s := (ring * env + crunch) * 0.9
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	var stream := _make_stream(rate, data, false)
	_armor_hit_cache[slot] = stream
	return stream


## Secondary ammo crackle after a vehicle is destroyed (~0.85 s).
static func cookoff_stream() -> AudioStreamWAV:
	if _cookoff_cached != null:
		return _cookoff_cached
	var rate := 22050
	var count := int(rate * 0.85)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41411
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, n, 0.16)
		var s := lp * 0.35 * exp(-t * 2.6)
		# Discrete rounds cooking off at irregular intervals.
		var phase := fmod(t, 0.115)
		if phase < 0.022 and rng.randf() < 0.22:
			s += n * exp(-phase * 95.0) * 0.85
			s += sin(TAU * 155.0 * phase) * exp(-phase * 70.0) * 0.40
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 26500.0))
	_cookoff_cached = _make_stream(rate, data, false)
	return _cookoff_cached


static func play_air_brake(parent: Node, world_position: Vector3,
		volume_db: float = -14.0) -> void:
	_play_3d(parent, air_brake_stream(), world_position, volume_db,
			8.0, 140.0, randf_range(0.95, 1.05))


static func play_armor_hit(parent: Node, world_position: Vector3,
		heavy: bool = true, volume_db: float = -10.0) -> void:
	_play_3d(parent, armor_hit_stream(heavy), world_position, volume_db,
			7.0, 160.0, randf_range(0.94, 1.06))


static func play_cookoff(parent: Node, world_position: Vector3,
		volume_db: float = -6.0) -> void:
	_play_3d(parent, cookoff_stream(), world_position, volume_db,
			12.0, 220.0, randf_range(0.92, 1.08))


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
static var _soldier_death_stream: AudioStreamWAV = null
static var _drone_impact_stream: AudioStreamWAV = null
static var _fpv_stream: AudioStreamWAV = null
static var _tank_stream: AudioStreamWAV = null
static var _bmp_stream: AudioStreamWAV = null
static var _apc_stream: AudioStreamWAV = null
static var _truck_stream: AudioStreamWAV = null
static var _heli_stream: AudioStreamWAV = null
static var _shahed_stream: AudioStreamWAV = null
static var _motor_streams := {}
static var _propwash_stream: AudioStreamWAV = null
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


## Large enemy FPV kamikaze drones: two distinct electric props + airframe hum.
## Cached per model id; identical to the other combat streams (no audio assets).
static func kamikaze_engine_stream(variant: int = 0) -> AudioStreamWAV:
	if _kamikaze_engines.has(variant):
		return _kamikaze_engines[variant] as AudioStreamWAV
	var base := 148.0 if variant == 0 else 116.0
	var whine := 940.0 if variant == 0 else 720.0
	var stream := _engine_loop(22050, 1.0, base, 8, 0.10, whine, 0.055, 22.0, 0.22)
	_kamikaze_engines[variant] = stream
	return stream


## Two short rising tones: proximity warning while the drone lines up a dive.
static func kamikaze_warning_stream() -> AudioStreamWAV:
	if _kamikaze_warning_stream != null:
		return _kamikaze_warning_stream
	var rate := 22050
	var count := int(rate * 0.55)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in range(count):
		var t := float(i) / float(rate)
		var hz := 620.0 if t < 0.22 else 930.0
		var env := sin(clampf(fmod(t, 0.22) / 0.22, 0.0, 1.0) * PI) * 0.45
		data.encode_s16(i * 2, int(clampf(sin(TAU * hz * t) * env, -1.0, 1.0) * 24000.0))
	_kamikaze_warning_stream = _make_stream(rate, data, false)
	return _kamikaze_warning_stream


## Falling/whistling airframe after a kill — descending pitch, no loop.
static func kamikaze_fall_stream() -> AudioStreamWAV:
	if _kamikaze_fall_stream != null:
		return _kamikaze_fall_stream
	var rate := 22050
	var count := int(rate * 1.2)
	var data := PackedByteArray()
	data.resize(count * 2)
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var k := float(i) / float(count)
		var hz := lerpf(1250.0, 180.0, k)
		lp = lerpf(lp, randf_range(-1.0, 1.0), 0.18)
		var env := (1.0 - k) * 0.42
		var s := (sin(TAU * hz * t) * 0.7 + lp * 0.3) * env
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 22000.0))
	_kamikaze_fall_stream = _make_stream(rate, data, false)
	return _kamikaze_fall_stream


static func play_kamikaze_warning(parent: Node, world_position: Vector3,
		volume_db: float = -6.0) -> void:
	_play_3d(parent, kamikaze_warning_stream(), world_position, volume_db,
			18.0, 260.0, 1.0, "Warning", true)


static func play_kamikaze_fall(parent: Node, world_position: Vector3,
		volume_db: float = -8.0) -> void:
	_play_3d(parent, kamikaze_fall_stream(), world_position, volume_db,
			20.0, 320.0, 1.0, "Combat")


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
			var p_mix := minf(pulse_mix, 0.24)
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
		volume_db: float = -18.0) -> void:
	_play_3d(parent, footstep_stream(randi() % 3), world_position, volume_db,
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


## FPV Drone / vessel motor sound synthesis.  Each kind has its own harmonic
## stack, blade-pass beat, whistle and aerodynamic wash.  Deterministic seeded
## noise keeps the cached sample identical between runs (QA waveform hashes).
##   0  5" combat quad       1  VTOL twin-prop      2  naval USV waterjet
##   3  Leleka pusher        4  Chaklun jet         5  Baba Yaga hexacopter
##   6  GRIM-7 long range    7  GRIM-7M high KV     8  Strila-8 tri-blade
##   9  10" military lifter  10 Furia wing pusher   11 3" micro whoop
##   12 5" juicy freestyle  13 7" cinematic cruiser
static func drone_motor_stream(kind: int = 0) -> AudioStreamWAV:
	if _motor_streams.has(kind):
		return _motor_streams[kind] as AudioStreamWAV
	var stream: AudioStreamWAV
	match kind:
		1:  # 134 Hz twin-prop thrum + 40 Hz flutter
			stream = _synth_quad_motor(22050, 1.0, 134.0, 7, 0.24, 536.0, 0.12,
					40.0, 0.26, [1.0, 1.0075], 0.22)
		2:  # 58 Hz marine diesel + cavitation wash + 1150 Hz waterjet whine
			stream = _synth_quad_motor(22050, 1.0, 58.0, 5, 0.30, 1150.0, 0.10,
					12.0, 0.30, [1.0, 1.02], 0.10)
		3:  # 94 Hz steady 2-blade pusher buzz + 18 Hz pulse, thin wash
			stream = _synth_quad_motor(22050, 1.0, 94.0, 4, 0.08, 376.0, 0.06,
					18.0, 0.12, [1.0, 1.003], 0.12)
		4:  # 460 Hz clean turbine + 1840 Hz compressor, no blade beat
			stream = _synth_quad_motor(22050, 1.0, 460.0, 3, 0.42, 1840.0, 0.30,
					0.0, 0.0, [1.0], 0.16)
		5:  # 64 Hz six-rotor throb, 10 harmonics, 13 Hz chop, sub wash
			stream = _synth_quad_motor(22050, 1.0, 64.0, 10, 0.28, 320.0, 0.12,
					13.0, 0.30, [1.0, 0.992, 1.008], 0.09)
		6:  # 118 Hz balanced endurance hum + 520 Hz whistle
			stream = _synth_quad_motor(22050, 1.0, 118.0, 6, 0.16, 520.0, 0.11,
					22.0, 0.18)
		7:  # 156 Hz punchy high-KV snarl + 690 Hz tip bite
			stream = _synth_quad_motor(22050, 1.0, 156.0, 6, 0.18, 690.0, 0.17,
					31.0, 0.22, [1.0, 1.02])
		8:  # 128 Hz crisp tri-blade chop (34 Hz, 0.28 mix)
			stream = _synth_quad_motor(22050, 1.0, 128.0, 5, 0.16, 512.0, 0.14,
					34.0, 0.28, [1.0, 1.01])
		9:  # 86 Hz lugging low-KV groan + 16 Hz loaded wash
			stream = _synth_quad_motor(22050, 1.0, 86.0, 8, 0.26, 344.0, 0.10,
					16.0, 0.30, [1.0, 0.99])
		10:  # 116 Hz higher-RPM pusher raspy buzz + 560 Hz airframe whistle
			stream = _synth_quad_motor(22050, 1.0, 116.0, 5, 0.12, 560.0, 0.16,
					20.0, 0.16, [1.0, 1.02])
		11:  # 340 Hz frantic micro scream + 1480 Hz duct whine + 62 Hz chatter
			stream = _synth_quad_motor(22050, 1.0, 340.0, 6, 0.12, 1480.0, 0.22,
					62.0, 0.24, [1.0, 1.025], 0.24)
		12:  # 215 Hz warm mid-rich chord + 32 Hz flip/throttle chop
			stream = _synth_quad_motor(22050, 1.0, 215.0, 7, 0.18, 860.0, 0.12,
					32.0, 0.30, [1.0, 1.005, 0.995], 0.20)
		13:  # 106 Hz silky purr, soft low-pass wash, minimal harsh whistle
			stream = _synth_quad_motor(22050, 1.0, 106.0, 5, 0.14, 424.0, 0.04,
					11.0, 0.10, [1.0, 1.004], 0.06)
		14:  # Wraith: low flying-wing throb + ducted-fan whistle
			stream = _synth_quad_motor(22050, 1.0, 96.0, 7, 0.20, 720.0, 0.15,
					19.0, 0.22, [1.0, 0.996], 0.12)
		15:  # Komar: high-pitched micro whoop + duct chatter
			stream = _synth_quad_motor(22050, 1.0, 355.0, 6, 0.11, 1520.0, 0.20,
					58.0, 0.22, [1.0, 1.03], 0.20)
		16:  # Shmel: aggressive 5" tri-blade snarl
			stream = _synth_quad_motor(22050, 1.0, 168.0, 7, 0.19, 810.0, 0.17,
					36.0, 0.28, [1.0, 1.012], 0.16)
		_:  # 245 Hz sharp BLDC scream + 980 Hz whistle + 48 Hz beat
			stream = _synth_quad_motor(22050, 1.0, 245.0, 7, 0.14, 980.0, 0.20,
					48.0, 0.15)
	_motor_streams[kind] = stream
	return stream


## Shared loop synthesiser. `detunes` creates the small whole-Hz offsets that
## make multiple motors beat against each other; `beat_hz` adds the real blade
## chop amplitude envelope; `lp_cutoff` sets the aerodynamic wash brightness.
static func _synth_quad_motor(rate: int, length: float, base_hz: float, harmonics: int,
		wash_mix: float, whistle_hz: float, whistle_mix: float,
		beat_hz: float, beat_mix: float,
		detunes: Array = [1.0, 1.015], lp_cutoff: float = 0.18) -> AudioStreamWAV:
	var count := int(rate * (length + 0.05))
	var values := PackedFloat32Array()
	values.resize(count)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(base_hz * 10.0) + int(whistle_hz) * 7 + harmonics * 131
	var factors: Array[float] = []
	for d in detunes:
		factors.append(float(d))
	if factors.is_empty():
		factors.append(1.0)
	var beat_rate := roundf(beat_hz)
	for i in range(count):
		var t := float(i) / float(rate)
		var s := 0.0
		# Detuned harmonic stacks: rounded to whole Hz so the loop stays seamless.
		for d in factors:
			var share := 1.0 / float(factors.size())
			for h in range(1, harmonics + 1):
				var h_amp: float = 0.55 / float(h)
				var hz := roundf(base_hz * d * float(h))
				s += sin(TAU * hz * t) * h_amp * 0.6 * share
		# Aerodynamic propeller wash (deterministic filtered noise).
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), clampf(lp_cutoff, 0.01, 1.0))
		s += lp * wash_mix
		# Blade-tip whistle plus distinct blade-pass harmonics.
		if whistle_hz > 0.0:
			var w := roundf(whistle_hz)
			s += sin(TAU * w * t) * whistle_mix
			s += sin(TAU * roundf(w * 2.0) * t) * whistle_mix * 0.35
			s += sin(TAU * maxf(roundf(w * 0.5), 1.0) * t) * whistle_mix * 0.18
		# Real blade-chop amplitude modulation.
		if beat_hz > 0.0 and beat_mix > 0.0:
			var beat_env := 1.0 - beat_mix * 0.5 \
					+ beat_mix * 0.5 * sin(TAU * beat_rate * t)
			s *= beat_env
		values[i] = clampf(s * 0.75, -1.0, 1.0)
	return _finalise_loop(values, rate)


## 1.2 s seamless dual-stage aerodynamic wash with turbulent prop flutter.
static func drone_propwash_stream() -> AudioStreamWAV:
	if _propwash_stream != null:
		return _propwash_stream
	var rate := 22050
	var count := int(rate * 1.2)
	var values := PackedFloat32Array()
	values.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 51500
	var low := 0.0
	var mid := 0.0
	var high := 0.0
	for i in range(count):
		var t := float(i) / float(rate)
		var n := rng.randf_range(-1.0, 1.0)
		# Two-stage band-pass plus a turbulent high band.
		low = lerpf(low, n, 0.04)
		mid = lerpf(mid, n, 0.18) - low
		high = lerpf(high, n, 0.55) - mid
		var flutter := 0.72 + 0.28 * sin(TAU * 23.0 * t)
		values[i] = clampf((low * 1.6 + mid * 1.25 + high * 0.55) * flutter, -1.0, 1.0)
	_propwash_stream = _finalise_loop(values, rate)
	return _propwash_stream


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
	_footstep_variants.clear()
	_rifle_variants.clear()
	_callout_variants.clear()
	_reload_stream_cached = null
	_mg_burst_stream_cached = null
	_bullet_whiz_stream_cached = null
	_infantry_hit_stream_cached = null
	_wheel_roll_cached = null
	_air_brake_cached = null
	_armor_hit_cache.clear()
	_cookoff_cached = null
	_soldier_death_stream = null
	_drone_impact_stream = null
	_fpv_stream = null
	_tank_stream = null
	_bmp_stream = null
	_apc_stream = null
	_truck_stream = null
	_heli_stream = null
	_shahed_stream = null
	_motor_streams.clear()
	_propwash_stream = null
	_thunder_stream = null
	_alert_streams.clear()
	_ew_crackle_stream = null
	_active_3d_voices = 0
