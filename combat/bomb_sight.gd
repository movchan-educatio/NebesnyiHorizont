class_name BombSight
extends Control

## CCIP bomb sight for the Baba Yaga heavy bomber.
##
## The pipper is a real ballistic impact point computed from the drone's
## current velocity, gravity, quadratic drag and the level wind.  It stays as a
## compact impact marker in the FPV frame; there is no separate bomb camera.
##
## Keys: T — thermal camera (white-hot).

const Ballistics = preload("res://combat/ballistics.gd")

var level: Node = null
var drone: Node3D = null
var camera: Camera3D = null
var kind := "82mm"
var bomb_view := false
var thermal := false

var _solution: Dictionary = {}
var _aim_point := Vector3.ZERO
var _aim_valid := false
var _tick := 0.0
var _font: Font = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font

	set_process(true)
	queue_redraw()


func set_thermal(on: bool) -> void:
	thermal = on
	queue_redraw()


func set_bomb_view(on: bool) -> void:
	bomb_view = on
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.11
		_recompute()
	queue_redraw()


func _recompute() -> void:
	if level == null or drone == null or not is_instance_valid(drone):
		_solution = {}
		return
	camera = get_viewport().get_camera_3d()
	if camera == null:
		_solution = {}
		return
	var wind: Vector3 = level.get("_current_wind_vector") if level.get("_current_wind_vector") != null else Vector3.ZERO
	var origin: Vector3 = drone.global_position + Vector3.DOWN * 1.15
	var vel: Vector3 = drone.linear_velocity + Vector3.DOWN * 0.5
	var map_name := String(level.get("frontline_map")) \
			if level.get("frontline_map") != null else ""
	_solution = Ballistics.simulate(level, map_name, origin, vel, wind, kind)

	# Ground point under the camera centre: this is what the pilot is aiming
	# at, and it drives the "release now" cue.
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 3000.0
	var space := camera.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	if drone is CollisionObject3D:
		q.exclude = [(drone as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	_aim_valid = not hit.is_empty()
	_aim_point = hit.get("position", Vector3.ZERO)


func _draw() -> void:
	if _solution.is_empty() or camera == null:
		return
	var impact: Vector3 = _solution.get("impact", Vector3.ZERO)
	if camera.is_position_behind(impact):
		return
	var p := camera.unproject_position(impact)
	var view := get_viewport_rect().size
	var col := Color(0.55, 1.0, 0.62, 0.95)
	if thermal:
		col = Color(1.0, 0.85, 0.55, 0.98)
	var font_size := 16 if not bomb_view else 18
	var wind: Vector3 = _solution.get("wind", Vector3.ZERO)
	var tof: float = _solution.get("tof", 0.0)
	var drift: Vector2 = _solution.get("drift", Vector2.ZERO)
	var dist_to_aim := impact.distance_to(_aim_point) if _aim_valid else 999.0
	var ready := _aim_valid and dist_to_aim < 9.0 and drone.global_position.y > _aim_point.y + 20.0

	if bomb_view:
		# dark scope frame, vertical mil ladder and an unobstructed centre
		draw_rect(Rect2(Vector2.ZERO, view), Color(0.005, 0.012, 0.010, 0.20), true)
		var cx := view.x * 0.5
		var cy := view.y * 0.5
		draw_line(Vector2(cx, 0), Vector2(cx, view.y), Color(0.1, 0.55, 0.25, 0.55), 2.0)
		draw_line(Vector2(0, cy), Vector2(view.x, cy), Color(0.1, 0.55, 0.25, 0.55), 2.0)
		for i in range(-5, 6):
			var y := cy + float(i) * 42.0
			var w := 22.0 if i % 5 == 0 else 12.0
			draw_line(Vector2(cx - w, y), Vector2(cx + w, y), col, 1.5)
		draw_circle(Vector2(cx, cy), 4.0, col)
		draw_arc(Vector2(cx, cy), 54.0, 0.0, TAU, 48, Color(col, 0.55), 1.5)

	# CCIP pipper
	draw_arc(p, 22.0 if bomb_view else 13.0, 0.0, TAU, 36, col, 2.0)
	draw_line(p + Vector2(-30, 0), p + Vector2(-8, 0), col, 2.0)
	draw_line(p + Vector2(8, 0), p + Vector2(30, 0), col, 2.0)
	draw_line(p + Vector2(0, -30), p + Vector2(0, -8), col, 2.0)
	draw_line(p + Vector2(0, 8), p + Vector2(0, 30), col, 2.0)

	# wind vector and flight solution
	var alt: float = drone.global_position.y - _aim_point.y if _aim_valid else 0.0
	var gs: float = Vector2(drone.linear_velocity.x, drone.linear_velocity.z).length() * 3.6
	var wind_speed := wind.length()
	var wind_dir := _compass_arrow(wind)
	var left_lines := [
		"BABA YAGA · %s" % ("BOMB SIGHT" if bomb_view else "CCIP"),
		"ALT  %4.0f m    GS  %3.0f km/h" % [alt, gs],
		"WIND %3.1f m/s %s    TOF %3.1f s" % [wind_speed, wind_dir, tof],
		"DRIFT  %4.1f m    AMMO %d" % [drift.length(), _ammo()],
	]
	var y0 := view.y - 132.0
	for i in range(left_lines.size()):
		var c := Color(0.82, 1.0, 0.86, 0.95) if thermal else Color(0.78, 0.95, 0.80, 0.95)
		draw_string(_font, Vector2(22, y0 + float(i) * 22.0), left_lines[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, c)

	if ready:
		var msg := "СКИД / RELEASE" if MenuUI.is_english() else "СКИД"
		draw_string(_font, Vector2(view.x * 0.5 - 78, view.y - 54),
				msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 24,
				Color(0.45, 1.0, 0.48, 1.0))
	if not bomb_view:
		var hint := "T — тепловізор" if not MenuUI.is_english() \
				else "T — thermal"
		draw_string(_font, Vector2(22, view.y - 24), hint,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.7, 0.84, 0.72, 0.8))
	else:
		var hint2 := "G — скид   T — тепловізор" if not MenuUI.is_english() \
				else "G — release   T — thermal"
		draw_string(_font, Vector2(view.x * 0.5 - 170, view.y - 22), hint2,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.7, 0.84, 0.72, 0.8))
	if thermal:
		draw_string(_font, Vector2(view.x - 132, 30), "THERMAL · WHITE HOT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(1.0, 0.82, 0.48, 0.95))


func _ammo() -> int:
	if level != null and level.has_method("_ammo_count"):
		return int(level.call("_ammo_count"))
	return 0


func _compass_arrow(w: Vector3) -> String:
	if w.length() < 0.1:
		return "—"
	var ang := atan2(w.x, -w.z) * 180.0 / PI
	if ang < 0.0:
		ang += 360.0
	var names := ["Пн", "ПнСх", "Сх", "ПдСх", "Пд", "ПдЗх", "Зх", "ПнЗх"]
	if MenuUI.is_english():
		names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return names[int(round(ang / 45.0)) % 8]
