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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	message.modulate = Color(1, 1, 1, 0)
	damage_flash.texture = _make_vignette()
	damage_flash.modulate = Color(1, 1, 1, 0)
	results.theme = MenuUI.theme()
	results.visible = false
	again_button.pressed.connect(_on_again_pressed)
	_build_menu_button()


func _build_menu_button() -> void:
	var parent := again_button.get_parent()
	if parent == null or parent.has_node("MenuButton"):
		return
	var menu_button := Button.new()
	menu_button.name = "MenuButton"
	menu_button.text = "ЗАВЕРШИТИ"
	menu_button.custom_minimum_size = Vector2(160, 0)
	menu_button.pressed.connect(_on_menu_pressed)
	parent.add_child(menu_button)


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://GUI/MainMenu.tscn")


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
		ammo_label.text = "СКИД: ВІДСУТНІЙ"
	else:
		ammo_label.text = "СКИД %d/%d" % [ammo, ammo_max]
	score_label.text = "SCR %04d" % score
	health_label.text = "HP %03d" % int(round(maxf(health, 0.0)))
	timer_label.text = "TIME %s" % time_text

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
	results_kicker.text = "РЕЗУЛЬТАТИ ВИЛЬОТУ"
	results_title.text = "ПІДСУМКИ МІСІЇ"
	again_button.text = "ПРОЛЕТІТИ ЩЕ РАЗ  [ENTER]"
	results_footer.text = "НАТИСНІТЬ ENTER АБО КНОПКУ, ЩОБ ПОЧАТИ ЗНОВУ"
	var level := get_tree().current_scene
	if level != null:
		var level_hud = level.get("_hud")
		if level_hud is CanvasLayer:
			(level_hud as CanvasLayer).visible = false
	var help := get_parent().get_node_or_null("Help")
	if help is CanvasLayer:
		(help as CanvasLayer).visible = false
	var drone := get_parent().get_node_or_null("Drone")
	if drone != null:
		var drone_hud = drone.get("hud")
		if drone_hud is CanvasItem:
			(drone_hud as CanvasItem).visible = false
	results_stats.text = "ЧАС ПОЛЬОТУ       %s\nОЧКИ              %d\nЦІЛІ              %d / %d\nЗЕНІТКИ           %d / %d\nПІХОТА            %d / %d" % [
		time_text, score, killed, total, aa_killed, aa_total, inf_killed, inf_total,
	]
	results.visible = true
	again_button.grab_focus()
	if OS.has_environment("DRONE_RESTART_TEST") and not _restart_test_used:
		_restart_test_used = true
		_qa_restart()


func _qa_restart() -> void:
	await get_tree().create_timer(0.6).timeout
	_restart()


func show_message(text: String, color: Color = Color(0.85, 1.0, 0.65),
		duration: float = 2.0) -> void:
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	message.text = text
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
