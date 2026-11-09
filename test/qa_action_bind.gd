## QA-only: verifies that the old Controls screen can bind an ELRS switch to
## an arbitrary action (here: deploy_payload).  Enabled by ACTION_BIND_QA=1.
extends Node

var _screen: Node = null
var _wifi: Node = null
var _settings: Node = null
var _saved_hud: Dictionary = {}
var _saved_actions: Dictionary = {}
var _real_path := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().create_timer(2.0).timeout
	_screen = get_tree().current_scene
	_wifi = get_node_or_null("/root/ElrsWifiInput")
	_settings = get_node_or_null("/root/GameSettings")
	if _screen == null or _wifi == null or _settings == null \
			or not _screen.has_method("_start_detect"):
		print("[BINDQA] FAIL: missing nodes")
		get_tree().quit()
		return
	_saved_hud = (_settings.get("hud_config") as Dictionary).duplicate(true)
	_saved_actions = (_wifi.get("action_channels") as Dictionary).duplicate(true)
	_real_path = str(_settings.get("game_settings_path"))
	_settings.set("game_settings_path", "user://qa_action_bind.cfg")

	_set_channels(16383)
	_wifi.set("valid", true)
	_wifi.set("module_ip", "127.0.0.1")
	await get_tree().create_timer(1.2).timeout
	# The screen discovers the late ELRS source in _process; no manual refresh.
	print("[BINDQA] source=", _screen.get("_active_virtual"))

	_screen.call("_start_detect", "action", "deploy_payload")
	await get_tree().create_timer(0.3).timeout
	# CH8 (index 7) high: the poller must capture it.
	_set_channels(16383, {7: 32767})
	await get_tree().create_timer(0.8).timeout

	var channel := int(_wifi.call("get_action_channel", "deploy_payload"))
	print("[BINDQA] deploy_payload -> CH", channel + 1)

	# Verify the switch actually reaches the InputMap action, not just the table.
	_set_channels(16383, {7: 0})
	_wifi.call("_update_switches")
	_set_channels(16383, {7: 32767})
	_wifi.call("_update_switches")
	var pressed := Input.is_action_pressed("deploy_payload")
	_set_channels(16383, {7: 0})
	_wifi.call("_update_switches")
	var released := not Input.is_action_pressed("deploy_payload")
	print("[BINDQA] dispatch pressed=", pressed, " released=", released)

	# The in-flight SETUP panel writes the legacy property directly; make sure
	# that still reaches the generic action table.
	_wifi.set("arm_channel", 9)
	_wifi.call("save_settings")
	var setup_arm := int(_wifi.call("get_action_channel", "toggle_arm"))
	print("[BINDQA] setup arm -> CH", setup_arm + 1)

	# Put ARM back on CH5, then assign a custom action there.  ARM must move
	# instead of silently sharing the switch.
	_wifi.set("arm_channel", 4)
	_wifi.call("save_settings")
	_wifi.call("set_action_channel", "deploy_payload", 4)
	var deploy_ch := int(_wifi.call("get_action_channel", "deploy_payload"))
	var conflict_arm := int(_wifi.call("get_action_channel", "toggle_arm"))
	print("[BINDQA] conflict deploy=CH", deploy_ch + 1, " arm=CH", conflict_arm + 1)
	print("[BINDQA] ", "PASS" if channel == 7 and pressed and released
			and setup_arm == 9 and deploy_ch == 4 and conflict_arm != 4 else "FAIL")

	_settings.set("hud_config", _saved_hud)
	_wifi.set("action_channels", _saved_actions)
	_settings.set("game_settings_path", _real_path)
	var absolute := ProjectSettings.globalize_path("user://qa_action_bind.cfg")
	if FileAccess.file_exists("user://qa_action_bind.cfg"):
		DirAccess.remove_absolute(absolute)
	get_tree().quit()


func _set_channels(center: int, overrides: Dictionary = {}) -> void:
	var channels := PackedFloat32Array()
	channels.resize(16)
	channels.fill(float(center))
	for key in overrides.keys():
		channels[int(key)] = float(overrides[key])
	_wifi.set("channels", channels)
	_wifi.set("valid", true)
	_wifi.set("_last_frame_ms", Time.get_ticks_msec())
