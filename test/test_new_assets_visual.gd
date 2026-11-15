extends Node3D

## Verifies imported bounding dimensions, ground contact (Y=0), procedural rifle
## & Spetsnaz kinematics, and optionally saves close-up screenshots when invoked
## with `-- <out_dir>`.

var _fails := 0


func _check(cond: bool, msg: String) -> void:
	print("[ASSETS-QA] ", "PASS " if cond else "FAIL ", msg)
	if not cond:
		_fails += 1


func _mesh_bounds_local(root: Node3D, relative_to: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		if mi.name == "MobileLodProxy":
			continue
		var xf := relative_to.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _ready() -> void:
	var shot_dir := ""
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() >= 1:
		shot_dir = uargs[0]
	var take_shots := not shot_dir.is_empty() and DisplayServer.get_name() != "headless"
	if take_shots:
		get_window().size = Vector2i(1280, 720)
		DirAccess.make_dir_recursive_absolute(shot_dir)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.56, 0.65, 0.72)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	floor_mi.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.32, 0.36, 0.28)
	floor_mat.roughness = 0.92
	floor_mi.material_override = floor_mat
	add_child(floor_mi)

	# Forward (-Z) ground arrow outside vehicle shadow so facing is unambiguous in shots.
	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_mat.albedo_color = Color(0.98, 0.85, 0.12)
	var stem := MeshInstance3D.new()
	var s_box := BoxMesh.new()
	s_box.size = Vector3(0.22, 0.02, 14.0)
	stem.mesh = s_box
	stem.material_override = arrow_mat
	stem.position = Vector3(-3.4, 0.015, -1.0)
	add_child(stem)
	var head := MeshInstance3D.new()
	var c_mesh := PrismMesh.new()
	c_mesh.size = Vector3(0.9, 1.4, 0.04)
	head.mesh = c_mesh
	head.material_override = arrow_mat
	head.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	head.position = Vector3(-3.4, 0.02, -8.5)
	add_child(head)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 500.0
	add_child(cam)
	cam.current = true

	var specs := [
		["btr8", Vehicle.Kind.APC, Vector3(-7.0, 3.6, -9.0), Vector3(0.0, 1.3, 0.0)],
		["mtsm", Vehicle.Kind.APC, Vector3(-9.5, 4.4, -11.5), Vector3(0.0, 1.5, 0.0)],
		["ural", Vehicle.Kind.TRUCK, Vector3(-7.2, 3.6, -9.2), Vector3(0.0, 1.4, 0.0)],
		["oreshnik", Vehicle.Kind.SAM, Vector3(-12.5, 5.6, -15.5), Vector3(0.0, 1.9, 0.0)],
	]

	for sp in specs:
		var variant: String = sp[0]
		var kind: int = sp[1]
		var v := Vehicle.new()
		v.kind = kind
		v.variant = variant
		v.hostile = false
		v.track_drone = false
		v.move_speed = 0.0
		v.position = Vector3.ZERO
		add_child(v)
		await get_tree().process_frame
		await get_tree().process_frame

		var m_node := v.get_node_or_null("Model") as Node3D
		_check(m_node != null, "%s spawned Model node" % variant)
		if m_node != null:
			var box := _mesh_bounds_local(m_node, v)
			print("[ASSETS-QA] ", variant, " bbox pos=", box.position, " size=", box.size)
			_check(box.size.x > 1.2 and box.size.y > 1.2 and box.size.z > 2.5,
					"%s has sane physical dimensions (%s)" % [variant, str(box.size)])
			_check(absf(box.position.y) <= 0.18,
					"%s wheels/tracks touch ground Y=0 (min_y=%.3f)" % [variant, box.position.y])
			if variant == "mtsm":
				_check(v.find_child("TrackBelt_L", true, false) == null,
						"mtsm skips procedural TrackBelt boxes")

		if take_shots:
			cam.global_position = sp[2]
			cam.look_at(sp[3], Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var out_path := shot_dir.path_join("shot_vehicle_%s.png" % variant)
			get_viewport().get_texture().get_image().save_png(out_path)
			print("[ASSETS-QA] saved ", out_path)
		v.queue_free()
		await get_tree().process_frame

	# Spetsnaz Soldier inspection: standing, crouching, dying
	var rig := DetailedSoldierRig.new()
	add_child(rig)
	await get_tree().process_frame
	var s_ok := rig.setup_rig(1, "spetsnaz")
	_check(s_ok and rig.skeleton != null and rig.rifle_pivot != null,
			"Spetsnaz rig setup succeeds with skeleton + RiflePivot")
	if s_ok:
		var box := _mesh_bounds_local(rig.model, self)
		print("[ASSETS-QA] spetsnaz scaled bbox pos=", box.position, " size=", box.size)
		_check(absf(box.position.y) <= 0.12 and box.size.y > 2.6,
				"Spetsnaz stands on ground Y=0 (min_y=%.3f, h=%.3f)" % [box.position.y, box.size.y])

		if take_shots:
			# Standing 3/4 view (Spetsnaz faces -Z; rig scaled 1.8x -> ~3.38m tall)
			rig.set("_crouch", 0.0)
			rig.call("_update_pose", 0.0)
			cam.global_position = Vector3(-4.0, 2.4, -4.8)
			cam.look_at(Vector3(0.0, 1.7, -0.1), Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					shot_dir.path_join("shot_spetsnaz_stand.png"))

			# Crouching side/3-4 view
			rig.set("_crouch", 1.0)
			rig.set("_crouch_target", 1.0)
			rig.set("_crouch_t", 1.0)
			rig.call("_update_pose", 0.0)
			cam.global_position = Vector3(-4.0, 1.9, -2.2)
			cam.look_at(Vector3(0.0, 1.3, -0.1), Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					shot_dir.path_join("shot_spetsnaz_crouch.png"))

			# Death pose
			rig.set("_dead", true)
			rig.set("_death_progress", 1.0)
			rig.set("_death_variant", 0)
			rig.call("_apply_death_pose")
			cam.global_position = Vector3(-3.0, 1.8, -2.5)
			cam.look_at(Vector3(0.0, 0.4, 0.4), Vector3.UP)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
					shot_dir.path_join("shot_spetsnaz_death.png"))
	rig.queue_free()
	await get_tree().process_frame

	print("[ASSETS-QA] fails=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
