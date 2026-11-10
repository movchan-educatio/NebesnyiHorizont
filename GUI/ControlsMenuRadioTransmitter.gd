extends WorldEnvironment


enum Stick {RIGHT_VERTICAL = 1, RIGHT_HORIZONTAL, LEFT_VERTICAL, LEFT_HORIZONTAL}
enum Axis {THROTTLE, YAW, PITCH, ROLL}
enum Mode {MODE_1, MODE_2, MODE_3, MODE_4}


const MAX_ANGLE := 27.0

const STICK_BONES := {
	Stick.RIGHT_VERTICAL: "RightStickVertical",
	Stick.RIGHT_HORIZONTAL: "RightStickHorizontal",
	Stick.LEFT_VERTICAL: "LeftStickVertical",
	Stick.LEFT_HORIZONTAL: "LeftStickHorizontal",
}


var mode: int = Mode.MODE_2

var skeleton: Skeleton3D = null
var accept_input := true

var tween: Tween = null
var tween_loop := 0


func _ready() -> void:
	_ensure_skeleton()


func _ensure_skeleton() -> void:
	if skeleton != null and is_instance_valid(skeleton):
		return
	var existing = get_node_or_null("RadioTransmitter")
	if existing != null:
		skeleton = _find_skeleton(existing)
		if skeleton != null:
			return
		existing.name = "RadioTransmitter_old"
		existing.queue_free()
	var path := "res://Assets/Drones/ua_norm/radiomaster_tx12_rig.glb"
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is PackedScene:
			var node: Node = res.instantiate()
			node.name = "RadioTransmitter"
			add_child(node)
			skeleton = _find_skeleton(node)
			if skeleton != null:
				return
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_buffer(bytes, "", state) == OK:
			var node := doc.generate_scene(state)
			if node != null:
				node.name = "RadioTransmitter"
				add_child(node)
				skeleton = _find_skeleton(node)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _set_stick_pose(stick: int, axis: Vector3, angle: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		_ensure_skeleton()
	if skeleton == null:
		return
	var bone := skeleton.find_bone(str(STICK_BONES.get(stick, "")))
	if bone < 0:
		return
	# Keep the bone's rest translation: the vertical bones are offset from Root,
	# so a pure rotation transform would move their pivot to the skeleton origin.
	var pose := skeleton.get_bone_rest(bone)
	pose.basis = pose.basis.rotated(axis, angle)
	skeleton.set_bone_pose(bone, pose)


func _input(event) -> void:
	if event is InputEventJoypadMotion and accept_input:
		var stick := -1
		var axis := Vector3.ZERO
		var value := 0.0
		if event.is_action("throttle_up") or event.is_action("throttle_down"):
			stick = get_stick(Axis.THROTTLE)
			axis = Vector3.RIGHT
			value = event.get_action_strength("throttle_down") - event.get_action_strength("throttle_up")
		elif event.is_action("yaw_left") or event.is_action("yaw_right"):
			stick = get_stick(Axis.YAW)
			axis = Vector3.FORWARD
			value = event.get_action_strength("yaw_right") - event.get_action_strength("yaw_left")
		elif event.is_action("pitch_up") or event.is_action("pitch_down"):
			stick = get_stick(Axis.PITCH)
			axis = Vector3.RIGHT
			value = event.get_action_strength("pitch_up") - event.get_action_strength("pitch_down")
		elif event.is_action("roll_left") or event.is_action("roll_right"):
			stick = get_stick(Axis.ROLL)
			axis = Vector3.FORWARD
			value = event.get_action_strength("roll_right") - event.get_action_strength("roll_left")
		if stick > -1:
			_set_stick_pose(stick, axis, get_stick_angle(value))


func get_stick_angle(value: float) -> float:
	return deg_to_rad(MAX_ANGLE * value)


func get_stick(axis: int) -> int:
	match mode:
		Mode.MODE_1:
			match axis:
				Axis.THROTTLE:
					return Stick.RIGHT_VERTICAL
				Axis.YAW:
					return Stick.LEFT_HORIZONTAL
				Axis.PITCH:
					return Stick.LEFT_VERTICAL
				Axis.ROLL:
					return Stick.RIGHT_HORIZONTAL
		Mode.MODE_2:
			match axis:
				Axis.THROTTLE:
					return Stick.LEFT_VERTICAL
				Axis.YAW:
					return Stick.LEFT_HORIZONTAL
				Axis.PITCH:
					return Stick.RIGHT_VERTICAL
				Axis.ROLL:
					return Stick.RIGHT_HORIZONTAL
		Mode.MODE_3:
			match axis:
				Axis.THROTTLE:
					return Stick.RIGHT_VERTICAL
				Axis.YAW:
					return Stick.RIGHT_HORIZONTAL
				Axis.PITCH:
					return Stick.LEFT_VERTICAL
				Axis.ROLL:
					return Stick.LEFT_HORIZONTAL
		Mode.MODE_4:
			match axis:
				Axis.THROTTLE:
					return Stick.LEFT_VERTICAL
				Axis.YAW:
					return Stick.RIGHT_HORIZONTAL
				Axis.PITCH:
					return Stick.RIGHT_VERTICAL
				Axis.ROLL:
					return Stick.LEFT_HORIZONTAL
	return -1


func set_left_stick_horizontal(value: float) -> void:
	_set_stick_pose(Stick.LEFT_HORIZONTAL, Vector3.FORWARD, get_stick_angle(value))


func set_left_stick_vertical(value: float) -> void:
	_set_stick_pose(Stick.LEFT_VERTICAL, Vector3.RIGHT, get_stick_angle(value))


func set_right_stick_horizontal(value: float) -> void:
	_set_stick_pose(Stick.RIGHT_HORIZONTAL, Vector3.FORWARD, get_stick_angle(value))


func set_right_stick_vertical(value: float) -> void:
	_set_stick_pose(Stick.RIGHT_VERTICAL, Vector3.RIGHT, get_stick_angle(value))


func set_throttle_stick(value: float) -> void:
	if mode == Mode.MODE_1 or mode == Mode.MODE_3:
		set_right_stick_vertical(value)
	else:
		set_left_stick_vertical(value)


func set_yaw_stick(value: float) -> void:
	if mode == Mode.MODE_1 or mode == Mode.MODE_2:
		set_left_stick_horizontal(value)
	else:
		set_right_stick_horizontal(value)


func set_pitch_stick(value: float) -> void:
	if mode == Mode.MODE_1 or mode == Mode.MODE_3:
		set_left_stick_vertical(value)
	else:
		set_right_stick_vertical(value)


func set_roll_stick(value: float) -> void:
	if mode == Mode.MODE_1 or mode == Mode.MODE_2:
		set_right_stick_horizontal(value)
	else:
		set_left_stick_horizontal(value)


func _begin_tween() -> Tween:
	if tween != null and tween.is_valid():
		tween.kill()
	tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tween


func play_animation(calibration_step: int) -> void:
	var tw := _begin_tween()
	tween_loop = 0
	match calibration_step:
		0:
			tw.tween_method(set_left_stick_horizontal, 0.0, -1.0, 0.5)
			tw.tween_method(set_left_stick_vertical, 0.0, -1.0, 0.5)
			tw.tween_method(set_right_stick_horizontal, 0.0, 1.0, 0.5)
			tw.tween_method(set_right_stick_vertical, 0.0, -1.0, 0.5)
			tw.finished.connect(loop_stick_animation)
		1:
			tw.tween_method(set_left_stick_horizontal, 0.0, 0.0, 0.5)
			tw.tween_method(set_left_stick_vertical, 0.0, 0.0, 0.5)
			tw.tween_method(set_right_stick_horizontal, 0.0, 0.0, 0.5)
			tw.tween_method(set_right_stick_vertical, 0.0, 0.0, 0.5)
		2:
			tw.tween_method(set_throttle_stick, 0.0, -1.0, 0.5)
		3:
			tw.tween_method(set_throttle_stick, -1.0, 1.0, 0.5)
		4:
			tw.tween_method(set_throttle_stick, 1.0, 0.0, 0.5)
		5:
			set_throttle_stick(0.0)
			tw.tween_method(set_yaw_stick, 0.0, -1.0, 0.5)
		6:
			tw.tween_method(set_yaw_stick, -1.0, 1.0, 0.5)
		7:
			tw.tween_method(set_yaw_stick, 1.0, 0.0, 0.5)
		8:
			set_yaw_stick(0.0)
			tw.tween_method(set_pitch_stick, 0.0, -1.0, 0.5)
		9:
			tw.tween_method(set_pitch_stick, -1.0, 1.0, 0.5)
		10:
			tw.tween_method(set_pitch_stick, 1.0, 0.0, 0.5)
		11:
			set_pitch_stick(0.0)
			tw.tween_method(set_roll_stick, 0.0, -1.0, 0.5)
		12:
			tw.tween_method(set_roll_stick, -1.0, 1.0, 0.5)
		13:
			tw.tween_method(set_roll_stick, 1.0, 0.0, 0.5)
		_:
			set_roll_stick(0.0)


func loop_stick_animation() -> void:
	tween_loop += 1
	var tw := _begin_tween()
	match tween_loop:
		1:
			tw.tween_method(set_left_stick_horizontal, -1.0, 1.0, 0.5)
			tw.tween_method(set_right_stick_horizontal, 1.0, -1.0, 0.5)
		2:
			tw.tween_method(set_left_stick_vertical, -1.0, 1.0, 0.5)
			tw.tween_method(set_right_stick_vertical, -1.0, 1.0, 0.5)
		3:
			tw.tween_method(set_left_stick_horizontal, 1.0, -1.0, 0.5)
			tw.tween_method(set_right_stick_horizontal, -1.0, 1.0, 0.5)
		4:
			tw.tween_method(set_left_stick_vertical, 1.0, -1.0, 0.5)
			tw.tween_method(set_right_stick_vertical, 1.0, -1.0, 0.5)
			tween_loop = 0
	tw.finished.connect(loop_stick_animation)


func _on_calibration_step_changed(step: int) -> void:
	play_animation(step)
