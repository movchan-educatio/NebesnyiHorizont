extends Camera3D
## Simple free-fly FPV preview camera for the lis_forest_freestyle map.
## WASD = move, Space/Ctrl = up/down, Shift = boost, mouse = look, Esc = release mouse.

@export var base_speed: float = 28.0
@export var boost_multiplier: float = 4.0
@export var mouse_sensitivity: float = 0.0022
@export var spawn_point_name: String = "Spawn_Z01"

var _yaw: float = 0.0
var _pitch: float = 0.0
var _mouse_captured: bool = false

func _ready() -> void:
	rotation_order = EulerOrder.EULER_ORDER_YXZ
	fov = 95.0
	near = 0.08
	far = 2200.0
	var sp := get_tree().get_first_node_in_group("lis_spawnpoints")
	if sp:
		var chosen := sp.get_node_or_null(spawn_point_name) as Node3D
		if chosen:
			global_position = chosen.global_position + Vector3.UP * 3.0
	global_position.y = maxf(global_position.y, 4.0)
	_apply_rotation()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	print("[LIS] preview camera ready at ", global_position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, -deg_to_rad(88.0), deg_to_rad(88.0))
		_apply_rotation()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_mouse_captured = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if event.keycode == KEY_M:
			_mouse_captured = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var forward := Input.get_axis("move_back", "move_forward")
	var strafe := Input.get_axis("move_left", "move_right")
	var vertical := Input.get_axis("move_down", "move_up")
	var dir := (transform.basis * Vector3(strafe, 0.0, -forward)).normalized()
	var speed := base_speed * (boost_multiplier if Input.is_action_pressed("boost") else 1.0)
	global_position += dir * speed * delta
	global_position.y += vertical * speed * delta

func _apply_rotation() -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)
