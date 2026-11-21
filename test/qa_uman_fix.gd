extends Node

## Regression + visual proof for the Uman freestyle map repair.
## Run windowed (viewport readback needs a real renderer):
##   Godot --windowed --path . res://test/qa_uman_fix.tscn
## Optional MOBILE_UI=1 for the iPhone-layout screenshots.

const OUT := "res://qa_shots/uman_fix"

var _fails := 0
var _suffix := ""

func _check(ok: bool, label: String) -> void:
	print("[UMAN_FIX] ", "PASS " if ok else "FAIL ", label)
	if not ok:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _shot(name: String, level: Node3D, cam_pos: Vector3, look: Vector3,
		fov: float = 72.0) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 2200.0
	level.add_child(cam)
	var chosen := cam_pos
	var offsets: Array[Vector3] = [Vector3.ZERO, Vector3.UP * 5.0,
			Vector3.UP * 10.0, Vector3(8.0, 4.0, 0.0), Vector3(-8.0, 4.0, 0.0),
			Vector3(0.0, 4.0, 8.0), Vector3(0.0, 4.0, -8.0)]
	for off in offsets:
		if bool(level.call("_freestyle_gate_clear", cam_pos + off, 2.0)):
			chosen = cam_pos + off
			break
	cam.global_position = chosen
	cam.look_at(look, Vector3.UP)
	await get_tree().process_frame
	cam.current = true
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_check(false, "screenshot " + name)
	else:
		var err := img.save_png(OUT.path_join(name + _suffix + ".png"))
		_check(err == OK, "screenshot " + name + " err=" + str(err))
	cam.queue_free()
	await get_tree().process_frame

func _aabb(node: Node) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var b := mi.global_transform * mi.mesh.get_aabb()
			if first:
				result = b
				first = false
			else:
				result = result.merge(b)
		for c in n.get_children():
			stack.append(c)
	return result

func _count_name(node: Node, part: String) -> int:
	var n := 1 if String(node.name).contains(part) else 0
	for c in node.get_children():
		n += _count_name(c, part)
	return n

func _run() -> void:
	OS.set_environment("DRONE_NO_RECORD", "1")
	if OS.has_environment("MOBILE_UI"):
		_suffix = "_mobile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.drone_preset = 10
	var packed := load("res://sceneries/UmanLevel.tscn") as PackedScene
	var level := packed.instantiate() as Node3D
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await get_tree().create_timer(4.0).timeout

	var rings: Array = level.get("_training_rings")
	_check(rings.size() == 24, "24 checkpoint gates (got %d)" % rings.size())
	_check(_count_name(level, "UmanNeonTrail") == 0, "old rope/trail course removed")
	_check(_count_name(level, "FreestyleGate") == 0, "old decorative gates removed")
	_check(_count_name(level, "uman_scenery_col") > 100,
			"trees/buildings have colliders (%d)" % _count_name(level, "uman_scenery_col"))
	_check((level.get("_uman_placed") as Array).size() <= 130,
			"stunt prop budget <= 130")

	# Exact water geometry: lake centre is water, promenade / landing pad is not.
	_check(bool(level.call("_uman_is_water", Vector3(60.0, 0.0, 25.0))),
			"lake centre detected as water")
	_check(not bool(level.call("_uman_is_water", Vector3(120.0, 0.0, 118.0))),
			"spawn promenade detected as dry")
	var pad := level.find_child("UmanLandingPad", true, false) as Node3D
	if pad != null:
		_check(not bool(level.call("_uman_is_water", pad.global_position)),
				"landing pad detected as dry")

	var blocked := 0
	var drowned_gates := 0
	for ring in rings:
		var area := ring as Area3D
		if area == null:
			continue
		var radius := float(area.get_meta("ring_radius", 3.0)) * 0.7 + 0.8
		if not bool(level.call("_freestyle_gate_clear", area.global_position, radius)):
			blocked += 1
		if bool(level.call("_uman_is_water", area.global_position)) \
				and area.global_position.y < 2.0:
			drowned_gates += 1
	_check(blocked == 0, "no gate sits inside a tree/prop/wall (blocked=%d)" % blocked)
	_check(drowned_gates == 0, "no gate is submerged (count=%d)" % drowned_gates)

	var floating_scenery := 0
	for n in level.find_children("uman_scenery_col*", "StaticBody3D", true, false):
		var body := n as StaticBody3D
		var bottom := body.global_position.y
		for cs in body.find_children("*", "CollisionShape3D", true, false):
			var shape := (cs as CollisionShape3D).shape
			var half := 0.0
			if shape is BoxShape3D:
				half = (shape as BoxShape3D).size.y * 0.5
			elif shape is CylinderShape3D:
				half = (shape as CylinderShape3D).height * 0.5
			bottom = mini(bottom, body.global_position.y + (cs as CollisionShape3D).position.y - half)
		if bottom > 2.0:
			floating_scenery += 1
			print("[UMAN_FIX] FLOAT_COL ", body.name, " pos=", str(body.global_position),
					" bottom=", bottom)
	_check(floating_scenery == 0,
			"no tree/building collider floats (count=%d)" % floating_scenery)
	_check((level.get("_uman_water_tris") as Array).size() > 100,
			"exact water mesh cached (%d triangles)" % (level.get("_uman_water_tris") as Array).size())

	var starts := 0
	var finishes := 0
	for l in level.find_children("GateNumber", "Label3D", true, false):
		var txt := (l as Label3D).text
		if txt.begins_with("START"):
			starts += 1
		if txt.begins_with("FINISH"):
			finishes += 1
	_check(starts == 1 and finishes == 1,
			"START and FINISH markers exist (%d/%d)" % [starts, finishes])
	var visible_gates := 0
	var arches := 0
	var floating_arches := 0
	var bad_aerial_feet := 0
	for ring in rings:
		var area := ring as Area3D
		if area == null:
			continue
		if area.visible:
			visible_gates += 1
		var shp := int(area.get_meta("ring_shape", -1))
		var r_sz := float(area.get_meta("ring_radius", 4.6))
		var fl := area.get_node_or_null("FootLeft") as MeshInstance3D
		var fr := area.get_node_or_null("FootRight") as MeshInstance3D
		if shp == 1:
			arches += 1
			var gy_c := float(level.call("_find_ground_y", area.global_position.x, area.global_position.z))
			var agl_c := area.global_position.y - gy_c
			var legs_ok := bool(area.get_meta("arch_grounded", false)) and fl != null and fr != null \
					and agl_c <= r_sz * 1.45
			if legs_ok:
				var gl := float(level.call("_find_ground_y", fl.global_position.x, fl.global_position.z))
				var gr := float(level.call("_find_ground_y", fr.global_position.x, fr.global_position.z))
				if absf(fl.global_position.y - (gl + 0.12)) >= 0.45 \
						or absf(fr.global_position.y - (gr + 0.12)) >= 0.45:
					legs_ok = false
			if not legs_ok:
				floating_arches += 1
		else:
			if fl != null or fr != null:
				bad_aerial_feet += 1
	_check(visible_gates == 24, "all freestyle arches are visible (%d/24)" % visible_gates)
	_check(arches >= 6, "Uman course uses grounded arch gates on low sections (%d/24)" % arches)
	_check(floating_arches == 0 and bad_aerial_feet == 0,
			"all arches grounded on terrain and aerial gates clean (%d/%d)" % [floating_arches, bad_aerial_feet])

	# A platform over water must NOT trigger the water respawn.
	var platform := StaticBody3D.new()
	platform.name = "QaWaterPlatform"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7.0, 0.5, 7.0)
	col.shape = box
	platform.add_child(col)
	platform.position = Vector3(60.0, 1.2, 25.0)
	level.add_child(platform)
	var drone := level.get_node_or_null("Drone") as Drone
	if drone != null:
		drone.global_position = Vector3(60.0, 1.8, 25.0)
		drone.linear_velocity = Vector3.ZERO
		await get_tree().create_timer(2.5).timeout
		var after := drone.global_position
		_check(after.distance_to(Vector3(60.0, 1.8, 25.0)) < 8.0,
				"platform over water does not force a respawn (pos=%s)" % str(after))
	platform.queue_free()
	await get_tree().process_frame

	var first := (rings[0] as Area3D).global_position
	var second := (rings[1] as Area3D).global_position
	var dir := (second - first).normalized()
	# Straight overhead so the START label and the gate opening are readable
	# regardless of which building happens to be behind it.
	await _shot("01_start_gate", level, first + Vector3.UP * 22.0, first, 66.0)
	await _shot("06_fpv_arches", level,
			first - dir * 12.0 + Vector3.UP * 1.4, second, 75.0)
	await _shot("02_course_overview", level, Vector3(118.0, 34.0, 128.0),
			Vector3(20.0, 2.0, 40.0), 78.0)
	await _shot("03_water_platform", level, Vector3(44.0, 12.0, 42.0),
			Vector3(60.0, 0.6, 25.0), 70.0)
	await _shot("04_stunt_area", level, Vector3(132.0, 16.0, 78.0),
			Vector3(132.0, 2.0, 62.0), 72.0)

	# Drone accent must stay subtle (no "salad-green flashlight").
	var accents := 0
	var loud := 0
	var led_loud := 0
	for model_root in level.find_children("DroneModel", "Node3D", true, false):
		for mi in (model_root as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in range(mesh.get_surface_count()):
				var mat := (mi as MeshInstance3D).get_surface_override_material(s)
				if mat is StandardMaterial3D and (mat as StandardMaterial3D).has_meta("uman_accent"):
					accents += 1
					if (mat as StandardMaterial3D).emission_energy_multiplier > 0.12:
						loud += 1
					if (mat as StandardMaterial3D).has_meta("uman_led_dimmed") \
							and (mat as StandardMaterial3D).emission_energy_multiplier > 0.6:
						led_loud += 1
	_check(accents > 0 and loud == 0 and led_loud == 0,
			"drone accent is subtle (%d accents, %d too bright, %d LEDs)" % [
					accents, loud, led_loud])
	var model := level.find_child("DroneModel", true, false) as Node3D
	if model != null:
		var center := _aabb(model).get_center()
		await _shot("05_drone", level, center + Vector3(3.5, 2.0, 4.5),
				center, 55.0)

	print("[UMAN_FIX] failures=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
