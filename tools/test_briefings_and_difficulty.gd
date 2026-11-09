extends Node

func _ready() -> void:
	print("=== STARTING CAMPAIGN BRIEFINGS & DIFFICULTY TESTS ===")
	
	# 1. Instantiate MainMenu
	var packed := load("res://GUI/MainMenu.tscn") as PackedScene
	assert(packed != null, "Failed to load MainMenu.tscn")
	var menu = packed.instantiate()
	add_child(menu)
	
	await get_tree().process_frame
	await get_tree().process_frame
	
	# 2. Test Difficulty Switching
	print("[TEST] Testing difficulty settings...")
	menu._select_diff(Global.Difficulty.RECRUIT)
	assert(Global.difficulty == Global.Difficulty.RECRUIT, "Expected RECRUIT")
	assert(is_equal_approx(Global.get_difficulty_time_limit(), 1500.0), "Expected 1500s (25 min)")
	assert(is_equal_approx(Global.get_difficulty_wind_scale(), 0.45), "Expected 0.45 wind")
	assert(is_equal_approx(Global.get_difficulty_score_multiplier(), 1.0), "Expected 1.0 score mult")
	
	menu._select_diff(Global.Difficulty.OPERATOR)
	assert(Global.difficulty == Global.Difficulty.OPERATOR, "Expected OPERATOR")
	assert(is_equal_approx(Global.get_difficulty_time_limit(), 1200.0), "Expected 1200s (20 min)")
	assert(is_equal_approx(Global.get_difficulty_wind_scale(), 1.0), "Expected 1.0 wind")
	assert(is_equal_approx(Global.get_difficulty_score_multiplier(), 1.25), "Expected 1.25 score mult")
	
	menu._select_diff(Global.Difficulty.ACE)
	assert(Global.difficulty == Global.Difficulty.ACE, "Expected ACE")
	assert(is_equal_approx(Global.get_difficulty_time_limit(), 900.0), "Expected 900s (15 min)")
	assert(is_equal_approx(Global.get_difficulty_wind_scale(), 1.45), "Expected 1.45 wind")
	assert(is_equal_approx(Global.get_difficulty_score_multiplier(), 1.75), "Expected 1.75 score mult")
	print("  -> Difficulty mechanics: PASS")
	
	# Reset to OPERATOR
	menu._select_diff(Global.Difficulty.OPERATOR)
	
	# 3. Test Campaign Records & Rewards
	print("[TEST] Testing campaign records & medals...")
	var rec := Global.record_mission_result(1, 1850, 192.5, Global.Difficulty.ACE)
	assert(rec.get("completed", false) == true, "Expected mission 1 to be completed")
	assert(int(rec.get("stars", 0)) == 3, "Expected 3 stars for ACE completion")
	assert(int(rec.get("best_score", 0)) >= 1850, "Expected best_score >= 1850")
	
	menu._update_selection_ui()
	var code_lbl: Label = menu._mission_code_labels.get(1)
	assert(code_lbl != null, "Expected mission 1 code label")
	assert(code_lbl.text.contains("★★★"), "Expected 3 stars on mission 1 button label, got: " + code_lbl.text)
	print("  -> Campaign progression & awards: PASS")
	
	# 4. Test Briefing Modal for all 5 missions
	print("[TEST] Testing briefing modal for TAC-01..TAC-05...")
	var vp := get_viewport()
	var out_dir := "C:/Users/USER_UA/.gemini/antigravity/brain/ee388256-6605-4a1e-9395-d4a4f9ddcf71"
	
	for mid in [1, 2, 3, 4, 5]:
		menu._open_briefing_dialog(mid)
		assert(menu._briefing_modal.visible == true, "Briefing modal should be visible")
		assert(menu._briefing_title_lbl.text.contains("TAC-0%d" % mid), "Briefing title should contain mission code")
		assert(not menu._briefing_intel_lbl.text.is_empty(), "Briefing intel text should not be empty")
		assert(menu._briefing_tasks_vbox.get_child_count() > 0, "Briefing tasks should have items")
		assert(not menu._briefing_threats_lbl.text.is_empty(), "Threats should not be empty")
		assert(not menu._briefing_drone_lbl.text.is_empty(), "Drone recommendation should not be empty")
		
		# Let it render
		for f in range(5):
			await get_tree().process_frame
			
		if mid in [1, 2, 5]:
			var img := vp.get_texture().get_image()
			var pth := "%s/menu_briefing_tac0%d.png" % [out_dir, mid]
			img.save_png(pth)
			print("  -> Captured briefing screenshot for TAC-0%d: %s" % [mid, pth])
			
		menu._close_briefing_dialog()
		assert(menu._briefing_modal.visible == false, "Briefing modal should close")
		
	# Capture main menu overview with quick diff selector and mission stars
	menu._update_selection_ui()
	for f in range(5):
		await get_tree().process_frame
	var main_img := vp.get_texture().get_image()
	var main_pth := "%s/menu_tactical_main.png" % out_dir
	main_img.save_png(main_pth)
	print("  -> Captured tactical main menu overview: %s" % main_pth)

	# 5. Test Flight School mode selection in MainMenu
	print("[TEST] Testing Flight School selection in MainMenu...")
	menu._select_mode(Global.PlayMode.TUTORIAL)
	assert(menu._selected_mode == Global.PlayMode.TUTORIAL, "Expected TUTORIAL mode selected")
	assert(menu._map_title_lbl.text.contains("ШКОЛА ПІЛОТА"), "Map title should mention Flight School")
	assert(menu._launch_btn.text.contains("КУРС ПІЛОТА"), "Launch button should say КУРС ПІЛОТА")
	for f in range(5):
		await get_tree().process_frame
	var tut_menu_img := vp.get_texture().get_image()
	var tut_menu_pth := "%s/menu_flight_school_selected.png" % out_dir
	tut_menu_img.save_png(tut_menu_pth)
	print("  -> Captured Flight School menu overview: %s" % tut_menu_pth)

	print("=== [BRIEFINGS-TEST] ALL TESTS PASSED! ===")
	get_tree().quit(0)
