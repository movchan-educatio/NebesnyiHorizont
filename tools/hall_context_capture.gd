## QA: build the real industrial terrain (same generator as Chaos) and capture
## the procedural halls in context, so real openings can be verified against the
## surrounding yard instead of an isolated white-box scene.
extends Node3D

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const OUT_DIR := "C:/Users/USER_UA/AppData/Local/Temp/opencode/building_qa"

var camera: Camera3D
var shots := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.49, 0.64)
	sky_mat.sky_horizon_color = Color(0.76, 0.79, 0.79)
	sky_mat.ground_bottom_color = Color(0.22, 0.22, 0.20)
	sky_mat.ground_horizon_color = Color(0.58, 0.58, 0.52)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.82)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.76, 0.78)
	env.fog_density = 0.0012
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.near = 0.05
	camera.far = 900.0
	camera.current = true
	add_child(camera)

	var t0 := Time.get_ticks_msec()
	TERRAIN.build_terrain(self, "industrial", 0.0)
	print("[HALLCTX] terrain_build_ms=", Time.get_ticks_msec() - t0)
	await get_tree().process_frame
	await get_tree().process_frame

	var hall := Vector2(-120.0, -40.0)
	var y := TERRAIN._height("industrial", hall.x, hall.y)
	var shots_list := [
		["ctx_hall_yard", Vector3(hall.x + 62.0, y + 38.0, hall.y - 76.0),
			Vector3(hall.x + 4.0, y + 7.0, hall.y + 2.0)],
		["ctx_hall_facade", Vector3(hall.x - 58.0, y + 9.0, hall.y - 21.0),
			Vector3(hall.x - 2.0, y + 5.0, hall.y - 14.0)],
		["ctx_hall_door", Vector3(hall.x - 15.66, y + 2.0, hall.y - 14.0 - 13.0),
			Vector3(hall.x - 15.66, y + 2.0, hall.y - 14.0)],
		["ctx_hall_window_inside", Vector3(hall.x - 8.12, y + 5.0, hall.y + 6.0),
			Vector3(hall.x - 8.12, y + 4.9, hall.y - 14.0)],
		["ctx_warehouse_yard", Vector3(-30.0 + 52.0, TERRAIN._height("industrial", -30.0, -120.0) + 22.0,
			-120.0 - 46.0), Vector3(-30.0, TERRAIN._height("industrial", -30.0, -120.0) + 5.0, -120.0)],
	]
	for shot in shots_list:
		await _capture(str(shot[0]), shot[1], shot[2])
	print("[HALLCTX] captured=", shots, " dir=", OUT_DIR)
	get_tree().quit()


func _capture(tag: String, pos: Vector3, target: Vector3) -> void:
	camera.look_at_from_position(pos, target, Vector3.UP)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, tag]
	print("[HALLCTX] ", tag, " saved=", path, " err=", img.save_png(path))
	shots += 1
