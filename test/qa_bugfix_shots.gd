extends Node

## Real-GPU visual capture of the reported bug areas after the fixes.
## Run windowed (headless viewports cannot read back pixels):
##   Godot --windowed --path . res://test/qa_bugfix_shots.tscn
## Output: res://qa_shots/bugs/fixed/*.png

const LevelScene := preload("res://sceneries/BigLevel.tscn")
const VillageScene := preload("res://sceneries/VillageLevel.tscn")
const MENU := preload("res://GUI/mobile/MobileMenu.tscn")
const OUT_DIR := "res://qa_shots/bugs/fixed"

var _saved_mode := 0
var _saved_special := 0
var _saved_fiber := false


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	call_deferred("_run")


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		print("[BUGFIX_SHOTS] FAIL no image for ", name)
		return
	var err := img.save_png(OUT_DIR.path_join(name))
	print("[BUGFIX_SHOTS] ", name, " size=", img.get_size(), " err=", err)


func _hide_hud(level: Node) -> void:
	for n in level.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false


func _free_level(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	level.queue_free()
	await get_tree().create_timer(0.4).timeout


func _spawn_level(packed: PackedScene) -> Node3D:
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(5.0).timeout
	return level


func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_saved_mode = Global.play_mode
	_saved_special = Global.special_mission
	_saved_fiber = bool(Global.menu_settings.get("fiber_optic_mode", false))

	# --- tutorial: grass carpet + fiber-optic cable ---------------------
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.special_mission = 0
	Global.drone_preset = 0
	Global.menu_settings["fiber_optic_mode"] = true
	var level := await _spawn_level(LevelScene)
	_hide_hud(level)

	var qa_cam := Camera3D.new()
	qa_cam.name = "QAShotCamera"
	qa_cam.fov = 70.0
	qa_cam.far = 3200.0
	level.add_child(qa_cam)
	qa_cam.global_position = Vector3(-112.0, 14.0, 122.0)
	qa_cam.look_at(Vector3(-127.0, 8.2, 137.0), Vector3.UP)
	qa_cam.current = true
	await get_tree().create_timer(0.5).timeout
	await _shot("01_grass_grounded.png")

	var drone := level.get_node_or_null("Drone") as Drone
	if drone != null:
		drone.freeze = true
		drone.global_position = Vector3(0.0, 12.0, 18.0)
		drone.rotation = Vector3(0.0, deg_to_rad(-35.0), 0.0)
		qa_cam.global_position = Vector3(-9.0, 15.5, 27.0)
		qa_cam.look_at(Vector3(0.0, 11.6, 18.0), Vector3.UP)
		await get_tree().create_timer(0.8).timeout
		await _shot("02_fiber_cable.png")
	await _free_level(level)

	# --- escort convoy --------------------------------------------------
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 2
	Global.drone_preset = 2
	var village := await _spawn_level(VillageScene)
	_hide_hud(village)
	var convoy := village.get("_special_convoy") as Node3D
	if convoy != null:
		qa_cam = Camera3D.new()
		qa_cam.fov = 65.0
		qa_cam.far = 3000.0
		village.add_child(qa_cam)
		var behind := convoy.global_transform.basis.z
		qa_cam.global_position = convoy.global_position + behind * 15.0 + Vector3.UP * 7.0
		qa_cam.look_at(convoy.global_position + Vector3.UP * 1.2, Vector3.UP)
		qa_cam.current = true
		await get_tree().create_timer(0.5).timeout
		await _shot("03_convoy_escort.png")
	await _free_level(village)

	# --- DVR replay with real captured frames ---------------------------
	Global.special_mission = 0
	Global.combat_mission = 1
	Global.drone_preset = 0
	Global.menu_settings["fiber_optic_mode"] = false
	var combat := await _spawn_level(LevelScene)
	var c_drone := combat.get_node_or_null("Drone") as Drone
	if c_drone != null:
		c_drone.freeze = true
		c_drone.global_position = Vector3(0.0, 42.0, 96.0)
		c_drone.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
		var fc = c_drone.flight_controller
		if fc != null:
			fc.call("request_arm")
		await get_tree().create_timer(1.8).timeout
	var frames: Array = combat.get("_dvr_frames")
	print("[BUGFIX_SHOTS] DVR frames captured=", frames.size() if frames != null else -1)
	var results: Control = combat.get("_results")
	if results != null:
		results.visible = true
	combat.call("_on_dvr_replay_pressed")
	await get_tree().create_timer(0.45).timeout
	await _shot("04_dvr_replay.png")
	var wait_start := Time.get_ticks_msec()
	while bool(combat.get("_dvr_replaying")) and Time.get_ticks_msec() - wait_start < 20000:
		await get_tree().create_timer(0.1).timeout
	await _free_level(combat)

	# --- mobile hangar: props motion and drag-to-scroll -----------------
	Global.play_mode = Global.PlayMode.TUTORIAL
	Global.drone_preset = 0
	var menu := MENU.instantiate()
	add_child(menu)
	await get_tree().create_timer(0.8).timeout
	menu.call("_show", "drone")
	await get_tree().create_timer(0.5).timeout
	await _shot("05_hangar_top.png")
	await get_tree().create_timer(0.25).timeout
	await _shot("06_hangar_props_moved.png")
	var scroll: ScrollContainer = menu.get("_hangar_scroll")
	if scroll != null:
		var bar := scroll.get_v_scroll_bar()
		scroll.scroll_vertical = int(bar.max_value)
		print("[BUGFIX_SHOTS] hangar scroll=", scroll.scroll_vertical,
				" max=", bar.max_value, " page=", bar.page)
		await get_tree().create_timer(0.4).timeout
		await _shot("07_hangar_scrolled_bottom.png")
	menu.queue_free()

	Global.menu_settings["fiber_optic_mode"] = _saved_fiber
	Global.play_mode = _saved_mode
	Global.special_mission = _saved_special
	print("[BUGFIX_SHOTS] done -> ", ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)
