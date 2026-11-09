extends Node3D

## QA-only terrain preview: builds one frontline map, places a low FPV-style
## camera near the ground and configures the cinematic environment without the
## HUD / FPV overlay.  Activated with MAP=village|steppe|industrial|wetlands.

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")
const VISUAL := preload("res://scripts/util/visual_enhancer.gd")
const QUALITY := preload("res://scripts/util/quality_manager.gd")

var _cam: Camera3D

func _ready() -> void:
	var map_name := OS.get_environment("MAP").to_lower()
	if map_name.is_empty():
		map_name = "village"
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	add_child(we)
	VISUAL.setup_world_environment(we.environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, -38.0, 0.0)
	add_child(sun)
	VISUAL.setup_sun_lighting(sun)
	QUALITY.apply_to_scene(self)
	if OS.has_environment("NO_SHADOWS"):
		sun.shadow_enabled = false

	TERRAIN.build_terrain(self, map_name, 0.0)
	TERRAIN.build(self, map_name, 0.0)

	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = 82.0
	_cam.near = 0.02
	_cam.far = 3000.0
	add_child(_cam)
	VISUAL.enhance_camera(_cam)
	_cam.attributes = null
	if OS.has_environment("POI_VIEW"):
		# Frame the map's signature landmark for a visual QA capture.
		var poi := find_child("POI_*", true, false) as Node3D
		if poi != null:
			_cam.global_position = poi.global_position + Vector3(14.0, 5.0, 16.0)
			_cam.look_at(poi.global_position + Vector3(0.0, 3.5, 0.0), Vector3.UP)
			print("[QA] POI view ", poi.name, " at ", poi.global_position)
	elif OS.has_environment("CAM_POS"):
		# QA camera override: CAM_POS="x,y,z" CAM_TARGET="x,y,z".
		var p := OS.get_environment("CAM_POS").split(",")
		var t := OS.get_environment("CAM_TARGET").split(",")
		if p.size() == 3 and t.size() == 3:
			_cam.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			_cam.look_at(Vector3(float(t[0]), float(t[1]), float(t[2])), Vector3.UP)
	elif OS.has_environment("AERIAL"):
		# Typical FPV diving view: high enough to judge the terrain palette and
		# the tree/prop placement, not just the ground under the camera.
		_cam.global_position = Vector3(-40.0, 38.0, 75.0)
		_cam.look_at(Vector3(10.0, 0.0, -110.0), Vector3.UP)
	else:
		_cam.global_position = Vector3(-2.0, 2.2, 18.0)
		_cam.look_at(Vector3(2.0, 0.0, -60.0), Vector3.UP)
	if OS.has_environment("DESTROY_DEMO"):
		_qa_destroy_demo()


## QA-only: blows up the first destructible landmark so a screenshot can show
## the rubble, smoke and crater.
func _qa_destroy_demo() -> void:
	await get_tree().create_timer(2.0).timeout
	var marks := get_tree().get_nodes_in_group("destructible")
	if marks.is_empty():
		print("[DEMO] no destructible")
		return
	var lm := marks[0] as Node3D
	var explosion := load("res://combat/explosion.gd")
	explosion.spawn(self, lm.global_position + Vector3.UP * 1.5, 10.0, 1.0)
	lm.take_damage(999999.0, lm.global_position)
	print("[DEMO] destroyed ", lm.name, " at ", lm.global_position)
