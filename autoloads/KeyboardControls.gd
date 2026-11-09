extends Node

## Adds keyboard bindings for the flight controls on top of the gamepad
## bindings stored in the project input map. Keyboard events are only added
## when the same key is not already bound to the action.

const KEY_BINDINGS := {
	"throttle_up": KEY_W,
	"throttle_down": KEY_S,
	"yaw_left": KEY_A,
	"yaw_right": KEY_D,
	"pitch_up": KEY_DOWN,
	"pitch_down": KEY_UP,
	"roll_left": KEY_LEFT,
	"roll_right": KEY_RIGHT,
	"respawn": KEY_R,
}


func _ready() -> void:
	ensure_bindings()


func ensure_bindings() -> void:
	for action in KEY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var keycode: int = KEY_BINDINGS[action]
		var exists := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				var key_event := event as InputEventKey
				if key_event.physical_keycode == keycode or key_event.keycode == keycode:
					exists = true
					break
		if not exists:
			var key_event := InputEventKey.new()
			key_event.keycode = keycode
			key_event.physical_keycode = keycode
			InputMap.action_add_event(action, key_event)
