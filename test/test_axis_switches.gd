extends Node


var _switch_presses := 0
var _switch_releases := 0
const TEST_ACTION := "deploy_payload"


func _ready() -> void:
	var radio := RadioController.new()
	add_child(radio)
	Controls.apply_action_binding(TEST_ACTION, ControllerAction.Type.AXIS, 5, 0.5, 1.0)
	radio.refresh_bindings()

	var motion := InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = 5
	motion.axis_value = 1.0
	radio._input(motion)
	motion.axis_value = 0.0
	radio._input(motion)
	await get_tree().process_frame

	if _switch_presses == 1 and _switch_releases == 1:
		print("[AXIS-SWITCH-TEST] PASS press/release reaches scene input handlers")
		get_tree().quit()
	else:
		push_error("Axis switch press/release was not delivered: %d/%d" % [
			_switch_presses, _switch_releases])
		get_tree().quit(1)


func _input(event: InputEvent) -> void:
	if event is InputEventAction and event.action == TEST_ACTION:
		if event.pressed:
			_switch_presses += 1
		else:
			_switch_releases += 1
