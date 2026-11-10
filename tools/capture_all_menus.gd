extends Node

const OUT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/e18dc734-8d47-468b-9855-6a7c4a7c4253"

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1920, 887))
	get_viewport().size = Vector2i(1920, 887)
	await get_tree().process_frame
	await get_tree().process_frame

	var mobile_scene = load("res://GUI/mobile/MobileMenu.tscn")
	if mobile_scene == null:
		print("[CAPTURE] Failed to load MobileMenu.tscn")
		get_tree().quit(1)
		return

	var mobile_inst = mobile_scene.instantiate()
	add_child(mobile_inst)

	if Global.startup:
		Global.initialize()

	var screens: Array[String] = [
		"main",
		"play",
		"controls",
		"rates",
		"drone",
		"settings"
	]

	for s: String in screens:
		if mobile_inst.has_method("_show"):
			mobile_inst.call("_show", s)

		for f in range(25):
			await get_tree().process_frame
			if mobile_inst.has_method("_process"):
				mobile_inst.call("_process", 1.0 / 60.0)

		await RenderingServer.frame_post_draw

		var img: Image = get_viewport().get_texture().get_image()
		var out_path: String = OUT_DIR + "/shot_mobile_" + s + ".png"
		var err: Error = img.save_png(out_path)
		print("[CAPTURE] Screen '", s, "' -> ", out_path, " (err=", err, ")")

		# If main screen, also capture specific drone presets to verify pedestal fit!
		if s == "main":
			var test_presets := [3, 8, 9, 14] # 3: VTOL «ПІСЮН», Falcon-X, Quad-5, Furia
			for p_idx: int in test_presets:
				Global.drone_preset = p_idx
				if mobile_inst.has_method("_load_hero_model"):
					mobile_inst.call("_load_hero_model", p_idx)
				for f in range(20):
					await get_tree().process_frame
					if mobile_inst.has_method("_process"):
						mobile_inst.call("_process", 1.0 / 60.0)
				await RenderingServer.frame_post_draw
				var d_img: Image = get_viewport().get_texture().get_image()
				var d_out: String = OUT_DIR + "/shot_mobile_hero_preset_" + str(p_idx) + ".png"
				d_img.save_png(d_out)
				print("[CAPTURE] Hero Preset ", p_idx, " -> ", d_out)
			# Reset back to default
			Global.drone_preset = 0
			if mobile_inst.has_method("_load_hero_model"):
				mobile_inst.call("_load_hero_model", 0)

		# If drone screen, also capture VTOL (preset 3) in hangar!
		if s == "drone":
			if mobile_inst.has_method("_select_hangar_drone"):
				mobile_inst.call("_select_hangar_drone", 3)
			for f in range(25):
				await get_tree().process_frame
				if mobile_inst.has_method("_process"):
					mobile_inst.call("_process", 1.0 / 60.0)
			await RenderingServer.frame_post_draw
			var vtol_h_img: Image = get_viewport().get_texture().get_image()
			vtol_h_img.save_png(OUT_DIR + "/shot_mobile_drone_vtol.png")
			print("[CAPTURE] Hangar VTOL -> ", OUT_DIR + "/shot_mobile_drone_vtol.png")

		# If settings, also capture all 4 tabs!
		if s == "settings":
			var tabs: Array[String] = ["sim", "hud", "gfx", "sys"]
			for t_name: String in tabs:
				mobile_inst.set("_settings_tab", t_name)
				if mobile_inst.has_method("_switch_settings_tab"):
					mobile_inst.call("_switch_settings_tab")
				for f in range(15):
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var tab_img: Image = get_viewport().get_texture().get_image()
				var tab_out: String = OUT_DIR + "/shot_mobile_settings_" + t_name + ".png"
				tab_img.save_png(tab_out)
				print("[CAPTURE] Settings Tab '", t_name, "' -> ", tab_out)

	mobile_inst.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var pause_scene = load("res://GUI/PauseMenu.tscn")
	if pause_scene != null:
		var pause_inst = pause_scene.instantiate()
		add_child(pause_inst)
		if pause_inst.has_method("show_menu"):
			pause_inst.call("show_menu", true)
		for f in range(20):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_pause: Image = get_viewport().get_texture().get_image()
		var out_pause: String = OUT_DIR + "/shot_pause_menu.png"
		img_pause.save_png(out_pause)
		print("[CAPTURE] Pause Menu -> ", out_pause)
		pause_inst.queue_free()

	DisplayServer.window_set_size(Vector2i(1920, 1080))
	get_viewport().size = Vector2i(1920, 1080)
	var start_scene = load("res://GUI/StartScreen.tscn")
	if start_scene != null:
		var start_inst = start_scene.instantiate()
		add_child(start_inst)
		for f in range(30):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img_start: Image = get_viewport().get_texture().get_image()
		var out_start: String = OUT_DIR + "/shot_desktop_start.png"
		var err_start: Error = img_start.save_png(out_start)
		print("[CAPTURE] Desktop Start -> ", out_start, " (err=", err_start, ")")
		start_inst.queue_free()

	print("[CAPTURE] ALL MENUS CAPTURED SUCCESSFULLY")
	get_tree().quit(0)
