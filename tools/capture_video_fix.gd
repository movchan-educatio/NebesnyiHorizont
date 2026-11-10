extends Node

## Captures the post-fix mobile screens used in the IMG_6820 report.
## Run with MOBILE_UI=1 (the SubViewport emulates the phone canvas).

const OUT := "C:/Users/USER_UA/Desktop/GodotDrone_LOWSPEC/docs/ios/v22_fix"


func _ready() -> void:
	call_deferred("_run")


func _save(vp: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(OUT)
	var path := OUT.path_join(name)
	var err := img.save_png(path)
	print("[FIXSHOT] ", path, " ", img.get_size(), " err=", err)


func _make_vp(w: int, h: int, base_w: int, base_h: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.size_2d_override = Vector2i(base_w, base_h)
	vp.size_2d_override_stretch = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	return vp


func _run() -> void:
	var global := get_node_or_null("/root/Global")
	if global != null:
		global.set("drone_preset", 6)

	for spec in [[1280, 592, 2340, 1080, "1280"], [2340, 1080, 2340, 1080, "2340"]]:
		var vp := _make_vp(int(spec[0]), int(spec[1]), int(spec[2]), int(spec[3]))
		var menu = load("res://GUI/mobile/MobileMenu.tscn").instantiate()
		vp.add_child(menu)
		await get_tree().create_timer(0.8).timeout
		menu.call("_load_hero_model", 6)
		menu.set("_hangar_preview_idx", 6)
		menu.call("_on_hangar_choose_pressed")
		menu.call("_load_hangar_model", 6)
		await get_tree().create_timer(1.6).timeout
		await _save(vp, "main_" + str(spec[4]) + ".png")
		menu.call("_show", "drone")
		await get_tree().create_timer(0.9).timeout
		await _save(vp, "hangar_" + str(spec[4]) + ".png")
		menu.queue_free()
		await get_tree().process_frame

		var pause = load("res://GUI/PauseMenu.tscn").instantiate()
		vp.add_child(pause)
		await get_tree().create_timer(0.8).timeout
		await _save(vp, "pause_" + str(spec[4]) + ".png")
		pause.queue_free()
		vp.queue_free()
		await get_tree().process_frame

		# Flight HUD stick monitor: prove the noisy captions are gone.
		var hud_vp := _make_vp(int(spec[0]), int(spec[1]), int(spec[2]), int(spec[3]))
		var bg := ColorRect.new()
		bg.color = Color(0.30, 0.22, 0.15)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_vp.add_child(bg)
		var left: Control = load("res://HUD/HUDStickInput.tscn").instantiate()
		var right: Control = load("res://HUD/HUDStickInput.tscn").instantiate()
		left.name = "StickMonitorLeft"
		right.name = "StickMonitorRight"
		hud_vp.add_child(left)
		hud_vp.add_child(right)
		left.position = Vector2(int(spec[2]) * 0.32, int(spec[3]) * 0.58)
		right.position = Vector2(int(spec[2]) * 0.58, int(spec[3]) * 0.58)
		left.scale = Vector2(1.8, 1.8)
		right.scale = Vector2(1.8, 1.8)
		left.call("update_stick_input", Vector2(0.35, 0.2))
		right.call("update_stick_input", Vector2(-0.25, 0.15))
		await get_tree().create_timer(0.2).timeout
		await _save(hud_vp, "hud_sticks_" + str(spec[4]) + ".png")
		hud_vp.queue_free()
		await get_tree().process_frame
	get_tree().quit()
