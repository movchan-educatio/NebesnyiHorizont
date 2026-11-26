class_name BombSight
extends Control

## CCIP bomb sight for the Baba Yaga heavy bomber.
##
## The pipper is a real ballistic impact point computed from the drone's
## current velocity, gravity, quadratic drag and the level wind.  The predicted
## impact is raychecked against the physics world so roofs, bridges, buildings
## and vehicle colliders receive a clean lock instead of being ignored in
## favour of the terrain field.
##
## A 3D impact reticle is projected on the exact surface: a small crosshair
## ring plus the exact blast-radius lethality circle, aligned to the hit
## normal.  It turns tactical green with a СКИД / DROP callout when a live
## enemy sits inside the payload's blast radius, otherwise it stays amber.
##
## Keys: T — thermal camera (white-hot).

const Ballistics = preload("res://combat/ballistics.gd")
const SOLVE_INTERVAL := 1.0 / 30.0
const LOCK_GREEN := Color(0.22, 1.0, 0.36)
const AMBER := Color(1.0, 0.85, 0.15)
const ENEMY_GROUPS := ["vehicles", "enemy_infantry", "targets", "mission_targets"]

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
var _solve_elapsed := 0.0
var _display_impact := Vector3.ZERO
var _font: Font = null
var _ray_query: PhysicsRayQueryParameters3D = null
var _hit_normal := Vector3.UP
var _locked := false
var _blast_radius := 8.0
var _wind := Vector3.ZERO
var _map_name := ""

# 3D ground reticle: the crosshair ring and the exact blast-radius circle,
# scaled to the live payload and laid on the hit surface.
var _reticle_root: Node3D = null
var _reticle_disc: MeshInstance3D = null
var _reticle_ring: MeshInstance3D = null
var _reticle_disc_mat: StandardMaterial3D = null
var _reticle_ring_mat: StandardMaterial3D = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("bomb_sight")
	_font = ThemeDB.fallback_font
	_build_impact_reticle()

	set_process(true)
	queue_redraw()


func _exit_tree() -> void:
	if _reticle_root != null and is_instance_valid(_reticle_root):
		_reticle_root.queue_free()
	_reticle_root = null


func set_thermal(on: bool) -> void:
	thermal = on
	queue_redraw()


func set_bomb_view(on: bool) -> void:
	bomb_view = on
	queue_redraw()


func _process(delta: float) -> void:
	if not visible:
		if _reticle_root != null:
			_reticle_root.visible = false
		return
	_solve_elapsed += delta
	_tick += delta
	if _solution.is_empty() or _tick >= SOLVE_INTERVAL:
		_tick = fmod(_tick, SOLVE_INTERVAL) if _tick >= SOLVE_INTERVAL else 0.0
		_recompute()
		_update_aim_ray()
	_extrapolate_pipper()
	_update_impact_reticle()
	queue_redraw()


## Cheap, every-frame follow-up: extrapolate the last solved impact with the
## drone's horizontal velocity without paying for a ballistic solve or raycast
## on intermediate frames above 30 Hz.
func _extrapolate_pipper() -> void:
	if _solution.is_empty():
		return
	var solved: Vector3 = _solution.get("impact", Vector3.ZERO)
	var vel: Vector3 = Vector3.ZERO
	if drone != null and is_instance_valid(drone):
		vel = drone.linear_velocity
	vel.y = 0.0
	_display_impact = solved + vel * minf(_solve_elapsed, 0.15)


func _build_impact_reticle() -> void:
	if _reticle_root != null and is_instance_valid(_reticle_root):
		return
	_reticle_root = Node3D.new()
	_reticle_root.name = "BombImpactReticle3D"
	_reticle_root.top_level = true
	add_child(_reticle_root)

	# Filled lethality circle.  The whole reticle is scaled to the payload's
	# blast radius, so a unit cylinder/ring is always exactly the right size.
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 64
	disc_mesh.rings = 1
	_reticle_disc = MeshInstance3D.new()
	_reticle_disc.name = "LethalityCircle"
	_reticle_disc.mesh = disc_mesh
	_reticle_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_disc_mat = _make_reticle_material(0.16)
	_reticle_disc.material_override = _reticle_disc_mat
	_reticle_root.add_child(_reticle_disc)

	# Exact blast-radius brim.
	_reticle_ring = MeshInstance3D.new()
	_reticle_ring.name = "BlastRadiusRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.98
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 8
	_reticle_ring.mesh = ring_mesh
	_reticle_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_reticle_ring_mat = _make_reticle_material(0.95)
	_reticle_ring.material_override = _reticle_ring_mat
	_reticle_root.add_child(_reticle_ring)

	# Small crosshair ring in the middle of the blast circle.
	var inner := MeshInstance3D.new()
	inner.name = "CrosshairRing"
	var inner_mesh := TorusMesh.new()
	inner_mesh.inner_radius = 0.17
	inner_mesh.outer_radius = 0.20
	inner_mesh.rings = 40
	inner_mesh.ring_segments = 6
	inner.mesh = inner_mesh
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inner.material_override = _reticle_ring_mat
	_reticle_root.add_child(inner)

	# Crosshair bars spanning the middle ring.
	var bar_x := MeshInstance3D.new()
	var bar_x_mesh := BoxMesh.new()
	bar_x_mesh.size = Vector3(0.52, 0.015, 0.015)
	bar_x.mesh = bar_x_mesh
	bar_x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar_x.material_override = _reticle_ring_mat
	_reticle_root.add_child(bar_x)

	var bar_z := MeshInstance3D.new()
	var bar_z_mesh := BoxMesh.new()
	bar_z_mesh.size = Vector3(0.015, 0.015, 0.52)
	bar_z.mesh = bar_z_mesh
	bar_z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar_z.material_override = _reticle_ring_mat
	_reticle_root.add_child(bar_z)

	_reticle_root.visible = false


func _make_reticle_material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.albedo_color = Color(AMBER.r, AMBER.g, AMBER.b, alpha)
	return mat


func _is_sight_idle_hidden() -> bool:
	if Global.play_mode == Global.PlayMode.TUTORIAL:
		return true
	if Global.play_mode == Global.PlayMode.TRAINING and not Global.combat_training and not bomb_view:
		return true
	if drone != null and is_instance_valid(drone) and not bomb_view:
		var fc: Variant = drone.get("flight_controller")
		if fc != null and not bool(fc.get("state_armed")):
			return true
	return false


func _update_impact_reticle() -> void:
	if _reticle_root == null or not is_instance_valid(_reticle_root):
		return
	if _is_sight_idle_hidden() or _solution.is_empty() or level == null or not is_instance_valid(level):
		_reticle_root.visible = false
		return
	var impact := _display_impact
	if not impact.is_finite():
		_reticle_root.visible = false
		return
	var hit_normal := _hit_normal
	if hit_normal.length_squared() < 0.0001 or not hit_normal.is_finite():
		hit_normal = Vector3.UP
	hit_normal = hit_normal.normalized()

	var ref := Vector3.FORWARD if absf(hit_normal.dot(Vector3.FORWARD)) < 0.95 \
			else Vector3.RIGHT
	var right := ref.cross(hit_normal)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT.cross(hit_normal)
	right = right.normalized()
	var back := right.cross(hit_normal).normalized()

	var radius := maxf(_blast_radius, 0.5)
	# Local X/Z are scaled to the blast radius; local Y stays along the normal.
	_reticle_root.global_transform = Transform3D(
			Basis(right * radius, hit_normal, back * radius),
			impact + hit_normal * 0.05)
	_reticle_root.visible = true

	var col := LOCK_GREEN if _locked else AMBER
	if _reticle_disc_mat != null:
		_reticle_disc_mat.albedo_color = Color(col.r, col.g, col.b, 0.16)
	if _reticle_ring_mat != null:
		_reticle_ring_mat.albedo_color = Color(col.r, col.g, col.b, 0.95)


func _update_aim_ray() -> void:
	camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 3000.0
	var world := camera.get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters3D.create(from, to)
		_ray_query.collision_mask = 1
	else:
		_ray_query.from = from
		_ray_query.to = to
	if drone is CollisionObject3D:
		_ray_query.exclude = [(drone as CollisionObject3D).get_rid()]
	else:
		_ray_query.exclude = []
	var hit := space.intersect_ray(_ray_query)
	_aim_valid = not hit.is_empty()
	_aim_point = hit.get("position", Vector3.ZERO)


func _recompute() -> void:
	_locked = false
	_solution = {}
	if level == null or drone == null or not is_instance_valid(drone) \
			or not is_instance_valid(level):
		return
	camera = get_viewport().get_camera_3d()
	if camera == null:
		return

	_wind = _current_wind()
	_map_name = _resolve_map_name()

	# Use the exact state the physical store will be spawned with.  A modelled
	# bomb rack supplies its own bay origin; every other dropper uses the
	# shared hardpoint.  Keeping the optional bay override here means the
	# pipper and the rigid body always leave from the same point.
	var bay_override: Variant = Vector3.INF
	var rack: Dictionary = {}
	if level.has_method("_bomb_release_state"):
		var rack_value: Variant = level.call("_bomb_release_state", drone, kind)
		if rack_value is Dictionary:
			rack = rack_value
			var rack_origin: Variant = rack.get("origin")
			if rack_origin is Vector3 and (rack_origin as Vector3).is_finite():
				bay_override = rack_origin
	var state: Dictionary = Ballistics.release_state(drone, bay_override)
	if rack.get("velocity") is Vector3:
		state["velocity"] = rack["velocity"]

	var origin: Vector3 = state.get("origin", drone.global_position)
	var vel: Vector3 = state.get("velocity", drone.linear_velocity)
	if not origin.is_finite():
		origin = drone.global_position
	if not vel.is_finite():
		vel = drone.linear_velocity

	var exclude: Array[RID] = []
	if drone is CollisionObject3D:
		exclude.append((drone as CollisionObject3D).get_rid())

	_blast_radius = Ballistics.blast_for(kind)
	# 40 ms segments keep the solve affordable while the raycast pass locks
	# cleanly onto roofs, bridges and vehicle colliders before the terrain
	# height field is used as a fallback.
	_solution = Ballistics.simulate_with_raycast(level, _map_name, origin, vel,
			_wind, Ballistics.kind_code(kind), 0.04, exclude)

	_solve_elapsed = 0.0
	_display_impact = _solution.get("impact", Vector3.ZERO)
	_hit_normal = _solution.get("hit_normal", Vector3.UP)
	_locked = _has_target_in_blast(_display_impact, _blast_radius)


func _has_target_in_blast(center: Vector3, radius: float) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var seen := {}
	for group_name in ENEMY_GROUPS:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node) or node == drone:
				continue
			if seen.has(node):
				continue
			seen[node] = true
			var target := node as Node3D
			if target == null or not _is_live_enemy(target):
				continue
			var delta := target.global_position - center
			# Blast lethality is radial around the impact; a roof hit still
			# catches enemies on the ground below it.
			if Vector2(delta.x, delta.z).length() <= radius \
					and absf(delta.y) <= radius * 2.0:
				return true
	# Some levels expose the same enemy sets as plain arrays/dictionaries
	# instead of groups; scan those too so the lock never misses a valid target.
	if level != null and is_instance_valid(level):
		for field in ENEMY_GROUPS:
			var source: Variant = level.get(field)
			if source != null and _scan_enemy_source(source, center, radius, 0):
				return true
	return false


func _scan_enemy_source(source: Variant, center: Vector3, radius: float,
		depth: int) -> bool:
	if source == null or depth > 3:
		return false
	if source is Vector3:
		return (source as Vector3).distance_to(center) <= radius
	if source is Node3D:
		var target := source as Node3D
		if is_instance_valid(target) and target != drone and _is_live_enemy(target) \
				and target.global_position.distance_to(center) <= radius:
			return true
		for child in target.get_children():
			if _scan_enemy_source(child, center, radius, depth + 1):
				return true
		return false
	if source is Node:
		var root := source as Node
		if not is_instance_valid(root):
			return false
		for child in root.get_children():
			if _scan_enemy_source(child, center, radius, depth + 1):
				return true
		return false
	if source is Array:
		for entry: Variant in (source as Array):
			if _scan_enemy_source(entry, center, radius, depth + 1):
				return true
		return false
	if source is PackedVector3Array:
		for entry: Vector3 in (source as PackedVector3Array):
			if entry.distance_to(center) <= radius:
				return true
		return false
	if source is Dictionary:
		var entry := source as Dictionary
		var alive := true
		for key in ["alive", "is_alive"]:
			if entry.has(key) and not bool(entry[key]):
				alive = false
		for key in ["dead", "destroyed", "is_dead"]:
			if entry.has(key) and bool(entry[key]):
				alive = false
		var pos_value: Variant = entry.get("position",
				entry.get("global_position", entry.get("pos", null)))
		if alive and pos_value is Vector3 \
				and (pos_value as Vector3).distance_to(center) <= radius:
			return true
		for value in entry.values():
			if _scan_enemy_source(value, center, radius, depth + 1):
				return true
	return false


func _is_live_enemy(target: Node3D) -> bool:
	if target.is_queued_for_deletion() or not target.is_inside_tree():
		return false
	if target.has_method("is_dead") and bool(target.call("is_dead")):
		return false
	if target.has_method("is_alive") and not bool(target.call("is_alive")):
		return false
	var hp: Variant = target.get("health")
	if hp != null and (hp is int or hp is float) and float(hp) <= 0.0:
		return false
	return true


func _draw() -> void:
	if _is_sight_idle_hidden() or _solution.is_empty() or camera == null:
		return
	var view := get_viewport_rect().size
	var centre := view * 0.5
	var col := LOCK_GREEN if _locked else AMBER
	var behind := camera.is_position_behind(_display_impact)
	var p := Vector2.ZERO
	var marker := Vector2.ZERO
	var below := false

	if not behind:
		p = camera.unproject_position(_display_impact)
		below = p.y > view.y + 1.0
		marker = _edge_marker(p, view)
		_draw_fall_line(marker, col)

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

	if not behind:
		_draw_sight(p, marker, view, centre, col)

	if behind or below:
		_draw_below_frustum_hint(view, _display_impact)

	_draw_ccip_panel(view, col)

	if _locked:
		var lock_text := "DROP" if MenuUI.is_english() else "СКИД"
		var lock_pos := Vector2(centre.x + 28.0, view.y - 122.0)
		if not (behind or below):
			lock_pos = marker + Vector2(36.0, -28.0)
		draw_string(_font, lock_pos, lock_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				19, LOCK_GREEN)

	if thermal:
		draw_string(_font, Vector2(view.x - 148, 30), "THERMAL · WHITE HOT",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(1.0, 0.82, 0.48, 0.95))


func _edge_marker(p: Vector2, view: Vector2) -> Vector2:
	var margin := 30.0
	return Vector2(
			clampf(p.x, margin, maxf(margin, view.x - margin)),
			clampf(p.y, margin, maxf(margin, view.y - margin)))


## Vertical fall line from the drone's nadir screen projection to the pipper.
func _draw_fall_line(marker: Vector2, col: Color) -> void:
	if drone == null or not is_instance_valid(drone) or level == null:
		return
	var ground := Ballistics.ground_at(level, _map_name,
			drone.global_position.x, drone.global_position.z)
	var nadir := Vector3(drone.global_position.x, ground, drone.global_position.z)
	if camera == null or camera.is_position_behind(nadir):
		return
	var p_nadir := camera.unproject_position(nadir)
	draw_dashed_line(p_nadir, marker, Color(col, 0.30), 1.5, 9.0, true, true)
	draw_circle(p_nadir, 3.0, Color(col, 0.60))


func _draw_sight(p: Vector2, marker: Vector2, view: Vector2, centre: Vector2,
		col: Color) -> void:
	var screen_dist := p.distance_to(centre)
	var dist_to_aim := _display_impact.distance_to(_aim_point) if _aim_valid else 999.0
	# The release cue is screen-space: a pipper sitting on the camera centre
	# means the predicted impact is exactly on the aim point.
	var ready := screen_dist <= 26.0 or (_aim_valid and dist_to_aim < 5.0)
	var off_screen := marker.distance_to(p) > 0.5

	# Centre bracket: the release reference.  It lights up when the pipper is
	# on it, so the pilot can see both the aim point and the predicted impact.
	var bracket := 38.0 if ready else 30.0
	var bracket_col := Color(0.45, 1.0, 0.48, 0.95) if ready \
			else Color(0.66, 1.0, 0.72, 0.5)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var tip: Vector2 = centre + corner * bracket
		draw_line(tip, tip - Vector2(corner.x * 14.0, 0), bracket_col, 2.0)
		draw_line(tip, tip - Vector2(0, corner.y * 14.0), bracket_col, 2.0)

	# CCIP pipper: brighter and larger than a tiny point so it stays readable
	# over bright terrain on a phone screen.
	var radius := 24.0 if bomb_view else 18.0
	draw_circle(marker, 2.6, col)
	draw_arc(marker, radius, 0.0, TAU, 40, col, 2.6)
	if _locked:
		# Target inside the payload's lethal circle: green lock ring + ДРОП.
		draw_arc(marker, radius + 9.0, 0.0, TAU, 56, LOCK_GREEN, 3.0)
		draw_arc(marker, radius + 15.0, 0.0, TAU, 56,
				Color(LOCK_GREEN.r, LOCK_GREEN.g, LOCK_GREEN.b, 0.42), 1.5)
	elif ready:
		draw_arc(marker, radius + 7.0, 0.0, TAU, 40,
				Color(0.45, 1.0, 0.48, 0.9), 2.0)
	draw_line(marker + Vector2(-radius - 16, 0), marker + Vector2(-radius - 4, 0), col, 2.2)
	draw_line(marker + Vector2(radius + 4, 0), marker + Vector2(radius + 16, 0), col, 2.2)
	draw_line(marker + Vector2(0, -radius - 16), marker + Vector2(0, -radius - 4), col, 2.2)
	draw_line(marker + Vector2(0, radius + 4), marker + Vector2(0, radius + 16), col, 2.2)

	if off_screen:
		# The true impact is outside the lens (common in level flight at
		# altitude).  Point toward it instead of silently clipping the sight.
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

	if ready and not _locked:
		var release_text := "DROP" if MenuUI.is_english() else "СКИД"
		draw_string(_font, centre + Vector2(-44, 72), release_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(0.45, 1.0, 0.48, 0.96))


func _draw_ccip_panel(view: Vector2, col: Color) -> void:
	var info_pos := Vector2(20.0, maxf(78.0, view.y - 170.0))
	draw_rect(Rect2(info_pos + Vector2(-8, -18), Vector2(340, 76)),
			Color(0.005, 0.012, 0.010, 0.32), true)
	var text_col := Color(0.82, 1.0, 0.86, 0.95)
	var tof := float(_solution.get("tof", 0.0))
	var ammo := _ammo()
	var agl := _agl()
	var ammo_label := "BOMBS" if MenuUI.is_english() else "БОМБИ"
	draw_string(_font, info_pos,
			"AGL %03d m   TOF %.1f s   %s %d" % [
				int(round(maxf(agl, 0.0))), tof, ammo_label, ammo],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_col)
	var wind := _current_wind()
	draw_string(_font, info_pos + Vector2(0, 20),
			"WIND %.1f m/s %s" % [wind.length(), _compass_arrow(wind)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_col)
	draw_string(_font, info_pos + Vector2(152, 20), _camera_indicator(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_col)
	_draw_wind_arrow(info_pos + Vector2(300, 10), wind, col)


func _draw_wind_arrow(origin: Vector2, wind: Vector3, col: Color) -> void:
	if camera == null:
		return
	var basis := camera.global_transform.basis
	var screen_dir := Vector2(wind.dot(basis.x), -wind.dot(basis.y))
	if screen_dir.length() < 0.01:
		draw_line(origin + Vector2(-7, 0), origin + Vector2(7, 0),
				Color(col, 0.55), 1.5, true)
		return
	_draw_screen_arrow(origin, screen_dir.normalized(),
			clampf(9.0 + wind.length() * 3.0, 10.0, 30.0), col)


func _draw_screen_arrow(origin: Vector2, dir: Vector2, length: float,
		col: Color) -> void:
	var d := dir.normalized()
	var tip := origin + d * length
	var side := Vector2(-d.y, d.x)
	draw_line(origin, tip, Color(col, 0.90), 2.0, true)
	draw_colored_polygon(PackedVector2Array([
		tip + d * 5.0,
		tip - d * 3.0 + side * 4.0,
		tip - d * 3.0 - side * 4.0,
	]), col)


## Impact is below the FPV frustum: keep a downward arrow with slant range.
func _draw_below_frustum_hint(view: Vector2, impact: Vector3) -> void:
	var col := LOCK_GREEN if _locked else AMBER
	var anchor := Vector2(view.x * 0.5, view.y - 86.0)
	draw_colored_polygon(PackedVector2Array([
		anchor + Vector2(0, 12),
		anchor + Vector2(-10, -4),
		anchor + Vector2(10, -4),
	]), Color(col, 0.95))
	var distance := int(round(impact.distance_to(camera.global_position)))
	var label := "▼ %d m — ПРИЦІЛ" % distance
	if MenuUI.is_english():
		label = "▼ %d m — AIM" % distance
	draw_string(_font, anchor + Vector2(18, -6), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(col, 0.98))


func _current_wind() -> Vector3:
	if level != null and is_instance_valid(level):
		var wind: Variant = level.get("_current_wind_vector")
		if wind is Vector3:
			return wind
	return Vector3.ZERO


func _resolve_map_name() -> String:
	if level == null or not is_instance_valid(level):
		return ""
	var value: Variant = level.get("frontline_map")
	return String(value) if value != null else ""


func _agl() -> float:
	if level == null or drone == null or not is_instance_valid(drone):
		return 0.0
	return drone.global_position.y - Ballistics.ground_at(level, _map_name,
			drone.global_position.x, drone.global_position.z)


func _camera_indicator() -> String:
	var english := MenuUI.is_english()
	var cam := "FPV"
	if level != null and is_instance_valid(level) \
			and level.has_method("is_bomb_drop_camera_active") \
			and bool(level.call("is_bomb_drop_camera_active")):
		cam = "BOMB CAM" if english else "ПРИЦІЛ"
	var zoom := 1.0
	if level != null and is_instance_valid(level) \
			and level.has_method("get_bomb_cam_zoom_level"):
		zoom = maxf(1.0, float(level.call("get_bomb_cam_zoom_level")))
	return "%s · %.1f×" % [cam, zoom]


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
	if level != null and is_instance_valid(level) and level.has_method("_ammo_count"):
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
