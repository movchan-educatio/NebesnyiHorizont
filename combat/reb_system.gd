## Radio-physics and electronic-warfare model for the FPV link.
##
## Computes a line-of-sight link between the pilot antenna and the drone:
##   * distance / radio-horizon loss;
##   * terrain and tree-line occlusion (raycast, so a dive into a ravine or
##     behind a hill really does break the picture);
##   * enemy EW domes (150-250 m) and directional jammers;
##   * latency, stick jitter, packet loss, video tearing and failsafe.
##
## The FPV overlay and the radio controller read the public fields every
## frame, so the picture and the controls degrade together.
class_name RebSystem
extends Node3D

signal link_updated(lq: float)
signal failsafe_changed(active: bool)

## Pilot/home antenna position.  Set by the level after spawning.
@export var home_position := Vector3.ZERO
@export var use_own_position_as_home := true
@export var antenna_height := 1.8
## Range at which the link reaches zero in free space (calibrated to the 384 m frontline arena).
@export var base_range_m := 680.0
## Extra loss when terrain blocks the direct ray.
@export var occlusion_loss := 0.72
## Global multiplier for EW effects.  The domes stay visible and dangerous, forcing
## altitude/routing adaptation without instantly downing the aircraft on a graze.
@export var ew_effect_scale := 0.78
## Smoothing so the picture does not flicker between two states.
@export var smoothing := 4.0
## Seconds below the failsafe threshold before the receiver cuts.
@export var failsafe_delay := 1.2
@export var failsafe_lq := 0.10

@export var ew_domes: Array = []

var link_quality := 1.0
var signal_strength := 1.0
var bitrate_mbps := 50.0
var packet_loss := 0.0
var latency_spike := 0.0
var tear_amount := 0.0
var interference := 0.0
var latency_ms := 18.0
var stick_jitter := Vector2.ZERO
var failsafe := false
var distance_m := 0.0
var blocked := false
var in_ew := 0.0
## False when the player disabled link limits in "Other settings".  The REB
## node then keeps reporting a perfect link so the drone can fly out of range.
var limits_enabled := true
## Independent gate for the EW domes.  Range/terrain loss can stay active
## while electronic warfare is switched off (training progression).
var reb_zones_enabled := true
## Always keep telemetry/video clean and mast domes disabled in Freestyle.
var unlimited_freestyle := false

var _drone: Node3D = null
var _radio: Node = null
var _below_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _masts: Array[Node3D] = []
var _los_timer := 0.0
var _cached_los := true


func _ready() -> void:
	add_to_group("reb_system")
	_rng.randomize()
	limits_enabled = _read_limits_enabled()
	reb_zones_enabled = _read_reb_zones_enabled()
	if use_own_position_as_home:
		home_position = global_position
	_drone = get_tree().get_first_node_in_group("player_drone")
	if _drone == null and get_tree().current_scene != null:
		_drone = get_tree().current_scene.get_node_or_null("Drone") as Node3D
	_radio = get_tree().current_scene.get_node_or_null("RadioController") if get_tree().current_scene != null else null
	if _radio != null:
		_radio.set("link_provider", self)
	_build_masts()


func _build_masts() -> void:
	for dome in ew_domes:
		_build_mast(dome.get("position", Vector3.ZERO),
				bool(dome.get("directional", false)))


func add_ew_dome(pos: Vector3, radius: float = 200.0, strength: float = 0.85,
		directional: bool = false, yaw_rad: float = 0.0, fov_deg: float = 70.0) -> void:
	ew_domes.append({
		"position": pos,
		"radius": clampf(radius, 20.0, 600.0),
		"strength": clampf(strength, 0.0, 1.0),
		"directional": directional,
		"yaw": yaw_rad,
		"fov": deg_to_rad(clampf(fov_deg, 10.0, 360.0)),
	})
	_build_mast(pos, directional)


## A visible antenna mast at each jammer so the player can learn to avoid it.
func _build_mast(pos: Vector3, directional: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	root.visible = limits_enabled and reb_zones_enabled
	add_child(root)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.13, 0.11)
	mat.roughness = 0.9
	var mast := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.11
	cyl.height = 6.0
	mast.mesh = cyl
	mast.material_override = mat
	mast.position.y = 3.0
	root.add_child(mast)
	var head := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.5, 0.35) if directional else Vector3(0.35, 0.9, 0.35)
	head.mesh = box
	head.position.y = 6.2
	root.add_child(head)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.12, 0.08)
	lamp.light_energy = 1.4
	lamp.omni_range = 5.0
	lamp.position.y = 6.6
	root.add_child(lamp)
	_masts.append(root)


func _physics_process(delta: float) -> void:
	if _drone == null or not is_instance_valid(_drone):
		_drone = get_tree().get_first_node_in_group("player_drone")
		if _drone == null and get_tree().current_scene != null:
			_drone = get_tree().current_scene.get_node_or_null("Drone") as Node3D
		if _drone == null:
			return
	var drone_pos := _drone.global_position
	distance_m = drone_pos.distance_to(home_position)

	if unlimited_freestyle:
		limits_enabled = false
		reb_zones_enabled = false
		_set_masts_visible(false)
		_apply_unlimited_link()
		return
	# Simulator aid: "link_limit" off means no range, terrain, EW or failsafe
	# effects.  Reading the setting live lets the pause menu toggle it in flight.
	var limits := _read_limits_enabled()
	var zones := _read_reb_zones_enabled()
	if limits != limits_enabled or zones != reb_zones_enabled:
		limits_enabled = limits
		reb_zones_enabled = zones
		_set_masts_visible(limits_enabled and reb_zones_enabled)
	if not limits_enabled:
		_apply_unlimited_link()
		return
	var global_node := get_node_or_null("/root/Global")
	if global_node != null:
		var ms = global_node.get("menu_settings")
		if ms is Dictionary and bool((ms as Dictionary).get("fiber_optic_mode", false)):
			_apply_unlimited_link()
			return

	# 1. Free-space distance loss.
	var distance_lq := clampf(1.0 - distance_m / maxf(base_range_m, 1.0), 0.0, 1.0)

	# 2. Terrain / tree-line occlusion.  The ray goes from the pilot antenna
	# to the drone; a hit means the picture is behind a hill or a tree line.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.10
		_cached_los = _line_of_sight(home_position + Vector3.UP * antenna_height, drone_pos)
	var los := _cached_los
	var occlusion := 0.0
	if not los:
		occlusion = occlusion_loss * clampf(distance_m / 120.0, 0.25, 1.0)

	# 3. EW domes: stronger near the centre, directional stations only inside
	# their cone.  The zones can be disabled independently from range loss.
	var ew := 0.0
	if reb_zones_enabled:
		for dome in ew_domes:
			var dpos: Vector3 = dome.get("position", Vector3.ZERO)
			var radius: float = float(dome.get("radius", 200.0))
			var d := drone_pos.distance_to(dpos)
			if d > radius:
				continue
			var falloff := 1.0 - d / radius
			var s: float = float(dome.get("strength", 0.8)) * falloff
			if bool(dome.get("directional", false)):
				var to_drone := (drone_pos - dpos)
				to_drone.y = 0.0
				var fwd := Vector3(sin(float(dome.get("yaw", 0.0))), 0.0,
						cos(float(dome.get("yaw", 0.0))))
				if to_drone.length() > 0.01 and fwd.angle_to(to_drone.normalized()) > float(dome.get("fov", 1.2)) * 0.5:
					s *= 0.15
			ew = maxf(ew, s)
	ew = clampf(ew * ew_effect_scale, 0.0, 1.0)
	in_ew = ew

	var target_lq := clampf(distance_lq - occlusion - ew * 0.85, 0.0, 1.0)
	var blend := clampf(delta * smoothing, 0.0, 1.0)
	link_quality = lerpf(link_quality, target_lq, blend)
	blocked = not los
	signal_strength = clampf(link_quality * (1.0 - ew * 0.35)
			+ _rng.randf_range(-0.025, 0.025), 0.0, 1.0)

	# 4. Downlink quality: digital bitrate collapses, analog tears.
	bitrate_mbps = lerpf(1.0, 50.0, pow(link_quality, 1.35))
	packet_loss = clampf((1.0 - link_quality) * 1.15 + ew * 0.18, 0.0, 1.0)
	latency_spike = clampf((1.0 - link_quality) * 0.95 + ew * 0.45, 0.0, 1.0)
	tear_amount = clampf((1.0 - link_quality) * 1.25 + ew * 0.55, 0.0, 1.0)
	interference = clampf(ew * 1.25 + (1.0 - link_quality) * 0.35, 0.0, 1.0)
	latency_ms = 18.0 + (1.0 - link_quality) * 230.0 + ew * 130.0

	# 5. Stick jitter: the pilot's corrections get noisy before the link dies.
	var jitter_scale := (1.0 - link_quality) * 0.30 + ew * 0.12
	stick_jitter = Vector2(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0)) * jitter_scale

	# 6. Failsafe: hold for a moment below the threshold, then cut.
	if link_quality < failsafe_lq:
		_below_timer += delta
		if _below_timer >= failsafe_delay and not failsafe:
			failsafe = true
			failsafe_changed.emit(true)
	else:
		_below_timer = maxf(_below_timer - delta * 2.0, 0.0)
		if failsafe and link_quality > 0.28:
			failsafe = false
			failsafe_changed.emit(false)

	if _radio != null:
		var tick_ms := 1000.0 / float(maxi(Engine.physics_ticks_per_second, 30))
		_radio.set("input_latency_frames", int(clampf(latency_ms / tick_ms, 0.0, 28.0)))
	emit_signal("link_updated", link_quality)


func _read_limits_enabled() -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return true
	var config = settings.get("hud_config")
	if config is Dictionary:
		return bool((config as Dictionary).get("link_limit", true))
	return true


func _read_reb_zones_enabled() -> bool:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return true
	var config = settings.get("hud_config")
	if config is Dictionary:
		return bool((config as Dictionary).get("reb_zones", true))
	return true


func _set_masts_visible(active: bool) -> void:
	for mast in _masts:
		if is_instance_valid(mast):
			mast.visible = active


## Perfect downlink and clean controls; used when link limits are disabled.
func _apply_unlimited_link() -> void:
	if failsafe:
		failsafe = false
		failsafe_changed.emit(false)
	link_quality = 1.0
	signal_strength = 1.0
	bitrate_mbps = 50.0
	packet_loss = 0.0
	latency_spike = 0.0
	tear_amount = 0.0
	interference = 0.0
	latency_ms = 18.0
	stick_jitter = Vector2.ZERO
	blocked = false
	in_ew = 0.0
	_below_timer = 0.0
	if _radio != null:
		_radio.set("input_latency_frames", 0)
	emit_signal("link_updated", link_quality)


func _line_of_sight(from: Vector3, to: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	if _drone is CollisionObject3D:
		query.exclude = [(_drone as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	return hit.is_empty()


func get_link_state() -> Dictionary:
	return {
		"lq": link_quality,
		"signal": signal_strength,
		"bitrate": bitrate_mbps,
		"packet_loss": packet_loss,
		"latency_spike": latency_spike,
		"tear": tear_amount,
		"interference": interference,
		"latency_ms": latency_ms,
		"failsafe": failsafe,
		"blocked": blocked,
		"distance": distance_m,
		"ew": in_ew,
	}


func get_lq_percent() -> int:
	return int(round(link_quality * 100.0))


func get_status_text() -> String:
	if not limits_enabled:
		return "UNLIMITED"
	if failsafe:
		return "FAILSAFE"
	if link_quality < 0.2:
		return "CRITICAL"
	if link_quality < 0.45:
		return "WEAK"
	if link_quality < 0.75:
		return "OK"
	return "LINK"
