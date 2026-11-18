extends Node

## Regression for the mobile hangar list.  The 13-drone roster used to be laid
## out as a plain vertical box with no ScrollContainer, so on a short phone
## screen half the drones were unreachable.  The list must own a vertical
## ScrollContainer and respond to touch drags that start on a drone row.

const MENU := preload("res://GUI/mobile/MobileMenu.tscn")
const TEST := "HANGAR_SCROLL"

var _failures := 0
var _had_mobile := false
var _saved_mobile := ""


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	print("[", TEST, "] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_failures += 1


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	return event


func _drag(index: int, pos: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	return event


func _run() -> void:
	_had_mobile = OS.has_environment("MOBILE_UI")
	_saved_mobile = OS.get_environment("MOBILE_UI")
	OS.set_environment("MOBILE_UI", "1")
	var menu := MENU.instantiate()
	add_child(menu)
	for i in range(20):
		await get_tree().process_frame
	menu.call("_show", "drone")
	for i in range(5):
		await get_tree().process_frame

	var scroll: ScrollContainer = menu.get("_hangar_scroll")
	var list: VBoxContainer = menu.get("_hangar_list_container")
	_check(scroll != null, "hangar owns a ScrollContainer")
	_check(list != null and list.get_child_count() >= DroneCatalog.count(),
			"all catalogue drones are built into the list")
	if scroll == null or list == null:
		_finish(menu)
		return
	_check(scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO,
			"hangar list enables vertical scrolling")
	_check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
			"hangar list locks horizontal scrolling")
	var rows_focusable := 0
	for row in list.get_children():
		if row is Button and (row as Button).focus_mode != Control.FOCUS_NONE:
			rows_focusable += 1
	_check(rows_focusable == 0, "drone rows never steal focus from the scroll list")

	# Phone-sized content overflows the card; add a spacer so the range check
	# is deterministic even in a 1080p headless window.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 900.0)
	list.add_child(spacer)
	for i in range(4):
		await get_tree().process_frame
	var bar := scroll.get_v_scroll_bar()
	_check(bar.max_value > bar.page, "hangar roster exceeds the visible card height")
	scroll.scroll_vertical = 0
	var before := scroll.scroll_vertical

	# A swipe that starts on a row must scroll the list and be remembered as a
	# gesture, so releasing it cannot select the drone under the finger.
	menu.call("_on_hangar_scroll_gui_input", _touch(0, true, Vector2(120, 260)), scroll)
	menu.call("_on_hangar_scroll_gui_input", _drag(0, Vector2(120, 140), Vector2(0, -120)), scroll)
	await get_tree().process_frame
	_check(scroll.scroll_vertical >= before + 100,
			"upward touch drag scrolls the hangar list")
	_check(float(menu.get("_hangar_scroll_drag_dist")) > 12.0,
			"a swipe is tagged as a scroll gesture, not a drone tap")

	menu.call("_on_hangar_scroll_gui_input", _touch(0, false, Vector2(120, 140)), scroll)
	_check(not bool(menu.get("_hangar_scroll_dragging")),
			"finger release clears the drag state")
	menu.call("_on_hangar_scroll_gui_input", _touch(1, true, Vector2(120, 260)), scroll)
	_check(absf(float(menu.get("_hangar_scroll_drag_dist"))) < 0.01,
			"a fresh press resets the gesture distance for the next tap")

	# Mouse drags cover the desktop/web build of the same menu.
	scroll.scroll_vertical = 0
	before = scroll.scroll_vertical
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(120, 260)
	menu.call("_on_hangar_scroll_gui_input", press, scroll)
	var move := InputEventMouseMotion.new()
	move.position = Vector2(120, 140)
	move.relative = Vector2(0, -90)
	menu.call("_on_hangar_scroll_gui_input", move, scroll)
	await get_tree().process_frame
	_check(scroll.scroll_vertical >= before + 70,
			"mouse drag scrolls the hangar list on desktop")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(120, 140)
	menu.call("_on_hangar_scroll_gui_input", release, scroll)
	_check(not bool(menu.get("_hangar_scroll_dragging")),
			"mouse release clears the drag state")

	_finish(menu)


func _finish(menu: Node) -> void:
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
		await get_tree().process_frame
	if _had_mobile:
		OS.set_environment("MOBILE_UI", _saved_mobile)
	else:
		OS.unset_environment("MOBILE_UI")
	print("[", TEST, "] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
