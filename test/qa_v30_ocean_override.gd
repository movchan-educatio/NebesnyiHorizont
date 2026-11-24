extends Node

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var packed := load("res://maps/oil_rig/oil_rig_map.tscn") as PackedScene
	var map := packed.instantiate()
	add_child(map)
	await get_tree().create_timer(1.0).timeout
	var ocean := map.find_child("Ocean", true, false) as MeshInstance3D
	var sm := ocean.material_override as ShaderMaterial
	print("[OCEAN] before deep=", sm.get_shader_parameter("deep_color"))
	sm.set_shader_parameter("deep_color", Color(0.01, 0.25, 0.55, 1.0))
	sm.set_shader_parameter("shallow_color", Color(0.02, 0.55, 0.70, 1.0))
	print("[OCEAN] after deep=", sm.get_shader_parameter("deep_color"))
	var cam := Camera3D.new()
	cam.far = 6000.0
	map.add_child(cam)
	cam.global_position = Vector3(-420.0, 720.0, 880.0)
	cam.look_at(Vector3(0.0, 400.0, 0.0), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("res://qa_shots/v30_ocean_override.png")
	get_tree().quit()
