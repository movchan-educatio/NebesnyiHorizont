extends Node

## Global UI audio: a looping menu theme and a short click for every button.
## The mission levels keep their own engine/wind/combat audio; this player only
## runs in the menus and fades out when a mission starts.

var audio_settings_path := "%s/Audio.cfg" % Global.config_dir

var audio_settings := {"master_volume": 1.0, "music_volume": 0.55, "sfx_volume": 0.8}

const MENU_THEME := "res://Assets/Audio/menu_theme_loop.wav"
const MENU_CLICK := "res://Assets/Audio/menu_click.wav"

const RADIO_DIR := "res://Assets/Audio/radio/"
const RADIO_LINE_FILES := {
	"01": "radio_01_bort_target_spotted.wav",
	"1": "radio_01_bort_target_spotted.wav",
	"target_spotted": "radio_01_bort_target_spotted.wav",
	"bort_target_spotted": "radio_01_bort_target_spotted.wav",
	"radio_01_bort_target_spotted": "radio_01_bort_target_spotted.wav",
	"02": "radio_02_hq_cleared_hot.wav",
	"2": "radio_02_hq_cleared_hot.wav",
	"cleared_hot": "radio_02_hq_cleared_hot.wav",
	"hq_cleared_hot": "radio_02_hq_cleared_hot.wav",
	"radio_02_hq_cleared_hot": "radio_02_hq_cleared_hot.wav",
	"03": "radio_03_bort_direct_hit.wav",
	"3": "radio_03_bort_direct_hit.wav",
	"direct_hit": "radio_03_bort_direct_hit.wav",
	"bort_direct_hit": "radio_03_bort_direct_hit.wav",
	"radio_03_bort_direct_hit": "radio_03_bort_direct_hit.wav",
	"04": "radio_04_hq_rtb.wav",
	"4": "radio_04_hq_rtb.wav",
	"rtb": "radio_04_hq_rtb.wav",
	"hq_rtb": "radio_04_hq_rtb.wav",
	"radio_04_hq_rtb": "radio_04_hq_rtb.wav",
}
const RADIO_LINE_FILES_EN := {
	"01": "radio_01_en_bort_target_spotted.wav",
	"1": "radio_01_en_bort_target_spotted.wav",
	"target_spotted": "radio_01_en_bort_target_spotted.wav",
	"bort_target_spotted": "radio_01_en_bort_target_spotted.wav",
	"radio_01_bort_target_spotted": "radio_01_en_bort_target_spotted.wav",
	"radio_01_en_bort_target_spotted": "radio_01_en_bort_target_spotted.wav",
	"02": "radio_02_en_hq_cleared_hot.wav",
	"2": "radio_02_en_hq_cleared_hot.wav",
	"cleared_hot": "radio_02_en_hq_cleared_hot.wav",
	"hq_cleared_hot": "radio_02_en_hq_cleared_hot.wav",
	"radio_02_hq_cleared_hot": "radio_02_en_hq_cleared_hot.wav",
	"radio_02_en_hq_cleared_hot": "radio_02_en_hq_cleared_hot.wav",
	"03": "radio_03_en_bort_direct_hit.wav",
	"3": "radio_03_en_bort_direct_hit.wav",
	"direct_hit": "radio_03_en_bort_direct_hit.wav",
	"bort_direct_hit": "radio_03_en_bort_direct_hit.wav",
	"radio_03_bort_direct_hit": "radio_03_en_bort_direct_hit.wav",
	"radio_03_en_bort_direct_hit": "radio_03_en_bort_direct_hit.wav",
	"04": "radio_04_en_hq_rtb.wav",
	"4": "radio_04_en_hq_rtb.wav",
	"rtb": "radio_04_en_hq_rtb.wav",
	"hq_rtb": "radio_04_en_hq_rtb.wav",
	"radio_04_hq_rtb": "radio_04_en_hq_rtb.wav",
	"radio_04_en_hq_rtb": "radio_04_en_hq_rtb.wav",
}

## Five cockpit/combat sub-buses under Master exposed to Settings sliders.
const SUB_BUSES := ["Engine", "Wind", "Combat", "Radio", "Warning"]

## Dedicated buses let the mission mix the cockpit by priority instead of
## letting wind, engines and gunfire all fight over Master.
const AUDIO_BUSES := ["Music", "Engine", "Wind", "Combat", "Radio", "Warning"]

var _music: AudioStreamPlayer = null
var _click: AudioStreamPlayer = null
var _radio_player: AudioStreamPlayer = null
var _shockwave_player: AudioStreamPlayer = null
var _static_player: AudioStreamPlayer = null
var _confirm_player: AudioStreamPlayer = null
var _radio_cache: Dictionary = {}
var _shockwave_stream: AudioStreamWAV = null
var _static_cache: Dictionary = {}
var _confirm_stream: AudioStreamWAV = null
var _subbus_volumes: Dictionary = {
	"Engine": 1.0,
	"Wind": 1.0,
	"Combat": 1.0,
	"Radio": 1.0,
	"Warning": 1.0,
}
var _music_tween: Tween = null
var _application_suspended := false
var _resume_bus_mutes: Array[bool] = []


func _ready() -> void:
	_ensure_audio_buses()
	_music = AudioStreamPlayer.new()
	_music.name = "MenuMusic"
	_music.bus = "Music"
	add_child(_music)
	_click = AudioStreamPlayer.new()
	_click.name = "MenuClick"
	_click.bus = "Master"
	add_child(_click)
	if ResourceLoader.exists(MENU_THEME):
		_music.stream = load(MENU_THEME)
	if ResourceLoader.exists(MENU_CLICK):
		_click.stream = load(MENU_CLICK)
	_configure_music_loop()
	if _music.stream == null:
		push_warning("[Audio] menu theme not found: %s" % MENU_THEME)
	if _click.stream == null:
		push_warning("[Audio] menu click not found: %s" % MENU_CLICK)
	# Every Button in every menu gets the click, including buttons created at
	# runtime by the procedural menu builders.
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "Button", true, false):
		_hook_button(node as Button)
	# Every combat unit now plays its own one-shots (footsteps, rifles, engines).
	# A soft limiter keeps the Master bus from clipping when dozens overlap.
	if AudioServer.get_bus_effect_count(0) == 0:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.threshold_db = -5.0
		limiter.soft_clip_db = 2.0
		AudioServer.add_bus_effect(0, limiter)
	update_master_volume()
	# Always process across pause/results transitions so radio & kill-cam static
	# play reliably on all platforms (including iOS interruptions).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _notification(what: int) -> void:
	if not (OS.has_feature("ios") or OS.get_name() == "iOS" \
			or OS.has_feature("mobile") or OS.has_environment("MOBILE_UI")):
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# iOS may send focus-out and pause for the same interruption. Preserve
		# the original user mute state rather than recording an OS mute twice.
		if not _application_suspended:
			_application_suspended = true
			_resume_bus_mutes.clear()
			for i in range(AudioServer.bus_count):
				_resume_bus_mutes.append(AudioServer.is_bus_mute(i))
	elif _application_suspended and (what == NOTIFICATION_APPLICATION_RESUMED \
			or what == NOTIFICATION_APPLICATION_FOCUS_IN):
		_application_suspended = false
		call_deferred("_restore_after_audio_interruption")


func _restore_after_audio_interruption() -> void:
	if not is_inside_tree():
		return
	# Do not leave a stale OS-interruption mute behind.  Reapply the user's
	# master/music/SFX levels; the active level then recomputes its ducking mix.
	for i in range(mini(AudioServer.bus_count, _resume_bus_mutes.size())):
		AudioServer.set_bus_mute(i, _resume_bus_mutes[i])
	_resume_bus_mutes.clear()
	update_master_volume()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("_on_audio_resumed"):
		scene.call_deferred("_on_audio_resumed")
	elif scene != null and String(scene.scene_file_path).contains("mobile/MobileMenu"):
		play_menu_music()


func _on_node_added(node: Node) -> void:
	if node is Button:
		_hook_button(node as Button)


## Create the cockpit buses once.  They are simple children of Master and can
## be ducked independently by the mission's priority mixer.
func _ensure_audio_buses() -> void:
	for bus_name in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
		AudioServer.set_bus_volume_db(index, 0.0)


func set_subbus_volume_linear(bus_name: String, linear: float, persist: bool = true) -> void:
	_ensure_audio_buses()
	var clamped := clampf(linear, 0.0, 1.5)
	_subbus_volumes[bus_name] = clamped
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		var muted := clamped <= 0.001
		AudioServer.set_bus_mute(idx, muted)
		AudioServer.set_bus_volume_db(idx, -80.0 if muted else linear_to_db(clamped))
	if persist:
		save_audio_settings()


func is_radio_playing() -> bool:
	return _radio_player != null and is_instance_valid(_radio_player) and _radio_player.playing


func get_subbus_volume_linear(bus_name: String) -> float:
	_ensure_audio_buses()
	if _subbus_volumes.has(bus_name):
		return float(_subbus_volumes[bus_name])
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


func play_radio_line(line_key: String) -> float:
	_ensure_audio_buses()
	var stream := _get_radio_stream(line_key)
	if stream == null:
		stream = _build_ptt_fallback_stream()
	var dur := stream.get_length()
	if _radio_player == null or not is_instance_valid(_radio_player):
		_radio_player = AudioStreamPlayer.new()
		_radio_player.name = "RadioCommsPlayer"
		_radio_player.bus = &"Radio"
		_radio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_radio_player)
	_radio_player.stop()
	_radio_player.bus = &"Radio"
	_radio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_radio_player.pitch_scale = 1.0
	_radio_player.stream = stream
	_radio_player.volume_db = 0.0
	_radio_player.play()
	return dur


func stop_radio() -> void:
	if _radio_player != null and is_instance_valid(_radio_player):
		_radio_player.stop()
		_radio_player.stream = null
		_radio_player.pitch_scale = 1.0
	if _static_player != null and is_instance_valid(_static_player):
		_static_player.stop()


func play_signal_loss_static(dur_s: float = 0.16, vol_db: float = -5.0) -> void:
	_ensure_audio_buses()
	var clamped_dur := clampf(dur_s, 0.06, 0.6)
	var key := int(round(clamped_dur * 1000.0))
	var stream: AudioStreamWAV = _static_cache.get(key, null) as AudioStreamWAV
	if stream == null:
		stream = _build_signal_loss_static_stream(clamped_dur)
		_static_cache[key] = stream
	if _static_player == null or not is_instance_valid(_static_player):
		_static_player = AudioStreamPlayer.new()
		_static_player.name = "SignalLossStaticPlayer"
		_static_player.bus = &"Radio"
		_static_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_static_player)
	_static_player.stop()
	_static_player.bus = &"Radio"
	_static_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_static_player.pitch_scale = 1.0
	_static_player.stream = stream
	_static_player.volume_db = vol_db
	_static_player.play()


func play_radio_confirm_beep(vol_db: float = -7.5) -> void:
	_ensure_audio_buses()
	if _confirm_stream == null:
		_confirm_stream = _build_radio_confirm_stream()
	if _confirm_player == null or not is_instance_valid(_confirm_player):
		_confirm_player = AudioStreamPlayer.new()
		_confirm_player.name = "RadioConfirmBeepPlayer"
		_confirm_player.bus = &"Radio"
		_confirm_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_confirm_player)
	_confirm_player.stop()
	_confirm_player.bus = &"Radio"
	_confirm_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_player.pitch_scale = 1.0
	_confirm_player.stream = _confirm_stream
	_confirm_player.volume_db = vol_db
	_confirm_player.play()


func play_recon_shockwave(volume_db: float = -4.0) -> void:
	_ensure_audio_buses()
	if _shockwave_stream == null:
		_shockwave_stream = _build_shockwave_stream()
	if _shockwave_player == null or not is_instance_valid(_shockwave_player):
		_shockwave_player = AudioStreamPlayer.new()
		_shockwave_player.name = "ReconShockwavePlayer"
		_shockwave_player.bus = &"Combat"
		_shockwave_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_shockwave_player)
	_shockwave_player.stop()
	_shockwave_player.stream = _shockwave_stream
	_shockwave_player.volume_db = volume_db
	_shockwave_player.play()


func _get_radio_stream(line_key: String) -> AudioStream:
	var key := line_key.strip_edges().to_lower()
	if key.ends_with(".wav"):
		key = key.substr(0, key.length() - 4)
	var is_en := MenuUI.is_english()
	var table: Dictionary = RADIO_LINE_FILES_EN if is_en else RADIO_LINE_FILES
	var fname := String(table.get(key, RADIO_LINE_FILES.get(key, "")))
	if fname.is_empty():
		return null
	if _radio_cache.has(fname):
		return _radio_cache[fname] as AudioStream
	var res_path := RADIO_DIR + fname
	var stream: AudioStream = null
	if FileAccess.file_exists(res_path):
		stream = _load_pcm16_wav(res_path)
	if stream == null and ResourceLoader.exists(res_path):
		var res := ResourceLoader.load(res_path)
		if res is AudioStream:
			stream = res as AudioStream
	if stream != null:
		_radio_cache[fname] = stream
	return stream


func _load_pcm16_wav(res_path: String) -> AudioStreamWAV:
	var raw := FileAccess.get_file_as_bytes(res_path)
	if raw.size() < 44:
		return null
	if raw.slice(0, 4).get_string_from_ascii() != "RIFF" or raw.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var offset := 12
	var audio_format := 1
	var channels := 1
	var sample_rate := 22050
	var bits_per_sample := 16
	var has_fmt := false
	var pcm_data := PackedByteArray()
	while offset + 8 <= raw.size():
		var chunk_id := raw.slice(offset, offset + 4).get_string_from_ascii()
		var chunk_size := int(raw.decode_u32(offset + 4))
		var chunk_start := offset + 8
		var chunk_end := mini(chunk_start + chunk_size, raw.size())
		if chunk_id == "fmt " and chunk_size >= 16 and chunk_end <= raw.size():
			audio_format = int(raw.decode_u16(chunk_start))
			channels = maxi(int(raw.decode_u16(chunk_start + 2)), 1)
			sample_rate = maxi(int(raw.decode_u32(chunk_start + 4)), 8000)
			bits_per_sample = int(raw.decode_u16(chunk_start + 14))
			has_fmt = true
		elif chunk_id == "data" and chunk_end > chunk_start:
			pcm_data = raw.slice(chunk_start, chunk_end)
		offset = chunk_start + chunk_size + (chunk_size & 1)
	if not has_fmt or pcm_data.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.mix_rate = sample_rate
	wav.stereo = channels >= 2
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	if audio_format == 1 and bits_per_sample == 16:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.data = pcm_data
		return wav
	if audio_format == 1 and bits_per_sample == 8:
		wav.format = AudioStreamWAV.FORMAT_8_BITS
		wav.data = pcm_data
		return wav
	if audio_format == 1 and bits_per_sample == 24:
		var samples_24 := pcm_data.size() / 3
		var out_16 := PackedByteArray()
		out_16.resize(samples_24 * 2)
		for i in range(samples_24):
			var b1 := int(pcm_data[i * 3 + 1])
			var b2 := int(pcm_data[i * 3 + 2])
			var val := (b2 << 8) | b1
			if val >= 32768:
				val -= 65536
			out_16.encode_s16(i * 2, val)
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.data = out_16
		return wav
	if (audio_format == 3 or audio_format == 1) and bits_per_sample == 32:
		var samples_32 := pcm_data.size() / 4
		var out_32 := PackedByteArray()
		out_32.resize(samples_32 * 2)
		for i in range(samples_32):
			var s_val := 0
			if audio_format == 3:
				s_val = clampi(int(round(pcm_data.decode_float(i * 4) * 32767.0)), -32768, 32767)
			else:
				s_val = clampi(pcm_data.decode_s32(i * 4) >> 16, -32768, 32767)
			out_32.encode_s16(i * 2, s_val)
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.data = out_32
		return wav
	return null


func _build_ptt_fallback_stream() -> AudioStreamWAV:
	var sr := 22050
	var dur := 4.5
	var count := int(dur * float(sr))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90125
	var lp := 0.0
	for i in range(count):
		var t := float(i) / float(sr)
		var sig := rng.randf_range(-0.028, 0.028)
		if t < 0.045:
			sig += sin(TAU * 1180.0 * t) * 0.34
		elif t >= 0.14 and t <= dur - 0.18:
			var local := t - 0.14
			var slot := fmod(local, 0.48)
			# Spoken-word phrase bursts (~2.1 Hz) with short inter-word pauses.
			var phrase_gate := 1.0 if fmod(local, 1.44) < 1.18 else 0.15
			var env := sin(clampf(slot / 0.48, 0.0, 1.0) * PI) * 0.22 * phrase_gate
			var n := rng.randf_range(-1.0, 1.0)
			lp = lerpf(lp, n, 0.18)
			var carrier := sin(TAU * 260.0 * local) * 0.42 + sin(TAU * 740.0 * local) * 0.24
			sig += (carrier * 0.55 + (lp - n * 0.4) * 0.45) * env
		elif t > dur - 0.14:
			sig += sin(TAU * 760.0 * t) * 0.28 * exp(-(t - (dur - 0.14)) * 18.0)
		var s := clampi(int(round(sig * 32767.0)), -32768, 32767)
		pcm.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav


func _build_signal_loss_static_stream(dur_s: float) -> AudioStreamWAV:
	var sr := 22050
	var count := maxi(int(round(dur_s * float(sr))), 64)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 65150
	var prev := 0.0
	for i in range(count):
		var u := float(i) / float(maxi(count - 1, 1))
		var fade_in := clampf(u * 16.0, 0.0, 1.0)
		var fade_out := clampf((1.0 - u) * 14.0, 0.0, 1.0)
		var env := fade_in * fade_out
		var white := rng.randf_range(-1.0, 1.0)
		var crisp := white - prev * 0.35
		prev = white
		var hum := sin(TAU * 150.0 * (float(i) / float(sr))) * 0.08
		var sig := clampf((crisp * 0.58 + hum) * env, -1.0, 1.0)
		pcm.encode_s16(i * 2, clampi(int(round(sig * 32767.0)), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav


func _build_radio_confirm_stream() -> AudioStreamWAV:
	var sr := 22050
	var dur := 0.24
	var count := int(dur * float(sr))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in range(count):
		var t := float(i) / float(sr)
		var sig := rng.randf_range(-0.02, 0.02)
		if t < 0.075:
			var env1 := sin(clampf(t / 0.075, 0.0, 1.0) * PI)
			sig += sin(TAU * 980.0 * t) * 0.28 * env1
		elif t >= 0.095 and t < 0.195:
			var lt := t - 0.095
			var env2 := sin(clampf(lt / 0.10, 0.0, 1.0) * PI)
			sig += sin(TAU * 1320.0 * t) * 0.30 * env2
		pcm.encode_s16(i * 2, clampi(int(round(sig * 32767.0)), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = pcm
	return wav


func _build_shockwave_stream() -> AudioStreamWAV:
	var sr := 22050
	var dur := 1.35
	var count := int(dur * float(sr))
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 34301
	var phase := 0.0
	var lp_noise := 0.0
	for i in range(count):
		var t := float(i) / float(sr)
		var freq := 24.0 + 91.0 * exp(-t * 9.5)
		phase += TAU * freq / float(sr)
		var boom := sin(phase) * 0.72 * exp(-t * 3.1)
		var cutoff := 180.0 + 1420.0 * exp(-t * 3.8)
		var alpha := clampf((TAU * cutoff / float(sr)) / (1.0 + TAU * cutoff / float(sr)), 0.01, 0.9)
		lp_noise = lerpf(lp_noise, rng.randf_range(-1.0, 1.0), alpha)
		var attack := clampf(t / 0.018, 0.0, 1.0)
		var rumble := lp_noise * 0.55 * exp(-t * 2.2)
		var sample := tanh((boom + rumble) * attack * 1.25) * 0.88
		pcm.encode_s16(i * 2, clampi(int(round(sample * 32767.0)), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = pcm
	return wav


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	for p in [_music, _click, _radio_player, _shockwave_player, _static_player, _confirm_player]:
		if p != null and is_instance_valid(p):
			p.stop()
			p.stream = null
			if p.get_parent() == self:
				remove_child(p)
			p.free()
	_music = null
	_click = null
	_radio_player = null
	_shockwave_player = null
	_static_player = null
	_confirm_player = null
	_radio_cache.clear()
	_shockwave_stream = null
	_static_cache.clear()
	_confirm_stream = null
	var sfx = load("res://combat/sfx.gd")
	if sfx != null and sfx.has_method("clear_caches"):
		sfx.call("clear_caches")


## Restore the cockpit mix before a new level or the menu theme after a sortie.
func reset_mission_buses() -> void:
	stop_radio()
	for bus_name in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			if _subbus_volumes.has(bus_name):
				var lin := clampf(float(_subbus_volumes[bus_name]), 0.0, 1.5)
				var muted := lin <= 0.001
				AudioServer.set_bus_mute(index, muted)
				AudioServer.set_bus_volume_db(index, -80.0 if muted else linear_to_db(lin))
			else:
				AudioServer.set_bus_mute(index, false)
				AudioServer.set_bus_volume_db(index, 0.0)


## The imported menu theme has loop_mode disabled.  Force a forward loop over
## the whole file so the menu never falls silent after one pass.
func _configure_music_loop() -> void:
	if _music == null or _music.stream == null:
		return
	var stream := _music.stream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))


func set_music_volume(value: float) -> void:
	audio_settings["music_volume"] = clampf(value, 0.0, 1.0)
	if _music != null:
		_music.volume_db = linear_to_db(maxf(0.001, float(audio_settings["music_volume"])))
	save_audio_settings()


func set_sfx_volume(value: float) -> void:
	audio_settings["sfx_volume"] = clampf(value, 0.0, 1.0)
	save_audio_settings()


func _hook_button(button: Button) -> void:
	if button == null:
		return
	if not button.pressed.is_connected(play_click):
		button.pressed.connect(play_click)


func play_menu_music() -> void:
	if _music == null or _music.stream == null:
		return
	reset_mission_buses()
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music.volume_db = linear_to_db(maxf(0.001, float(audio_settings["music_volume"])))
	if not _music.playing:
		_music.play()


func stop_menu_music(fade: float = 0.0) -> void:
	if _music == null:
		return
	if fade <= 0.0:
		_music.stop()
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", -60.0, fade)
	_music_tween.tween_callback(_music.stop)


func play_click() -> void:
	if _click == null or _click.stream == null:
		return
	_click.volume_db = linear_to_db(maxf(0.001, float(audio_settings["sfx_volume"]) * 0.5))
	_click.play()


func load_audio_settings() -> String:
	var config := ConfigFile.new()
	var text := ""
	var err := config.load(audio_settings_path)
	if err == OK:
		for key in audio_settings.keys():
			if config.has_section_key("audio", key):
				audio_settings[key] = config.get_value("audio", key)
		for bus_name in SUB_BUSES:
			set_subbus_volume_linear(bus_name, float(config.get_value("subbuses", bus_name, 1.0)), false)
		update_master_volume()
		if _music != null and _music.playing:
			_music.volume_db = linear_to_db(maxf(0.001, float(audio_settings["music_volume"])))
	elif err == ERR_PARSE_ERROR:
		Global.log_error(err, "Parse error while loading audio configuration file.")
		text = "Failed to read audio configuration file."
		text = "%s\nThe default settings will be loaded." % text
	elif err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Could not open audio config file.")
		text = "Could not open audio configuration file."
		text = "%s\nThe default settings will be loaded." % err
	return text


func save_audio_settings() -> void:
	var config := ConfigFile.new()
	var err := config.load(audio_settings_path)
	if err == OK or err == ERR_FILE_NOT_FOUND or err == ERR_PARSE_ERROR:
		for key in audio_settings.keys():
			config.set_value("audio", key, audio_settings[key])
		for bus_name in SUB_BUSES:
			config.set_value("subbuses", bus_name, float(_subbus_volumes.get(bus_name, 1.0)))
		err = config.save(audio_settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Error while saving audio settings.")


func update_master_volume() -> void:
	var volume: float = audio_settings["master_volume"]
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
