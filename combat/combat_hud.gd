## FPV-style combat OSD: target counter, payload ammo, score, hull health,
## mission timer, damage vignette and the end-of-range results screen.
class_name CombatHUD
extends CanvasLayer

const MenuUI = preload("res://GUI/ui/MenuUI.gd")

signal restart_requested

@onready var targets_label: Label = $Root/TopRight/Targets
@onready var ammo_label: Label = $Root/TopRight/Ammo
@onready var score_label: Label = $Root/TopRight/Score
@onready var health_label: Label = $Root/TopRight/Health
@onready var timer_label: Label = $Root/TopRight/Timer
@onready var message: Label = $Root/Message
@onready var root: Control = $Root
@onready var damage_flash: TextureRect = $Root/DamageFlash
@onready var results: Control = $Results
@onready var results_stats: Label = $Results/Panel/VBox/Stats
@onready var results_kicker: Label = $Results/Panel/VBox/Kicker
@onready var results_title: Label = $Results/Panel/VBox/Title
@onready var results_footer: Label = $Results/Panel/VBox/Footer
@onready var again_button: Button = $Results/Panel/VBox/Again

var _message_tween: Tween
var _damage_tween: Tween
var _restart_sent := false
static var _restart_test_used := false


func _is_mobile() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


func _tx(ua: String, en: String) -> String:
	return en if MenuUI.is_english() else ua


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	message.modulate = Color(1, 1, 1, 0)
	damage_flash.texture = _make_vignette()
	damage_flash.modulate = Color(1, 1, 1, 0)
	results.theme = MenuUI.theme()
	results.visible = false
	again_button.pressed.connect(_on_again_pressed)
	_build_menu_button()
	MenuUI.localize_tree(self)


func _build_menu_button() -> void:
	var parent := again_button.get_parent()
	if parent == null or parent.has_node("MenuButton"):
		return
	var menu_button := Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = _tx("ЗАВЕРШИТИ", "END SORTIE")
	menu_button.custom_minimum_size = Vector2(160, 0)
	menu_button.pressed.connect(_on_menu_pressed)
	parent.add_child(menu_button)


func _on_menu_pressed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = false
	tree.change_scene_to_file("res://GUI/MainMenu.tscn")


func _make_vignette() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.42, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.08, 0.04, 0.0),
		Color(1.0, 0.05, 0.02, 0.0),
		Color(0.90, 0.03, 0.01, 0.18),
		Color(0.80, 0.0, 0.0, 0.45),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func set_stats(remaining: int, total: int, ammo: int, ammo_max: int, score: int,
		health: float, health_max: float, time_text: String) -> void:
	targets_label.text = "TGT %d/%d" % [remaining, total]
	if ammo_max <= 0:
		ammo_label.text = _tx("СКИД: ВІДСУТНІЙ", "PAYLOAD: NONE")
	else:
		ammo_label.text = _tx("СКИД %d/%d" % [ammo, ammo_max],
				"DROP %d/%d" % [ammo, ammo_max])
	score_label.text = "SCR %04d" % score
	health_label.text = "HP %03d" % int(round(maxf(health, 0.0)))
	timer_label.text = _tx("ЧАС %s" % time_text, "TIME %s" % time_text)

	if remaining <= 0:
		targets_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	else:
		targets_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.62))
	if ammo_max <= 0:
		ammo_label.add_theme_color_override("font_color", Color(0.60, 0.65, 0.60))
	elif ammo <= 0:
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
	else:
		ammo_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.62))

	var ratio := health / maxf(health_max, 1.0)
	if ratio <= 0.30:
		health_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.22))
	elif ratio <= 0.60:
		health_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.28))
	else:
		health_label.add_theme_color_override("font_color", Color(0.62, 1.0, 0.62))


func flash_damage() -> void:
	if _damage_tween != null and _damage_tween.is_valid():
		_damage_tween.kill()
	damage_flash.modulate.a = 1.0
	_damage_tween = create_tween()
	_damage_tween.tween_property(damage_flash, "modulate:a", 0.0, 0.5)


func show_results(time_text: String, score: int, killed: int, total: int,
		aa_killed: int, aa_total: int, inf_killed: int = 0, inf_total: int = 0) -> void:
	_restart_sent = false
	root.visible = false
	results_kicker.text = _tx("РЕЗУЛЬТАТИ ВИЛЬОТУ", "SORTIE RESULTS")
	results_title.text = _tx("ПІДСУМКИ МІСІЇ", "MISSION DEBRIEF")
	again_button.text = _tx("ПРОЛЕТІТИ ЩЕ РАЗ  [ENTER]", "FLY AGAIN  [ENTER]")
	results_footer.text = _tx(
		"НАТИСНІТЬ ENTER АБО КНОПКУ, ЩОБ ПОЧАТИ ЗНОВУ",
		"PRESS ENTER OR THE BUTTON TO RESTART")
	if _is_mobile():
		# TouchControls is a separate CanvasLayer at layer 30.  Keep the debrief
		# above it and hide the flight-only controls while the result modal is up.
		layer = 120
		var touch := get_node_or_null("/root/TouchControls")
		if touch != null and touch.has_method("set_enabled"):
			touch.call("set_enabled", false)
	var tree := get_tree()
	var level := tree.current_scene if tree != null else null
	if level != null:
		var level_hud = level.get("_hud")
		if level_hud is CanvasLayer:
			(level_hud as CanvasLayer).visible = false
	var parent := get_parent()
	if parent != null:
		var help := parent.get_node_or_null("Help")
		if help is CanvasLayer:
			(help as CanvasLayer).visible = false
		var drone := parent.get_node_or_null("Drone")
		if drone != null:
			var drone_hud = drone.get("hud")
			if drone_hud is CanvasItem:
				(drone_hud as CanvasItem).visible = false
	var rank_line := ""
	if Global.has_method("get_pilot_rank_info"):
		var rinfo = Global.call("get_pilot_rank_info")
		if rinfo is Dictionary:
			var rank_name := String(rinfo.get(
					"rank_en" if MenuUI.is_english() else "rank_ua", ""))
			var r_xp := int(rinfo.get("xp", 0))
			rank_line = _tx("\nЗВАННЯ            %s (%d XP)",
					"\nRANK              %s (%d XP)") % [rank_name, r_xp]
	var total_hits := killed + aa_killed + inf_killed
	var level_drops := 0
	if level != null:
		var pd = level.get("_payload_drops")
		if pd != null:
			level_drops += int(pd)
		var cs = level.get_node_or_null("CombatSystem")
		if cs != null and cs.get("drops_count") != null:
			level_drops += int(cs.get("drops_count"))
	var acc_str := "%d%% (%d/%d)" % [
		int(round(100.0 * float(mini(total_hits, level_drops)) / float(maxi(level_drops, 1)))),
		mini(total_hits, level_drops), level_drops
	] if level_drops > 0 else "—"
	results_stats.text = _tx(
		"ЧАС ПОЛЬОТУ       %s\nОЧКИ              %d\nЦІЛІ              %d / %d\nЗЕНІТКИ           %d / %d\nПІХОТА            %d / %d\nТОЧНІСТЬ          %s%s",
		"FLIGHT TIME       %s\nSCORE             %d\nTARGETS           %d / %d\nAIR DEFENSE       %d / %d\nINFANTRY          %d / %d\nACCURACY          %s%s") % [
		time_text, score, killed, total, aa_killed, aa_total, inf_killed, inf_total, acc_str, rank_line
	]
	results.visible = true
	again_button.grab_focus()
	if OS.has_environment("DRONE_RESTART_TEST") and not _restart_test_used:
		_restart_test_used = true
		_qa_restart()


func _qa_restart() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(0.6).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	_restart()


func show_message(text: String, color: Color = Color(0.85, 1.0, 0.65),
		duration: float = 2.0) -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	message.text = MenuUI.translate_text(text)
	message.modulate = Color(color.r, color.g, color.b, 1.0)
	_message_tween = create_tween()
	_message_tween.tween_interval(maxf(duration, 0.2))
	_message_tween.tween_property(message, "modulate:a", 0.0, 0.55)


func _on_again_pressed() -> void:
	_restart()


func _unhandled_input(event: InputEvent) -> void:
	if not results.visible:
		return
	if event.is_action_pressed("ui_accept"):
		_restart()
		get_viewport().set_input_as_handled()


func _restart() -> void:
	if _restart_sent:
		return
	_restart_sent = true
	restart_requested.emit()
