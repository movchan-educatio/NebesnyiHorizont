extends Control


@onready var title := $PanelContainer/VBoxContainer/Title
@onready var label_action := $PanelContainer/VBoxContainer/LabelAction

var calibration_step := -1
var device := 0
var axes := []
var throttle := []
var yaw := []
var pitch := []
var roll := []

var calibration_finished := false
var packed_popup := load("res://GUI/ConfirmationPopup.tscn")
var display_popup := false

signal calibration_step_changed
signal calibration_done
signal back


func _ready() -> void:
	var _discard = $PanelContainer/VBoxContainer/ButtonCancel.connect("pressed", Callable(self, "_on_cancel_pressed"))
	_discard = connect("calibration_done", Callable(self, "_on_calibration_done"))
	
	reset_calibration()


func _process(_delta: float) -> void:
	var next_step_ready := true
	if calibration_step == 0 and axes.size() == 4:
		for i in range(4):
			if abs(Input.get_joy_axis(device, i)) < 0.5:
				next_step_ready = false
				break
	elif calibration_step == 1:
		for i in range(4):
			if abs(Input.get_joy_axis(device, i)) > 0.2:
				next_step_ready = false
				break
	else:
		next_step_ready = false
	if next_step_ready:
		go_to_next_step()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		if calibration_step == 0:
			if abs(event.axis_value) > 0.9:
				if axes.size() == 0:
					device = event.device
					title.text = "Calibrating %s..." % [Input.get_joy_name(device)]
				elif event.device != device and !display_popup:
					display_popup = true
					var popup: Control = packed_popup.instantiate()
					add_child(popup)
					popup.set_text("Please input axes from %s." % [Input.get_joy_name(device)])
					popup.set_buttons("OK")
					popup.show_modal(true)
					await popup.validated
					popup.queue_free()
					display_popup = false
				if axes.find(event.axis) < 0:
					axes.append(event.axis)
		elif calibration_step == 2:
			# Throttle axis
			if axes.find(event.axis) >= 0 and abs(event.axis_value) > 0.9:
				throttle.append(event.axis)
				throttle.append(event)
				go_to_next_step()
		elif calibration_step == 3:
			if event.axis == throttle[0]:
				if abs(event.axis_value + throttle[1].axis_value) < 0.2:
					throttle.append(event)
					go_to_next_step()
		elif calibration_step == 4:
			if event.axis == throttle[0] and abs(event.axis_value) < 0.2:
				go_to_next_step()
		elif calibration_step == 5:
			# Yaw axis
			if axes.find(event.axis) >= 0 and abs(event.axis_value) > 0.9:
				yaw.append(event.axis)
				yaw.append(event)
				go_to_next_step()
		elif calibration_step == 6:
			if event.axis == yaw[0]:
				if abs(event.axis_value + yaw[1].axis_value) < 0.2:
					yaw.append(event)
					go_to_next_step()
		elif calibration_step == 7:
			if event.axis == yaw[0] and abs(event.axis_value) < 0.2:
				go_to_next_step()
		elif calibration_step == 8:
			# Pitch axis
			if axes.find(event.axis) >= 0 and abs(event.axis_value) > 0.9:
				pitch.append(event.axis)
				pitch.append(event)
				go_to_next_step()
		elif calibration_step == 9:
			if event.axis == pitch[0]:
				if abs(event.axis_value + pitch[1].axis_value) < 0.2:
					pitch.append(event)
					go_to_next_step()
		elif calibration_step == 10:
			if event.axis == pitch[0] and abs(event.axis_value) < 0.2:
				go_to_next_step()
		elif calibration_step == 11:
			# Roll axis
			if axes.find(event.axis) >= 0 and abs(event.axis_value) > 0.9:
				roll.append(event.axis)
				roll.append(event)
				go_to_next_step()
		elif calibration_step == 12:
			if event.axis == roll[0]:
				if abs(event.axis_value + roll[1].axis_value) < 0.2:
					roll.append(event)
					go_to_next_step()
		elif calibration_step == 13:
			if event.axis == roll[0] and abs(event.axis_value) < 0.2:
				go_to_next_step()
	elif event.is_action("ui_cancel") and event.is_pressed() and not event.is_echo():
		accept_event()
		emit_signal("back")


func go_to_next_step() -> void:
	calibration_step += 1
	emit_signal("calibration_step_changed", calibration_step)
	
	match calibration_step:
		0:
			label_action.text = "Move sticks to corners"
		1:
			label_action.text = "Center sticks"
		2:
			label_action.text = "Move throttle up"
		3:
			label_action.text = "Move throttle down"
		4:
			label_action.text = "Center throttle"
		5:
			label_action.text = "Move yaw left"
		6:
			label_action.text = "Move yaw right"
		7:
			label_action.text = "Center yaw"
		8:
			label_action.text = "Move pitch up"
		9:
			label_action.text = "Move pitch down"
		10:
			label_action.text = "Center pitch"
		11:
			label_action.text = "Move roll left"
		12:
			label_action.text = "Move roll right"
		13:
			label_action.text = "Center roll"
		_:
			label_action.text = "Calibration successful"
			emit_signal("calibration_done")


func _on_calibration_done() -> void:
	calibration_finished = true
	if throttle.size() < 3 or yaw.size() < 3 or pitch.size() < 3 or roll.size() < 3:
		calibration_finished = false
		return
	var used := {}
	for pair in [["throttle", throttle], ["yaw", yaw], ["pitch", pitch], ["roll", roll]]:
		var axis := int(pair[1][0])
		if used.has(axis):
			calibration_finished = false
			return
		used[axis] = pair[0]
	Controls.active_device = device
	Controls.active_controller_guid = Input.get_joy_guid(device)
	# The wizard captures both ends of each axis, so these are the actual
	# positive-direction samples (throttle up, yaw right, pitch up, roll right).
	Controls.apply_stick("throttle", throttle[1].axis, throttle[1].axis_value)
	Controls.apply_stick("yaw", yaw[2].axis, yaw[2].axis_value)
	Controls.apply_stick("pitch", pitch[1].axis, pitch[1].axis_value)
	Controls.apply_stick("roll", roll[2].axis, roll[2].axis_value)
	Controls.save_bindings()

	await get_tree().create_timer(2.0).timeout
	emit_signal("back")


func reset_calibration() -> void:
	calibration_finished = false
	calibration_step = -1
	axes.clear()
	throttle.clear()
	yaw.clear()
	pitch.clear()
	roll.clear()
	go_to_next_step()


func _on_cancel_pressed() -> void:
	reset_calibration()
	emit_signal("back")
