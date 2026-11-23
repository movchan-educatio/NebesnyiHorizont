extends Node

## QA (phase 5b): six clean 1280x720 polish captures.
## Run windowed (headless viewports cannot read back pixels):
##   Godot --windowed --path . res://test/qa_polish_shots.tscn
## Output: res://qa_shots/polish/*.png

const OUT_DIR := "res://qa_shots/polish"

var _captured := 0


func _ready() -> void:
	# Exact target resolution must be in place before any shot is grabbed.
	get_window().size = Vector2i(1280, 720)
	get_viewport().size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	OS.set_environment("DRONE_NO_RECORD", "1")
	OS.set_environment("DRONE_WEATHER", "clear")
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.combat_mission = 0
	Global.special_mission = 0
	Global.drone_preset = 0

	var shots: Array[Dictionary] = [
		{
			"file": "01_industrial_daylight_freestyle.png",
			"scene": "res://sceneries/IndustrialLevel.tscn",
			"pos": Vector3(60, 25, 60),
			"look": Vector3(0, 5, 0),
			"pipe": false,
		},
		{
			"file": "02_industrial_pipe_bore.png",
			"scene": "res://sceneries/IndustrialLevel.tscn",
			"pos": Vector3(50, 3, 0),
			"look": Vector3(50, 3, -20),
			"pipe": true,
		},
		{
			"file": "03_wetlands_daylight_freestyle.png",
			"scene": "res://sceneries/WetlandsLevel.tscn",
			"pos": Vector3(55, 22, 55),
			"look": Vector3(0, 4, 0),
			"pipe": false,
		},
		{
			"file": "04_airport_daylight_freestyle.png",
			"scene": "res://sceneries/AirportLevel.tscn",
			"pos": Vector3(80, 30, 80),
			"look": Vector3(0, 5, 0),
			"pipe": false,
		},
		{
			"file": "05_uman_daylight_freestyle.png",
			"scene": "res://sceneries/UmanLevel.tscn",
			"pos": Vector3(60, 24, 60),
			"look": Vector3(0, 5, 0),
			"pipe": false,
		},
	]

	for shot in shots:
		await _capture_level_shot(shot)

	await _capture_settings()

	print("[QA_POLISH_SHOTS] captured=%d" % _captured)
	print("[QA_POLISH_SHOTS] DONE")
	get_tree().quit(0)


func _settle() -> void:
	# Let the level finish its deferred build before the camera is placed.
	for i in range(5):
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout


func _spawn_level(path: String) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[QA_POLISH_SHOTS] cannot load level: " + path)
		return null
	var level := packed.instantiate() as Node3D
	if level == null:
		push_warning("[QA_POLISH_SHOTS] cannot instantiate level: " + path)
		return null
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	await _settle()
	return level


func _clean_level(level: Node3D) -> void:
	# No HUD overlay and no player drone mesh in the QA frames.
	for n in level.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for n in level.find_children("*", "Drone", true, false):
		n.visible = false


func _make_cam(parent: Node3D) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = "QAPolishCamera"
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 4000.0
	parent.add_child(cam)
	return cam


func _capture_level_shot(shot: Dictionary) -> void:
	var level := await _spawn_level(String(shot["scene"]))
	if level == null:
		return
	_clean_level(level)

	var cam := _make_cam(level)
	if bool(shot["pipe"]):
		var pipe := _find_pipe(level)
		if pipe != null:
			var pipe_length := _pipe_length(pipe)
			var offset := pipe_length * 0.5 + 2.0
			cam.global_position = pipe.global_position + Vector3(0, 0, offset)
			cam.look_at(pipe.global_position - Vector3(0, 0, offset), Vector3.UP)
		else:
			# Fallback: no authored pipe in this layout.
			cam.global_position = Vector3(50, 3, 0)
			cam.look_at(Vector3(50, 3, -20), Vector3.UP)
	else:
		cam.global_position = shot["pos"]
		cam.look_at(shot["look"], Vector3.UP)
	cam.current = true

	await get_tree().process_frame
	await _capture(String(shot["file"]))
	await _free_level(level)


func _free_level(level: Node) -> void:
	if level == null or not is_instance_valid(level):
		return
	if get_tree().current_scene == level:
		get_tree().current_scene = null
	level.queue_free()
	# Give queue_free() a full frame so the next level starts from a clean tree.
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout


func _capture_settings() -> void:
	var packed := load("res://GUI/QuadSettingsMenu.tscn") as PackedScene
	if packed == null:
		push_warning("[QA_POLISH_SHOTS] QuadSettingsMenu.tscn failed to load; skipping 06")
		return
	var menu := packed.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	await _capture("06_settings_rates_controls.png")
	menu.queue_free()
	await get_tree().process_frame


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_warning("[QA_POLISH_SHOTS] no image for " + file_name)
		return
	var err := img.save_png(OUT_DIR.path_join(file_name))
	if err != OK:
		push_warning("[QA_POLISH_SHOTS] save failed for %s (err=%d)" % [file_name, err])
		return
	_captured += 1
	print("[QA_POLISH_SHOTS] saved %s %s" % [file_name, img.get_size()])


func _find_pipe(root: Node) -> Node3D:
	if root is Node3D:
		var nm := String(root.name)
		if nm.contains("HollowPipe") or nm.contains("PipeCulvert") or nm.contains("Culvert"):
			return root as Node3D
	for child in root.get_children():
		var hit := _find_pipe(child)
		if hit != null:
			return hit
	return null


func _pipe_length(pipe: Node3D) -> float:
	var v: Variant = pipe.get("pipe_length")
	if v is float or v is int:
		return maxf(float(v), 1.0)
	if pipe.has_meta("pipe_length"):
		return maxf(float(pipe.get_meta("pipe_length")), 1.0)

	# Structures are generated procedurally without a helper property: measure
	# the merged local-space Z extent of their mesh slabs instead.
	var inv := pipe.global_transform.affine_inverse()
	var merged := AABB()
	var have_aabb := false
	for mesh in pipe.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = inv * mi.global_transform * mi.mesh.get_aabb()
		if have_aabb:
			merged = merged.merge(box)
		else:
			merged = box
			have_aabb = true
	if have_aabb and merged.size.z > 0.1:
		return merged.size.z
	return 9.5
