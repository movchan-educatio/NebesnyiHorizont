## Drone selection screen with a live 3D preview (third person) of each model
## and a caption. In-game the drone is flown in first person (FPV).
extends Control

const MAIN_MENU := "res://GUI/MainMenu.tscn"
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")
const GlbMaterialUtilsScript = preload("res://scripts/util/glb_material_utils.gd")
const MenuDioramaStageScript = preload("res://scripts/util/MenuDioramaStage.gd")

var _pending := 0
var _rows: Array[Dictionary] = []
var _preview: SubViewport = null
var _preview_container: SubViewportContainer = null
var _holder: Node3D = null
var _preview_camera: Camera3D = null
var _preview_ring: MeshInstance3D = null
var _diorama: Node3D = null
var _pad_rotator: Node3D = null
var _is_dragging_preview := false
var _caption: Label = null
var _tag: Label = null
var _specs: Label = null
var _info: Label = null
var _choose: Button = null
var _confirm: Label = null


func _ready() -> void:
	theme = MenuUI.theme()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if OS.has_environment("DRONE_HANGAR_TEST_PRESET"):
		Global.drone_preset = int(OS.get_environment("DRONE_HANGAR_TEST_PRESET"))
	_pending = Global.drone_preset
	_build()
	_pending = Global.drone_preset
	_refresh()
	_show_model(_pending)
	MenuUI.localize_tree(self)
	if OS.has_environment("DRONE_HANGAR_TEST_SELECT"):
		call_deferred("_qa_select_preset",
				int(OS.get_environment("DRONE_HANGAR_TEST_SELECT")))


func _build() -> void:
	add_child(MenuUI.background(MenuUI.BG))

	var center := CenterContainer.new()
	MenuUI.full_rect(center)
	var viewport_size := get_viewport_rect().size
	var short_screen := MenuUI.is_mobile_ui() and viewport_size.y < 700.0
	var hangar_edges := MenuUI.mobile_edge_margins(viewport_size) if MenuUI.is_mobile_ui() else Vector4(12, 12, 12, 24)
	center.offset_top = 10.0 if short_screen else maxf(16.0, hangar_edges.y)
	center.offset_bottom = -10.0 if short_screen else -maxf(24.0, hangar_edges.w)
	add_child(center)

	var panel := PanelContainer.new()
	var panel_width := minf(1840.0, maxf(320.0, viewport_size.x - (hangar_edges.x + hangar_edges.z)))
	var column_width := minf(720.0, maxf(260.0, (panel_width - 110.0) * 0.47))
	panel.custom_minimum_size = Vector2(panel_width, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 18)
	margin.add_theme_constant_override("margin_top", 8 if short_screen else 12)
	margin.add_theme_constant_override("margin_bottom", 8 if short_screen else 12)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6 if short_screen else 8)
	margin.add_child(box)

	var title := MenuUI.title("ОБРАТИ ДРОН", 26 if short_screen else 30)
	box.add_child(title)
	if not short_screen:
		box.add_child(MenuUI.subtitle("Готові моделі для фрістайлу, тренування та бойових місій"))

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(columns)

	# left: list
	var list_scroll := ScrollContainer.new()
	var list_height := (viewport_size.y * 0.50 if short_screen
			else viewport_size.y - 280.0)
	list_scroll.custom_minimum_size = Vector2(column_width, clampf(list_height, 200.0, 520.0))
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.size_flags_stretch_ratio = 1.0
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	list_scroll.add_child(list)
	# Ангар показує тільки ті дрони, які дозволені на поточній карті.
	for i in DroneCatalog.allowed_for_map(str(Global.menu_settings.get("selected_map", "uman"))):
		list.add_child(_make_row(i))

	# right: 3D preview + caption
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = column_width
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	columns.add_child(right)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	var preview_height := viewport_size.y * (0.40 if short_screen
			else (0.48 if MenuUI.is_mobile_ui() else 0.46))
	container.custom_minimum_size = Vector2(column_width, clampf(preview_height, 200.0, 560.0))
	container.gui_input.connect(_on_preview_gui_input)
	if MenuUI.is_mobile_ui():
		container.resized.connect(_on_preview_resized)
	right.add_child(container)
	_preview_container = container
	_preview = SubViewport.new()
	_preview.size = Vector2i(1600, 800)
	_preview.own_world_3d = true
	_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Separate viewport: inherit no root MSAA, so ask for it explicitly.
	_preview.msaa_3d = Viewport.MSAA_4X
	_preview.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	container.add_child(_preview)
	_setup_preview_world()

	_caption = MenuUI.body("", 20 if MenuUI.is_mobile_ui() else 24, MenuUI.TEXT)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.custom_minimum_size = Vector2(column_width, 0)
	right.add_child(_caption)
	_tag = MenuUI.body("", 12 if MenuUI.is_mobile_ui() else 13, MenuUI.ACCENT)
	_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag.custom_minimum_size = Vector2(column_width, 0)
	right.add_child(_tag)
	_specs = MenuUI.body("", 12 if MenuUI.is_mobile_ui() else 14, MenuUI.MUTED)
	_specs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_specs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_specs.custom_minimum_size = Vector2(column_width, 0)
	right.add_child(_specs)
	_info = MenuUI.body("", 11 if MenuUI.is_mobile_ui() else 13, MenuUI.MUTED)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(column_width, 0 if short_screen else 48)
	# On phone/tablet the long descriptive paragraph is the first thing to go;
	# the stats, selection state and buttons stay visible.  PC keeps it.
	_info.visible = not MenuUI.is_mobile_ui()
	right.add_child(_info)

	_pending = Global.drone_preset
	_choose = MenuUI.button("ОБРАТИ ЦЕЙ ДРОН", 40 if short_screen else 48)
	_choose.pressed.connect(_apply_pending)
	right.add_child(_choose)

	_confirm = MenuUI.body("", 15, MenuUI.ACCENT)
	_confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.custom_minimum_size = Vector2(column_width, 30 if short_screen else 44)
	_confirm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var selected_preset := DroneCatalog.preset(Global.drone_preset)
	var selected_name := str(selected_preset["name"])
	if MenuUI.is_english():
		selected_name = str(selected_preset.get("name_en", MenuUI.translate_text(selected_name)))
	_confirm.text = ("Selected: %s" if MenuUI.is_english() else "Зараз обрано: %s") % selected_name
	# The highlighted "ОБРАНО ✓" button already states the selection; the
	# repeated caption is dropped on mobile to keep the back button on screen.
	_confirm.visible = not MenuUI.is_mobile_ui()
	right.add_child(_confirm)

	var back := MenuUI.button("←  НАЗАД", 38 if short_screen else 46)
	back.pressed.connect(_go_back)
	box.add_child(back)
	back.grab_focus()


func _setup_preview_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# A near-black hangar swallowed the carbon airframes.  A mid-dark slate
	# backdrop plus a stronger ambient fill keeps even black drones readable.
	env.background_color = Color(0.18, 0.22, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.81, 0.76)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.08
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.05
	env.adjustment_contrast = 1.01
	env.adjustment_saturation = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	_preview.add_child(world)

	# Key Light (top-front-right)
	var key := DirectionalLight3D.new()
	key.light_energy = 2.2
	key.light_color = Color(1.0, 0.96, 0.86)
	key.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	_preview.add_child(key)

	# Fill Light (left-side)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 1.3
	fill.light_color = Color(0.52, 0.80, 0.64)
	fill.rotation_degrees = Vector3(-20.0, -60.0, 0.0)
	_preview.add_child(fill)

	# Strong Back / Rim Light to highlight dark carbon silhouettes
	var rim := DirectionalLight3D.new()
	rim.light_energy = 2.0
	rim.light_color = Color(0.80, 0.96, 0.84)
	rim.rotation_degrees = Vector3(25.0, -145.0, 0.0)
	_preview.add_child(rim)

	# Low frontal fill keeps the nose and payload visible when the holder
	# turns the model away from the key light.
	var front := DirectionalLight3D.new()
	front.light_energy = 0.9
	front.light_color = Color(0.78, 0.88, 0.90)
	front.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
	_preview.add_child(front)

	# Illuminated tactical turntable pedestal
	var pedestal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.36
	cyl.bottom_radius = 0.40
	cyl.height = 0.04
	pedestal.mesh = cyl
	pedestal.position = Vector3(0.0, -0.35, 0.0)
	var ped_mat := StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.12, 0.16, 0.14)
	ped_mat.roughness = 0.75
	ped_mat.metallic = 0.3
	ped_mat.emission_enabled = true
	ped_mat.emission = Color(0.05, 0.15, 0.10)
	pedestal.material_override = ped_mat
	pedestal.visible = not MenuUI.is_mobile_ui()
	_preview.add_child(pedestal)

	# Glowing tactical accent ring around pedestal
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.38
	ring.mesh = torus
	ring.position = Vector3(0.0, -0.328, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = MenuUI.ACCENT
	ring.material_override = ring_mat
	_preview.add_child(ring)
	_preview_ring = ring
	_pad_rotator = _add_tactical_podium_details(_preview, -0.328, 0.36)
	_diorama = MenuDioramaStageScript.attach(_preview, -0.328, 0.36, Vector2(0.62, 1.0), false)

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.position = Vector3(0.60, 0.42, 1.00)
	_preview.add_child(cam)
	cam.look_at(Vector3(0, -0.02, 0), Vector3.UP)
	cam.current = true
	_preview_camera = cam

	_holder = Node3D.new()
	_preview.add_child(_holder)


func _add_tactical_podium_details(vp: Node, top_y: float, radius: float) -> Node3D:
	var pad_rotator := Node3D.new()
	pad_rotator.name = "TurntableDeckDetails"
	vp.add_child(pad_rotator)

	var inner_ring := MeshInstance3D.new()
	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = radius * 0.52
	inner_torus.outer_radius = radius * 0.55
	inner_torus.rings = 36
	inner_torus.ring_segments = 16
	inner_ring.mesh = inner_torus
	inner_ring.scale = Vector3(1.0, 0.03, 1.0)
	inner_ring.position = Vector3(0.0, top_y + 0.001, 0.0)
	var ir_mat := StandardMaterial3D.new()
	ir_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ir_mat.albedo_color = Color(0.95, 0.76, 0.30, 0.85)
	inner_ring.material_override = ir_mat
	pad_rotator.add_child(inner_ring)

	var lug_mat := StandardMaterial3D.new()
	lug_mat.albedo_color = Color(0.20, 0.25, 0.21)
	lug_mat.roughness = 0.65
	lug_mat.metallic = 0.45
	for i in range(8):
		var a := float(i) * PI * 0.25
		var tick := MeshInstance3D.new()
		var t_box := BoxMesh.new()
		t_box.size = Vector3(0.014, 0.003, radius * 0.18)
		tick.mesh = t_box
		var r_mid := radius * 0.74
		tick.position = Vector3(sin(a) * r_mid, top_y + 0.0015, cos(a) * r_mid)
		tick.rotation.y = a
		tick.material_override = ir_mat if (i % 2 == 0) else lug_mat
		pad_rotator.add_child(tick)
		if i % 2 == 1:
			var lug := MeshInstance3D.new()
			var l_box := BoxMesh.new()
			l_box.size = Vector3(0.055, 0.018, 0.04)
			lug.mesh = l_box
			var r_lug := radius * 0.99
			lug.position = Vector3(sin(a) * r_lug, top_y - 0.004, cos(a) * r_lug)
			lug.rotation.y = a
			lug.material_override = lug_mat
			pad_rotator.add_child(lug)
	return pad_rotator


func _make_row(index: int) -> Control:
	var p := DroneCatalog.preset(index)
	var row := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	info.add_child(title_row)
	var display_name := DroneCatalog.get_drone_name(index)
	var name_label := MenuUI.body(display_name, 18 if MenuUI.is_mobile_ui() else 19, MenuUI.TEXT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long military-airframe names must shrink inside the list column instead
	# of forcing the whole right-hand preview off the screen.
	name_label.clip_text = true
	name_label.custom_minimum_size = Vector2(0, 0)
	title_row.add_child(name_label)
	var tag_label := MenuUI.body(DroneCatalog.get_drone_tag(index), 11, MenuUI.ACCENT)
	tag_label.clip_text = true
	# The description below already carries the class/role; dropping the tag
	# on the phone leaves enough width for the full drone name.
	tag_label.visible = not MenuUI.is_mobile_ui()
	title_row.add_child(tag_label)
	var desc_label := MenuUI.body(DroneCatalog.get_drone_desc(index), 12,
			MenuUI.MUTED)
	desc_label.clip_text = true
	info.add_child(desc_label)
	var pick := MenuUI.button("ОБРАТИ", 40)
	pick.custom_minimum_size = Vector2(120 if MenuUI.is_mobile_ui() else 160, 40)
	if MenuUI.is_mobile_ui():
		pick.add_theme_font_size_override("font_size", 18)
	pick.pressed.connect(_on_row_clicked.bind(index))
	hbox.add_child(pick)
	var mark := MenuUI.body("", 15, MenuUI.ACCENT)
	mark.custom_minimum_size = Vector2(60 if MenuUI.is_mobile_ui() else 90, 0)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(mark)
	_rows.append({"mark": mark})
	return row


func _qa_select_preset(index: int) -> void:
	_on_row_clicked(index)
	var p := DroneCatalog.preset(index)
	print("[HANGAR-TEST] requested=", index, " selected=", Global.drone_preset,
			" combat=", bool(p.get("combat", false)),
			" mode=", Global.play_mode,
			" confirm='", _confirm.text.replace("\n", " | "), "'")
	get_tree().quit(0 if Global.drone_preset == index else 1)


func _on_row_clicked(index: int) -> void:
	_pending = index
	_apply_pending()
	_show_model(index)


func _on_preview_gui_input(event: InputEvent) -> void:
	# Clicking the large hangar turntable selects the previewed airframe;
	# dragging/swiping spins the turntable & scatters brass shell casings.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging_preview = mb.pressed
			if mb.pressed:
				_apply_pending()
				accept_event()
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_is_dragging_preview = touch.pressed
		if touch.pressed:
			_apply_pending()
			accept_event()
	elif event is InputEventMouseMotion and _is_dragging_preview:
		var mm := event as InputEventMouseMotion
		var dyaw := mm.relative.x * 0.012
		if _holder != null:
			_holder.rotation.y += dyaw
		if _pad_rotator != null:
			_pad_rotator.rotation.y += dyaw
		if _diorama != null:
			_diorama.apply_swipe_spin(dyaw)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		var dyaw := sd.relative.x * 0.012
		if _holder != null:
			_holder.rotation.y += dyaw
		if _pad_rotator != null:
			_pad_rotator.rotation.y += dyaw
		if _diorama != null:
			_diorama.apply_swipe_spin(dyaw)


## Combat sorties may only use combat airframes.
func _combat_locked(index: int) -> bool:
	if Global.play_mode != Global.PlayMode.COMBAT:
		return false
	if DroneCatalog.is_combat(index):
		return false
	if _confirm != null:
		_confirm.text = ("This airframe is not available for combat missions.\nPick a strike / bomber drone." if MenuUI.is_english() else "Цей дрон недоступний для бойових місій.\nОберіть ударний дрон або дрон зі скидом.")
	return true


func _select_preview(index: int) -> void:
	_pending = index
	_refresh()
	_show_model(index)
	if _confirm != null:
		var preset_name := DroneCatalog.get_drone_name(index)
		_confirm.text = ("Previewing %s. Select this drone to confirm." if MenuUI.is_english() else "Перегляд: %s. Натисніть «ОБРАТИ ЦЕЙ ДРОН»." ) % preset_name


func _apply_pending() -> void:
	var is_freestyle_only := DroneCatalog.is_uman(_pending)
	if is_freestyle_only:
		Global.play_mode = Global.PlayMode.TRAINING
		Global.menu_settings["selected_mode"] = Global.PlayMode.TRAINING
		Global.special_mission = 0
		Global.menu_settings["selected_special"] = 0
		Global.combat_training = false
	var was_combat_locked := _combat_locked(_pending)
	# A civilian/freestyle airframe cannot fly an armed combat sortie. Instead of
	# rejecting the click, select the drone and switch the pending sortie to
	# Freestyle (the mode where it is available across all maps).
	if was_combat_locked:
		Global.play_mode = Global.PlayMode.TRAINING
		Global.special_mission = 0
		Global.menu_settings["selected_mode"] = Global.PlayMode.TRAINING
		Global.menu_settings["selected_special"] = 0
	# Applying the drone keeps a pilot-tuned rate/expo profile intact; its
	# factory rates are used only while custom_rates is false.
	DroneCatalog.apply(_pending)
	Global.drone_preset = _pending
	Global.menu_settings["drone_preset"] = _pending
	Global.save_menu_settings()
	_refresh()
	var preset_name := DroneCatalog.get_drone_name(_pending)
	if _choose != null:
		_choose.text = "SELECTED ✓" if MenuUI.is_english() else "ОБРАНО ✓"
	if _confirm != null:
		if is_freestyle_only:
			_confirm.text = ("✓ %s selected for Freestyle on any map (non-combat).\nSwitch to a combat drone for tactical missions." if MenuUI.is_english() else "✓ %s обрано для фрістайлу на будь-якій карті (без бойових місій).\nДля бойових завдань оберіть ударний дрон.") % preset_name
		elif was_combat_locked:
			_confirm.text = ("✓ %s selected for Free Flight (no tactical payload).\nCombat sorties require a tactical / drop drone." if MenuUI.is_english() else "✓ %s обрано для вільного польотів (без БЧ).\nДля бойових місій потрібен тактичний дрон або дрон зі скидом.") % preset_name
		else:
			_confirm.text = ("✓ %s is selected for your next sortie.\nGo back to choose a flight mode." if MenuUI.is_english() else "✓ %s — саме цей дрон злетить у наступному польоті.\nНатисніть «НАЗАД» і виберіть режим.") % preset_name


func _show_model(index: int) -> void:
	var p := DroneCatalog.preset(index)
	var is_en := MenuUI.is_english()
	_caption.text = DroneCatalog.get_drone_name(index)
	_tag.text = DroneCatalog.get_drone_tag(index)
	var is_combat: bool = bool(p.get("combat", false))
	var has_drop: bool = bool(p.get("has_drop", false))
	var ammo_count := int(p.get("payload", 0)) if is_combat else 0
	var ammo_str: String
	if not is_combat:
		ammo_str = "no payload" if is_en else "без навантаження"
	elif has_drop:
		var drop_name := DroneCatalog.get_drone_drop_name(index)
		if drop_name.is_empty():
			drop_name = "%d× payload" % ammo_count if is_en else "%d× скид" % ammo_count
		ammo_str = ("drop: %s" if is_en else "скид: %s") % drop_name
	else:
		ammo_str = "%d× tactical payload" % ammo_count if is_en else "%d× тактична БЧ" % ammo_count
	_specs.text = ("%.2f kg · %d KV · %.1f\" propeller · %d blades · %s" if is_en else "%.2f кг · %d KV · пропелер %.1f\" · %d лопаті · %s") % [
			float(p["dry"]) + float(p["batt"]), int(p["kv"]), float(p["prop_d"]),
			int(p["blades"]), ammo_str]
	_info.text = DroneCatalog.get_drone_info(index)
	if _holder == null:
		return
	for child in _holder.get_children():
		child.queue_free()
	var path := str(p.get("model", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		return
	_holder.add_child(model)
	# The hangar preview instantiates the PackedScene directly instead of going
	# through DroneCatalog.attach_model(), so it needs the same material wrapper.
	GlbMaterialUtilsScript.ensure_pbr(model)
	if index >= 10 and index <= 12:
		DroneCatalog.apply_uman_drone_materials(model, index)
	model.rotation.y = float(p.get("model_yaw", 0.0))
	model.rotation_degrees.x = float(p.get("model_pitch", 0.0))
	DronePropellerSystem.setup_propellers(model, index,
			float(p.get("prop_d", 5.0)), int(p.get("blades", 3)))
	DroneCatalog._apply_composite_detail(model, index)
	MenuUI.fit_preview_model(model, 1.25, -0.18)
	_fit_preview_camera()
	if MenuUI.is_mobile_ui():
		_on_preview_resized.call_deferred()


func _on_preview_resized() -> void:
	if _preview == null or _preview_container == null:
		return
	var target := _preview_container.size
	if target.x < 16.0 or target.y < 16.0:
		return
	if not _preview_container.stretch:
		_preview.size = Vector2i(clampi(int(target.x), 64, 1600),
				clampi(int(target.y), 64, 1000))
	_fit_preview_camera()


func _fit_preview_camera() -> void:
	if _holder == null or _preview_camera == null:
		return
	var box := _combined_aabb(_holder)
	if box.size.length() < 0.01:
		return
	# Keep the airframe as the framing target: the turntable is decoration and
	# must not shrink the drone just to keep its full ring on screen.
	var ring_scale := 1.0
	if _preview_ring != null:
		# The pedestal ring is decorative.  On a phone the preview panel is
		# shallower, so hide it rather than show a sliced circle under the drone.
		_preview_ring.visible = not MenuUI.is_mobile_ui()
		if MenuUI.is_mobile_ui():
			# Small pedestal that fits fully inside the phone preview instead of
			# a large ring sliced by the bottom edge.
			ring_scale = clampf(maxf(box.size.x, box.size.z) / 1.6, 0.48, 0.62)
			_preview_ring.position.y = -0.20
		else:
			ring_scale = clampf(maxf(box.size.x, box.size.z) / 0.76, 0.7, 2.2)
			_preview_ring.position.y = -0.328
		_preview_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	var frame_box := box
	var center := frame_box.get_center()
	var fov := 40.0
	var aspect := 1600.0 / 800.0
	if _preview != null and _preview.size.y > 0:
		aspect = float(_preview.size.x) / float(_preview.size.y)
	var half_w := maxf(frame_box.size.x, frame_box.size.z) * 0.5
	var half_h := frame_box.size.y * 0.5
	var vfov := deg_to_rad(fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * aspect)
	var dist_w := half_w / maxf(tan(hfov * 0.5), 0.001)
	var dist_h := half_h / maxf(tan(vfov * 0.5), 0.001)
	var dist_mult := 1.55 if MenuUI.is_mobile_ui() else 1.65
	var dist := maxf(maxf(dist_w, dist_h) * dist_mult, 0.62)
	var dir := Vector3(0.62, 0.38, 1.0).normalized()
	var focus := center - Vector3(0.0, frame_box.size.y * 0.04, 0.0)
	_preview_camera.fov = fov
	_preview_camera.position = focus + dir * dist
	_preview_camera.look_at(focus, Vector3.UP)


func _combined_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is VisualInstance3D:
			var b: AABB = (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
		for child in n.get_children():
			stack.append(child)
	return result


func _refresh() -> void:
	for i in range(_rows.size()):
		var mark: Label = _rows[i]["mark"]
		if mark != null:
			mark.text = ("SELECTED" if i == Global.drone_preset else ("PREVIEW" if i == _pending else "")) if MenuUI.is_english() else ("ОБРАНО" if i == Global.drone_preset else ("ГЛЯНУ" if i == _pending else ""))
	if _choose != null:
		_choose.text = ("SELECTED ✓" if _pending == Global.drone_preset else "SELECT THIS DRONE") if MenuUI.is_english() else ("ОБРАНО ✓" if _pending == Global.drone_preset else "ОБРАТИ ЦЕЙ ДРОН")


func _process(delta: float) -> void:
	if _holder != null:
		if not _is_dragging_preview:
			var dyaw := delta * 0.5
			_holder.rotate_y(dyaw)
			if _pad_rotator != null:
				_pad_rotator.rotate_y(dyaw)
			if _diorama != null:
				_diorama.sync_idle_spin(dyaw)
		for m in _holder.get_children():
			if m is Node3D:
				DroneCatalog.animate_propellers(m as Node3D, delta)
	if _diorama != null:
		_diorama.step(delta)


func _go_back() -> void:
	# The hangar is opened from the fleet panel of MainMenu; returning to the
	# intro clip looked like the selection was discarded.  Go back where the
	# player came from so the new craft/mode is immediately visible.
	if OS.has_feature("mobile"):
		get_tree().change_scene_to_file("res://GUI/mobile/MobileMenu.tscn")
		return
	get_tree().change_scene_to_file(MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_go_back()
