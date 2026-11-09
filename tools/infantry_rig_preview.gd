## QA: preview the integrated EnemyRifleman with the detailed soldier rig.
extends Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.21)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.83, 0.9)
	e.ambient_light_energy = 1.15
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 2.1
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, -140, 0)
	fill.light_energy = 0.8
	fill.light_color = Color(0.72, 0.84, 1.0)
	add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.29, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)

	var soldier := EnemyRifleman.new()
	add_child(soldier)
	soldier.position = Vector3.ZERO
	soldier.rotation.y = 0.0
	await get_tree().process_frame
	var rig = soldier.get("_detailed_rig")
	if rig != null:
		rig.set_aim_pitch(0.12)
		rig.set_walk(float(OS.get_environment("WALK_PHASE")), 1.0)
		print("[INFANTRY] detailed rig OK, muzzle=", rig.muzzle)
		if OS.get_environment("TEST_L_ARM") != "":
			var skel_dbg = rig.get("skeleton")
			if skel_dbg != null:
				for bi in range(skel_dbg.get_bone_count()):
					if skel_dbg.get_bone_name(bi).contains("Bip01 L UpperArm"):
						var spec: String = OS.get_environment("TEST_L_ARM")
						var parts := spec.split(":")
						var axis := Vector3.BACK
						if parts[0] == "x": axis = Vector3.RIGHT
						elif parts[0] == "y": axis = Vector3.UP
						skel_dbg.set_bone_pose_rotation(bi,
								Quaternion(axis, deg_to_rad(float(parts[1]))))
						print("[INFANTRY] L arm ", spec, " bone ", bi)
						break
		for apn in rig.find_children("*", "AnimationPlayer", true, false):
			var ap := apn as AnimationPlayer
			print("[INFANTRY] animplayer current=", ap.current_animation, " playing=", ap.is_playing())
		var model = rig.get("model")
		if model != null:
			for n in model.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var mats: Array[String] = []
				if mi.mesh != null:
					for s in range(mi.mesh.get_surface_count()):
						var m := mi.mesh.surface_get_material(s)
						if m != null:
							mats.append(String(m.resource_name))
				print("[INFANTRY] mesh ", mi.name, " visible=", mi.visible, " mats=", mats)
		if rig.get("rifle_pivot") != null:
			var rp = rig.get("rifle_pivot")
			var skel = rig.get("skeleton")
			var sup = rig.get("_b_support")
			if skel != null and sup != null and int(sup) >= 0:
				print("[INFANTRY] support bone=", skel.get_bone_name(int(sup)),
						" rot=", skel.get_bone_pose_rotation(int(sup)))
			print("[INFANTRY] rifle pivot pos=", rp.position, " rot=", rp.rotation_degrees,
					" children=", rp.get_child_count())
			var copy := rp.get_child(0) as MeshInstance3D
			if copy != null:
				await get_tree().process_frame
				print("[INFANTRY] copy pos=", copy.position, " global_basis=", copy.global_transform.basis)
				print("[INFANTRY] copy world aabb=", copy.global_transform * copy.get_aabb())
	else:
		print("[INFANTRY] detailed rig FAILED, fallback model")

	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 40.0
	var cam_yaw := deg_to_rad(float(OS.get_environment("CAM_YAW")))
	cam.position = Vector3(sin(cam_yaw) * 3.6, 1.2, -cos(cam_yaw) * 3.6)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for i in range(10):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("MODEL_OUT")
	if out.is_empty():
		out = "C:/Users/USER_UA/AppData/Local/Temp/opencode/infantry_rig.png"
	print("[INFANTRY] saved ", out, " err=", img.save_png(out))
	get_tree().quit(0)
