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
	add_to_group("bomb_sight")
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
	# Use the exact state the physical store will be spawned with.  A modelled
	# bomb rack (Baba Yaga) supplies its own bay origin; every other dropper uses
	# the shared hardpoint.  The old sight guessed a point 1.15 m below the
	# airframe while the bomber released from its bay 0.3 m below, so the pipper
	# always landed short of the real impact.
	var state: Dictionary = Ballistics.release_state(drone)
	if level.has_method("_bomb_release_state"):
		state = level.call("_bomb_release_state", drone, kind)
	var origin: Vector3 = state.get("origin", drone.global_position \
			+ Vector3.DOWN * Ballistics.RELEASE_DOWN_OFFSET)
	var vel: Vector3 = state.get("velocity", drone.linear_velocity \
			+ Vector3.DOWN * Ballistics.RELEASE_DOWN_IMPULSE)
	var map_name := String(level.get("frontline_map")) \
			if level.get("frontline_map") != null else ""
	_solution = Ballistics.simulate(level, map_name, origin, vel, wind, kind, 0.02)

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
	var centre := view * 0.5
	var col := Color(0.55, 1.0, 0.62, 0.98)
	if thermal:
		col = Color(1.0, 0.85, 0.55, 0.99)
	var screen_dist := p.distance_to(centre)
	var dist_to_aim := impact.distance_to(_aim_point) if _aim_valid else 999.0
	# The release cue is screen-space: a pipper sitting on the camera centre
	# means the predicted impact is exactly on the aim point.  The old 20 m
	# altitude gate hid the cue for every normal low-level drop.
	var ready := screen_dist <= 26.0 or (_aim_valid and dist_to_aim < 5.0)
	var margin := 30.0
	var marker := Vector2(
			clampf(p.x, margin, maxf(margin, view.x - margin)),
			clampf(p.y, margin, maxf(margin, view.y - margin)))
	var off_screen := marker.distance_to(p) > 0.5

	if bomb_view:
		# dark scope frame, vertical mil ladder and an unobstructed centre
		draw_rect(Rect2(Vector2.ZERO, view), Color(0.005, 0.012, 0.010, 0.20), true)
		draw_line(Vector2(centre.x, 0), Vector2(centre.x, view.y),
				Color(0.1, 0.55, 0.25, 0.55), 2.0)
		draw_line(Vector2(0, centre.y), Vector2(view.x, centre.y),
				Color(0.1, 0.55, 0.25, 0.55), 2.0)
		for i in range(-5, 6):
			var y := centre.y + float(i) * 42.0
			var w := 22.0 if i % 5 == 0 else 12.0
			draw_line(Vector2(centre.x - w, y), Vector2(centre.x + w, y), col, 1.5)
		draw_circle(centre, 4.0, col)
		draw_arc(centre, 54.0, 0.0, TAU, 48, Color(col, 0.55), 1.5)

	# Centre bracket: the release reference.  It lights up when the pipper is
	# on it, so the pilot can see both the aim point and the predicted impact.
	var bracket := 38.0 if ready else 30.0
	var bracket_col := Color(0.45, 1.0, 0.48, 0.95) if ready \
			else Color(0.66, 1.0, 0.72, 0.5)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tip: Vector2 = centre + corner * bracket
		draw_line(tip, tip - Vector2(corner.x * 14.0, 0), bracket_col, 2.0)
		draw_line(tip, tip - Vector2(0, corner.y * 14.0), bracket_col, 2.0)

	# CCIP pipper: brighter and larger than the old 13 px ring so it stays
	# readable over bright terrain on a phone screen.
	var radius := 24.0 if bomb_view else 18.0
	draw_circle(marker, 2.6, col)
	draw_arc(marker, radius, 0.0, TAU, 40, col, 2.6)
	if ready:
		draw_arc(marker, radius + 7.0, 0.0, TAU, 40, Color(0.45, 1.0, 0.48, 0.9), 2.0)
	draw_line(marker + Vector2(-radius - 16, 0), marker + Vector2(-radius - 4, 0), col, 2.2)
	draw_line(marker + Vector2(radius + 4, 0), marker + Vector2(radius + 16, 0), col, 2.2)
	draw_line(marker + Vector2(0, -radius - 16), marker + Vector2(0, -radius - 4), col, 2.2)
	draw_line(marker + Vector2(0, radius + 4), marker + Vector2(0, radius + 16), col, 2.2)

	if off_screen:
		# The true impact is outside the lens (common in level flight at
		# altitude).  Keep an edge marker and point toward it instead of
		# silently clipping the whole sight.
		var dir := (p - marker).normalized()
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			marker + dir * 16.0,
			marker - dir * 4.0 + side * 8.0,
			marker - dir * 4.0 - side * 8.0,
		]), col)
		var tof := float(_solution.get("tof", 0.0))
		draw_string(_font, marker + Vector2(-34, -30), "%.1f s" % tof,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(col, 0.9))

	if ready:
		var release_text := "RELEASE" if MenuUI.is_english() else "СКИД"
		draw_string(_font, centre + Vector2(-44, 72), release_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(0.45, 1.0, 0.48, 0.96))

	if thermal:
		draw_string(_font, Vector2(view.x - 132, 30), "THERMAL · WHITE HOT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(1.0, 0.82, 0.48, 0.95))


func _airframe_label() -> String:
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		var preset: Dictionary = DroneCatalog.preset(Global.drone_preset)
		var name_key := "name_en" if MenuUI.is_english() else "name"
		return String(preset.get(name_key, preset.get("name", "ДРОН")))
	return "BABA YAGA"


func _control_hint(in_bomb_view: bool) -> String:
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		if MenuUI.is_english():
			return "DROP — release   VIDEO — image" if in_bomb_view else "VIDEO — image mode"
		return "СКИД — боєприпас   ВІДЕО — зображення" if in_bomb_view \
				else "ВІДЕО — режим зображення"
	if in_bomb_view:
		return "G — release   T — thermal" if MenuUI.is_english() else "G — скид   T — тепловізор"
	return "T — thermal" if MenuUI.is_english() else "T — тепловізор"


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
