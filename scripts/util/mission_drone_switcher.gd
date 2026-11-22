## Mid-mission aircraft selector overlay.
## Scans active targets in the level to recommend optimal drones for the
## current threat mix (armor / infantry / aerial), while respecting mode rules:
##   - COMBAT: only presets allowed for COMBAT via DroneCatalog.allowed_for_mode()
##   - TRAINING / FREESTYLE: all catalog presets including Uman freestyle quads
class_name MissionDroneSwitcher
extends CanvasLayer

signal drone_selected(preset_index: int)
signal switcher_closed()

const PANEL_BG := Color(0.03, 0.06, 0.05, 0.96)
const PANEL_BORDER := Color(0.32, 0.56, 0.40, 0.85)
const CARD_BG := Color(0.06, 0.11, 0.09, 0.94)
const CARD_REC_BG := Color(0.07, 0.15, 0.10, 0.96)
const CARD_ACTIVE_BG := Color(0.11, 0.22, 0.14, 0.98)
const TEXT_MAIN := Color(0.92, 0.97, 0.92)
const TEXT_MUTED := Color(0.68, 0.78, 0.72)
const ACCENT_GREEN := Color(0.45, 0.95, 0.55)
const ACCENT_AMBER := Color(0.96, 0.78, 0.34)

var _root: Control = null
var _panel: PanelContainer = null
var _title_lbl: Label = null
var _threat_lbl: Label = null
var _grid: GridContainer = null
var _close_btn: Button = null
var _prev_paused: bool = false
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _open: bool = false
var _current_preset: int = 0
var _level_root: Node = null


func _init() -> void:
	layer = 92
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	visible = false
	add_to_group("mission_drone_switcher")
	_build_ui()


func _tx(ua: String, en: String) -> String:
	return en if MenuUI.is_english() else ua


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "SwitcherRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.02, 0.02, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(center)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = PANEL_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	vb.add_child(hdr)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 4)
	hdr.add_child(title_box)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 24)
	_title_lbl.add_theme_color_override("font_color", ACCENT_AMBER)
	title_box.add_child(_title_lbl)

	_threat_lbl = Label.new()
	_threat_lbl.add_theme_font_size_override("font_size", 15)
	_threat_lbl.add_theme_color_override("font_color", TEXT_MUTED)
	_threat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(_threat_lbl)

	_close_btn = Button.new()
	_close_btn.custom_minimum_size = Vector2(140, 44)
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.add_theme_font_size_override("font_size", 16)
	_close_btn.add_theme_color_override("font_color", Color(0.98, 0.72, 0.72))
	var close_sb := StyleBoxFlat.new()
	close_sb.bg_color = Color(0.18, 0.06, 0.06, 0.92)
	close_sb.border_color = Color(0.75, 0.30, 0.30, 0.85)
	close_sb.set_border_width_all(1)
	close_sb.set_corner_radius_all(8)
	_close_btn.add_theme_stylebox_override("normal", close_sb)
	_close_btn.add_theme_stylebox_override("hover", close_sb)
	_close_btn.add_theme_stylebox_override("pressed", close_sb)
	_close_btn.pressed.connect(close)
	hdr.add_child(_close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	_sync_panel_bounds()


func _sync_panel_bounds() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 10.0 or vp.y < 10.0:
		vp = Vector2(1280.0, 720.0)
	var pw := clampf(vp.x * 0.88, 560.0, 980.0)
	var ph := clampf(vp.y * 0.84, 400.0, 740.0)
	_panel.custom_minimum_size = Vector2(pw, ph)
	if _grid != null:
		_grid.columns = 2 if vp.x >= 720.0 else 1


func open(level_root: Node, current_preset: int) -> void:
	if _open:
		return
	_level_root = level_root
	_current_preset = current_preset
	_open = true
	var tree := get_tree()
	_prev_paused = tree.paused if tree != null else false
	_prev_mouse_mode = Input.get_mouse_mode()
	if tree != null:
		tree.paused = true
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_sync_panel_bounds()
	_populate(level_root, current_preset)
	visible = true


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = _prev_paused
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(_prev_mouse_mode)
	emit_signal("switcher_closed")


func is_open() -> bool:
	return _open


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_B:
			close()
			get_viewport().set_input_as_handled()


func _scan_threats(level_root: Node) -> Dictionary:
	var counts := {"air": 0, "armor": 0, "soft": 0, "infantry": 0}
	if level_root == null or not is_instance_valid(level_root):
		return counts
	var seen: Dictionary = {}
	var tree := get_tree()
	var candidates: Array = []
	if tree != null:
		for grp in ["primary_combat_target", "combat_target", "enemy_infantry", "aa_gun"]:
			for node in tree.get_nodes_in_group(grp):
				candidates.append(node)
	for child in level_root.get_children():
		if child is Vehicle:
			candidates.append(child)
	for item in candidates:
		if not (item is Node) or not is_instance_valid(item):
			continue
		var node := item as Node
		var id := node.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		if node.get("is_destroyed") == true:
			continue
		if node is Vehicle:
			var v := node as Vehicle
			if not v.hostile:
				continue
			match v.kind:
				Vehicle.Kind.HELI, Vehicle.Kind.SHAHED:
					counts["air"] += 1
				Vehicle.Kind.TANK, Vehicle.Kind.BMP, Vehicle.Kind.APC, Vehicle.Kind.SAM:
					counts["armor"] += 1
				Vehicle.Kind.TRUCK:
					counts["soft"] += 1
		elif node.is_in_group("enemy_infantry"):
			counts["infantry"] += 1
		elif node.is_in_group("aa_gun"):
			counts["soft"] += 1
		elif node is CombatTarget:
			var ct := node as CombatTarget
			match ct.kind:
				CombatTarget.Kind.TANK:
					counts["armor"] += 1
				CombatTarget.Kind.INFANTRY:
					counts["infantry"] += 1
				_:
					counts["soft"] += 1
	return counts


func _eligible_presets() -> Array[int]:
	var is_combat_or_ct := Global.play_mode == Global.PlayMode.COMBAT \
			or (Global.play_mode == Global.PlayMode.TRAINING and Global.combat_training)
	if is_combat_or_ct:
		var out: Array[int] = []
		for i in range(DroneCatalog.count()):
			if not DroneCatalog.is_uman(i):
				out.append(i)
		return out
	return DroneCatalog.allowed_for_mode(Global.play_mode)


func _recommended_indices(threats: Dictionary) -> Array[int]:
	var rec: Array[int] = []
	var has_air := int(threats.get("air", 0)) > 0
	var has_armor := int(threats.get("armor", 0)) > 0
	var has_inf := (int(threats.get("infantry", 0)) + int(threats.get("soft", 0))) > 0
	for i in _eligible_presets():
		var p := DroneCatalog.preset(i)
		if not bool(p.get("combat", false)):
			continue
		var pid := str(p.get("id", ""))
		var is_rec := false
		if has_air and (bool(p.get("interceptor", false)) or pid in ["strila8", "chaklun_jet", "furia"]):
			is_rec = true
		if has_armor and (bool(p.get("heavy_bomber", false)) or bool(p.get("kamikaze", false)) and float(p.get("payload_mass", 0.0)) >= 1.2):
			is_rec = true
		if has_inf and bool(p.get("has_drop", false)):
			is_rec = true
		if is_rec:
			rec.append(i)
	if rec.is_empty():
		rec.append_array([0, 1, 6])
	return rec


func _weapon_badge(p: Dictionary) -> String:
	var has_drop := bool(p.get("has_drop", false))
	var kamikaze := bool(p.get("kamikaze", false))
	var payload_n := int(p.get("payload", 0))
	if not bool(p.get("combat", false)):
		return _tx("ФРІСТАЙЛ", "FREESTYLE")
	if has_drop and kamikaze:
		return _tx("СКИД ×%d + БЧ" % maxi(1, payload_n), "DROP ×%d + WARHEAD" % maxi(1, payload_n))
	if has_drop:
		return _tx("СКИД ×%d" % maxi(1, payload_n), "DROP ×%d" % maxi(1, payload_n))
	if kamikaze:
		return _tx("КАМІКАДЗЕ БЧ", "KAMIKAZE")
	return _tx("РОЗВІДКА", "RECON")


func _populate(level_root: Node, current_preset: int) -> void:
	for child in _grid.get_children():
		child.queue_free()
	var mode_label := _tx("БОЙОВИЙ ВИЛІТ", "COMBAT SORTIE") if Global.play_mode == Global.PlayMode.COMBAT \
			else _tx("ПОЛІГОН / ФРІСТАЙЛ", "TRAINING / FREESTYLE")
	_title_lbl.text = _tx("ЗАМІНА ДРОНА ПІД ЧАС МІСІЇ  [%s]" % mode_label,
			"MID-MISSION DRONE SWITCH  [%s]" % mode_label)
	_close_btn.text = _tx("✕ ЗАКРИТИ", "✕ CLOSE")

	var threats := _scan_threats(level_root)
	var total_t := int(threats["air"]) + int(threats["armor"]) + int(threats["soft"]) + int(threats["infantry"])
	if total_t > 0:
		_threat_lbl.text = _tx(
				"АКТИВНІ ЦІЛІ:  Броня: %d  ·  Техніка/ППО: %d  ·  Піхота: %d  ·  Повітря: %d",
				"ACTIVE TARGETS:  Armor: %d  ·  Vehicles/AA: %d  ·  Infantry: %d  ·  Air: %d"
			) % [int(threats["armor"]), int(threats["soft"]), int(threats["infantry"]), int(threats["air"])]
	else:
		_threat_lbl.text = _tx(
				"У бойовому режимі доступні бойові БПЛА (0–9). Натисніть карту для заміни борту.",
				"Combat mode allows tactical UAVs (0–9). Tap a card to deploy.")

	var recs := _recommended_indices(threats)
	var allowed := _eligible_presets()
	for idx in allowed:
		var p := DroneCatalog.preset(idx)
		var is_active := (idx == current_preset)
		var is_rec := idx in recs
		var card := _make_drone_card(idx, p, is_active, is_rec)
		_grid.add_child(card)


func _make_drone_card(idx: int, p: Dictionary, is_active: bool, is_rec: bool) -> Button:
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(260, 88)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_ACTIVE_BG if is_active else (CARD_REC_BG if is_rec else CARD_BG)
	sb.border_color = ACCENT_AMBER if is_active else (ACCENT_GREEN if is_rec else Color(0.26, 0.42, 0.32, 0.72))
	sb.set_border_width_all(2 if (is_active or is_rec) else 1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	var sb_hover := sb.duplicate() as StyleBoxFlat
	sb_hover.bg_color = sb.bg_color.lightened(0.08)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)

	var d_name := DroneCatalog.get_drone_name(idx)
	var d_tag := DroneCatalog.get_drone_tag(idx)
	var weapon := _weapon_badge(p)
	var badge := ""
	if is_active:
		badge = _tx("  ● АКТИВНИЙ", "  ● ACTIVE")
	elif is_rec:
		badge = _tx("  ★ РЕКОМЕНДОВАНО", "  ★ RECOMMENDED")
	btn.text = "%s%s\n%s  ·  %s" % [d_name, badge, d_tag, weapon]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", ACCENT_AMBER if is_active else (TEXT_MAIN if not is_rec else Color(0.86, 1.0, 0.88)))
	btn.pressed.connect(_on_card_pressed.bind(idx))
	return btn


func _on_card_pressed(idx: int) -> void:
	_open = false
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = _prev_paused
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(_prev_mouse_mode)
	emit_signal("drone_selected", idx)
