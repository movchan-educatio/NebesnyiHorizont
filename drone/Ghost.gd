extends Node3D
class_name Ghost


enum State {STANDBY, PLAYING}
enum Type {GOLD, SILVER, BRONZE, PREVIOUS, ABORTED}


var replay_path := ""
var replay := []
var type: int = Type.PREVIOUS
var state: int = State.STANDBY
var frame := 0
var manual_step := false


func _ready() -> void:
	visible = false


func _physics_process(_delta: float) -> void:
	if state == State.PLAYING and not manual_step:
		frame += 1
		update_transform()


func add_meshes(node: Node) -> void:
	for child in node.get_children():
		add_meshes(child)
		if child is MeshInstance3D:
			if child.name != "CW" and child.name != "CCW":
				var xform := get_mesh_transform(child)
				add_child(child.duplicate(0))
				get_child(get_child_count() - 1).transform = xform


func get_mesh_transform(node: Node) -> Transform3D:
	var xform: Transform3D = node.transform
	if not node.get_parent() is Drone:
		xform *= get_mesh_transform(node.get_parent())
	return xform


func update_drone_model(path: String) -> void:
	for ch in get_children():
		ch.queue_free()
	var loaded_meshes := false
	if not path.is_empty() and ResourceLoader.exists(path):
		var drone_packed: PackedScene = load(path)
		if drone_packed != null and drone_packed.can_instantiate():
			var drone: Drone = drone_packed.instantiate() as Drone
			if drone != null:
				add_meshes(drone)
				drone.queue_free()
				loaded_meshes = get_child_count() > 0
	if not loaded_meshes:
		_build_procedural_beacon()
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.85, 1.0, 0.34)
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_max_distance = 1.2
	mat.distance_fade_min_distance = 0.25
	match type:
		Type.GOLD:
			mat.emission = Color(0.95, 0.72, 0.15)
		Type.SILVER:
			mat.emission = Color(0.65, 0.75, 0.90)
		Type.BRONZE:
			mat.emission = Color(0.55, 0.30, 0.10)
		Type.PREVIOUS:
			mat.emission = Color(0.20, 0.75, 1.0)
		Type.ABORTED:
			mat.emission = Color(0.90, 0.20, 0.20)
	mat.emission_enabled = true
	for child in get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat


func _build_procedural_beacon() -> void:
	var frame := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.28, 0.08, 0.28)
	frame.mesh = box
	add_child(frame)


func set_samples(samples: Array, model_path: String = "") -> void:
	replay = samples.duplicate(true)
	frame = 0
	if get_child_count() == 0:
		update_drone_model(model_path)


func update_transform() -> void:
	if frame < replay.size():
		var xform: Array = replay[frame]
		if xform.size() < 12:
			return
		var basis_x := Vector3(float(xform[0]), float(xform[1]), float(xform[2]))
		var basis_y := Vector3(float(xform[3]), float(xform[4]), float(xform[5]))
		var basis_z := Vector3(float(xform[6]), float(xform[7]), float(xform[8]))
		var origin := Vector3(float(xform[9]), float(xform[10]), float(xform[11]))
		global_transform = Transform3D(basis_x, basis_y, basis_z, origin).orthonormalized()


func read_replay():
	replay.clear()
	match type:
		Type.PREVIOUS:
			replay_path = replay_path.replace(".rpl", "_prev.rpl")
		Type.GOLD:
			replay_path = replay_path.replace(".rpl", "_gold.rpl")
		Type.SILVER:
			replay_path = replay_path.replace(".rpl", "_silver.rpl")
		Type.BRONZE:
			replay_path = replay_path.replace(".rpl", "_bronze.rpl")
		Type.ABORTED:
			replay_path = replay_path.replace(".rpl", "_aborted.rpl")
	var file := FileAccess.open(replay_path, FileAccess.READ)
	if file != null:
		while not file.eof_reached():
			var line := file.get_line()
			if line == "":
				break
			var xform: Array = line.split(",")
			replay.append(xform)
		file.close()
		if not replay.is_empty():
			update_drone_model(replay[0][0])
		


func start_replay() -> void:
	visible = true
	state = State.PLAYING


func stop_replay() -> void:
	state = State.STANDBY
	visible = false


func reset_replay() -> void:
	frame = 0


func export_to_text() -> String:
	return Global.export_ghost_track_text("", replay)


func import_from_text(encoded: String, model_path: String = "") -> bool:
	var imported := Global.import_ghost_track_text(encoded)
	if imported.is_empty():
		return false
	set_samples(imported, model_path)
	return true
