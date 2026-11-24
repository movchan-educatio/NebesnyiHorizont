class_name EnemyKamikazeDrone
extends StaticBody3D
## Великий ворожий FPV-дрон-камікадзе (KT-8 «Гриф» / KT-12 «Василіск»).
## Повноцінний combat_target: переслідує пілота, попереджає, пікірує,
## падає з обертанням і вибухає. Використовує існуючі Explosion/DestructionFx/Sfx.

signal destroyed(points: int)

const MODEL_PATHS := [
	"res://Assets/enemy_drones/KT8_Grif.glb",
	"res://Assets/enemy_drones/KT12_Basilisk.glb",
]

enum Phase { SPAWN, APPROACH, LOCK, DIVE, FALLING, DEAD }

@export var variant: int = 0
@export var max_health: float = 140.0
@export var points: int = 260
@export var move_speed: float = 23.0
@export var dive_speed: float = 39.0
@export var turn_speed: float = 2.6
@export var prop_spin_speed: float = 14.0
@export var detect_range: float = 230.0
@export var dive_range: float = 78.0
@export var impact_damage: float = 34.0
@export var cruise_height: float = 58.0
@export var hostile: bool = true

var is_primary_target: bool = true
var impacted_player: bool = false
var phase: int = Phase.SPAWN
var health: float = 1.0
var _target: Node3D = null
var _model: Node3D = null
var _props: Array[Node3D] = []
var _engine: AudioStreamPlayer3D = null
var _phase_timer: float = 0.0
var _fall_velocity := Vector3.ZERO
var _fall_timer: float = 0.0
var _warned: bool = false
var _dead_notified: bool = false


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("air_target")
	if is_primary_target:
		add_to_group("primary_combat_target")
	add_to_group("enemy_kamikaze")
	collision_layer = 1
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.4
	shape.shape = sphere
	add_child(shape)
	_build_model()
	_build_audio()
	if OS.has_environment("DRONE_KAMIKAZE_DEBUG"):
		print("[KAMIKAZE] spawned variant=", variant, " hp=", health)


func _build_model() -> void:
	var path: String = MODEL_PATHS[clampi(variant, 0, MODEL_PATHS.size() - 1)]
	if not ResourceLoader.exists(path):
		push_warning("[KAMIKAZE] model missing: " + path)
		return
	var packed := load(path) as PackedScene
	if packed == null:
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	_model.scale = Vector3.ONE * 1.15
	add_child(_model)
	DroneCatalog.apply_pack_colors(_model)
	_setup_rotor_pivots(_model)
	print("[KAMIKAZE] model ", path, " props=", _props.size())


func set_primary_target(primary: bool) -> void:
	is_primary_target = primary
	set_meta("is_primary_target", primary)
	if primary:
		if not is_in_group("primary_combat_target"):
			add_to_group("primary_combat_target")
	else:
		if is_in_group("primary_combat_target"):
			remove_from_group("primary_combat_target")


func activate() -> void:
	if phase == Phase.SPAWN:
		phase = Phase.APPROACH
		_phase_timer = 0.0


func _rotor_prefix(node_name: String) -> String:
	for token in ["_Blade_", "_Tip_", "_Stripe_", "_HubScrew_", "_RootFairing_"]:
		var idx := node_name.find(token)
		if idx > 0:
			return node_name.substr(0, idx + 1)
	for suffix in ["_HubUpper", "_HubLower", "_Nut"]:
		if node_name.ends_with(suffix):
			return node_name.substr(0, node_name.length() - suffix.length() + 1)
	return ""


func _setup_rotor_pivots(root: Node) -> void:
	_props.clear()
	var groups := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for ch in cur.get_children():
			stack.append(ch)
		if not (cur is Node3D):
			continue
		var n := String(cur.name)
		var prefix := _rotor_prefix(n)
		if prefix.is_empty():
			continue
		var p := cur.get_parent()
		if p == null:
			continue
		var key := "%d:%s" % [p.get_instance_id(), prefix]
		if not groups.has(key):
			groups[key] = {"parent": p, "prefix": prefix, "parts": [], "hub": null}
		var g: Dictionary = groups[key]
		(g["parts"] as Array).append(cur)
		if n.ends_with("_HubUpper"):
			g["hub"] = cur
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var g: Dictionary = groups[k]
		var p: Node = g["parent"]
		var parts: Array = g["parts"]
		if p == null or parts.is_empty():
			continue
		var hub: Node3D = g["hub"] as Node3D
		var origin := hub.transform.origin if hub != null else (parts[0] as Node3D).transform.origin
		var pivot := Node3D.new()
		pivot.name = "KamikazePivot_%d" % _props.size()
		pivot.transform = Transform3D(Basis.IDENTITY, origin)
		p.add_child(pivot)
		for part in parts:
			var nd := part as Node3D
			var xf := nd.transform
			p.remove_child(nd)
			pivot.add_child(nd)
			nd.transform = Transform3D(xf.basis, xf.origin - origin)
		_props.append(pivot)


func _build_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_engine = CombatSfx.make_looping_player(
			CombatSfx.kamikaze_engine_stream(variant), -12.0, 14.0, 320.0)
	if _engine != null:
		_engine.name = "KamikazeEngine"
		add_child(_engine)
		_engine.play()


func _find_level() -> Node:
	var p := get_parent()
	while p != null:
		if p.has_method("_spawn_special_or_campaign") or p.name == "BigLevel" \
				or p.name.begins_with("LisLevel") or p.name.begins_with("OilRigLevel"):
			return p
		p = p.get_parent()
	return null


func _find_target() -> Node3D:
	var level := _find_level()
	if level != null:
		var d := level.get_node_or_null("Drone") as Node3D
		if d != null and is_instance_valid(d):
			return d
	return null


func _physics_process(delta: float) -> void:
	if phase == Phase.FALLING:
		_process_fall(delta)
		return
	if phase == Phase.DEAD:
		return
	if phase == Phase.SPAWN:
		var lvl := _find_level()
		if lvl == null or bool(lvl.get("_mission_started")):
			activate()
		else:
			return
	_spin_props(delta)
	if _target == null or not is_instance_valid(_target):
		_target = _find_target()
	if _target == null:
		return
	var to_target := _target.global_position - global_position
	var dist := to_target.length()
	_phase_timer += delta
	if phase == Phase.APPROACH:
		_approach(delta, to_target, dist)
		if dist < detect_range and not _warned:
			_warned = true
			CombatSfx.play_kamikaze_warning(self, global_position)
		if dist <= dive_range or _phase_timer > 14.0:
			phase = Phase.LOCK
			_phase_timer = 0.0
			CombatSfx.play_kamikaze_warning(self, global_position)
	elif phase == Phase.LOCK:
		_approach(delta, to_target, dist)
		if _phase_timer >= 2.4 or dist <= dive_range * 0.55:
			phase = Phase.DIVE
			_phase_timer = 0.0
	elif phase == Phase.DIVE:
		_approach(delta, to_target, dist, dive_speed)
		if dist <= 8.5:
			_impact()
		if _engine != null:
			_engine.pitch_scale = 1.15 if phase == Phase.DIVE else 0.95


func _spin_props(delta: float) -> void:
	var step := prop_spin_speed * delta * (1.7 if phase == Phase.DIVE else 1.0)
	for i in range(_props.size()):
		var p := _props[i]
		if is_instance_valid(p):
			var dir := 1.0 if (i % 2 == 0) else -1.0
			p.rotate_object_local(Vector3.UP, step * dir)


func _ground_floor_y() -> float:
	var lvl := _find_level()
	if lvl != null and lvl.has_method("_find_ground_y"):
		return float(lvl.call("_find_ground_y", global_position.x, global_position.z))
	return 0.0


func _approach(delta: float, to_target: Vector3, _dist: float, speed: float = -1.0) -> void:
	var spd := move_speed if speed < 0.0 else speed
	var floor_y := _ground_floor_y()
	var aim := to_target
	if phase == Phase.APPROACH and global_position.y < floor_y + cruise_height * 0.65:
		aim.y = maxf(aim.y, (floor_y + cruise_height * 0.75) - global_position.y)
	var desired := aim.normalized() if aim.length_squared() > 0.0001 else Vector3.FORWARD
	var forward := -global_transform.basis.z.normalized()
	var cross := forward.cross(desired)
	var angle := acos(clampf(forward.dot(desired), -1.0, 1.0))
	var rot := Quaternion()
	if cross.length_squared() > 0.0001 and angle > 0.0001:
		rot = Quaternion(cross.normalized(), angle)
	var applied := Quaternion().slerp(rot, clampf(turn_speed * delta, 0.0, 1.0))
	global_transform.basis = (Basis(applied) * global_transform.basis).orthonormalized()
	global_position += desired * spd * delta
	var min_y := floor_y + (2.5 if phase == Phase.DIVE else cruise_height * 0.5)
	if global_position.y < min_y:
		global_position.y = lerpf(global_position.y, min_y, clampf(delta * 3.0, 0.0, 1.0))


func take_damage(amount: float, _hit_position: Vector3 = Vector3.ZERO) -> void:
	if phase == Phase.FALLING or phase == Phase.DEAD:
		return
	health -= amount
	if OS.has_environment("DRONE_KAMIKAZE_DEBUG"):
		print("[KAMIKAZE] hit remaining=", health)
	if health <= 0.0:
		_begin_fall(false)


func _impact() -> void:
	if _target != null and is_instance_valid(_target):
		var level := _find_level()
		var combat := level.get_node_or_null("CombatSystem") if level != null else null
		if combat != null and combat.has_method("damage_drone"):
			var dmg := impact_damage
			if Global.difficulty == Global.Difficulty.RECRUIT:
				dmg *= 0.7
			elif Global.difficulty == Global.Difficulty.ACE:
				dmg *= 1.35
			combat.call("damage_drone", dmg, _target.global_position, global_position)
	impacted_player = true
	_begin_fall(true)


func _begin_fall(impacted: bool) -> void:
	if phase == Phase.FALLING or phase == Phase.DEAD:
		return
	phase = Phase.FALLING
	_fall_timer = 0.0
	_fall_velocity = Vector3(randf_range(-6.0, 6.0), -8.0 if impacted else -3.0,
			randf_range(-6.0, 6.0))
	collision_layer = 0
	collision_mask = 0
	if _engine != null:
		_engine.pitch_scale = 0.6
	CombatSfx.play_kamikaze_fall(self, global_position)
	DestructionFx.trail(self)
	if not _dead_notified:
		_dead_notified = true
		destroyed.emit(points)


func _process_fall(delta: float) -> void:
	_fall_timer += delta
	_fall_velocity.y -= 18.0 * delta
	global_position += _fall_velocity * delta
	if _model != null:
		_model.rotate_x(4.5 * delta)
		_model.rotate_z(3.1 * delta)
	_spin_props(delta * 0.4)
	if _fall_timer >= 1.4:
		_explode()


func _explode() -> void:
	if phase == Phase.DEAD:
		return
	phase = Phase.DEAD
	if get_parent() != null:
		Explosion.spawn(get_parent(), global_position, 7.5, 0.0)
		DestructionFx.destroy(get_parent(), self, "shahed", 0.0,
				{"char_unit": false, "move_unit": false, "burn": false, "debris": true})
	CombatSfx.play_boom(get_parent(), global_position, -2.0)
	queue_free()


func get_points() -> int:
	return points
