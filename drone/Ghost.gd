extends Node3D
class_name Ghost


enum State {STANDBY, PLAYING}
enum Type {GOLD, SILVER, BRONZE, PREVIOUS, ABORTED}

const TARGET_VISUAL_SPAN := 1.25
const MIN_VISUAL_SCALE := 2.4
const MAX_VISUAL_SCALE := 4.4
const TRAIL_MAX_POINTS := 72
const TRAIL_MIN_STEP := 0.42
const TRAIL_TELEPORT_RESET := 14.0
const TRAIL_HEAD_HALF_W := 0.22
const TRAIL_TAIL_HALF_W := 0.025

var replay_path := ""
var replay := []
var type: int = Type.PREVIOUS
var state: int = State.STANDBY
var frame := 0
var manual_step := false

var _visual_root: Node3D = null
var _trail_mesh_inst: MeshInstance3D = null
var _trail_mat: StandardMaterial3D = null
var _trail_points: Array[Vector3] = []
var _last_sample_pos: Vector3 = Vector3.INF
var _last_frame_idx: int = -1


func _ready() -> void:
	visible = false
	_ensure_trail_node()


func _physics_process(_delta: float) -> void:
	if state == State.PLAYING and not manual_step:
		frame += 1
		update_transform()


func _ghost_color() -> Color:
	match type:
		Type.GOLD:
			return Color(1.0, 0.82, 0.16)
		Type.SILVER:
			return Color(0.76, 0.88, 1.0)
		Type.BRONZE:
			return Color(1.0, 0.56, 0.24)
		Type.ABORTED:
			return Color(1.0, 0.26, 0.28)
		_:
			return Color(0.10, 0.95, 1.0)


func _ensure_trail_node() -> void:
	if _trail_mesh_inst != null and is_instance_valid(_trail_mesh_inst):
		_trail_mesh_inst.visible = visible
		return
	_trail_mesh_inst = MeshInstance3D.new()
	_trail_mesh_inst.name = "GhostTrail"
	_trail_mesh_inst.top_level = true
	_trail_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mesh_inst.visible = visible
	var col := _ghost_color()
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.albedo_color = Color.WHITE
	_trail_mat.emission_enabled = false
	_trail_mat.no_depth_test = false
	_trail_mesh_inst.material_override = _trail_mat
	_trail_mesh_inst.set_meta("trail_color", col)
	add_child(_trail_mesh_inst)


func add_meshes(node: Node, target_parent: Node3D = null) -> void:
	var dest: Node3D = target_parent if target_parent != null else self
	for child in node.get_children():
		add_meshes(child, dest)
		if child is MeshInstance3D:
			if child.name != "CW" and child.name != "CCW":
				var xform := get_mesh_transform(child)
				var dup := (child as MeshInstance3D).duplicate(0) as MeshInstance3D
				dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				dest.add_child(dup)
				dup.transform = xform


func get_mesh_transform(node: Node) -> Transform3D:
	var xform: Transform3D = node.transform if node is Node3D else Transform3D.IDENTITY
	var p := node.get_parent()
	if p is Node3D and not (p is Drone):
		xform = get_mesh_transform(p) * xform
	return xform


func update_drone_model(path: String) -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_visual_root = null
	_trail_mesh_inst = null

	_visual_root = Node3D.new()
	_visual_root.name = "GhostVisualRoot"
	add_child(_visual_root)

	var loaded_meshes := false
	if not path.is_empty() and ResourceLoader.exists(path):
		var drone_packed: PackedScene = load(path)
		if drone_packed != null and drone_packed.can_instantiate():
			var inst: Node3D = drone_packed.instantiate() as Node3D
			if inst != null:
				var holder: Node3D = inst
				if not (inst is Drone):
					holder = Drone.new()
					holder.add_child(inst)
				add_meshes(holder, _visual_root)
				holder.free()
				loaded_meshes = _visual_root.get_child_count() > 0
	if not loaded_meshes:
		_build_procedural_beacon(_visual_root)

	var combined_aabb := AABB()
	var has_aabb := false
	for child in _visual_root.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var local_box := mi.get_aabb()
			for cx in [0, 1]:
				for cy in [0, 1]:
					for cz in [0, 1]:
						var corner := mi.transform * Vector3(
							local_box.position.x + float(cx) * local_box.size.x,
							local_box.position.y + float(cy) * local_box.size.y,
							local_box.position.z + float(cz) * local_box.size.z
						)
						if not has_aabb:
							combined_aabb = AABB(corner, Vector3.ZERO)
							has_aabb = true
						else:
							combined_aabb = combined_aabb.expand(corner)
	var max_extent := maxf(combined_aabb.size.x, combined_aabb.size.z) if has_aabb else 0.35
	var v_scale := clampf(TARGET_VISUAL_SPAN / maxf(max_extent, 0.18), MIN_VISUAL_SCALE, MAX_VISUAL_SCALE)
	_visual_root.scale = Vector3.ONE * v_scale

	var col := _ghost_color()
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.72)
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	mat.distance_fade_max_distance = 1.4
	mat.distance_fade_min_distance = 0.35
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.8
	for child in _visual_root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = mat

	# Glowing holographic beacon halo around the ghost drone for instant visibility at distance.
	var halo := MeshInstance3D.new()
	halo.name = "GhostBeaconHalo"
	var torus := TorusMesh.new()
	var world_r := 0.62
	torus.inner_radius = world_r / v_scale
	torus.outer_radius = (world_r + 0.055) / v_scale
	torus.rings = 24
	torus.ring_segments = 8
	halo.mesh = torus
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hmat.albedo_color = Color(col.r, col.g, col.b, 0.65)
	halo.material_override = hmat
	_visual_root.add_child(halo)

	_ensure_trail_node()


func _build_procedural_beacon(parent_node: Node3D = null) -> void:
	var dest: Node3D = parent_node if parent_node != null else self
	for rot_deg in [45.0, -45.0]:
		var arm := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.45, 0.045, 0.055)
		arm.mesh = box
		arm.rotation_degrees.y = rot_deg
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dest.add_child(arm)
	var body := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(0.16, 0.075, 0.24)
	body.mesh = bbox
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dest.add_child(body)
	for px in [-0.16, 0.16]:
		for pz in [-0.16, 0.16]:
			var prop := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.085
			tor.outer_radius = 0.11
			tor.rings = 14
			tor.ring_segments = 6
			prop.mesh = tor
			prop.position = Vector3(px, 0.025, pz)
			prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			dest.add_child(prop)


func set_samples(samples: Array, model_path: String = "") -> void:
	replay = samples.duplicate(true)
	frame = 0
	_trail_points.clear()
	_last_sample_pos = Vector3.INF
	_last_frame_idx = -1
	if _visual_root == null or not is_instance_valid(_visual_root):
		update_drone_model(model_path)


func _parse_sample_transform(xform: Variant) -> Transform3D:
	var arr: Array = xform as Array
	var bx := Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	var by := Vector3(float(arr[3]), float(arr[4]), float(arr[5]))
	var bz := Vector3(float(arr[6]), float(arr[7]), float(arr[8]))
	var org := Vector3(float(arr[9]), float(arr[10]), float(arr[11]))
	return Transform3D(bx, by, bz, org).orthonormalized()


func update_transform(frac: float = 0.0) -> void:
	if frame < 0 or frame >= replay.size():
		return
	var xform: Variant = replay[frame]
	if xform == null or not (xform is Array) or (xform as Array).size() < 12:
		return
	var xf := _parse_sample_transform(xform)
	if frac > 0.001 and frame + 1 < replay.size():
		var xform_next: Variant = replay[frame + 1]
		if xform_next is Array and (xform_next as Array).size() >= 12:
			var xf1 := _parse_sample_transform(xform_next)
			if xf.origin.distance_to(xf1.origin) < TRAIL_TELEPORT_RESET:
				var f := clampf(frac, 0.0, 1.0)
				xf = Transform3D(xf.basis.slerp(xf1.basis, f), xf.origin.lerp(xf1.origin, f))
	global_transform = xf

	if frame < _last_frame_idx or (_last_sample_pos.is_finite() and xf.origin.distance_to(_last_sample_pos) > TRAIL_TELEPORT_RESET):
		_trail_points.clear()
		if _trail_mesh_inst != null and is_instance_valid(_trail_mesh_inst):
			_trail_mesh_inst.mesh = null
	_last_frame_idx = frame
	_last_sample_pos = xf.origin

	if state == State.PLAYING and visible:
		if _trail_points.is_empty() or _trail_points[_trail_points.size() - 1].distance_to(xf.origin) >= TRAIL_MIN_STEP:
			_trail_points.append(xf.origin)
			if _trail_points.size() > TRAIL_MAX_POINTS:
				_trail_points.remove_at(0)
			_rebuild_trail_mesh()


func _rebuild_trail_mesh() -> void:
	_ensure_trail_node()
	if _trail_mesh_inst == null:
		return
	var n := _trail_points.size()
	if n < 2:
		_trail_mesh_inst.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col := _ghost_color()
	var hdr_r := minf(col.r * 1.35, 1.5)
	var hdr_g := minf(col.g * 1.35, 1.5)
	var hdr_b := minf(col.b * 1.35, 1.5)
	var prev_side := Vector3.RIGHT
	var sides: Array[Vector3] = []
	var vups: Array[Vector3] = []
	sides.resize(n)
	vups.resize(n)

	for i in range(n):
		var fwd: Vector3
		if i == 0:
			fwd = _trail_points[1] - _trail_points[0]
		elif i == n - 1:
			fwd = _trail_points[n - 1] - _trail_points[n - 2]
		else:
			fwd = (_trail_points[i + 1] - _trail_points[i]).normalized() + (_trail_points[i] - _trail_points[i - 1]).normalized()
		if fwd.length_squared() < 1e-5:
			fwd = Vector3.FORWARD
		else:
			fwd = fwd.normalized()
		var s_vec := prev_side - fwd * prev_side.dot(fwd)
		if i == 0 or s_vec.length_squared() < 1e-4:
			s_vec = fwd.cross(Vector3.UP)
			if s_vec.length_squared() < 1e-4:
				s_vec = fwd.cross(Vector3.FORWARD)
		s_vec = s_vec.normalized()
		prev_side = s_vec
		var u_vec := s_vec.cross(fwd).normalized()
		var t := float(i) / float(n - 1)
		var hw := lerpf(TRAIL_TAIL_HALF_W, TRAIL_HEAD_HALF_W, t)
		sides[i] = s_vec * hw
		vups[i] = u_vec * hw

	var has_verts := false
	for i in range(n - 1):
		var a := _trail_points[i]
		var b := _trail_points[i + 1]
		if a.distance_squared_to(b) < 0.0004:
			continue
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		var c0 := Color(hdr_r, hdr_g, hdr_b, pow(t0, 1.35) * 0.86)
		var c1 := Color(hdr_r, hdr_g, hdr_b, pow(t1, 1.35) * 0.86)
		_emit_trail_quad(st, a - sides[i], a + sides[i], b + sides[i + 1], b - sides[i + 1], c0, c1)
		_emit_trail_quad(st, a - vups[i], a + vups[i], b + vups[i + 1], b - vups[i + 1], c0, c1)
		has_verts = true
	_trail_mesh_inst.mesh = st.commit() if has_verts else null


func _emit_trail_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
		c0: Color, c1: Color) -> void:
	st.set_color(c0)
	st.add_vertex(v0)
	st.set_color(c0)
	st.add_vertex(v1)
	st.set_color(c1)
	st.add_vertex(v2)
	st.set_color(c0)
	st.add_vertex(v0)
	st.set_color(c1)
	st.add_vertex(v2)
	st.set_color(c1)
	st.add_vertex(v3)


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
			var parts: PackedStringArray = line.split(",")
			var xform: Array = []
			xform.resize(parts.size())
			for i in range(parts.size()):
				xform[i] = float(parts[i])
			replay.append(xform)
		file.close()
		if not replay.is_empty():
			update_drone_model(str(replay[0][0]))


func _clear_trail() -> void:
	_trail_points.clear()
	_last_sample_pos = Vector3.INF
	_last_frame_idx = -1
	if _trail_mesh_inst != null and is_instance_valid(_trail_mesh_inst):
		_trail_mesh_inst.mesh = null
		_trail_mesh_inst.visible = visible


func start_replay() -> void:
	visible = true
	state = State.PLAYING
	_clear_trail()
	update_transform()


func stop_replay() -> void:
	state = State.STANDBY
	visible = false
	_clear_trail()


func reset_replay() -> void:
	frame = 0
	_clear_trail()


func export_to_text() -> String:
	return Global.export_ghost_track_text("", replay)


func import_from_text(encoded: String, model_path: String = "") -> bool:
	var imported := Global.import_ghost_track_text(encoded)
	if imported.is_empty():
		return false
	set_samples(imported, model_path)
	return true
