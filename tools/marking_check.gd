## QA: verify the final enemy-marking rules.
##   * enemy infantry: exactly one small RussianFlag, zero ChalkZ
##   * every hostile vehicle kind: exactly one RussianFlag and one ChalkZ
##   * friendly / Chaos-blue vehicles: no Russian markings
extends Node3D

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("[MARK] PASS ", msg)
	else:
		_failed = true
		print("[MARK] FAIL ", msg)


func _ready() -> void:
	# --- infantry ---
	var soldier := EnemyRifleman.new()
	add_child(soldier)
	await get_tree().process_frame
	var flags := soldier.find_children("RussianFlag", "MeshInstance3D", true, false)
	var zs := soldier.find_children("ChalkZ", "MeshInstance3D", true, false)
	_check(flags.size() == 1, "infantry has one shoulder flag (got %d)" % flags.size())
	_check(zs.is_empty(), "infantry has no chalk Z (got %d)" % zs.size())
	if flags.size() == 1:
		var q := (flags[0] as MeshInstance3D).mesh as QuadMesh
		var w := q.size.x if q != null else 999.0
		_check(w <= 0.10, "infantry flag is small (%.3f m wide)" % w)
	soldier.queue_free()

	# --- all hostile vehicle kinds ---
	for kind_name in ["TANK", "BMP", "APC", "TRUCK", "SAM", "HELI", "SHAHED"]:
		var kind_value: int = int(Vehicle.Kind[kind_name])
		var v := Vehicle.new()
		v.kind = kind_value
		v.hostile = true
		v.move_speed = 0.0
		add_child(v)
		await get_tree().process_frame
		var vf := v.find_children("RussianFlag", "MeshInstance3D", true, false)
		var vz := v.find_children("ChalkZ", "MeshInstance3D", true, false)
		_check(vf.size() == 1, "%s has one flag (got %d)" % [kind_name, vf.size()])
		_check(vz.size() == 1, "%s has exactly one Z (got %d)" % [kind_name, vz.size()])
		v.queue_free()
		await get_tree().process_frame

	# --- friendly vehicle must stay clean ---
	var friendly := Vehicle.new()
	friendly.kind = Vehicle.Kind.TANK
	friendly.hostile = false
	friendly.move_speed = 0.0
	add_child(friendly)
	await get_tree().process_frame
	_check(friendly.find_children("RussianFlag", "MeshInstance3D", true, false).is_empty()
			and friendly.find_children("ChalkZ", "MeshInstance3D", true, false).is_empty(),
			"friendly vehicle has no Russian markings")
	friendly.queue_free()

	# --- Chaos blue (ai_team 0) must stay clean, red (1) marked ---
	var blue := Vehicle.new()
	blue.kind = Vehicle.Kind.BMP
	blue.ai_vs_ai = true
	blue.ai_team = 0
	blue.move_speed = 0.0
	add_child(blue)
	await get_tree().process_frame
	_check(blue.find_children("ChalkZ", "MeshInstance3D", true, false).is_empty(),
			"Chaos blue vehicle has no Z")
	blue.queue_free()

	print("[MARK] RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
