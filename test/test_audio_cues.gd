extends Node

## Verifies the cockpit audio buses and the synthesised warning cues used by
## REB / low-LQ / SAM / kamikaze feedback.

func _ready() -> void:
	var ok := true
	for bus_name in ["Music", "Engine", "Wind", "Combat", "Radio", "Warning"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			printerr("[AUDIOCUES] FAIL missing bus ", bus_name)
			ok = false
	for kind in ["ew_enter", "ew_exit", "lq_critical", "sam_lock", "kamikaze", "incoming"]:
		var stream := CombatSfx.alert_stream(kind)
		if stream == null or stream.data.is_empty():
			printerr("[AUDIOCUES] FAIL empty alert ", kind)
			ok = false
		else:
			print("[AUDIOCUES] PASS ", kind, " bytes=", stream.data.size())
	var crackle := CombatSfx.ew_crackle_stream()
	if crackle == null or crackle.data.is_empty() or crackle.loop_mode == AudioStreamWAV.LOOP_DISABLED:
		printerr("[AUDIOCUES] FAIL EW crackle stream")
		ok = false
	else:
		print("[AUDIOCUES] PASS ew_crackle loop=", crackle.loop_mode)
	print("[AUDIOCUES] RESULT ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
