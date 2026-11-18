extends Node3D

## Captures the four frontline maps with the corrected daylight grade.
## Run: Godot_v4.7.2-stable_win64.exe --path . res://test/qa_map_brightness.tscn

const SHOT_DIR := "res://screenshots/maps_bright/"
const MAPS := {
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
}

var _cam: Camera3D = null

func _ready() -> void:
	OS.set_environment("MOBILE_UI", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 0
	Global.combat_mission = 1

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 70.0
	_cam.far = 2000.0
	_cam.current = true

	for map_id in MAPS.keys():
		var packed := load(str(MAPS[map_id])) as PackedScene
		if packed == null:
			printerr("[MAP-QA] cannot load ", MAPS[map_id])
			continue
		var level := packed.instantiate()
		add_child(level)
		await get_tree().create_timer(4.0).timeout
		_cam.global_position = Vector3(0.0, 38.0, 72.0)
		_cam.look_at(Vector3(0.0, 18.0, 0.0), Vector3.UP)
		await _shot("map_%s" % map_id)
		level.queue_free()
		await get_tree().create_timer(1.2).timeout

	print("[MAP-QA] done")
	get_tree().quit(0)


func _shot(name: String) -> void:
	_cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var path := ProjectSettings.globalize_path(SHOT_DIR + name + ".png")
	img.save_png(path)
	print("[MAP-QA] shot ", name, " -> ", path)
