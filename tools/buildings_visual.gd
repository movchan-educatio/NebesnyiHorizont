## QA: visual stills of a procedural industrial hall and farmhouse after the
## collision rebuild.  The shots show real door/window holes (no glass) and the
## roof eaves, so the invisible-wall fix can be checked by eye alongside the
## raycast tests.
extends Node3D

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const OUT_DIR := "C:/Users/USER_UA/AppData/Local/Temp/opencode/building_qa"

var viewport: SubViewport
var camera: Camera3D
var shots_taken := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.48, 0.62)
	sky_mat.sky_horizon_color = Color(0.74, 0.78, 0.78)
	sky_mat.ground_bottom_color = Color(0.20, 0.21, 0.19)
	sky_mat.ground_horizon_color = Color(0.55, 0.56, 0.50)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.76, 0.80)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	viewport.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.shadow_enabled = true
	viewport.add_child(sun)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 600.0
	viewport.add_child(camera)

	var world := Node3D.new()
	viewport.add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(300.0, 300.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.33, 0.33, 0.30)
	gm.roughness = 1.0
	ground.material_override = gm
	ground.position = Vector3(-80.0, TERRAIN._height("industrial", -80.0, -40.0) - 0.03,
			-40.0)
	world.add_child(ground)

	var concrete := TERRAIN._pbr("concrete", Color(0.84, 0.83, 0.79), 0.18)
	var brick := TERRAIN._pbr("brick", Color(0.82, 0.68, 0.58), 0.22)
	var metal := TERRAIN._pbr("steel", Color(0.52, 0.55, 0.57), 0.14)
	var wall := TERRAIN._pbr("wood", Color(0.67, 0.61, 0.51), 0.30)
	var roof := TERRAIN._pbr("roof", Color(0.32, 0.25, 0.20), 0.36)
	var stone := TERRAIN._pbr("stone", Color(0.55, 0.53, 0.48), 0.22)
	# Hall exactly as the industrial map builds it.
	var hall_pos := Vector2(-120.0, -40.0)
	TERRAIN._add_hall(world, "industrial", hall_pos, 58.0, 14.0, 28.0, 0.0,
			brick, metal)
	var hy := TERRAIN._height("industrial", hall_pos.x, hall_pos.y)
	# A procedural farmhouse nearby, same shell as the village outskirts.
	var hp := Vector2(-10.0, -40.0)
	TERRAIN._add_simple_house(world, "industrial", hp, 0.0, 8.0, 7.0, 4.0,
			wall, roof, stone)
	var wy := TERRAIN._height("industrial", hp.x, hp.y)

	var shots := [
		["hall_front", Vector3(-120.0 + 29.0, hy + 9.0, -40.0 - 40.0),
			Vector3(-120.0 + 6.0, hy + 4.5, -40.0 - 12.0)],
		["hall_window", Vector3(-120.0 + 8.12, hy + 6.0, -40.0 - 21.0),
			Vector3(-120.0 + 8.12, hy + 5.6, -40.0 + 4.0)],
		["hall_door", Vector3(-120.0 - 15.66, hy + 2.1, -40.0 - 21.0),
			Vector3(-120.0 - 15.66, hy + 2.1, -40.0 + 4.0)],
		["hall_side", Vector3(-120.0 + 42.0, hy + 7.0, -40.0 + 6.0),
			Vector3(-120.0 + 29.0, hy + 4.6, -40.0 + 1.0)],
		["hall_eave", Vector3(-120.0 + 31.0, hy + 17.0, -40.0 - 22.0),
			Vector3(-120.0 + 20.0, hy + 14.2, -40.0 - 15.0)],
		["house_front", Vector3(hp.x + 7.0, wy + 3.2, -40.0 - 10.0),
			Vector3(hp.x + 1.0, wy + 1.9, -40.0 - 3.5)],
		# Perpendicular elevation of the +Z front: door in the middle, two
		# windows with visible sills, no glass.
		["house_elevation", Vector3(hp.x + 0.2, wy + 2.0, -40.0 + 15.0),
			Vector3(hp.x + 0.2, wy + 2.0, -40.0 + 3.5)],
		["house_window", Vector3(hp.x + 2.4, wy + 1.9, -40.0 - 8.0),
			Vector3(hp.x + 2.4, wy + 1.9, -40.0 + 2.0)],
	]
	for shot in shots:
		await _capture(str(shot[0]), shot[1], shot[2])
	print("[BUILDQA] captured=", shots_taken, " dir=", OUT_DIR)
	get_tree().quit()


func _capture(tag: String, pos: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(pos, target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[BUILDQA] ", tag, " saved=", path, " err=", err)
	shots_taken += 1
