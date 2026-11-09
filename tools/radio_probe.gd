extends SceneTree

var _t := 0.0
var _next := 0.0


func _initialize() -> void:
	print("[RADIO] sampling 8s... move sticks / flip switches now")


func _process(delta: float) -> bool:
	_t += delta
	if _t >= _next:
		_next += 1.0
		var parts := PackedStringArray(["t=%.1f" % _t])
		for dev in Input.get_connected_joypads():
			var axes := PackedStringArray()
			for i in range(8):
				axes.append("%d=%.2f" % [i, Input.get_joy_axis(dev, i)])
			var btns := PackedStringArray()
			for i in range(24):
				if Input.is_joy_button_pressed(dev, i):
					btns.append(str(i))
			var btntext := ",".join(btns) if not btns.is_empty() else "-"
			parts.append("dev%d axes[%s] btn[%s]" % [dev, ",".join(axes), btntext])
		print("[RADIO] ", " ".join(parts))
	if _t >= 8.0:
		return true
	return false
