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
	get_tree().quit()
