## Combat glue: payload drops, kamikaze/crash detection, score, target roster
## and OSD updates. Place as a sibling of Drone / CombatRange / CombatHUD.
class_name CombatSystem
extends Node3D

const MenuUI = preload("res://GUI/ui/MenuUI.gd")
const PayloadScript = preload("res://combat/payload.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const Ballistics = preload("res://combat/ballistics.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")

@export var payload_count := 3
@export var payload_damage := 480.0
@export var payload_radius := 9.0
@export var kamikaze_damage := 2000.0
@export var kamikaze_min_speed := 4.0
@export var crash_speed := 15.0
@export var drone_max_health := 100.0

## Airframes are much larger than their origin point, and a crossing intercept
## closes fast.  The old 4.8 m / 3.2 m spheres demanded a pixel-perfect hit on
## a 16.5 m helicopter and a 3.8 m Shahed, so campaign 3/4 were unwinnable in
## practice.  These envelopes cover the airframe silhouette and the rotor disc.
const KAMIKAZE_RADIUS_HELI := 8.4
const KAMIKAZE_RADIUS_SHAHED := 6.0
const KAMIKAZE_RADIUS_VEHICLE := 4.2

var score := 0
var ammo := 0
var drops_count := 0
var targets_total := 0
var targets_destroyed := 0
var explosions := 0
var aa_total := 0
var aa_destroyed := 0
var inf_total := 0
var inf_destroyed := 0
var drone_health := 100.0

var _drone: Drone = null
var _range: Node = null
var _hud: Node = null
var _impact_marker: MeshInstance3D = null
var _last_speed := 0.0
var _lost := false
var _range_cleared := false
var _registered: Dictionary = {}
var _elapsed := 0.0
var _timer_started := false
var _timer_running := false
var _hud_accum := 0.0
var _results_shown := false
var _critical_warned := false
var _near_miss_tracers: Dictionary = {}
var _near_miss_cooldown := 0.0


func _ready() -> void:
	if Global.play_mode != Global.PlayMode.COMBAT:
		set_process(false)
		set_physics_process(false)
		var combat_hud := get_parent().get_node_or_null("CombatHUD")
		if combat_hud is CanvasLayer:
			(combat_hud as CanvasLayer).visible = false
		return
	_drone = get_parent().get_node_or_null("Drone") as Drone
	_range = get_parent().get_node_or_null("CombatRange")
	_hud = get_parent().get_node_or_null("CombatHUD")
	var parent_lvl := get_parent()
	if _hud != null and parent_lvl != null and parent_lvl.has_method("_spawn_combat_mission"):
		for sub in ["Root/TopRight", "Root/Message", "Root/Hint"]:
			var item := _hud.get_node_or_null(sub) as CanvasItem
			if item != null:
				item.visible = false
	var p := DroneCatalog.preset(Global.drone_preset)
	var is_combat: bool = bool(p.get("combat", false))
	var has_drop: bool = bool(p.get("has_drop", false))
	if not is_combat or not has_drop:
		payload_count = 0
		ammo = 0
	else:
		payload_count = int(p.get("payload", 3))
		ammo = payload_count
	drone_health = drone_max_health

	if _range != null:
		if _range.has_signal("target_spawned"):
			_range.connect("target_spawned", Callable(self, "_on_target_spawned"))
		if _range.has_signal("aa_spawned"):
			_range.connect("aa_spawned", Callable(self, "_on_aa_spawned"))
		if _range.has_signal("infantry_spawned"):
			_range.connect("infantry_spawned", Callable(self, "_on_infantry_spawned"))
		if _range.has_signal("range_ready"):
			_range.connect("range_ready", Callable(self, "_on_range_ready"))
		for child in _range.get_children():
			_register_target(child)

	if _hud != null and _hud.has_signal("restart_requested"):
		if not _hud.is_connected("restart_requested", Callable(self, "_on_restart_requested")):
			_hud.connect("restart_requested", Callable(self, "_on_restart_requested"))

	if _drone != null:
		_drone.contact_monitor = true
		_drone.max_contacts_reported = 8
		_drone.body_entered.connect(_on_drone_body_entered)
		if not _drone.is_connected("respawned", Callable(self, "_on_drone_respawned")):
			_drone.connect("respawned", Callable(self, "_on_drone_respawned"))

	_update_hud()
	if _drone != null and not _has_bomb_sight():
		_build_impact_marker()
	if OS.has_environment("DRONE_AUTOTEST_COMBAT"):
		_combat_autotest()
	elif OS.has_environment("DRONE_AUTOTEST_INFANTRY"):
		_infantry_autotest()
	elif OS.has_environment("DRONE_CLEAR_RANGE"):
		_clear_range_test()
	elif OS.has_environment("DRONE_SCREENSHOT"):
		_capture_screenshot()
	elif not OS.has_environment("DRONE_AUTOTEST"):
		if get_parent() == null or not get_parent().has_method("_spawn_combat_mission"):
			_message("RANGE LIVE — F TO DROP — AA + INFANTRY ACTIVE", Color(0.75, 1.0, 0.7), 3.5)


func _capture_screenshot() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	var delay := 5.0
	if OS.has_environment("DRONE_COMBAT_DEMO"):
		await _demo_bomb_run()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		delay = 0.05
	elif OS.has_environment("DRONE_AA_DEMO"):
		await _aa_demo()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		delay = 0.08
	elif OS.has_environment("DRONE_INFANTRY_DEMO"):
		await _infantry_demo()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		delay = 0.05
	elif OS.has_environment("DRONE_WALK_DEMO"):
		await _walk_demo()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		delay = 0.2
	elif OS.has_environment("DRONE_RESULTS_DEMO"):
		await _results_demo()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		delay = 0.55
	elif OS.has_environment("DRONE_SHOWCASE"):
		await _showcase_setup()
		if not is_inside_tree() or not is_instance_valid(self):
			return
		if OS.has_environment("DRONE_SHOWCASE_BOOM"):
			await tree.create_timer(0.6).timeout
			if not is_inside_tree() or not is_instance_valid(self):
				return
			var targets := _ground_targets()
			if not targets.is_empty():
				ExplosionScript.spawn(get_parent(), (targets[2] if targets.size() > 2 else targets[0]).global_position + Vector3.UP * 2.0, 7.0, 0.0)
			delay = 0.3
		else:
			delay = 0.35
	await tree.create_timer(delay).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var image := get_viewport().get_texture().get_image()
	var path := OS.get_environment("DRONE_SCREENSHOT")
	var err := image.save_png(path)
	print("[SCREENSHOT] ", path, " size=", image.get_size(), " err=", err)
	tree.quit()


func _demo_bomb_run() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(3.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var targets := _ground_targets()
	if targets.is_empty() or _drone == null or not is_instance_valid(_drone):
		return
	var target: Node3D = targets[0]
	if target == null or not is_instance_valid(target):
		return
	var parent := get_parent()
	var spawn_node: Node3D = null
	if parent != null:
		spawn_node = parent.get_node_or_null("Respawn") as Node3D
	var origin := spawn_node.global_position if spawn_node != null else target.global_position + Vector3(0, 0, 15)
	var approach := origin - target.global_position
	approach.y = 0.0
	if approach.length_squared() < 0.01:
		approach = Vector3(0, 0, 1)
	approach = approach.normalized()
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.global_position = target.global_position + approach * 1.5 + Vector3.UP * 15.0
	_drone.look_at(target.global_position + Vector3.UP * 0.8, Vector3.UP)
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller != null:
		controller.set_armed(true)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	await tree.create_timer(0.25).timeout
	if not is_inside_tree() or not is_instance_valid(self) or _drone == null \
			or not is_instance_valid(_drone):
		return
	var before := explosions
	drop_payload()
	for i in range(160):
		await tree.create_timer(0.05).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		if explosions > before:
			break
	await tree.create_timer(0.18).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return


func _showcase_setup() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	# Wait for the range to place its targets (same race as the infantry demo).
	var targets: Array[Node3D] = []
	for i in range(60):
		await tree.create_timer(0.25).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		targets = _ground_targets()
		if not targets.is_empty() and _drone != null and is_instance_valid(_drone):
			break
	if targets.is_empty() or _drone == null or not is_instance_valid(_drone):
		print("[DEMO] showcase aborted targets=", targets.size(),
				" drone=", _drone)
		return
	var target: Node3D = targets[2] if targets.size() > 2 else targets[0]
	if target == null or not is_instance_valid(target):
		return
	var parent := get_parent()
	var spawn: Node3D = null
	if parent != null:
		spawn = parent.get_node_or_null("Respawn") as Node3D
	var origin := spawn.global_position if spawn != null else target.global_position + Vector3(0, 0, 15)
	var dir := origin - target.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.global_position = target.global_position + dir * 13.0 + Vector3.UP * 4.5
	_drone.look_at(target.global_position + Vector3.UP * 1.3, Vector3.UP)
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller != null:
		controller.set_armed(true)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO


func _aa_demo() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(3.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var guns := tree.get_nodes_in_group("aa_gun")
	if guns.is_empty() or _drone == null or not is_instance_valid(_drone):
		return
	var gun: Node3D = guns[0]
	if gun == null or not is_instance_valid(gun):
		return
	var approach := -gun.global_transform.basis.z
	approach.y = 0.0
	if approach.length_squared() < 0.01:
		approach = Vector3(0, 0, 1)
	approach = approach.normalized()
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.global_position = gun.global_position + approach * 12.0 + Vector3.UP * 3.8
	_drone.look_at(gun.global_position + Vector3.UP * 1.6, Vector3.UP)
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller != null:
		controller.set_armed(true)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	await tree.create_timer(0.4).timeout
	if not is_inside_tree() or not is_instance_valid(self) or not is_instance_valid(gun):
		return
	if gun.has_method("demo_warm_up"):
		gun.call("demo_warm_up")
	await tree.create_timer(0.42).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return


func _results_demo() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(3.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	if _hud == null or not is_instance_valid(_hud):
		return
	var time_str := _format_time(_elapsed) if _elapsed > 0.0 else "01:42.00"
	var t_tot := targets_total if targets_total > 0 else 10
	var t_dst := targets_destroyed if targets_destroyed > 0 else t_tot
	var a_tot := aa_total if aa_total > 0 else 2
	var a_dst := aa_destroyed if aa_destroyed > 0 else a_tot
	var i_tot := inf_total if inf_total > 0 else 4
	var i_dst := inf_destroyed if inf_destroyed > 0 else i_tot
	var sc := score if score > 0 else 3850
	_hud.call("show_results", time_str, sc, t_dst, t_tot, a_dst, a_tot, i_dst, i_tot)
	await tree.create_timer(0.4).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return


func _infantry_demo() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	# The range builds its units only after the city reports spawn_ready, which
	# can take several seconds. Poll instead of assuming a fixed delay.
	var units: Array = []
	for i in range(60):
		await tree.create_timer(0.25).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		units = tree.get_nodes_in_group("enemy_infantry")
		if not units.is_empty() and _drone != null and is_instance_valid(_drone):
			break
	if units.is_empty() or _drone == null or not is_instance_valid(_drone):
		print("[DEMO] infantry demo aborted units=", units.size(),
				" drone=", _drone)
		return
	print("[DEMO] infantry demo units=", units.size(),
			" drone_at=", _drone.global_position)
	var soldier: Node3D = units[2] if units.size() > 2 else units[0]
	if soldier == null or not is_instance_valid(soldier):
		return
	var forward := -soldier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, 1)
	forward = forward.normalized()
	# Put the drone over the street rather than against the nearest facade.
	var toward_street := 1.0 if 70.0 > soldier.global_position.z else -1.0
	var closeness := 0.6 if OS.has_environment("DRONE_INFANTRY_CLOSE") else 1.0
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	if OS.has_environment("DRONE_INFANTRY_SIDE"):
		var right := soldier.global_transform.basis.x
		right.y = 0.0
		_drone.global_position = soldier.global_position + right.normalized() * 4.2 \
				- forward * 0.4 + Vector3.UP * 1.9
	else:
		_drone.global_position = soldier.global_position + forward * 4.5 * closeness \
				+ Vector3(0, 0, toward_street * 4.8 * closeness) + Vector3.UP * 3.0 * closeness
	_drone.look_at(soldier.global_position + Vector3.UP * 1.25, Vector3.UP)
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller != null:
		controller.set_armed(true)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	await tree.create_timer(0.8).timeout
	if not is_inside_tree() or not is_instance_valid(self) or not is_instance_valid(soldier):
		return
	for unit in units:
		if unit != null and is_instance_valid(unit) and unit is Node3D \
				and unit.global_position.distance_to(soldier.global_position) < 35.0:
			if unit.has_method("demo_warm_up"):
				unit.call("demo_warm_up")
	await tree.physics_frame
	if not is_inside_tree() or not is_instance_valid(self):
		return


func _walk_demo() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	var units: Array = []
	for i in range(60):
		await tree.create_timer(0.25).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		units = tree.get_nodes_in_group("enemy_infantry")
		if units.size() > 1 and _drone != null and is_instance_valid(_drone):
			break
	if units.size() < 2 or _drone == null or not is_instance_valid(_drone):
		print("[DEMO] walk demo aborted units=", units.size(),
				" drone=", _drone)
		return
	print("[DEMO] walk demo units=", units.size())
	var soldier: Node3D = units[1] if units.size() > 1 else units[0]
	if soldier == null or not is_instance_valid(soldier):
		return
	var forward := -soldier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, 1)
	forward = forward.normalized()
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.global_position = soldier.global_position + forward * 4.6 + Vector3.UP * 2.5
	_drone.look_at(soldier.global_position + Vector3.UP * 1.0, Vector3.UP)
	await tree.create_timer(0.6).timeout
	if not is_inside_tree() or not is_instance_valid(self) or not is_instance_valid(soldier):
		return
	if OS.has_environment("DRONE_INFANTRY_DEBUG"):
		for i in range(8):
			var hip_l = soldier.get("_hip_l")
			var hip_r = soldier.get("_hip_r")
			var stride = soldier.get("_stride")
			var patrol = soldier.get("_patrol_active")
			print("[WALKDBG] t=", i * 0.15, " patrol=", patrol, " stride=", stride,
					" hipL=", hip_l.rotation.x if hip_l != null else -99.0,
					" hipR=", hip_r.rotation.x if hip_r != null else -99.0)
			await tree.create_timer(0.15).timeout
			if not is_inside_tree() or not is_instance_valid(self) or not is_instance_valid(soldier):
				return


func _ground_targets() -> Array[Node3D]:
	var tree := get_tree()
	if tree == null:
		return []
	var out: Array[Node3D] = []
	for node in tree.get_nodes_in_group("combat_target"):
		if node != null and is_instance_valid(node) and not node.is_in_group("aa_gun") \
				and not node.is_in_group("enemy_infantry"):
			out.append(node)
	return out


func _physics_process(delta: float) -> void:
	if _near_miss_cooldown > 0.0:
		_near_miss_cooldown = maxf(_near_miss_cooldown - delta, 0.0)
	if _drone != null and is_instance_valid(_drone):
		_last_speed = _drone.linear_velocity.length()
		_update_impact_marker()
		_check_aerial_and_moving_kamikaze()
		_check_tracer_near_miss()

	if not _timer_started and not _range_cleared and _drone != null and is_instance_valid(_drone):
		var controller := _drone.get_node_or_null("FlightController") as FlightController
		if controller != null and controller.state_armed:
			_timer_started = true
			_timer_running = true

	if _timer_running and not _range_cleared:
		_elapsed += delta
		_hud_accum += delta
		if _hud_accum >= 0.1:
			_hud_accum = 0.0
			_update_hud()


func _has_bomb_sight() -> bool:
	var tree := get_tree()
	if tree != null and not tree.get_nodes_in_group("bomb_sight").is_empty():
		return true
	var p := get_parent()
	if p != null:
		if p.get("_bomb_sight") != null:
			return true
		if p.get_node_or_null("BombSight") != null:
			return true
	return false


func _check_tracer_near_miss() -> void:
	if _lost or _range_cleared or _results_shown or _near_miss_cooldown > 0.0:
		return
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return
	var tree := get_tree()
	if tree == null:
		return
	var tracers := tree.get_nodes_in_group("aa_tracer")
	if tracers.is_empty():
		return
	if _near_miss_tracers.size() > 64:
		_near_miss_tracers.clear()
	var d_pos := _drone.global_position
	for node in tracers:
		if not (node is Node3D) or not is_instance_valid(node):
			continue
		var id := node.get_instance_id()
		if _near_miss_tracers.has(id):
			continue
		var dist_sq := (node as Node3D).global_position.distance_squared_to(d_pos)
		if dist_sq <= 30.25 and dist_sq >= 0.16:
			_near_miss_tracers[id] = true
			_near_miss_cooldown = 0.14
			Haptics.trigger_ui_tap()
			return


## Small orange ring on the ground showing where a bomb released right now
## would land. Only visible while armed and carrying bombs.
func _build_impact_marker() -> void:
	if _has_bomb_sight():
		return
	_impact_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.9
	torus.rings = 40
	torus.ring_segments = 8
	_impact_marker.mesh = torus
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.55, 0.10, 0.7)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.45, 0.08)
	material.emission_energy_multiplier = 2.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_impact_marker.material_override = material
	_impact_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_impact_marker.visible = false
	add_child(_impact_marker)


func _update_impact_marker() -> void:
	if _impact_marker == null or not is_instance_valid(_impact_marker):
		return
	if _drone == null or not is_instance_valid(_drone):
		_impact_marker.visible = false
		return
	if _has_bomb_sight():
		_impact_marker.visible = false
		return
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	var armed := controller != null and controller.state_armed
	if not armed or ammo <= 0 or _lost:
		_impact_marker.visible = false
		return
	var forward := -_drone.global_transform.basis.z
	var velocity := _drone.linear_velocity + forward * 2.0 + Vector3.DOWN * 1.0
	var height := _drone.global_position.y - 0.5
	var gravity := 9.8
	var discriminant := velocity.y * velocity.y + 2.0 * gravity * height
	if discriminant < 0.0:
		_impact_marker.visible = false
		return
	var t := (velocity.y + sqrt(discriminant)) / gravity
	if t <= 0.0 or t > 30.0:
		_impact_marker.visible = false
		return
	var impact := _drone.global_position + Vector3(velocity.x, 0.0, velocity.z) * t
	impact.y = 0.06
	_impact_marker.global_position = impact
	_impact_marker.visible = true
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.07
	_impact_marker.scale = Vector3.ONE * pulse


func _unhandled_input(event: InputEvent) -> void:
	if Controls.is_action_edge(event, "deploy_payload"):
		drop_payload()
		get_viewport().set_input_as_handled()


## Returns true only when a physical store was actually released.  The level
## uses this to avoid hiding the pylon model when the guard rejects the drop.
func drop_payload() -> bool:
	if not is_inside_tree():
		return false
	if _drone == null or not is_instance_valid(_drone) or _lost:
		return false
	var p := DroneCatalog.preset(Global.drone_preset)
	var is_combat: bool = bool(p.get("combat", false))
	if not is_combat:
		_message("НЕ БОЙОВИЙ ДРОН — БОЙОВИЙ СКИД ВІДСУТНІЙ", Color(1.0, 0.45, 0.3), 1.8)
		return false
	var has_drop: bool = bool(p.get("has_drop", false))
	if not has_drop:
		_message("КАМІКАДЗЕ — СКИД ВІДСУТНІЙ (ДЕТОНАЦІЯ ПРИ УДАРІ)", Color(1.0, 0.65, 0.3), 1.8)
		return false
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		_message("СПОЧАТКУ УВІМКНІТЬ ДВИГУНИ (ARM)", Color(1.0, 0.55, 0.3), 1.6)
		return false
	if ammo <= 0:
		_message("НЕМАЄ БОЄПРИПАСІВ — R ДЛЯ ПЕРЕЗАРЯДКИ", Color(1.0, 0.45, 0.3), 1.8)
		return false
	# Altitude above ground, not world Y: on the frontline maps the terrain can
	# sit several metres below the origin, so the old absolute `y < 1.6` test
	# rejected legal releases or accepted dangerously low ones.
	var agl := _drone.global_position.y
	var level := get_parent()
	if level != null and level.has_method("_find_ground_y"):
		agl -= float(level.call("_find_ground_y",
				_drone.global_position.x, _drone.global_position.z))
	if agl < 1.6:
		_message("TOO LOW TO RELEASE", Color(1.0, 0.6, 0.3), 1.4)
		return false
	var forward := -_drone.global_transform.basis.z
	var unit_mass := _payload_unit_mass(p)
	var state := Ballistics.release_state(_drone)
	var payload = PayloadScript.new()
	payload.kind = Ballistics.kind_for_mass(unit_mass)
	payload.mass_override = unit_mass
	payload.damage = payload_damage
	payload.blast_radius = payload_radius
	payload.exploded.connect(_on_payload_exploded)
	var parent := get_parent()
	if parent == null:
		return false
	parent.add_child(payload)
	payload.global_position = state.get("origin", _drone.global_position \
			+ Vector3.DOWN * 0.35 + forward * 0.2)
	payload.linear_velocity = state.get("velocity", _drone.linear_velocity \
			+ forward * 2.0 + Vector3.DOWN * 1.0)
	payload.angular_velocity = Vector3(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0),
			randf_range(-3.0, 3.0))
	payload.add_collision_exception_with(_drone)
	ammo -= 1
	drops_count += 1
	if OS.has_environment("DRONE_PAYLOAD_DEBUG"):
		print("[PAYLOAD] preset=%d kind=%s unit_mass=%.2f" % [
			Global.drone_preset, payload.kind, unit_mass])
	var dropped_weight := 0.0
	if _drone != null and _drone.has_method("drop_payload_action"):
		dropped_weight = _drone.drop_payload_action()
	if dropped_weight > 0.001:
		var drop_message := ("PAYLOAD DROP: -%.2f kg (THRUST INCREASED)" if MenuUI.is_english()
				else "СКИД: -%.2f кг (ТЯГА ЗРОСЛА)") % dropped_weight
		_message(drop_message, Color(1.0, 0.9, 0.55), 1.5)
	else:
		_message("BOMB AWAY", Color(1.0, 0.9, 0.55), 1.2)
	_update_hud()
	return true


## Per-unit munition mass for the current airframe.  `payload_mass` is the
## total load; `payload` is the number of rounds.
func _payload_unit_mass(p: Dictionary) -> float:
	var units := maxf(1.0, float(p.get("payload", 1)))
	var total := float(p.get("payload_mass", 0.0))
	if total <= 0.0:
		return 0.0
	return total / units


func _on_payload_exploded() -> void:
	explosions += 1
	Haptics.trigger_explosion(0.55)
	var lvl := get_parent()
	if lvl != null and lvl.has_method("notify_payload_exploded"):
		lvl.call("notify_payload_exploded")


func _on_target_spawned(target: Node3D) -> void:
	_register_target(target)


func _register_target(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group("combat_target"):
		return
	var id := node.get_instance_id()
	if _registered.has(id):
		return
	_registered[id] = true
	targets_total += 1
	node.connect("destroyed", Callable(self, "_on_target_destroyed"))
	_update_hud()


func _on_range_ready(_count: int) -> void:
	_update_hud()


func _on_aa_spawned(gun: Node3D) -> void:
	if gun == null or not is_instance_valid(gun):
		return
	aa_total += 1
	if gun.has_signal("destroyed") and not gun.is_connected("destroyed", Callable(self, "_on_aa_destroyed")):
		gun.connect("destroyed", Callable(self, "_on_aa_destroyed"))
	_update_hud()


func _on_aa_destroyed(points: int) -> void:
	aa_destroyed += 1
	score += points
	Haptics.pulse(36, 0.55, "kill")
	CombatSfxScript.play_hitmarker(self, true)
	_message("AA DESTROYED  +%d" % points, Color(1.0, 0.82, 0.35), 1.8)
	_update_hud()


func _on_infantry_spawned(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	inf_total += 1
	if unit.has_signal("destroyed") and not unit.is_connected("destroyed", Callable(self, "_on_infantry_destroyed")):
		unit.connect("destroyed", Callable(self, "_on_infantry_destroyed"))
	_update_hud()


func _on_infantry_destroyed(points: int) -> void:
	inf_destroyed += 1
	score += points
	Haptics.pulse(32, 0.48, "kill")
	CombatSfxScript.play_hitmarker(self, true)
	_message("INFANTRY DOWN  +%d" % points, Color(1.0, 0.78, 0.30), 1.5)
	_update_hud()


## Bonus destructibles (moving vehicles) that are not part of the TGT roster.
func add_bonus_score(points: int, label: String = "TARGET DOWN") -> void:
	score += points
	_message("%s  +%d" % [label, points], Color(1.0, 0.8, 0.4), 1.5)
	_update_hud()


## Proximity envelope for a kinetic intercept.  One source of truth for the
## live detector, the campaign tuning and the regression test.
static func kamikaze_hit_radius(node: Node) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if node is Vehicle:
		var v := node as Vehicle
		match v.kind:
			Vehicle.Kind.HELI:
				return KAMIKAZE_RADIUS_HELI
			Vehicle.Kind.SHAHED:
				return KAMIKAZE_RADIUS_SHAHED
			_:
				return KAMIKAZE_RADIUS_VEHICLE
	if node.is_in_group("enemy_infantry"):
		return 2.16
	if node.is_in_group("enemy_kamikaze"):
		return KAMIKAZE_RADIUS_SHAHED + 1.6
	return 0.0


func _check_aerial_and_moving_kamikaze() -> void:
	if _lost or _range_cleared or _drone == null or not is_instance_valid(_drone):
		return
	var preset := DroneCatalog.preset(Global.drone_preset)
	if bool(preset.get("has_drop", false)) and ammo <= 0:
		return
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return
	var speed := maxf(_last_speed, _drone.linear_velocity.length())
	if speed < kamikaze_min_speed:
		return
	var d_pos := _drone.global_position
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("combat_target"):
		if not (node is Node3D) or not is_instance_valid(node) or not node.has_method("take_damage"):
			continue
		var n3 := node as Node3D
		var hit_radius := kamikaze_hit_radius(node)
		if hit_radius <= 0.0:
			# Static buildings and landmarks use physical contact (_on_drone_body_entered)
			continue
		if d_pos.distance_to(n3.global_position + Vector3.UP * 1.0) <= hit_radius:
			# Let the level replace the legacy small crash blast with the
			# physical warhead (area damage + impulse + crater).
			if get_parent() != null \
					and get_parent().has_method("try_strike_warhead_contact"):
				if bool(get_parent().call("try_strike_warhead_contact", n3, speed)):
					return
			_message("УДАР КАМІКАДЗЕ!", Color(1.0, 0.6, 0.2), 1.6)
			node.call("take_damage", kamikaze_damage, d_pos)
			_destroy_drone("ДРОН ВТРАЧЕНО — РЕСПАВН")
			return


func _on_target_destroyed(points: int) -> void:
	targets_destroyed += 1
	score += points
	Haptics.pulse(42, 0.62, "kill")
	CombatSfxScript.play_hitmarker(self, true)
	_message("TARGET DESTROYED  +%d" % points, Color(1.0, 0.85, 0.4), 1.8)
	_update_hud()
	if get_parent() != null and get_parent().has_method("_spawn_combat_mission"):
		return
	if targets_total > 0 and targets_destroyed >= targets_total and not _range_cleared:
		_range_cleared = true
		_timer_running = false
		var tree := get_tree()
		if tree == null or not is_inside_tree():
			return
		await tree.create_timer(1.0).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		_show_results()


func can_take_damage() -> bool:
	return not _lost and not _range_cleared and _drone != null and is_instance_valid(_drone)


func is_range_cleared() -> bool:
	return _range_cleared


func damage_drone(amount: float, _hit_position: Vector3 = Vector3.ZERO,
		source_position: Vector3 = Vector3.ZERO) -> void:
	if _lost or _range_cleared or amount <= 0.0 or _results_shown:
		return
	if source_position != Vector3.ZERO and get_parent() != null \
			and get_parent().has_method("report_incoming_fire"):
		get_parent().call("report_incoming_fire", source_position, "ВОГОНЬ")
	drone_health = maxf(drone_health - amount, 0.0)
	Haptics.trigger_collision(maxf(amount * 0.9, 6.0))
	Haptics.pulse(55, 0.72, "damage")
	if _hud != null and is_instance_valid(_hud):
		_hud.call("flash_damage")
	_update_hud()
	if drone_health <= 0.0:
		_destroy_drone("DRONE SHOT DOWN — RESPAWNING")
		return
	if drone_health <= 30.0 and not _critical_warned:
		_critical_warned = true
		_message("HULL CRITICAL — %d%%" % int(round(drone_health)), Color(1.0, 0.35, 0.25), 1.6)


func _show_results() -> void:
	if _results_shown:
		return
	_results_shown = true
	_range_cleared = true
	_timer_running = false
	if _drone != null and is_instance_valid(_drone):
		_drone.freeze = true
		_drone.linear_velocity = Vector3.ZERO
		_drone.angular_velocity = Vector3.ZERO
	if _hud != null and is_instance_valid(_hud):
		_hud.call("show_results", _format_time(_elapsed), score, targets_destroyed,
				targets_total, aa_destroyed, aa_total, inf_destroyed, inf_total)
	var hud_ok := false
	var chud := _hud as CombatHUD
	if chud != null:
		hud_ok = chud.results.visible
	print("[Combat] RESULTS time=%s score=%d targets=%d/%d aa=%d/%d inf=%d/%d hud_ok=%s" % [
		_format_time(_elapsed), score, targets_destroyed, targets_total,
		aa_destroyed, aa_total, inf_destroyed, inf_total, str(hud_ok),
	])
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = true
	print("[Combat] RESULTS paused=", tree.paused)


func _on_restart_requested() -> void:
	if not _results_shown:
		return
	var tree := get_tree()
	if tree == null:
		return
	print("[Combat] RESTART requested; paused=", tree.paused)
	tree.paused = false
	tree.reload_current_scene()


func _format_time(seconds: float) -> String:
	var s := maxf(seconds, 0.0)
	var minutes := int(s) / 60
	var secs := int(s) % 60
	var hundredths := int((s - floor(s)) * 100.0)
	return "%02d:%02d.%02d" % [minutes, secs, hundredths]


func _on_drone_body_entered(body: Node) -> void:
	if _lost or _drone == null or not is_instance_valid(_drone):
		return
	if body == null or not is_instance_valid(body):
		return
	var speed := maxf(_last_speed, _drone.linear_velocity.length())
	# Strike airframes own their warhead.  Let the level perform the single
	# area blast (particles, impulse, crater, radius damage) and stop the old
	# generic crash path from spawning a second explosion.
	var parent_node := get_parent()
	if parent_node != null and parent_node.has_method("try_strike_warhead_contact"):
		if bool(parent_node.call("try_strike_warhead_contact", body, speed)):
			return
	var preset := DroneCatalog.preset(Global.drone_preset)
	var has_warhead := not bool(preset.get("has_drop", false)) or ammo > 0
	if has_warhead and body.is_in_group("combat_target") and body.has_method("take_damage"):
		if speed < kamikaze_min_speed:
			return
		_message("KAMIKAZE HIT", Color(1.0, 0.6, 0.2), 1.6)
		body.call("take_damage", kamikaze_damage, _drone.global_position)
		_destroy_drone("DRONE LOST — RESPAWNING")
		return
	if speed >= crash_speed:
		_destroy_drone("CRASH — DRONE LOST")


func _destroy_drone(text: String) -> void:
	if _lost:
		return
	if _drone == null or not is_instance_valid(_drone):
		return
	_lost = true
	var position := _drone.global_position
	ExplosionScript.spawn(get_parent(), position, 5.0, 0.0)
	Haptics.trigger_explosion(0.9)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_message(text, Color(1.0, 0.4, 0.3), 2.0)
	var lvl := get_parent()
	if lvl != null and lvl.has_method("consume_sortie_airframe"):
		if not bool(lvl.call("consume_sortie_airframe", text)):
			return
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(1.3).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	if lvl != null and not is_instance_valid(lvl):
		lvl = null
	if lvl != null and lvl.has_method("request_kamikaze_respawn_after_replay"):
		lvl.call("request_kamikaze_respawn_after_replay")
	elif lvl != null and lvl.has_method("_execute_kamikaze_respawn"):
		lvl.call("_execute_kamikaze_respawn")
	elif is_instance_valid(_drone):
		_drone.freeze = false
		_drone.reset()
	_lost = false


func _on_drone_respawned() -> void:
	var p := DroneCatalog.preset(Global.drone_preset)
	var is_combat: bool = bool(p.get("combat", false))
	ammo = payload_count if is_combat else 0
	drone_health = drone_max_health
	_lost = false
	_critical_warned = false
	_update_hud()


func _update_hud() -> void:
	if _hud == null or not is_instance_valid(_hud):
		return
	_hud.call("set_stats", targets_total - targets_destroyed, targets_total, ammo,
			payload_count, score, drone_health, drone_max_health, _format_time(_elapsed))


func _message(text: String, color: Color = Color(0.85, 1.0, 0.65), duration: float = 2.0) -> void:
	if _hud == null or not is_instance_valid(_hud):
		print("[Combat] ", text)
		return
	_hud.call("show_message", text, color, duration)


# ---------------------------------------------------------------- self-test

func _clear_range_test() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(4.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var targets := _ground_targets()
	print("[CLEAR-TEST] destroying ", targets.size(), " ground targets")
	for target in targets:
		if is_instance_valid(target) and target.has_method("take_damage"):
			target.call("take_damage", 99999.0, target.global_position + Vector3.UP)
	await tree.create_timer(0.35).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	print("[CLEAR-TEST] destroyed=", targets_destroyed, "/", targets_total,
			" cleared=", _range_cleared, " results=", _results_shown)


func _infantry_autotest() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(4.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var inf := tree.get_nodes_in_group("enemy_infantry")
	print("[INF-AUTOTEST] infantry: ", inf.size(), " hud: ", _hud != null)
	if inf.is_empty() or _drone == null or not is_instance_valid(_drone):
		print("[INF-AUTOTEST] FAIL: no infantry or drone")
		tree.quit()
		return
	var soldier: Node3D = inf[2] if inf.size() > 2 else inf[0]
	if soldier == null or not is_instance_valid(soldier):
		print("[INF-AUTOTEST] FAIL: invalid soldier")
		tree.quit()
		return
	var forward := -soldier.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.01:
		forward = Vector3(0, 0, 1)
	forward = forward.normalized()
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	_drone.angular_velocity = Vector3.ZERO
	_drone.global_position = soldier.global_position + forward * 16.0 + Vector3.UP * 3.5
	_drone.look_at(soldier.global_position + Vector3.UP * 1.3, Vector3.UP)
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller != null:
		controller.set_armed(true)
	_drone.freeze = true
	_drone.linear_velocity = Vector3.ZERO
	var before := drone_health
	var hit := false
	for i in range(240):
		await tree.create_timer(0.05).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		if drone_health < before - 0.5:
			hit = true
			break
	print("[INF-AUTOTEST] infantry fire damage: ", hit, " health ", before, " -> ", drone_health)
	if controller != null and is_instance_valid(controller):
		controller.set_armed(false)
	if hit:
		print("[INF-AUTOTEST] PASS infantry fire")
	else:
		print("[INF-AUTOTEST] FAIL infantry fire")
	tree.quit()


## Kill counter of BigLevel's structured mission system (0 when absent).
func _mission_destroyed_count() -> int:
	var p := get_parent()
	if p == null:
		return 0
	var v = p.get("_mission_targets_destroyed")
	return int(v) if v != null else 0


func _combat_autotest() -> void:
	var tree := get_tree()
	if tree == null or not is_inside_tree():
		return
	await tree.create_timer(4.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	if _drone == null or not is_instance_valid(_drone):
		tree.quit()
		return
	if not bool(DroneCatalog.preset(Global.drone_preset).get("has_drop", false)):
		DroneCatalog.apply_to_drone(_drone, 6)
		ammo = 4
	var all_targets := tree.get_nodes_in_group("combat_target")
	var targets := _ground_targets()
	var aa := tree.get_nodes_in_group("aa_gun")
	var inf := tree.get_nodes_in_group("enemy_infantry")
	print("[COMBAT-AUTOTEST] ground targets: ", targets.size(), " aa: ", aa.size(),
			" inf: ", inf.size(), " all combat bodies: ", all_targets.size(), " hud: ", _hud != null)
	if targets.is_empty():
		print("[COMBAT-AUTOTEST] FAIL: no targets")
		tree.quit()
		return
	var first: Node3D = targets[0]
	if first == null or not is_instance_valid(first):
		tree.quit()
		return
	var score_before := score
	var mission_before := _mission_destroyed_count()
	print("[COMBAT-AUTOTEST] detonating at ", first.name, " ", first.global_position)
	ExplosionScript.spawn(get_parent(), first.global_position + Vector3.UP * 1.2, 8.0, 2000.0)
	await tree.create_timer(0.6).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	# BigLevel's structured missions track their own kill counter; the legacy
	# CombatRange map uses targets_destroyed.  Accept either.
	var mission_after := _mission_destroyed_count()
	var explosion_kill := (targets_destroyed > 0 or mission_after > mission_before) and score > score_before
	print("[COMBAT-AUTOTEST] explosion kill: ", explosion_kill, " destroyed: ", targets_destroyed,
			" mission: ", mission_before, " -> ", mission_after, " score: ", score)

	var payload = PayloadScript.new()
	payload.damage = payload_damage
	payload.blast_radius = payload_radius
	payload.exploded.connect(_on_payload_exploded)
	var parent := get_parent()
	if parent == null:
		tree.quit()
		return
	parent.add_child(payload)
	if _drone == null or not is_instance_valid(_drone):
		tree.quit()
		return
	var origin := _drone.global_position + Vector3(4.0, 20.0, 0.0)
	payload.global_position = origin
	payload.linear_velocity = Vector3.ZERO
	var explosions_before := explosions
	await tree.create_timer(4.0).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var payload_ok := explosions > explosions_before
	print("[COMBAT-AUTOTEST] payload exploded: ", payload_ok, " (", explosions_before, " -> ", explosions, ")")

	if _drone == null or not is_instance_valid(_drone):
		tree.quit()
		return
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	var ammo_before := ammo
	if controller != null:
		controller.set_armed(true)
	drop_payload()
	await tree.create_timer(0.15).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var drop_ok := ammo == ammo_before - 1
	print("[COMBAT-AUTOTEST] drop_payload: ", drop_ok, " ammo ", ammo_before, " -> ", ammo)

	var health_before := drone_health
	damage_drone(10.0)
	await tree.create_timer(0.1).timeout
	if not is_inside_tree() or not is_instance_valid(self):
		return
	var hull_ok := drone_health < health_before
	print("[COMBAT-AUTOTEST] hull damage: ", hull_ok, " health ", health_before, " -> ", drone_health)

	var aa_ok := true
	if not aa.is_empty():
		var aa_before := score
		var gun: Node3D = aa[0]
		if gun == null or not is_instance_valid(gun):
			tree.quit()
			return
		print("[COMBAT-AUTOTEST] destroying AA at ", gun.global_position)
		gun.call("take_damage", 99999.0, gun.global_position + Vector3.UP)
		await tree.create_timer(0.25).timeout
		if not is_inside_tree() or not is_instance_valid(self):
			return
		aa_ok = aa_destroyed > 0 and score >= aa_before + 500
		print("[COMBAT-AUTOTEST] AA destroyed: ", aa_ok, " count ", aa_destroyed,
				" score ", aa_before, " -> ", score)
	if controller != null and is_instance_valid(controller):
		controller.set_armed(false)

	# Structured missions spawn a handful of objectives, not the eight-target
	# legacy range, so the thresholds depend on which mode is running.
	var structured := get_parent() != null and get_parent().has_method("_spawn_combat_mission")
	var enough_targets := targets.size() >= (1 if structured else 8)
	var enough_aa := aa.size() >= 1 or structured
	var enough_inf := inf.size() >= 3 or structured
	if explosion_kill and payload_ok and drop_ok and hull_ok and aa_ok and enough_targets and enough_aa and enough_inf:
		print("[COMBAT-AUTOTEST] PASS combat range")
	else:
		print("[COMBAT-AUTOTEST] FAIL combat range")
	tree.quit()
