extends Label


enum Status {DISARMED, ARMED, LAUNCH, TURTLE, RECOVERY}


var status: int = Status.DISARMED: set = set_status
var message_timer := Timer.new()


func _ready() -> void:
	add_child(message_timer)
	message_timer.one_shot = true
	var _discard = message_timer.connect("timeout", Callable(self, "_on_message_timer_timeout"))
	
	set_message("ДВИГУНИ ВИМКНЕНО")


func set_status(s: int) -> void:
	if s < Status.size():
		status = s
		var status_text := ""
		match status:
			Status.DISARMED:
				status_text = "ДВИГУНИ ВИМКНЕНО  (ПРОБІЛ — увімкнути)"
			Status.ARMED:
				status_text = "ДВИГУНИ УВІМКНЕНО — ГАЗ УГОРУ"
				message_timer.start(1.0)
			Status.LAUNCH:
				status_text = "ЗАПУСК"
			Status.TURTLE:
				status_text = "ПЕРЕВЕРНУТО"
			Status.RECOVERY:
				status_text = "АВТОВІДНОВЛЕННЯ"
		if status != Status.ARMED and not message_timer.is_stopped():
			message_timer.stop()
		set_message(status_text)


func set_message(msg: String = "") -> void:
	text = "\n\n\n\n\n\n\n%s" % msg


func clear_message() -> void:
	set_message()


func _on_message_timer_timeout() -> void:
	clear_message()
	if status == Status.DISARMED:
		set_status(Status.DISARMED)


func _on_armed(mode: int) -> void:
	match mode:
		FlightController.FlightMode.TURTLE:
			self.status = Status.TURTLE
		FlightController.FlightMode.LAUNCH:
			self.status = Status.LAUNCH
		_:
			self.status = Status.ARMED


func _on_disarmed() -> void:
	self.status = Status.DISARMED


func _on_arm_failed(reason) -> void:
	var reason_msg := ""
	var r_str := str(reason)
	if r_str == str(FlightController.ArmFail.THROTTLE_HIGH) or r_str == "THROTTLE_NOT_LOW" or r_str == "THROTTLE_HIGH":
		reason_msg = "ГАЗ НЕ В НУЛІ — ОПУСТІТЬ ГАЗ"
	elif r_str == str(FlightController.ArmFail.CRASH_RECOVERY_MODE) or r_str == "CRASH_RECOVERY_MODE":
		reason_msg = "РЕЖИМ ВІДНОВЛЕННЯ"
	else:
		reason_msg = "ОПУСТІТЬ ГАЗ, ЩОБ УВІМКНУТИ ДВИГУНИ"
	set_message("*** %s ***" % reason_msg)
	message_timer.start(2.0)


func _on_mode_changed(mode: int) -> void:
	if status == Status.DISARMED:
		return
	if mode != FlightController.FlightMode.TURTLE and mode != FlightController.FlightMode.LAUNCH \
			and (status == Status.TURTLE or status == Status.LAUNCH):
		clear_message()
	elif mode == FlightController.FlightMode.AUTO:
		self.status = Status.RECOVERY
	else:
		clear_message()
