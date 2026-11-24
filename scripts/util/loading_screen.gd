## Full-screen mission loading card shared by the main menu, the flight-school
## help page and in-game retry/next-mission transitions.
##
## The same authored battlefield photograph is used on every map and mission;
## the map / TAC / difficulty line is generated from the current selection.
class_name LoadingScreen
extends RefCounted

const BG_PATH := "res://Assets/ui/mission_loading.jpg"
const VoltThemeScript = preload("res://GUI/mobile/VoltTheme.gd")


static func build(mode: int, mission_id: int, map_name: String,
		difficulty: String = "", with_progress: bool = true) -> Dictionary:
	var is_mobile := MenuUI.is_mobile_ui()
	var layer := CanvasLayer.new()
	layer.name = "GlobalLoadingOverlay"
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuUI.theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	# Full-bleed photograph, cropped to cover without stretching.
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	root.add_child(bg)

	# Soft vignette / contrast pass so the HUD copy stays readable on every map.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.031, 0.031, 0.036, 0.34) if is_mobile else Color(0.008, 0.014, 0.011, 0.26)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var bottom_band := ColorRect.new()
	bottom_band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_band.offset_top = -250.0
	bottom_band.color = Color(0.031, 0.031, 0.036, 0.88) if is_mobile else Color(0.008, 0.014, 0.011, 0.70)
	bottom_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_band)

	# Bottom dossier.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	margin.offset_left = 58.0
	margin.offset_right = -58.0
	margin.offset_top = -220.0
	margin.offset_bottom = -34.0
	root.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)

	var context := Label.new()
	context.text = _context_line(mode, mission_id, map_name, difficulty)
	context.add_theme_font_size_override("font_size", 13)
	if is_mobile:
		context.add_theme_font_override("font", VoltThemeScript.font_mono())
		context.add_theme_color_override("font_color", VoltThemeScript.YELLOW)
	else:
		context.add_theme_color_override("font_color", MenuUI.FPV_AMBER)
	box.add_child(context)

	var title := Label.new()
	title.text = _title(mode)
	title.add_theme_font_size_override("font_size", 28 if is_mobile else 32)
	if is_mobile:
		title.add_theme_font_override("font", VoltThemeScript.font_display())
		title.add_theme_color_override("font_color", VoltThemeScript.TEXT)
		title.add_theme_constant_override("outline_size", 0)
	else:
		title.add_theme_color_override("font_color", MenuUI.FPV_TEXT)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		title.add_theme_constant_override("outline_size", 4)
	box.add_child(title)

	var bar: ProgressBar = null
	if with_progress:
		bar = ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 100.0
		bar.value = 6.0
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(760, 8 if is_mobile else 10)
		bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if is_mobile:
			bar.add_theme_stylebox_override("background",
					VoltThemeScript.panel_box(Color(0.094, 0.094, 0.114, 1.0), VoltThemeScript.BORDER, 1, 4, 0, 0, 0))
			bar.add_theme_stylebox_override("fill",
					VoltThemeScript.panel_box(VoltThemeScript.YELLOW, VoltThemeScript.YELLOW, 0, 4, 0, 0, 0))
		else:
			bar.add_theme_stylebox_override("background",
					VoltThemeScript.panel_box(Color(0.06, 0.062, 0.07, 0.94), VoltThemeScript.BORDER, 1, 4, 0, 0, 0))
			bar.add_theme_stylebox_override("fill",
					VoltThemeScript.panel_box(VoltThemeScript.YELLOW, VoltThemeScript.YELLOW, 0, 4, 0, 0, 0))
		box.add_child(bar)

	var tip := Label.new()
	tip.text = ("ПІДГОТОВКА КАРТИ, ТЕХНІКИ ТА ЦІЛЕЙ…" if not MenuUI.is_english()
			else "BUILDING TERRAIN, VEHICLES AND TARGETS…")
	tip.add_theme_font_size_override("font_size", 12)
	if is_mobile:
		tip.add_theme_font_override("font", VoltThemeScript.font_ui())
		tip.add_theme_color_override("font_color", VoltThemeScript.STONE_DIM)
	else:
		tip.add_theme_color_override("font_color", MenuUI.MUTED)
	box.add_child(tip)
	return {"layer": layer, "bar": bar}


static func _title(mode: int) -> String:
	if MenuUI.is_english():
		match mode:
			Global.PlayMode.TUTORIAL:
				return "LOADING TUTORIAL"
			Global.PlayMode.TRAINING:
				return "LOADING TRAINING"
			_:
				return "LOADING COMBAT MISSION"
	match mode:
		Global.PlayMode.TUTORIAL:
			return "ЗАВАНТАЖЕННЯ ТУТОРІАЛУ"
		Global.PlayMode.TRAINING:
			return "ЗАВАНТАЖЕННЯ ТРЕНУВАННЯ"
		_:
			return "ЗАВАНТАЖЕННЯ БОЙОВОГО РЕЖИМУ"


static func _context_line(mode: int, mission_id: int, map_name: String,
		difficulty: String) -> String:
	var map_upper := map_name.to_upper()
	var is_en := MenuUI.is_english()
	if mode == Global.PlayMode.COMBAT:
		if Global.special_mission > 0:
			var op_prefix := "OP" if is_en else "СО"
			return "%s  ·  %s-%02d: %s  ·  %s" % [
				map_upper, op_prefix, Global.special_mission,
				Global.get_special_mission_name(Global.special_mission), difficulty.to_upper()]
		return "%s  ·  TAC-0%d  ·  %s" % [map_upper, mission_id, difficulty.to_upper()]
	if mode == Global.PlayMode.TUTORIAL:
		return "%s  ·  %s" % [map_upper, "FLIGHT SCHOOL" if is_en else "ШКОЛА ПІЛОТА"]
	return "%s  ·  %s" % [map_upper, "TRAINING" if is_en else "ТРЕНУВАННЯ"]
