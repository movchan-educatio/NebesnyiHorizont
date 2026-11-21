extends Node

## Windowed showcase renderer for all 13 DroneCatalog presets using live Godot
## PBR shaders, DroneCatalog.attach_model(), and DronePropellerSystem props.
## Usage: SHOWCASE_OUT_DIR=<dir> ... qa_all_drones_showcase.tscn

var _fails := 0
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(ok: bool, msg: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("[QA-SHOWCASE] FAIL: ", msg)
	else:
		print("[QA-SHOWCASE] PASS: ", msg)


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for vi_n in node.find_children("*", "VisualInstance3D", true, false):
		var vi := vi_n as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var lb := vi.get_aabb()
		if lb.size.length_squared() < 1e-8:
			continue
		var b: AABB = vi.global_transform * lb
		box = b if first else box.merge(b)
		first = false
	return box


func _run() -> void:
	var out_dir := OS.get_environment("SHOWCASE_OUT_DIR").strip_edges()
	if out_dir.is_empty():
		out_dir = "C:/Users/USER_UA/.gemini/antigravity/brain/3e1fc674-fea9-4635-a574-57c85e14dad7/scratch/godot_before"
	DirAccess.make_dir_recursive_absolute(out_dir)
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(640, 420)

	var stage := Node3D.new()
	add_child(stage)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.08, 0.10, 0.12, 1.0)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.55, 0.58, 0.62)
	we.ambient_light_energy = 0.72
	env.environment = we
	stage.add_child(env)

	var key := DirectionalLight3D.new()
	key.light_energy = 2.1
	key.light_color = Color(1.0, 0.98, 0.94)
	key.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	stage.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.85
	fill.light_color = Color(0.78, 0.88, 1.0)
	fill.rotation_degrees = Vector3(26.0, -138.0, 0.0)
	stage.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.01
	cam.far = 200.0
	stage.add_child(cam)
	cam.make_current()

	var holder := Node3D.new()
	stage.add_child(holder)

	var expected_pivots := {
		0: 4, 1: 4, 2: 4, 3: 4, 4: 4, 5: 4,
		6: 6,
		7: 1, 8: 1,
		9: 0,
		10: 4, 11: 4, 12: 4,
	}

	var saved_preset := Global.drone_preset
	for idx in range(DroneCatalog.count()):
		for c in holder.get_children():
			holder.remove_child(c)
			c.queue_free()
		await get_tree().process_frame

		Global.drone_preset = idx
		var p := DroneCatalog.preset(idx)
		var did := str(p.get("id", "p%d" % idx))
		var model := DroneCatalog.attach_model(holder, idx)
		_check(model != null, "Attached model preset=%d (%s)" % [idx, did])
		if model == null:
			continue

		await get_tree().process_frame
		await get_tree().process_frame

		var pivots = model.get_meta("prop_pivots", [])
		var pcount := (pivots as Array).size() if pivots is Array else 0
		var exp_count := int(expected_pivots.get(idx, 4))
		_check(pcount == exp_count,
				"Preset %d (%s) prop pivots=%d (expected %d)" % [idx, did, pcount, exp_count])

		var box := _bounds(holder)
		var center := box.get_center()
		var rad := maxf(box.size.length() * 0.5, 0.06)
		var angle := Vector3(0.76, 0.50, -0.78).normalized()
		if idx == 4: # VTOL stands vertically; frame cleanly front-3/4
			angle = Vector3(0.72, 0.32, -0.82).normalized()
		elif idx in [7, 8, 9]: # Fixed wings look sleekest from slightly forward-above
			angle = Vector3(0.78, 0.44, -0.74).normalized()
		var dist := rad / sin(deg_to_rad(cam.fov * 0.5)) * 1.06
		cam.look_at_from_position(center + angle * dist, center, Vector3.UP)

		if DisplayServer.get_name() != "headless":
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var fname := "%02d_%s.png" % [idx, did]
			var err := img.save_png(out_dir.path_join(fname))
			_check(err == OK, "Rendered %s" % fname)

	Global.drone_preset = saved_preset
	print("[QA-SHOWCASE] SUMMARY checks=", _checks, " fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
