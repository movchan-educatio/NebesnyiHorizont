extends Node

## QA: the self-centering throttle must map stick centre to HOVER when armed,
## not to zero.  Also lock the lower half (descent) and upper half (climb).


func _ready() -> void:
	var rc = load("res://drone/RadioController.gd")
	var fails := 0
	var checks := [
		["armed centre", 0.0, true, 0.45, 0.001],
		["armed deadband +", 0.04, true, 0.45, 0.001],
		["armed deadband -", -0.04, true, 0.45, 0.001],
		["armed bottom", -1.0, true, 0.0, 0.001],
		["armed top", 1.0, true, 1.0, 0.001],
		["armed half climb", 0.5, true, 0.725, 0.001],
		["armed half descend", -0.5, true, 0.225, 0.001],
		["unarmed centre", 0.0, false, 0.0, 0.001],
		["unarmed top", 1.0, false, 1.0, 0.001],
	]
	for c in checks:
		var got: float = rc.centered_throttle_power(float(c[1]), bool(c[2]))
		var ok: bool = absf(got - float(c[3])) <= float(c[4])
		if not ok:
			fails += 1
		print("[CTRL] ", "OK  " if ok else "FAIL", " ", c[0], " in=", c[1],
				" armed=", c[2], " got=", snappedf(got, 0.001),
				" want=", c[3])
	print("[CTRL] fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
