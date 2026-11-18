extends Node3D

## Drives special op 10 (cruise missile intercept) and captures up to 10
## screenshots of the warning, waves, destruction VFX and results.
## Run windowed: Godot_v4.7.2-stable_win64.exe --path . res://test/qa_missile_capture.tscn

const SHOT_DIR := "res://screenshots/missile_intercept/"
const LEVEL := "res://sceneries/VillageLevel.tscn"

var _level: Node = null
var _cam: Camera3D = null
var _saved := 0

func _ready() -> void:
	# Match the real iOS build: the seamless horizon apron and the results
	# canvas layer (120, above the touch layer) are both mobile-gated.
	OS.set_environment("MOBILE_UI", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	Global.play_mode = Global.PlayMode.COMBAT
	Global.special_mission = 10
	Global.combat_mission = 1
	Global.drone_preset = 2
	Global.chain_briefing_pending = false
	var packed := load(LEVEL) as PackedScene
	_level = packed.instantiate()
	add_child(_level)
	await get_tree().create_timer(4.0).timeout

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = 68.0
	_cam.far = 2000.0
	_aim(Vector3(0.0, 32.0, 60.0), Vector3(0.0, 26.0, 0.0))
	_cam.current = true

	_level.call("_start_mission")
	await get_tree().create_timer(1.2).timeout
	await _shot("01_defence_ready")

	# Announced wave with countdown banner.
	_level.set("_intercept_timer", 7.0)
	_level.set("_intercept_warned", false)
	await get_tree().create_timer(0.5).timeout
	await _shot("02_air_raid_warning")

	# Launch the first wave and follow it in.
	_level.set("_intercept_timer", 0.05)
	await get_tree().create_timer(1.0).timeout
	await _follow_missile(26.0, 7.0)
	await _shot("03_wave01_launch")

	await get_tree().create_timer(3.0).timeout
	_aim(Vector3(-10.0, 34.0, 50.0), Vector3(-70.0, 28.0, 0.0))
	await _shot("04_wave01_formation")

	await _follow_missile(16.0, 4.0)
	await _shot("05_missile_closeup")

	# Lethal hit -> cinematic multiphase explosion.
	var missile := _first_missile()
	if missile != null:
		missile.take_damage(99999.0, missile.global_position)
		await _follow_missile(21.0, 5.0)
	await get_tree().create_timer(0.35).timeout
	await _shot("06_intercept_blast")

	await get_tree().create_timer(1.4).timeout
	_aim(Vector3(-20.0, 22.0, 40.0), Vector3(-70.0, 12.0, 0.0))
	await _shot("07_wreck_falling")

	# Jump to a later wave to show the repeating single-missile cadence.
	_level.set("_intercept_wave", 4)
	_level.set("_intercept_timer", 0.05)
	_level.set("_intercept_warned", false)
	await get_tree().create_timer(1.6).timeout
	_aim(Vector3(-10.0, 38.0, 70.0), Vector3(-40.0, 28.0, 0.0))
	await _shot("08_wave05_inbound")

	# Force one missile through the defended edge -> breach VFX + flash.
	var leaker := _first_missile()
	if leaker != null:
		var goal: Vector3 = (_current_entry() as Dictionary).get("goal", Vector3.ZERO)
		leaker.global_position = Vector3(goal.x - 1.0, leaker.global_position.y, goal.z)
	_aim(Vector3(108.0, 30.0, 48.0), Vector3(142.0, 24.0, 0.0))
	await get_tree().create_timer(0.6).timeout
	await _shot("09_leak_breach")

	# Direct success -> results/debrief screen.
	_level.call("_finish_special_success")
	await get_tree().create_timer(1.5).timeout
	await _shot("10_results")
	print("[QA-MISSILE] captured ", _saved, " screenshots in ", SHOT_DIR)
	get_tree().quit(0)


func _first_missile() -> Vehicle:
	var arr: Array = _level.get("_intercept_missiles")
	for e in arr:
		var v := (e as Dictionary).get("vehicle") as Vehicle
		if v != null and is_instance_valid(v) and not v.is_destroyed:
			return v
	return null


func _current_entry() -> Variant:
	var arr: Array = _level.get("_intercept_missiles")
	if arr.is_empty():
		return {"goal": Vector3(148.0, 0.0, 0.0)}
	return arr[0]


## Place the observer between the missile and the map centre, inside the
## arena, so no playable-edge geometry is ever framed.
func _follow_missile(distance: float, height: float) -> void:
	var m := _first_missile()
	if m == null:
		return
	var p := m.global_position
	var inward := Vector3(-p.x, 0.0, -p.z)
	if inward.length_squared() < 0.01:
		inward = Vector3.FORWARD
	inward = inward.normalized()
	var cam_pos := p + inward * distance + Vector3.UP * height
	cam_pos.x = clampf(cam_pos.x, -130.0, 130.0)
	cam_pos.z = clampf(cam_pos.z, -130.0, 130.0)
	_aim(cam_pos, p)


func _aim(pos: Vector3, target: Vector3) -> void:
	if _cam == null:
		return
	_cam.global_position = pos
	_cam.look_at(target, Vector3.UP)


func _shot(name: String) -> void:
	if _cam != null:
		_cam.current = true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		printerr("[QA-MISSILE] no viewport image for ", name)
		return
	var path := ProjectSettings.globalize_path(SHOT_DIR + name + ".png")
	img.save_png(path)
	_saved += 1
	print("[QA-MISSILE] shot ", name, " -> ", path)
