## Single-pass FPV downlink overlay.
##
## One shader renders the whole video channel look:
##   ANALOG 5.8 GHz  - snow, sync tears, motor EMI, signal-loss desaturation;
##   DIGITAL O3      - bitrate macroblocks, packet corruption, latency spikes;
##   FLIR white/black-hot - thermal ramp with hot-spot emphasis.
##
## Link state comes from combat/reb_system.gd (group "reb_system"), so the
## picture degrades exactly when the drone flies behind a hill, into an EW dome
## or out past the radio horizon.  F2 toggles the filter; B cycles the mode.
extends CanvasLayer

@onready var overlay: ColorRect = $Overlay

var _material: ShaderMaterial = null
var _reb: Node = null
var _radio: Node = null
var _mode: int = 0
# The lens effects stay opt-in, but a badly degraded link forces the analog /
# digital noise overlay on so the player can see why the picture is breaking up.
var _user_visible := false
var _auto_visible := false
var _manual_override := false

# Cached shader parameter names keep the per-frame update allocation-free.
const _P := [
	"video_mode", "link_quality", "signal_strength", "bitrate_mbps",
	"packet_loss", "latency_spike", "throttle", "tear_amount", "interference",
]


func _ready() -> void:
	# Camera simulation effects are opt-in for a clean lens.  The link-loss
	# auto layer is independent: it only appears when the radio actually breaks.
	_user_visible = (DisplayServer.get_name() != "headless") \
			and (OS.has_environment("DRONE_VIDEO_MODE") \
			or OS.has_environment("DRONE_SHOW_FPV_EFFECTS"))
	_material = overlay.material as ShaderMaterial
	_update_auto_visibility()
	_mode = int(Graphics.fpv_video_mode)
	# QA hook: render a specific downlink look without touching saved settings.
	if OS.has_environment("DRONE_VIDEO_MODE"):
		_mode = clampi(int(OS.get_environment("DRONE_VIDEO_MODE")), 0, 3)
	if not Graphics.fpv_video_mode_changed.is_connected(_on_video_mode_changed):
		Graphics.fpv_video_mode_changed.connect(_on_video_mode_changed)
	_on_video_mode_changed(_mode)
	_reb = get_tree().get_first_node_in_group("reb_system")
	var parent := get_parent()
	if parent != null:
		_radio = parent.get_node_or_null("RadioController")


func _needs_clean_sharpen() -> bool:
	if DisplayServer.get_name() == "headless" or OS.has_environment("DRONE_NO_SHARPEN"):
		return false
	var vp := get_viewport()
	var s3d := clampf(vp.scaling_3d_scale, 0.25, 1.0) if vp != null else 1.0
	return s3d < 0.95


func _process(_delta: float) -> void:
	if _material == null:
		return
	_update_auto_visibility()
	if not visible:
		return
	var vp := get_viewport()
	var s3d := clampf(vp.scaling_3d_scale, 0.25, 1.0) if vp != null else 1.0
	var clean_only := not (_user_visible or _auto_visible)
	_material.set_shader_parameter("screen_size",
			vp.get_visible_rect().size if vp != null else Vector2(1920.0, 1080.0))
	_material.set_shader_parameter("render_scale_3d", s3d)
	_material.set_shader_parameter("clean_sharpen_only", clean_only)
	if clean_only:
		return
	if _reb == null or not is_instance_valid(_reb):
		_reb = get_tree().get_first_node_in_group("reb_system")
	var lq := 1.0
	var sig := 1.0
	var bitrate := 50.0
	var loss := 0.0
	var spike := 0.0
	var tear := 0.0
	var interference := 0.0
	if _reb != null:
		lq = clampf(float(_reb.get("link_quality")), 0.0, 1.0)
		sig = clampf(float(_reb.get("signal_strength")), 0.0, 1.0)
		bitrate = clampf(float(_reb.get("bitrate_mbps")), 1.0, 50.0)
		loss = clampf(float(_reb.get("packet_loss")), 0.0, 1.0)
		spike = clampf(float(_reb.get("latency_spike")), 0.0, 1.0)
		tear = clampf(float(_reb.get("tear_amount")), 0.0, 1.0)
		interference = clampf(float(_reb.get("interference")), 0.0, 1.0)
	var throttle := 0.0
	if _radio != null:
		var input_arr = _radio.get("input")
		if input_arr is Array and input_arr.size() > 0:
			throttle = clampf(float(input_arr[0]), 0.0, 1.0)
	_material.set_shader_parameter("video_mode", _mode)
	_material.set_shader_parameter("link_quality", lq)
	_material.set_shader_parameter("signal_strength", sig)
	_material.set_shader_parameter("bitrate_mbps", bitrate)
	_material.set_shader_parameter("packet_loss", loss)
	_material.set_shader_parameter("latency_spike", spike)
	_material.set_shader_parameter("throttle", throttle)
	_material.set_shader_parameter("tear_amount", tear)
	_material.set_shader_parameter("interference", interference)


func _update_auto_visibility() -> void:
	var sharpen := _needs_clean_sharpen()
	if _manual_override:
		visible = _user_visible or sharpen
		return
	if _reb == null or not is_instance_valid(_reb):
		_reb = get_tree().get_first_node_in_group("reb_system")
	var auto := false
	if bool(GameSettings.hud_config.get("link_limit", false)):
		if _reb != null:
			var lq := clampf(float(_reb.get("link_quality")), 0.0, 1.0)
			var ew := clampf(float(_reb.get("in_ew")), 0.0, 1.0)
			auto = lq < 0.72 or ew > 0.08 or bool(_reb.get("failsafe"))
	_auto_visible = auto
	visible = _user_visible or _auto_visible or sharpen


func _on_video_mode_changed(mode: int) -> void:
	_mode = clampi(mode, 0, 3)
	if _material != null:
		_material.set_shader_parameter("video_mode", _mode)


## External push used by the REB system and QA harnesses.
func set_link_state(lq: float, sig: float, bitrate: float, loss: float,
		spike: float, tear: float, emi: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("link_quality", clampf(lq, 0.0, 1.0))
	_material.set_shader_parameter("signal_strength", clampf(sig, 0.0, 1.0))
	_material.set_shader_parameter("bitrate_mbps", clampf(bitrate, 1.0, 50.0))
	_material.set_shader_parameter("packet_loss", clampf(loss, 0.0, 1.0))
	_material.set_shader_parameter("latency_spike", clampf(spike, 0.0, 1.0))
	_material.set_shader_parameter("tear_amount", clampf(tear, 0.0, 1.0))
	_material.set_shader_parameter("interference", clampf(emi, 0.0, 1.0))


func set_video_mode(mode: int) -> void:
	Graphics.set_fpv_video_mode(mode)
	_on_video_mode_changed(mode)


## Force the downlink filter on/off from the touch VIDEO button.  The link-loss
## auto layer is bypassed once the pilot makes a manual choice.
func set_user_visible(on: bool) -> void:
	_manual_override = true
	_user_visible = on
	visible = on or _needs_clean_sharpen()


func is_user_visible() -> bool:
	return _user_visible


func _unhandled_input(event: InputEvent) -> void:
	if Controls.is_action_edge(event, "toggle_fpv_effects"):
		# Once the pilot touches the shortcut, the link-loss auto layer stops
		# fighting the manual choice until the next scene load.
		_manual_override = true
		_user_visible = not _user_visible
		visible = _user_visible or _needs_clean_sharpen()
		get_viewport().set_input_as_handled()
