class_name ChaosBattle
extends Node3D

## Two-sided AI battle for the Industrial map ("Бойовий хаос").
##
## Two mechanised infantry groups advance, take rifle range, fire animated
## bursts with muzzle flashes/sound/tracers, call in artillery that leaves
## craters, and collapse destructible buildings.  Reuses the authored rifleman
## model, Vehicle models, Explosion VFX, DestructibleBuilding and CombatSfx.

const ChaosSoldierScript = preload("res://combat/chaos_soldier.gd")
const VehicleScript = preload("res://combat/vehicle.gd")
const DestructibleBuildingScript = preload("res://combat/destructible_building.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const FT = preload("res://scripts/util/frontline_terrain.gd")

const BATTLE_CENTER := Vector2(30.0, -28.0)
const TEAM_BLUE := 0
const TEAM_RED := 1

var _team_a: Array[Node3D] = []
var _team_b: Array[Node3D] = []
var _vehicles: Array[Node3D] = []
var _buildings: Array[Node3D] = []
var _target_cd := 0.0
var _artillery_cd := 7.0
var _barrage_cd := 3.0
var _battle_time := 0.0
var _finished := false
var _demo_demolition_done := false
var _hud: CanvasLayer = null
var _title: Label = null
var _score: Label = null
var _status: Label = null
var _rng := RandomNumberGenerator.new()
var _fpv: Camera3D = null
var _target_load: Dictionary = {}


func setup(_level: Node3D, _base_y: float) -> void:
	_rng.randomize()
	_build_battlefield()
	_build_hud()
	_setup_chaos_fpv()
	print("[CHAOS] battle started: ", _team_a.size(), " blue vs ", _team_b.size(),
			" red, ", _vehicles.size(), " vehicles, ", _buildings.size(),
			" destructible buildings")


func _build_battlefield() -> void:
	# Two sides start ~190 m apart so the battle reads as a real advance, not a
	# knife fight on top of the player's spawn.
	var blue_center := BATTLE_CENTER + Vector2(-95.0, 0.0)
	var red_center := BATTLE_CENTER + Vector2(95.0, 0.0)
	var squad := 4 if QualityManager.get_active_level() == QualityManager.Level.LOW else 12
	for i in range(squad):
		_spawn_soldier(TEAM_BLUE, blue_center + _formation_offset(i), blue_center)
		_spawn_soldier(TEAM_RED, red_center + _formation_offset(i + 12), red_center)
	# Armour on both flanks. Vehicles stay strictly within the open container
	# yard (Z between -50 and +20, away from HeroHall at Z in [38, 122]).
	_spawn_vehicle(TEAM_BLUE, VehicleScript.Kind.TANK,
			BATTLE_CENTER + Vector2(-65.0, -16.0),
			[Vector3(-72.0, 0.0, -32.0), Vector3(-28.0, 0.0, -18.0),
			Vector3(-58.0, 0.0, 4.0)])
	_spawn_vehicle(TEAM_BLUE, VehicleScript.Kind.APC,
			BATTLE_CENTER + Vector2(-30.0, 14.0),
			[Vector3(-32.0, 0.0, 4.0), Vector3(-6.0, 0.0, 16.0),
			Vector3(-36.0, 0.0, -6.0)])
	_spawn_vehicle(TEAM_RED, VehicleScript.Kind.TANK,
			BATTLE_CENTER + Vector2(65.0, -14.0),
			[Vector3(72.0, 0.0, -32.0), Vector3(32.0, 0.0, -16.0),
			Vector3(62.0, 0.0, 4.0)])
	_spawn_vehicle(TEAM_RED, VehicleScript.Kind.APC,
			BATTLE_CENTER + Vector2(30.0, 14.0),
			[Vector3(32.0, 0.0, 4.0), Vector3(8.0, 0.0, 18.0),
			Vector3(38.0, 0.0, -8.0)])
	# Second wave of armour/transport per side
	_spawn_vehicle(TEAM_BLUE, VehicleScript.Kind.BMP,
			BATTLE_CENTER + Vector2(-75.0, 18.0),
			[Vector3(-80.0, 0.0, 12.0), Vector3(-52.0, 0.0, 20.0),
			Vector3(-70.0, 0.0, -12.0)])
	_spawn_vehicle(TEAM_BLUE, VehicleScript.Kind.TRUCK,
			BATTLE_CENTER + Vector2(-90.0, -4.0),
			[Vector3(-102.0, 0.0, -8.0), Vector3(-78.0, 0.0, 8.0)])
	_spawn_vehicle(TEAM_RED, VehicleScript.Kind.BMP,
			BATTLE_CENTER + Vector2(75.0, 18.0),
			[Vector3(80.0, 0.0, 12.0), Vector3(52.0, 0.0, 20.0),
			Vector3(72.0, 0.0, -14.0)])
	_spawn_vehicle(TEAM_RED, VehicleScript.Kind.TRUCK,
			BATTLE_CENTER + Vector2(90.0, -4.0),
			[Vector3(104.0, 0.0, -8.0), Vector3(80.0, 0.0, 8.0)])
	# Flanking mechanised units along the southern perimeter
	_spawn_vehicle(TEAM_BLUE, VehicleScript.Kind.APC,
			BATTLE_CENTER + Vector2(-55.0, -32.0),
			[Vector3(-60.0, 0.0, -44.0), Vector3(-25.0, 0.0, -36.0),
			Vector3(-48.0, 0.0, -20.0)])
	_spawn_vehicle(TEAM_RED, VehicleScript.Kind.APC,
			BATTLE_CENTER + Vector2(55.0, -32.0),
			[Vector3(60.0, 0.0, -44.0), Vector3(25.0, 0.0, -36.0),
			Vector3(48.0, 0.0, -20.0)])
	_build_atmosphere()
	# Buildings are cover and destruction targets; Explosion artillery damages
	# them through the combat_target group.
	# Keep the two demolition targets away from the spawn lines: the 6-second
	# showcase strike should collapse a building, not delete half a squad.
	for spec in [
		[Vector3(20.0, 0.0, -56.0), Vector3(13.0, 0.0, 9.0), 2,
			Color(0.46, 0.40, 0.34)],
		[Vector3(62.0, 0.0, 0.0), Vector3(12.0, 0.0, 9.0), 2,
			Color(0.48, 0.34, 0.28)],
		[Vector3(-34.0, 0.0, -62.0), Vector3(11.0, 0.0, 8.0), 2,
			Color(0.42, 0.38, 0.33)],
		[Vector3(104.0, 0.0, -46.0), Vector3(12.0, 0.0, 9.0), 2,
			Color(0.50, 0.36, 0.30)],
	]:
		_spawn_building(spec[0], spec[1], int(spec[2]), spec[3])
	# Sandbag lines at the centre.
	var assets = load("res://scripts/util/frontline_assets.gd")
	if assets != null:
		assets.spawn(self, "sandbag_wall", _ground_pos(Vector3(-12.0, 0.0, -26.0)),
				0.15, 1.0)
		assets.spawn(self, "sandbag_wall", _ground_pos(Vector3(24.0, 0.0, -18.0)),
				-0.2, 1.0)


func _build_atmosphere() -> void:
	# Static smoke/fire columns make the battle readable from the far spawn
	# and give the industrial yard a war-zone silhouette before the player
	# arrives.  The durations cover the whole 120 s engagement.
	for p in [
		Vector3(-36.0, 0.0, -52.0),
		Vector3(58.0, 0.0, -24.0),
		Vector3(96.0, 0.0, 12.0),
		Vector3(-78.0, 0.0, 22.0),
	]:
		var pos := _ground_pos(p)
		ExplosionScript.smoke_column(self, pos + Vector3.UP * 1.2, 130.0)
		ExplosionScript.fire_column(self, pos + Vector3.UP * 0.2, 25.0)
	# A pair of flares over the centre helps the player find the fight when
	# they launch from the southern spawn.
	for p in [Vector3(10.0, 0.0, -26.0), Vector3(50.0, 0.0, -30.0)]:
		var pos := _ground_pos(p)
		ExplosionScript.fire_column(self, pos + Vector3.UP * 0.1, 12.0)


func _formation_offset(i: int) -> Vector2:
	var col := i % 4
	var row := i / 4
	return Vector2((float(col) - 1.5) * 4.0, (float(row) - 0.5) * 5.5)


func _ground_pos(v: Vector3) -> Vector3:
	var y := FT.height_at("industrial", v.x, v.z)
	return Vector3(v.x, y + 0.03, v.z)


func _spawn_soldier(team: int, offset: Vector2, home: Vector2) -> void:
	var unit := ChaosSoldierScript.new()
	unit.team = team
	unit.battle = self
	var p := offset
	unit.position = _ground_pos(Vector3(p.x, 0.0, p.y))
	add_child(unit)
	var enemy_home := home + Vector2(84.0, 0.0) if team == TEAM_BLUE \
			else home + Vector2(-84.0, 0.0)
	var look := Vector3(enemy_home.x, unit.position.y, enemy_home.y)
	unit.look_at(look, Vector3.UP)
	unit.destroyed.connect(_on_unit_destroyed.bind(team, unit))
	if team == TEAM_BLUE:
		_team_a.append(unit)
	else:
		_team_b.append(unit)


func _spawn_vehicle(team: int, kind: int, offset: Vector2,
		waypoints: Array) -> void:
	var v := VehicleScript.new()
	v.kind = kind
	v.ai_vs_ai = true
	v.ai_team = team
	v.hostile = true
	v.track_drone = false
	v.move_speed = 4.2 if kind == VehicleScript.Kind.TANK else 7.0
	v.name = ("BlueVeh" if team == TEAM_BLUE else "RedVeh") + str(_vehicles.size())
	add_child(v)
	v.global_position = _ground_pos(Vector3(offset.x, 0.0, offset.y))
	var shifted: Array = []
	for wp in waypoints:
		var w: Vector3 = wp
		shifted.append(Vector3(w.x, 0.0, w.z))
	v.set_waypoints(shifted)
	v.destroyed.connect(_on_unit_destroyed.bind(team, v))
	_vehicles.append(v)


func _spawn_building(pos: Vector3, size: Vector3, floors: int, color: Color) -> void:
	var b := DestructibleBuildingScript.new()
	b.configure(size, floors, color)
	add_child(b)
	b.global_position = _ground_pos(pos)
	b.destroyed.connect(_on_building_destroyed)
	_buildings.append(b)


func _ready() -> void:
	# Battle is driven by the manager, not the level HUD.
	set_process(true)


func _process(delta: float) -> void:
	if _finished:
		return
	_battle_time += delta
	_target_cd -= delta
	_artillery_cd -= delta
	if _target_cd <= 0.0:
		_target_cd = 0.7
		_assign_all_targets()
	if _artillery_cd <= 0.0:
		_artillery_cd = _rng.randf_range(6.0, 11.0)
		_artillery_strike()
	# Guaranteed demolition beat for the demo: a named building is hit by a
	# heavy strike about six seconds into the battle, showing chunks/fire.
	if not _demo_demolition_done and _battle_time > 6.0:
		_demo_demolition_done = true
		_demolition_strike()
	# Late-battle barrage: a long 1-vs-1 stalk through the container yard can
	# otherwise stall the simulation.  Shells keep falling until a winner
	# emerges, and every impact leaves a fresh crater.
	if _battle_time > 50.0:
		_barrage_cd -= delta
		if _barrage_cd <= 0.0:
			_barrage_cd = 1.8
			_barrage_remaining()
	_update_hud()
	if _alive_team(TEAM_BLUE) == 0 or _alive_team(TEAM_RED) == 0 \
			or _battle_time > 120.0:
		_finish_battle()


func _assign_all_targets() -> void:
	_target_load.clear()
	for u in _team_a:
		if is_instance_valid(u) and not bool(u.get("is_destroyed")):
			u.target = assign_target(u)
			_note_target(u.target)
	for u in _team_b:
		if is_instance_valid(u) and not bool(u.get("is_destroyed")):
			u.target = assign_target(u)
			_note_target(u.target)
	for v in _vehicles:
		if is_instance_valid(v) and not bool(v.is_destroyed):
			v.ai_target = assign_target(v)
			_note_target(v.ai_target)


func _note_target(target: Node3D) -> void:
	if target != null and is_instance_valid(target):
		_target_load[target] = int(_target_load.get(target, 0)) + 1


func assign_target(unit: Node3D) -> Node3D:
	if unit == null:
		return null
	var enemy_team := TEAM_RED
	# Soldiers expose `team`; vehicles expose `ai_team`.
	var own_team = unit.get("team")
	if own_team == null:
		own_team = unit.get("ai_team")
	if own_team != null:
		enemy_team = 1 - int(own_team)
	# Armour prefers a tank duel most of the time; infantry remains a valid
	# target so a lone APC still supports the squad fight.
	if unit.get("team") == null and unit.get("ai_team") != null \
			and _rng.randf() < 0.65:
		var best_armor: Node3D = null
		var best_armor_d := 1e20
		for other in _vehicles:
			if not is_instance_valid(other) or bool(other.get("is_destroyed")):
				continue
			if int(other.get("ai_team")) != enemy_team:
				continue
			var da := unit.global_position.distance_squared_to(other.global_position)
			da += float(_target_load.get(other, 0)) * 12.0
			if da < best_armor_d:
				best_armor_d = da
				best_armor = other
		if best_armor != null:
			return best_armor
	var pool: Array = _team_b if enemy_team == TEAM_RED else _team_a
	var best: Node3D = null
	var best_d := 1e20
	for other in pool:
		if not is_instance_valid(other) or bool(other.get("is_destroyed")):
			continue
		var d := unit.global_position.distance_squared_to(other.global_position)
		# Spread fire across the squad: a target already engaged by two
		# friendlies costs extra, so the whole line does not tunnel one soldier.
		d += float(_target_load.get(other, 0)) * 16.0
		d += _rng.randf() * 3.0
		if d < best_d:
			best_d = d
			best = other
	# Vehicles can also be targeted by the other team's armour.
	if best == null:
		for other in _vehicles:
			if not is_instance_valid(other) or bool(other.get("is_destroyed")):
				continue
			if int(other.get("ai_team")) == enemy_team:
				var d2 := unit.global_position.distance_squared_to(other.global_position)
				d2 += float(_target_load.get(other, 0)) * 16.0
				if d2 < best_d:
					best_d = d2
					best = other
	return best


func _artillery_strike() -> void:
	# Alternate between counter-battery fire at infantry and deliberate
	# demolition of a building so craters and collapsing structures are both
	# visible during a short demonstration.
	var target_pos := Vector3.ZERO
	var hit_building := false
	if not _buildings.is_empty() and _rng.randf() < 0.42:
		var b: Node3D = _buildings[_rng.randi_range(0, _buildings.size() - 1)]
		if is_instance_valid(b) and not bool(b.get("is_destroyed")):
			target_pos = b.global_position + Vector3.UP * 1.0
			hit_building = true
	if target_pos == Vector3.ZERO:
		var pool: Array = _team_a if _rng.randf() < 0.5 else _team_b
		if not pool.is_empty():
			var u: Node3D = pool[_rng.randi_range(0, pool.size() - 1)]
			if is_instance_valid(u):
				target_pos = u.global_position
	if target_pos == Vector3.ZERO:
		return
	var blast := 10.0 if hit_building else 7.0
	var damage := 650.0 if hit_building else 170.0
	ExplosionScript.spawn(self, target_pos + Vector3.UP * 0.2, blast, damage)
	_set_status("АРТИЛЕРІЙСЬКИЙ УДАР / ARTILLERY" if MenuUI.is_english()
			else "АРТИЛЕРІЙСЬКИЙ УДАР")


func _barrage_remaining() -> void:
	var pool: Array = []
	for u in _team_a:
		if is_instance_valid(u) and not bool(u.get("is_destroyed")):
			pool.append(u)
	for u in _team_b:
		if is_instance_valid(u) and not bool(u.get("is_destroyed")):
			pool.append(u)
	for v in _vehicles:
		if is_instance_valid(v) and not bool(v.get("is_destroyed")):
			pool.append(v)
	if pool.is_empty():
		return
	var unit: Node3D = pool[_rng.randi_range(0, pool.size() - 1)]
	ExplosionScript.spawn(self, unit.global_position + Vector3.UP * 0.3,
			6.0, 150.0)
	_set_status("ШКВАЛЬНИЙ ВОГОНЬ / BARRAGE" if MenuUI.is_english()
			else "ШКВАЛЬНИЙ ВОГОНЬ")


func _demolition_strike() -> void:
	for b in _buildings:
		if is_instance_valid(b) and not bool(b.get("is_destroyed")):
			var p: Vector3 = b.global_position + Vector3.UP * 2.0
			ExplosionScript.spawn(self, p, 12.0, 900.0)
			print("[CHAOS] demolition strike on building ", b.name)
			return


func _on_unit_destroyed(_points: int, _team: int, unit: Node3D) -> void:
	if is_instance_valid(unit):
		unit.set_physics_process(false)


func _on_building_destroyed(_points: int) -> void:
	print("[CHAOS] building destroyed")
	_set_status("БУДІВЛЮ ЗРУЙНОВАНО / BUILDING COLLAPSED"
			if MenuUI.is_english() else "БУДІВЛЮ ЗРУЙНОВАНО")


func _alive(team: Array) -> int:
	var n := 0
	for unit in team:
		if is_instance_valid(unit) and not bool(unit.get("is_destroyed")):
			n += 1
	return n


func _alive_team(team: int) -> int:
	var n := _alive(_team_a if team == TEAM_BLUE else _team_b)
	for v in _vehicles:
		if is_instance_valid(v) and int(v.get("ai_team")) == team \
				and not bool(v.get("is_destroyed")):
			n += 1
	return n


func _finish_battle() -> void:
	if _finished:
		return
	_finished = true
	var blue := _alive_team(TEAM_BLUE)
	var red := _alive_team(TEAM_RED)
	var winner := "СИНІ" if blue > red else ("ЧЕРВОНІ" if red > blue else "НІЧИЯ")
	if MenuUI.is_english():
		winner = "BLUE" if blue > red else ("RED" if red > blue else "DRAW")
	_title.text = "ПЕРЕМОГА: " + winner if not MenuUI.is_english() \
			else "VICTORY: " + winner
	_status.text = "R / ENTER — ЩЕ БІЙ" if not MenuUI.is_english() \
			else "R / ENTER — FIGHT AGAIN"
	print("[CHAOS] finished: blue=", blue, " red=", red, " winner=", winner)


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "ChaosHUD"
	_hud.layer = 14
	add_child(_hud)
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.045, 0.05, 0.62)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 76.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(panel)
	_title = Label.new()
	_title.text = "БОЙОВИЙ ХАОС — ПРОМЗОНА"
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.32))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 8.0
	_title.offset_bottom = 38.0
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_title)
	_score = Label.new()
	_score.add_theme_font_size_override("font_size", 16)
	_score.add_theme_color_override("font_color", Color(0.82, 0.92, 0.94))
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_score.offset_top = 40.0
	_score.offset_bottom = 62.0
	_score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_score)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", Color(1.0, 0.52, 0.26))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_status.offset_top = 82.0
	_status.offset_bottom = 108.0
	_status.offset_left = -380.0
	_status.offset_right = 380.0
	_hud.add_child(_status)
	_update_hud()


func _setup_chaos_fpv() -> void:
	# First-person only: the player flies the drone from its FPV lens.
	var level := get_tree().current_scene
	if level != null:
		_fpv = level.get_node_or_null("Drone/FPVCamera") as Camera3D
	if _fpv != null:
		_fpv.current = true


func _update_hud() -> void:
	if _score == null:
		return
	var blue := _alive_team(TEAM_BLUE)
	var red := _alive_team(TEAM_RED)
	_score.text = "🔵 СИНІ: %d     🔴 ЧЕРВОНІ: %d     ⏱ %.1f с" % [
		blue, red, _battle_time]
	if _status.text == "":
		_status.text = "АВТОМАТИЧНА БОЙОВА СИМУЛЯЦІЯ" if not MenuUI.is_english() \
				else "AUTONOMOUS BATTLE SIMULATION"


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _unhandled_input(event: InputEvent) -> void:
	if _finished and event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_R or key.keycode == KEY_ENTER:
			get_tree().reload_current_scene()
