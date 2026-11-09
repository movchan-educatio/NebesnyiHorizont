## QA: render the authored infantry and vehicle hit VFX.
extends Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.14, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.8)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.22, 0.20, 0.17)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 45.0
	cam.position = Vector3(0.0, 2.0, 7.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)

	var inf := (load("res://Assets/combat/hit_infantry.glb") as PackedScene).instantiate()
	add_child(inf)
	inf.position = Vector3(-1.4, 1.0, 0.0)
	var veh := (load("res://Assets/combat/hit_vehicle.glb") as PackedScene).instantiate()
	add_child(veh)
	veh.position = Vector3(1.2, 1.0, 0.0)
	for n in [inf, veh]:
		for apn in n.find_children("*", "AnimationPlayer", true, false):
			var ap := apn as AnimationPlayer
			if ap.get_animation_list().has("Hit"):
				ap.play("Hit")
				ap.seek(0.20, true)
	await get_tree().create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/hitfx.png"
	print("[HITFXQA] ", out, " err=", img.save_png(out))
	get_tree().quit(0)
