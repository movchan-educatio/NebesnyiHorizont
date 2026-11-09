extends SceneTree


func _initialize() -> void:
	InputMap.add_action("t")
	var src := InputEventJoypadButton.new()
	src.button_index = 1
	src.pressed = true
	src.device = -1
	InputMap.action_add_event("t", src)

	for dev in [0, 1, 5]:
		var probe := InputEventJoypadButton.new()
		probe.button_index = 1
		probe.pressed = true
		probe.device = dev
		print("[DEVICE] event.device=0 matches probe device ", dev, " -> ", probe.is_action("t"))

	# axis test
	InputMap.add_action("a")
	var ax := InputEventJoypadMotion.new()
	ax.axis = 1
	ax.axis_value = -1.0
	ax.device = -1
	InputMap.action_add_event("a", ax)
	for dev in [0, 1, 5]:
		var probe := InputEventJoypadMotion.new()
		probe.axis = 1
		probe.axis_value = -1.0
		probe.device = dev
		print("[DEVICE] axis event.device=0 matches probe device ", dev, " -> ", probe.is_action("a"))

	quit()
