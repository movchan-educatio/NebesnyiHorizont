extends Node3D

## QA-only: render one merged infantryman against a neutral sky and save the
## frame, so texture-atlas seams or missing parts are obvious.


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.64, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)

	var cam := Camera3D.new()
	cam.position = Vector3(1.4, 1.35, 2.9)
	cam.fov = 42.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, 0.0))

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = PlaneMesh.new()
	(floor_mesh.mesh as PlaneMesh).size = Vector2(12.0, 12.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.28, 0.30, 0.26)
	floor_mesh.material_override = fm
	add_child(floor_mesh)

	var rig := DetailedSoldierRig.new()
	add_child(rig)
	var ok := rig.setup_rig(99)
	print("[SOLDIER-SHOT] rig=", ok)

	await get_tree().create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var shot := OS.get_environment("SHOT_PATH")
	if shot.is_empty():
		shot = "res://qa_shots/soldier_merged.png"
	var err := img.save_png(shot)
	print("[SOLDIER-SHOT] ", ProjectSettings.globalize_path(shot), " err=", err)
	get_tree().quit()
