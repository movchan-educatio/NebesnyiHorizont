extends Node

## Regression test: physical motor RPM must not alias the visible propellers into
## a frozen disc.  The visual layer is clamped to a readable rotation rate while
## preserving direction, the zero-RPM stop and the idle menu spin.

const PropSystem := preload("res://scripts/util/DronePropellerSystem.gd")
const DT := 1.0 / 60.0

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var model := Node3D.new()
	add_child(model)
	var pivots: Array[Node3D] = []
	for i in range(4):
		var pivot := Node3D.new()
		pivot.name = "PropPivot%d" % i
		pivot.set_meta("spin_dir", 1.0 if i % 2 == 0 else -1.0)
		pivot.set_meta("spin_axis", Vector3.UP)
		model.add_child(pivot)
		pivots.append(pivot)
	model.set_meta("prop_pivots", pivots)

	# 18k RPM physical: 13 readable revolutions per second -> 78 deg/frame.
	PropSystem.animate_propellers(model, DT, [18000.0, 18000.0, 18000.0, 18000.0])
	var cw_step := absf(pivots[0].rotation.y)
	var ccw_step := absf(pivots[1].rotation.y)
	var max_step := deg_to_rad(78.5)
	_check(cw_step > deg_to_rad(70.0) and cw_step <= max_step,
			"high RPM props turn at a visible ~13 rev/s (%.1f deg/frame)" % \
			rad_to_deg(cw_step))
	_check(pivots[0].rotation.y > 0.0 and pivots[1].rotation.y < 0.0,
			"counter-rotating props keep their opposite directions")
	_check(absf(cw_step - ccw_step) < 0.0001,
			"both rotation directions use the same visual rate")

	# A real 30k RPM race quad must not alias differently from an 18k camera drone.
	for p in pivots:
		p.rotation = Vector3.ZERO
	PropSystem.animate_propellers(model, DT, [30000.0, 30000.0, 30000.0, 30000.0])
	_check(absf(absf(pivots[0].rotation.y) - cw_step) < 0.0001,
			"all high physical RPM values clamp to the same readable rate")

	# Very low but live throttle must not freeze a blade.
	for p in pivots:
		p.rotation = Vector3.ZERO
	PropSystem.animate_propellers(model, DT, [100.0, 100.0, 100.0, 100.0])
	_check(absf(pivots[0].rotation.y) > deg_to_rad(15.0),
			"armed low-RPM motors still visibly rotate (%.1f deg/frame)" % \
			rad_to_deg(absf(pivots[0].rotation.y)))

	# Zero RPM is a real stop, not idle spin.
	for p in pivots:
		p.rotation = Vector3.ZERO
	PropSystem.animate_propellers(model, DT, [0.0, 0.0, 0.0, 0.0])
	_check(is_zero_approx(pivots[0].rotation.y) and is_zero_approx(pivots[3].rotation.y),
			"zero motor RPM stops the visual propeller")

	# Menus/previews keep their slow idle rotation.
	for p in pivots:
		p.rotation = Vector3.ZERO
	PropSystem.animate_propellers(model, DT, [])
	_check(absf(pivots[0].rotation.y) > deg_to_rad(10.0),
			"menu preview keeps the idle prop spin")

	print("[PROP_QA] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PROP_QA] PASS ", label)
	else:
		_failures += 1
		push_error("[PROP_QA] FAIL " + label)
