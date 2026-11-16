extends Node

## Exercises custom touch positions, shared UI scale, normalized resize behavior,
## and settings persistence without leaving test values in the player's profile.

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved_settings: Dictionary = Global.menu_settings.duplicate(true)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var controls := get_node_or_null("/root/TouchControls")
	if controls == null:
		push_error("[TOUCH_LAYOUT] TouchControls autoload missing")
		get_tree().quit(1)
		return
	controls.call("set_enabled", true)
	controls.set("touch_mode", true)
	controls.call("_layout")
	var original_radius := float(controls.get("_radius"))
	controls.call("_on_layout_edit_pressed")
	_check(bool(controls.get("_layout_editing")), "layout editor opens")
	var toolbar := controls.get("_layout_toolbar") as Control
	print("[TOUCH_LAYOUT] toolbar rect=", toolbar.get_global_rect(),
			" anchors=", toolbar.anchor_left, ",", toolbar.anchor_top, ",",
			toolbar.anchor_right, ",", toolbar.anchor_bottom,
			" min=", toolbar.get_combined_minimum_size(),
			" vp=", get_viewport().get_visible_rect().size,
			" child=", toolbar.get_child(0).size,
			" child_min=", toolbar.get_child(0).get_combined_minimum_size())
	for item in toolbar.get_child(0).get_children():
		if item is Control:
			print("[TOUCH_LAYOUT] toolbar child ", item.name, " size=", item.size,
					" min=", (item as Control).get_combined_minimum_size())
	var start: Vector2 = controls.get("_left_center")
	var target := start + Vector2(34.0, -26.0)
	_check(bool(controls.call("_begin_layout_drag", -1, start)),
			"left stick can be grabbed for editing")
	controls.call("_move_layout_drag", target)
	controls.call("_end_layout_drag")
	var moved: Vector2 = controls.get("_left_center")
	_check(moved.distance_to(target) < 1.0, "stick moves without changing input logic")
	var positions: Dictionary = Global.menu_settings.get("touch_layout_positions", {})
	_check(positions.get("left") is Vector2, "normalized stick position is saved")
	var saved_left: Vector2 = positions.get("left", Vector2.ZERO)
	controls.call("_on_layout_scale_changed", 1.25)
	controls.call("_on_layout_scale_drag_ended", true)
	_check(float(controls.get("_radius")) > original_radius,
			"layout size scales the sticks and touch buttons")
	get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	controls.call("_layout")
	var resized_left: Vector2 = controls.get("_left_center")
	var viewport_size := Vector2(get_viewport().get_visible_rect().size)
	var resized_normalized := Vector2(resized_left.x / viewport_size.x,
			resized_left.y / viewport_size.y)
	_check(resized_normalized.distance_to(saved_left) < 0.015,
			"saved positions survive viewport resizing")
	controls.call("_on_layout_reset_pressed")
	_check(float(controls.get("_touch_ui_scale")) == 1.0,
			"reset restores scale and default positions")
	controls.call("set_enabled", false)
	controls.call("open_layout_editor", true)
	_check(bool(controls.get("_preview")) and bool(controls.get("_layout_editing")),
			"settings shortcut opens a mouse-editable layout preview")
	controls.call("_on_layout_done_pressed")
	_check(not bool(controls.get("enabled")) and not bool(controls.get("_preview")),
			"settings shortcut closes its temporary preview on Done")
	controls.call("set_enabled", true)
	controls.set("touch_mode", true)
	controls.call("_on_more_pressed")
	var layout_button := controls.get("_layout_button") as Button
	if layout_button != null:
		layout_button.emit_signal("button_down")
	_check(bool(controls.get("_layout_editing")),
			"in-flight quick options opens the layout editor")
	controls.call("_on_layout_done_pressed")
	controls.call("set_enabled", false)
	Global.menu_settings = saved_settings
	Global.save_menu_settings()
	print("[TOUCH_LAYOUT] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[TOUCH_LAYOUT] PASS ", label)
	else:
		_failures += 1
		push_error("[TOUCH_LAYOUT] FAIL " + label)
