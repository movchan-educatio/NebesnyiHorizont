extends Node

## QA: render the Grim-7M menu preview with a desaturated battery atlas.

func _ready() -> void:
	Global.drone_preset = 6
	var menu := (load("res://GUI/MainMenu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i in range(30):
		await get_tree().process_frame
	var tex_img := Image.load_from_file("C:/Users/USER_UA/AppData/Local/Temp/opencode/grim7m_Image_0_dark.jpg")
	if tex_img == null:
		print("[GRIMTEX] image load failed")
		get_tree().quit(1)
		return
	var tex := ImageTexture.create_from_image(tex_img)
	for mi in menu.find_children("*", "MeshInstance3D", true, false):
		var node := mi as MeshInstance3D
		if node.name != "Object_4" or node.mesh == null:
			continue
		for s in range(node.mesh.get_surface_count()):
			var mat := node.mesh.surface_get_material(s)
			if mat is StandardMaterial3D:
				var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				copy.albedo_texture = tex
				node.set_surface_override_material(s, copy)
		print("[GRIMTEX] recolored ", node.name)
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/qa_menu_grim_dark.png"
	print("[GRIMTEX] saved=", out, " err=", img.save_png(out))
	get_tree().quit(0)
