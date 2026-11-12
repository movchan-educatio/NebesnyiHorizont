extends Node

## Global UI audio: a looping menu theme and a short click for every button.
## The mission levels keep their own engine/wind/combat audio; this player only
## runs in the menus and fades out when a mission starts.

var audio_settings_path := "%s/Audio.cfg" % Global.config_dir

var audio_settings := {"master_volume": 1.0, "music_volume": 0.55, "sfx_volume": 0.8}

const MENU_THEME := "res://Assets/Audio/menu_theme_loop.wav"
const MENU_CLICK := "res://Assets/Audio/menu_click.wav"

## Dedicated buses let the mission mix the cockpit by priority instead of
## letting wind, engines and gunfire all fight over Master.
const AUDIO_BUSES := ["Music", "Engine", "Wind", "Combat", "Radio", "Warning"]

var _music: AudioStreamPlayer = null
var _click: AudioStreamPlayer = null
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
	if OS.has_feature("ios") or OS.get_name() == "iOS":
		# iOS audio interruptions (alarm, Siri, call, Control Center) can leave
		# the app alive but its buses muted after foregrounding.  Restore the
		# mixer explicitly on the resume notification.
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


## Restore the cockpit mix before a new level or the menu theme after a sortie.
func reset_mission_buses() -> void:
	for bus_name in AUDIO_BUSES:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
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
		err = config.save(audio_settings_path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		Global.log_error(err, "Error while saving audio settings.")


func update_master_volume() -> void:
	var volume: float = audio_settings["master_volume"]
	AudioServer.set_bus_volume_db(0, linear_to_db(volume))
