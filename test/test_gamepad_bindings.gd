extends Node

## Verifies that every flight/tutorial action has the promised gamepad button,
## not merely "some" joypad event.

const EXPECTED := {
	"toggle_arm": 8,        # RS
	"arm": 8,
	"respawn": 9,           # LB
	"pause_menu": 4,        # Back
	"cycle_flight_modes": 0, # A
	"deploy_payload": 2,    # X
	"activate_payload": 3,  # Y
	"altitude_hold": 7,     # LS
	"tutorial_help": 6,     # Start
	"tutorial_retry": 1,    # B
	"toggle_fpv_effects": 15, # MISC1 / extra
}


func _ready() -> void:
	var missing: Array[String] = []
	var wrong: Array[String] = []
	for action in EXPECTED:
		if not InputMap.has_action(action):
			missing.append(action + " (no action)")
			continue
		var expected: int = int(EXPECTED[action])
		var found := false
		var buttons: Array[int] = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton:
				buttons.append(ev.button_index)
				if ev.button_index == expected:
					found = true
		if not found:
			wrong.append("%s expected=%d got=%s" % [action, expected, str(buttons)])
		print("[PAD] %-20s expected=%d got=%s" % [action, expected, str(buttons)])
	if missing.is_empty() and wrong.is_empty():
		print("[PAD] RESULT PASS — core pad map is coherent")
		get_tree().quit(0)
	else:
		print("[PAD] RESULT FAIL — missing: ", missing, " wrong: ", wrong)
		get_tree().quit(1)
