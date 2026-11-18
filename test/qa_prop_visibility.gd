extends Node

## Regression: Grim-7 propeller blades must stay visible from every camera
## angle and must never be drawn through the FPV lens.
##
## The old blade material was single-sided (CULL_BACK).  Thin twisted airfoils
## therefore disappeared as soon as their back face turned toward the camera,
## which read as "invisible/static" propellers in the hangar and chase view.
## In FPV the front props sit millimetres from the camera, so they clipped
## through the near plane as huge black arcs.

const PropSystem := preload("res://scripts/util/DronePropellerSystem.gd")
const PRESETS := [0, 1, 6]

var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[PROP_VIS] PASS ", label)
	else:
		_failures += 1
		print("[PROP_VIS] FAIL ", label)


func _run() -> void:
	var roots: Array[Node3D] = []
	for index in PRESETS:
		var holder := Node3D.new()
		holder.name = "Holder%d" % index
		add_child(holder)
		var model := DroneCatalog.attach_model(holder, index)
		if model == null:
			_check(false, "preset %d attaches a model" % index)
			continue
		roots.append(model)
		_check_model(model, index)
	await get_tree().process_frame

	var level_script = load("res://sceneries/BigLevel.gd")
	var level = level_script.new()
	_check(level != null, "BigLevel script instantiates for visibility checks")
	if level != null:
		var probe := Node3D.new()
		add_child(probe)
		var pivot := Node3D.new()
		pivot.name = "motor_FL"
		pivot.add_to_group("drone_prop_pivot")
		probe.add_child(pivot)
		var blade := MeshInstance3D.new()
		blade.name = "propeller_FL"
		pivot.add_child(blade)
		var motor := MeshInstance3D.new()
		motor.name = "motor_FL"
		pivot.add_child(motor)
		var warhead := MeshInstance3D.new()
		warhead.name = "Morkva_Warhead"
		probe.add_child(warhead)
		var plate := MeshInstance3D.new()
		plate.name = "frame_carbon_0"
		probe.add_child(plate)
		var shell := MeshInstance3D.new()
		shell.name = "Object_Material_003_0"
		probe.add_child(shell)

		level.call("_configure_model_for_camera", probe, true, true)
		_check(not pivot.visible, "FPV hides the propeller pivot")
		_check(not blade.is_visible_in_tree(), "FPV hides the front propeller mesh")
		_check(not motor.is_visible_in_tree(), "FPV hides the front motor bell")
		_check(warhead.is_visible_in_tree(), "FPV keeps the warhead/body cue visible")
		_check(not plate.is_visible_in_tree(),
				"FPV hides the carbon lens plate that clipped the frame corners")
		_check(not shell.is_visible_in_tree(), "FPV hides the main airframe shell")

		level.call("_configure_model_for_camera", probe, false, false)
		_check(pivot.visible, "external view restores the propeller pivot")
		_check(blade.is_visible_in_tree(), "external view restores the propeller mesh")
		level.free()

	# The final visibility pass must never re-show a pivot in FPV.
	var src := FileAccess.get_file_as_string("res://sceneries/BigLevel.gd")
	_check(src.contains("(pivot as Node3D).visible = third_person"),
			"final pivot pass only shows props in external view")
	_check(not src.contains("propeller_fl") and not src.contains("propeller_fr"),
			"FPV does not opt the front propellers back in")

	for root in roots:
		root.get_parent().queue_free()
	print("[PROP_VIS] failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _check_model(model: Node3D, index: int) -> void:
	var pivots: Array = model.get_meta("prop_pivots", [])
	_check(pivots.size() >= 4, "preset %d has animated prop pivots (%d)" % [
			index, pivots.size()])
	var blades := model.find_children("NewPropMesh", "MeshInstance3D", true, false)
	_check(blades.size() == pivots.size() and not blades.is_empty(),
			"preset %d every pivot carries a new blade mesh (%d)" % [
					index, blades.size()])
	var bad_cull := 0
	var dark := 0
	var one_sided_override := 0
	for node in blades:
		var mi := node as MeshInstance3D
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			one_sided_override += 1
			continue
		if mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
			bad_cull += 1
		if mat.albedo_color.get_luminance() < 0.20:
			dark += 1
	_check(one_sided_override == 0,
			"preset %d blades use an explicit material override" % index)
	_check(bad_cull == 0,
			"preset %d blade material is double-sided (%d bad)" % [index, bad_cull])
	_check(dark == 0,
			"preset %d blade tint stays readable (%d too dark)" % [index, dark])

	# Idle menu animation must actually move every pivot, not just one.
	var before: Array[float] = []
	for p in pivots:
		before.append((p as Node3D).rotation.y)
	DroneCatalog.animate_propellers(model, 1.0 / 60.0)
	var moved := 0
	for i in range(pivots.size()):
		if absf((pivots[i] as Node3D).rotation.y - before[i]) > 0.0001:
			moved += 1
	_check(moved == pivots.size(),
			"preset %d idle animation turns every blade (%d/%d)" % [
					index, moved, pivots.size()])
