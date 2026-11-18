extends Node

## Verifies the six standalone special-operation entries and that selecting one
## updates the flight-prep card without requiring a campaign mission.

func _ready() -> void:
	var packed := load("res://GUI/MainMenu.tscn") as PackedScene
	var menu: Variant = packed.instantiate()
	add_child(menu)
	for i in range(6):
		await get_tree().process_frame
	var ok := true
	if menu._special_mission_btns.size() != 10:
		printerr("[SPECIALUI] FAIL special buttons: ", menu._special_mission_btns.size())
		ok = false
	else:
		print("[SPECIALUI] PASS special buttons=10")
	menu._selected_mode = Global.PlayMode.COMBAT
	menu._selected_special = 9
	Global.special_mission = 9
	menu._update_selection_ui()
	await get_tree().process_frame
	if not String(menu._launch_btn.text).contains("ГЛИБОКИЙ ТИЛ"):
		printerr("[SPECIALUI] FAIL launch text: ", menu._launch_btn.text)
		ok = false
	else:
		print("[SPECIALUI] PASS launch text")
	if menu._briefing_btn.visible:
		printerr("[SPECIALUI] FAIL campaign briefing must be hidden for special ops")
		ok = false
	if not String(menu._campaign_progress_lbl.text).contains("СПЕЦОПЕРАЦІЯ"):
		printerr("[SPECIALUI] FAIL progress label: ", menu._campaign_progress_lbl.text)
		ok = false
	menu._selected_special = 0
	Global.special_mission = 0
	menu._update_selection_ui()
	print("[SPECIALUI] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
