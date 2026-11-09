extends Node

## QA: place a camera from the actual CoolingTower/SiloShell AABB and capture.
func _ready() -> void:
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 1
	Global.combat_mission = 1
	Global.drone_preset = 6
	var packed := load("res://sceneries/IndustrialLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	await get_tree().create_timer(5.0).timeout
	var ft := level.get_node_or_null("FrontlineTerrain")
	var ct := level.get_node_or_null("FrontlineTerrain/CoolingTower") as MeshInstance3D
	var target := Vector3.ZERO
	var dist := 80.0
	if ct != null:
		var bb: AABB = ct.global_transform * ct.mesh.get_aabb()
		target = bb.get_center()
		dist = maxf(bb.size.x, bb.size.z) * 2.2
		print("[TOWERSHOT] cooling center=", target, " size=", bb.size,
				" dist=", dist)
	else:
		print("[TOWERSHOT] no cooling tower")
	# Find the first silo shell.
	for n in level.find_children("SiloShell", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var bb: AABB = mi.global_transform * mi.mesh.get_aabb()
		print("[TOWERSHOT] silo center=", bb.get_center(), " size=", bb.size)
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 2000.0
	level.add_child(cam)
	cam.global_position = target + Vector3(0.0, 8.0, dist)
	cam.look_at(target, Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://qa_shots/tower_actual.png"
	img.save_png(path)
	print("[TOWERSHOT] saved ", path, " err=", img)
	get_tree().quit()
