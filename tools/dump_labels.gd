extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load("res://sceneries/BigLevel.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in range(6):
		await process_frame
	var hud := root.get_node_or_null("BigLevel/Drone/HUD")
	if hud != null:
		print("HUD size=", hud.size, " pos=", hud.position, " scale=", hud.scale, " xf=", hud.get_global_transform_with_canvas(), " vp=", root.get_viewport().get_visible_rect())
		var mc := hud.get_node_or_null("MarginContainer")
		if mc != null:
			print("MARGIN rect=", mc.get_global_rect(), " pos=", mc.position, " size=", mc.size, " xf=", mc.get_global_transform_with_canvas())
		var fm := hud.get_node_or_null("MarginContainer/FlightMode")
		if fm != null:
			print("FLIGHTMODE text=", JSON.stringify(fm.text), " rect=", fm.get_global_rect(), " pos=", fm.global_position, " xf=", fm.get_global_transform_with_canvas(), " color=", fm.get_theme_color("font_color"))
	var st := root.get_node_or_null("BigLevel/Drone/HUD/HUDStatus")
	if st != null:
		print("STATUS rect=", st.get_global_rect(), " xf=", st.get_global_transform_with_canvas(), " size=", st.size)
	quit()
