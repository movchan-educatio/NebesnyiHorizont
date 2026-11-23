extends Node

## Phase 4 audio QA. Pure synthesis checks, safe in --headless (no audio device
## is required). Quits 0 on pass, 1 on any failed assertion.

const TAG := "[QA_POLISH_AUDIO]"
const Catalog = preload("res://autoloads/DroneCatalog.gd")
const Sfx = preload("res://combat/sfx.gd")

var _fail := 0


func _ready() -> void:
	_run()
	print(TAG, " ", "PASS" if _fail == 0 else "FAIL",
			" (failures=", _fail, ")")
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
		print(TAG, " FAIL ", label)


## Sampled RMS of a 16-bit mono buffer, normalised to [-1, 1].
func _rms(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var frames := data.size() / 2
	if frames <= 0:
		return 0.0
	var stride := maxi(1, frames / 4096)
	var sum := 0.0
	var count := 0
	var i := 0
	while i < frames:
		var s := float(data.decode_s16(i * 2)) / 32768.0
		sum += s * s
		count += 1
		i += stride
	return sqrt(sum / float(maxi(count, 1)))


## Zero-crossing rate: a cheap, robust proxy for spectral brightness. Used to
## prove the 14 motor profiles are not just 14 copies of one waveform.
func _zcr(stream: AudioStreamWAV) -> float:
	var data: PackedByteArray = stream.data
	var frames := data.size() / 2
	if frames <= 1:
		return 0.0
	var stride := maxi(1, frames / 4096)
	var prev := 0.0
	var crossings := 0
	var count := 0
	var i := 0
	while i < frames:
		var s := float(data.decode_s16(i * 2)) / 32768.0
		if (s >= 0.0) != (prev >= 0.0):
			crossings += 1
		prev = s
		count += 1
		i += stride
	return float(crossings) / float(maxi(count, 1))


func _check_stream(name: String, stream: AudioStreamWAV, min_rms: float,
		want_loop: bool = false) -> void:
	if stream == null:
		_check(false, name + " is null")
		return
	_check(stream.format == AudioStreamWAV.FORMAT_16_BITS,
			name + " is 16-bit PCM")
	if want_loop:
		_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
				name + " is LOOP_FORWARD")
	var rms := _rms(stream)
	_check(rms > min_rms, name + " non-silent (rms=%.4f)" % rms)


func _run() -> void:
	# 1) Exactly one unique recorded-audio identity per preset.
	var kinds := {}
	for p in Catalog.PRESETS:
		kinds[int(p.get("audio_kind", -1))] = true
	_check(kinds.size() == Catalog.PRESETS.size(),
			"13 unique audio_kind IDs (got %d)" % kinds.size())

	# 2) Fourteen distinct, looped, non-silent motor signatures.
	var hashes := {}
	var spectra := {}
	for k in range(14):
		var stream := Sfx.drone_motor_stream(k)
		_check_stream("motor_%d" % k, stream, 0.02, true)
		if stream == null:
			continue
		hashes[hash(stream.data)] = true
		var z := snappedf(_zcr(stream), 0.0001)
		spectra[z] = true
		print(TAG, " motor_%d zcr=%.4f bytes=%d" % [
				k, z, stream.data.size()])
	_check(hashes.size() == 14,
			"14 unique motor waveforms (got %d)" % hashes.size())
	_check(spectra.size() >= 7,
			"measurable spectral separation across classes (got %d distinct)" % spectra.size())

	# 3) Propwash bed.
	var wash := Sfx.drone_propwash_stream()
	_check_stream("propwash", wash, 0.01, true)

	# 4) Infantry, projectile and vehicle detail streams.
	var detail: Array = [
		["footstep_0", Sfx.footstep_stream(0), false],
		["footstep_1", Sfx.footstep_stream(1), false],
		["footstep_2", Sfx.footstep_stream(2), false],
		["reload", Sfx.reload_stream(), false],
		["mg_burst", Sfx.mg_burst_stream(), false],
		["rifle_variant_0", Sfx.rifle_variant_stream(0), false],
		["rifle_variant_1", Sfx.rifle_variant_stream(1), false],
		["rifle_variant_2", Sfx.rifle_variant_stream(2), false],
		["bullet_whiz", Sfx.bullet_whiz_stream(), false],
		["infantry_hit", Sfx.infantry_hit_stream(), false],
		["callout_0", Sfx.infantry_callout_stream(0), false],
		["callout_1", Sfx.infantry_callout_stream(1), false],
		["callout_2", Sfx.infantry_callout_stream(2), false],
		["wheel_roll", Sfx.wheel_roll_stream(), true],
		["air_brake", Sfx.air_brake_stream(), false],
		["armor_hit_heavy", Sfx.armor_hit_stream(true), false],
		["armor_hit_light", Sfx.armor_hit_stream(false), false],
		["cookoff", Sfx.cookoff_stream(), false],
	]
	for entry in detail:
		_check_stream(String(entry[0]), entry[1] as AudioStreamWAV, 0.01,
				bool(entry[2]))
