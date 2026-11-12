## Enemy rifleman: a Blender-authored soldier who spots the armed drone,
## shoulders his rifle and fires small-arms bursts.  He is a bonus threat like
## the AA nest, not one of the ten TGT objectives, and can be destroyed by
## bombs, explosions or a kamikaze hit.
class_name EnemyRifleman
extends StaticBody3D

signal destroyed(points: int)

const RIFLEMAN_SCENE = preload("res://Assets/combat/rifleman.glb")
const INFANTRY_IMPOSTOR_ATLAS := "res://Assets/combat/soldier_impostor_atlas.png"
## The authored, articulated rifleman. This one has separate leg/arm meshes and
## a sane 1.9 m skeleton, unlike the HECU rip whose bind matrices are scaled x100
## and collapse inside Godot.
const SOLDIER_MODEL := "res://Assets/combat/rifleman.glb"
const TracerScript = preload("res://combat/tracer.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const CombatSfxScript = preload("res://combat/sfx.gd")
const HitFxScript = preload("res://combat/hit_fx.gd")
const DestructionFxScript = preload("res://combat/destruction_fx.gd")
const FrontlineTerrainScript = preload("res://scripts/util/frontline_terrain.gd")

@export var max_health := 55.0
@export var points := 150
@export var detect_range := 115.0
@export var tracer_damage := 2.0
@export var tracer_speed := 95.0
@export var burst_shots := 4
@export var shot_interval := 0.14
@export var burst_pause_min := 1.25
@export var burst_pause_max := 1.95
## A drone this close and in sight spooks the squad: most soldiers scatter and
## go prone, the rest stand their ground and shoot. 0 disables the reaction.
@export var panic_range := 18.0
@export var panic_chance := 0.25
@export var scatter_speed := 4.8

var health := 0.0
var is_destroyed := false

var _drone: Drone = null
var _combat: Node = null
var _model: Node3D = null
var _pitch: Node3D = null
var _muzzle: Node3D = null
var _label: Label3D = null
var _disabled := false
var _los_clear := false
var _distance := 999.0
## Low-end presets tick distant AI at 1/3 rate.
var _ai_low := false
var _ai_tick := 0
var _los_timer := 0.0
var _burst_left := 0
var _shot_cd := 0.0
var _recover := 1.2
var _recoil := 0.0
var _demo_miss := false
var _demo_visual := false
var _meshes: Array[MeshInstance3D] = []
var _detailed_rig: DetailedSoldierRig = null
var _flash_material: StandardMaterial3D = null
var _flash_token := 0
var _last_hit_fx_ms := 0
var _lod_proxy: Node3D = null
var _lod_impostor: Sprite3D = null
var _using_proxy := false
var _lod_tick := 0.0

# Simple procedural locomotion, driven by the Blender hip/knee pivots.
var _hip_l: Node3D = null
var _knee_l: Node3D = null
var _hip_r: Node3D = null
var _knee_r: Node3D = null
var _anim: AnimationPlayer = null
var _walk_phase := 0.0
var _step_timer := 0.0
var _stride := 0.0
var _patrol_active := false
var _patrol_origin := Vector3.ZERO
var _patrol_axis := Vector3.FORWARD
var _patrol_range := 0.0
var _patrol_speed := 0.0
var _patrol_dir := 1.0
var _panic_state := 0          # 0 calm, 1 scattering, 2 prone
var _panic_timer := 0.0
var _panic_dir := Vector3.ZERO
var _panic_checked := false
var _prone_pose := 0.0
var _mag_capacity := 15
var _mag_rounds := 15
var _reload_timer := 0.0
var _suppress_timer := 0.0
var _crouching := false
var _scan_phase := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _tactical_knee := false


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("enemy_infantry")
	collision_layer = 1
	collision_mask = 1
	_disabled = _qa_disabled()
	_ai_low = QualityManager.get_active_level() == QualityManager.Level.LOW
	_strafe_dir = -1.0 if (abs(get_instance_id()) % 2 == 0) else 1.0
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		# Deterministic per-soldier gait offset so squads never march in lockstep.
		_walk_phase = fmod(float(abs(get_instance_id())) * 0.6180339, TAU)
	_build()
	_build_lod_proxy()
	_drone = get_tree().current_scene.get_node_or_null("Drone") as Drone
	_combat = get_tree().current_scene.get_node_or_null("CombatSystem")
	match Global.difficulty:
		Global.Difficulty.RECRUIT:
			tracer_damage = 1.2
			detect_range = 85.0
			burst_shots = 3
		Global.Difficulty.ACE:
			tracer_damage = 3.2
			detect_range = 145.0
			burst_shots = 5


func _build() -> void:
	# Prefer the detailed skinned soldier.  The old 58-box rifleman remains as
	# a fallback if the imported GLB is unavailable.
	var rig := DetailedSoldierRig.new()
	rig.name = "Model"
	add_child(rig)
	var team_id := 99
	if get("team") != null:
		team_id = int(get("team"))
	if rig.setup_rig(team_id):
		_model = rig
		_detailed_rig = rig
		_muzzle = rig.muzzle
		if _muzzle == null:
			var marker := Marker3D.new()
			marker.name = "MuzzleFallback"
			marker.position = Vector3(0.0, 1.25, -0.85)
			rig.add_child(marker)
			_muzzle = marker
		_pitch = null
		_collect_meshes(_model)
	else:
		rig.queue_free()
		_model = _create_model()
		if _model == null:
			_build_fallback()
		else:
			_model.name = "Model"
			add_child(_model)
			_pitch = _model.find_child("PitchPivot", true, false) as Node3D
			_muzzle = _model.find_child("Muzzle", true, false) as Node3D
			_hip_l = _model.find_child("HipJoint_L", true, false) as Node3D
			_knee_l = _model.find_child("KneeJoint_L", true, false) as Node3D
			_hip_r = _model.find_child("HipJoint_R", true, false) as Node3D
			_knee_r = _model.find_child("KneeJoint_R", true, false) as Node3D
			if _pitch == null:
				# Authored rifleman: scale to human height, keep facing -Z (its rifle
				# already points that way) and build hip/knee pivots so the legs
				# actually walk instead of the soldier sliding around.
				_model.rotation.y = 0.0
				_setup_rifleman_rig(_model)
				_anim = _find_anim(_model)
			if _muzzle == null:
				var marker := Marker3D.new()
				marker.name = "MuzzleFallback"
				marker.position = Vector3(0.10, 1.39, -1.25)
				_model.add_child(marker)
				_muzzle = marker
			_collect_meshes(_model)

	_label = Label3D.new()
	_label.text = "INF"
	_label.font_size = 56
	_label.pixel_size = 0.0085
	_label.modulate = Color(1.0, 0.48, 0.20)
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_label.outline_size = 12
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.position = Vector3(0, 3.9, 0)
	# No floating "INF" tag over each soldier; the player identifies infantry
	# visually.  The label is kept hidden for compatibility.
	_label.visible = false
	add_child(_label)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.92, 2.75, 0.92)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, 1.68, 0)
	add_child(collision)


func _create_model() -> Node3D:
	if ResourceLoader.exists(SOLDIER_MODEL):
		var packed := load(SOLDIER_MODEL) as PackedScene
		if packed != null:
			var model := packed.instantiate() as Node3D
			if model != null:
				return model
	return RIFLEMAN_SCENE.instantiate() as Node3D


func _normalise_soldier(model: Node3D, height: float) -> void:
	var box := DroneCatalog.model_bounds(model)
	if box.size.y <= 0.0001:
		return
	model.scale = Vector3.ONE * (height / box.size.y)
	var after := DroneCatalog.model_bounds(model)
	var centre := after.get_center()
	model.global_position += Vector3(global_position.x - centre.x, 0.0,
			global_position.z - centre.z)
	model.global_position.y += global_position.y - after.position.y


## The rifleman ships as 58 separate rigid parts with the leg meshes split at
## the knee. Hang each leg on a hip pivot and a knee pivot so the generic
## locomotion code can swing them; the rifle stays in the hands.
func _setup_rifleman_rig(model: Node3D) -> void:
	_normalise_soldier(model, 2.75)
	if model.find_child("Thigh_L", true, false) == null:
		return
	var left := _make_leg_rig(model, -1.0, "L")
	_hip_l = left[0]
	_knee_l = left[1]
	var right := _make_leg_rig(model, 1.0, "R")
	_hip_r = right[0]
	_knee_r = right[1]


func _make_leg_rig(model: Node3D, side: float, suffix: String) -> Array:
	var upper := ["Thigh_" + suffix, "Thigh_pocket_" + suffix]
	var lower := ["Knee_" + suffix, "Shin_" + suffix, "Boot_" + suffix,
			"Boot_toe_" + suffix]
	var hip := Node3D.new()
	hip.name = "HipJoint_" + suffix
	model.add_child(hip)
	hip.position = Vector3(side * 0.145, 0.95, 0.0)
	var knee := Node3D.new()
	knee.name = "KneeJoint_" + suffix
	hip.add_child(knee)
	knee.position = Vector3(0.0, -0.43, -0.02)
	for part_name in upper:
		_reparent_part(model, hip, part_name)
	for part_name in lower:
		_reparent_part(model, knee, part_name)
	return [hip, knee]


func _reparent_part(model: Node3D, pivot: Node3D, part_name: String) -> void:
	var part := model.find_child(part_name, true, false) as Node3D
	if part != null:
		part.reparent(pivot, true)


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


func _build_fallback() -> void:
	# Keeps the threat visible if the GLB has not been imported yet.
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.36
	capsule.height = 3.1
	var body := MeshInstance3D.new()
	body.mesh = capsule
	body.position = Vector3(0, 1.28, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.27, 0.14)
	body.material_override = material
	add_child(body)
	_meshes.append(body)
	var marker := Marker3D.new()
	marker.name = "MuzzleFallback"
	marker.position = Vector3(0.14, 2.02, -1.65)
	add_child(marker)
	_muzzle = marker


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if QualityManager.get_active_level() != QualityManager.Level.LOW:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 360.0
		_meshes.append(mi)
	for child in node.get_children():
		_collect_meshes(child)


func _build_lod_proxy() -> void:
	# Keep the desktop presentation unchanged; the simplified proxy is mobile-only.
	if not _mobile_visual_lod_enabled() or _model == null:
		return
	_lod_proxy = Node3D.new()
	_lod_proxy.name = "LodProxy"
	_lod_proxy.visible = false
	add_child(_lod_proxy)
	_lod_proxy.scale = Vector3.ONE * 1.8
	var atlas := load(INFANTRY_IMPOSTOR_ATLAS) as Texture2D \
			if ResourceLoader.exists(INFANTRY_IMPOSTOR_ATLAS) else null
	if atlas != null:
		_lod_impostor = Sprite3D.new()
		_lod_impostor.name = "FourViewInfantryImpostor"
		_lod_impostor.texture = atlas
		_lod_impostor.hframes = 2
		_lod_impostor.vframes = 2
		_lod_impostor.pixel_size = 1.88 / 512.0
		_lod_impostor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_lod_impostor.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		_lod_impostor.position = Vector3(0.0, 0.94, 0.0)
		_lod_impostor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lod_proxy.add_child(_lod_impostor)
	else:
		# Safe fallback until the baked atlas has been imported by Godot.
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.18, 0.21, 0.15)
		mat.roughness = 0.92
		mat.metallic = 0.04
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.25
		capsule.height = 1.18
		var sphere := SphereMesh.new()
		sphere.radius = 0.14
		sphere.height = 0.28
		var box := BoxMesh.new()
		box.size = Vector3(0.055, 0.055, 0.62)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(capsule, 0, Transform3D(Basis(), Vector3(0.0, 0.92, 0.0)))
		st.append_from(sphere, 0, Transform3D(Basis(), Vector3(0.0, 1.62, 0.0)))
		st.append_from(box, 0, Transform3D(Basis(), Vector3(0.18, 1.28, -0.22)))
		var proxy := MeshInstance3D.new()
		proxy.mesh = st.commit()
		proxy.material_override = mat
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_lod_proxy.add_child(proxy)
		_meshes.append(proxy)


func _update_lod(delta: float) -> void:
	_lod_tick -= delta
	if _lod_tick > 0.0:
		return
	_lod_tick = 0.25
	if _lod_proxy == null or _model == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dist := global_position.distance_to(cam.global_position)
	if _detailed_rig != null:
		_detailed_rig.set_mobile_animation_lod(dist)
	if _lod_impostor != null:
		_update_impostor_frame(cam)
	_apply_animation_lod(dist)
	if dist > 260.0:
		# Beyond 260 m a soldier is sub-pixel; stop drawing the rig/proxy.
		_using_proxy = true # lets the hysteretic transition restore LOD on return
		_model.visible = false
		_lod_proxy.visible = false
		_pause_lod_animation()
		return
	if _using_proxy:
		if dist < 95.0:
			_using_proxy = false
			_lod_proxy.visible = false
			_model.visible = true
			_resume_lod_animation()
		else:
			_lod_proxy.visible = true
			_model.visible = false
	elif dist > 125.0:
		_using_proxy = true
		_lod_proxy.visible = true
		_model.visible = false
		_pause_lod_animation()
	else:
		_resume_lod_animation()


func _update_impostor_frame(cam: Camera3D) -> void:
	if _lod_impostor == null:
		return
	var to_camera := cam.global_position - global_position
	to_camera.y = 0.0
	if to_camera.length_squared() < 0.0001:
		return
	var local_dir := global_transform.basis.inverse() * to_camera.normalized()
	var angle := atan2(local_dir.x, -local_dir.z)
	if angle > PI * 0.75 or angle < -PI * 0.75:
		_lod_impostor.frame = 2 # back
	elif angle > PI * 0.25:
		_lod_impostor.frame = 1 # right
	elif angle < -PI * 0.25:
		_lod_impostor.frame = 3 # left
	else:
		_lod_impostor.frame = 0 # front


func _pause_lod_animation() -> void:
	if _anim == null or not _anim.is_playing():
		return
	if _mobile_visual_lod_enabled():
		_anim.pause()


func _resume_lod_animation() -> void:
	if not _mobile_visual_lod_enabled() or _anim == null \
			or _using_proxy or not _model.visible:
		return
	if _stride > 0.02 and _anim.get_animation_list().has("Walk") \
			and not _anim.is_playing():
		_anim.play("Walk")
		_anim.playback_speed = 1.0  # Near LOD: full speed (30 fps)


func _apply_animation_lod(dist: float) -> void:
	if not _mobile_visual_lod_enabled() or _anim == null or not _anim.is_playing():
		return
	# Near LOD (0–95 m): 30 fps
	# Mid LOD (95–260 m): 15 fps (playback speed 0.5)
	# Far LOD (>260 m): paused (speed 0.0)
	if dist < 95.0:
		_anim.playback_speed = 1.0
	elif dist < 260.0:
		_anim.playback_speed = 0.5
	else:
		_anim.playback_speed = 0.0


func _mobile_visual_lod_enabled() -> bool:
	return OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI")


func _physics_process(delta: float) -> void:
	if is_destroyed or _disabled:
		return
	# Visual LOD follows the camera independently of AI distance throttling or
	# the presence of a drone. Use every frame's delta for its 0.25 s timer.
	if _mobile_visual_lod_enabled():
		_update_lod(delta)
	if _drone == null or not is_instance_valid(_drone):
		_drone = get_tree().current_scene.get_node_or_null("Drone") as Drone
	if _drone == null:
		_burst_left = 0
		_tactical_knee = false
		_patrol_step(delta)
		return
	var dist_sq := global_position.distance_squared_to(_drone.global_position)
	if (_ai_low and dist_sq > 22500.0) or dist_sq > 28900.0:
		var step := 5 if dist_sq > 90000.0 else 3
		_ai_tick += 1
		if _ai_tick % step != 0:
			return

	_apply_recoil(delta)
	if _reload_timer > 0.0:
		_reload_timer = maxf(0.0, _reload_timer - delta)
	if _suppress_timer > 0.0:
		_suppress_timer = maxf(0.0, _suppress_timer - delta)
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.12
		_update_target()

	_crouching = (_panic_state == 2) or (_reload_timer > 0.0) or (_suppress_timer > 0.0) or _tactical_knee
	if not _using_proxy:
		_update_pose(delta)
	_update_panic()
	if _panic_state != 0:
		_panic_step(delta)
		return

	if not _can_engage():
		_burst_left = 0
		_tactical_knee = false
		_recover = maxf(_recover, 0.45)
		_patrol_step(delta)
		return

	if _reload_timer > 0.0:
		_set_locomotion(delta, 0.0)
		return
	var aligned := _aim_at_drone(delta)
	if not aligned:
		_set_locomotion(delta, 1.2)
		return

	if _burst_left > 0:
		_set_locomotion(delta, 0.0)
		_shot_cd -= delta
		if _shot_cd <= 0.0:
			_fire()
			_burst_left -= 1
			_mag_rounds -= 1
			_shot_cd = shot_interval
			if _mag_rounds <= 0:
				_burst_left = 0
				_mag_rounds = _mag_capacity
				_reload_timer = 1.75
				_recover = 1.9
				_tactical_knee = true
				if _detailed_rig != null:
					_detailed_rig.start_reload(1.75)
			elif _burst_left <= 0:
				_recover = randf_range(burst_pause_min, burst_pause_max)
				_strafe_timer = randf_range(0.65, 1.15)
				_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
				_tactical_knee = randf() < 0.38
				if _anim != null and _anim.get_animation_list().has("Walk"):
					_anim.play("Walk")
	else:
		if _strafe_timer > 0.0 and not _tactical_knee and not _demo_visual:
			_strafe_timer -= delta
			var side := global_transform.basis.x * _strafe_dir
			side.y = 0.0
			if side.length_squared() > 0.001:
				side = side.normalized()
				var step_d := 2.15 * delta
				if _can_step(side, step_d):
					global_position += side * step_d
				else:
					_strafe_dir = -_strafe_dir
			_snap_to_ground()
			_set_locomotion(delta, 2.15)
		else:
			_set_locomotion(delta, 0.0)
		_recover -= delta
		if _recover <= 0.0:
			_tactical_knee = false
			_burst_left = burst_shots
			_shot_cd = 0.0


## Assign a short back-and-forth patrol along `axis` (street direction).
func set_patrol(origin: Vector3, axis: Vector3, distance: float, speed: float) -> void:
	_patrol_active = true
	_patrol_origin = origin
	var flat := Vector3(axis.x, 0.0, axis.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	_patrol_axis = flat.normalized()
	_patrol_range = maxf(0.5, distance)
	_patrol_speed = speed
	_patrol_dir = 1.0


func _can_step(move_dir: Vector3, step_len: float) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 0.95
	var to := from + move_dir * (step_len + 0.55)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return false
	if _mobile_visual_lod_enabled():
		# A single chest ray can pass beside thin posts and rails. On mobile the
		# soldiers often fight around fences and hedgehogs, so also probe both
		# shoulder lines before committing to the step.
		var right := Vector3(move_dir.z, 0.0, -move_dir.x).normalized()
		for side: float in [-0.45, 0.45]:
			var origin := from + right * side
			var side_query := PhysicsRayQueryParameters3D.create(
					origin, origin + move_dir * (step_len + 0.55))
			side_query.collision_mask = 1
			side_query.exclude = [get_rid()]
			if not space.intersect_ray(side_query).is_empty():
				return false
	return true


## Idle riflemen that have no patrol advance on an armed drone in a jog, weaving
## around obstacles, and stop at ~32 m to take a firing position.  Legs animate
## through _set_locomotion like every other move.
func _advance_on_drone(delta: float) -> bool:
	if _drone == null or not is_instance_valid(_drone):
		return false
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return false
	var to_drone := _drone.global_position - global_position
	to_drone.y = 0.0
	var flat := to_drone.length()
	if flat > 170.0 or flat < 32.0:
		return false
	var dir := to_drone / maxf(flat, 0.001)
	var desired_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 5.0, 0.0, 1.0))
	if absf(angle_difference(rotation.y, desired_yaw)) > 0.5:
		_set_locomotion(delta, 1.0)
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var step := 3.4 * delta
	if _can_step(forward, step):
		global_position += forward * step
	else:
		# Sidestep around the obstacle instead of walking into the wall.
		var side := global_transform.basis.x * _strafe_dir
		side.y = 0.0
		side = side.normalized()
		if _can_step(side, step):
			global_position += side * step
		else:
			_strafe_dir = -_strafe_dir
	_snap_to_ground()
	_set_locomotion(delta, 3.4)
	return true


func _patrol_step(delta: float) -> void:
	if not _patrol_active or _demo_visual:
		_scan_phase += delta * 0.85
		if _detailed_rig != null:
			_detailed_rig.set_look_yaw(sin(_scan_phase) * 0.35)
		if not _demo_visual and _advance_on_drone(delta):
			return
		_set_locomotion(delta, 0.0)
		_snap_to_ground()
		return
	var along := (global_position - _patrol_origin).dot(_patrol_axis)
	if along >= _patrol_range:
		_patrol_dir = -1.0
	elif along <= -_patrol_range:
		_patrol_dir = 1.0
	var step_dir := _patrol_axis * _patrol_dir
	var desired_yaw := atan2(-step_dir.x, -step_dir.z)
	var yaw_diff := absf(angle_difference(rotation.y, desired_yaw))
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 6.5, 0.0, 1.0))
	if _detailed_rig != null:
		_detailed_rig.set_aim_pitch(0.0)
		_detailed_rig.set_look_yaw(0.0)
	elif _pitch != null:
		_pitch.rotation.x = lerp_angle(_pitch.rotation.x, 0.0, clampf(delta * 4.0, 0.0, 1.0))
	# Turn in place first at patrol endpoints; only advance along forward (-Z) once aligned.
	if yaw_diff > 0.28:
		_set_locomotion(delta, _patrol_speed * 0.45)
		_snap_to_ground()
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = step_dir
	var step_dist := _patrol_speed * delta
	if _can_step(forward, step_dist):
		global_position += forward * step_dist
	else:
		_patrol_dir = -_patrol_dir
	_snap_to_ground()
	_set_locomotion(delta, _patrol_speed)


## Scatter / go-to-ground reaction. Each soldier decides once per approach
## whether to panic; the rest keep shooting.
func _update_panic() -> void:
	if _panic_state != 0 or _disabled:
		return
	if _drone == null or not is_instance_valid(_drone):
		return
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		_panic_checked = false
		return
	# Use the live distance, not the cached value from the 0.12 s LOS timer:
	# the drone can be teleported by respawn while the cache is still stale.
	var dist := global_position.distance_to(_drone.global_position)
	# A drone parked on the ground does not spook the squad; it has to be up
	# and buzzing before soldiers dive for cover.
	if _drone.global_position.y < global_position.y + 6.0:
		_panic_checked = false
		return
	if dist > detect_range + 20.0:
		_panic_checked = false
		return
	if _panic_checked or dist > panic_range or not _los_clear:
		return
	_panic_checked = true
	if randf() >= panic_chance:
		return
	var away := global_position - _drone.global_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized().rotated(Vector3.UP, randf_range(-0.7, 0.7))
	_panic_dir = away
	_panic_state = 1
	_panic_timer = randf_range(1.1, 2.2)


func _panic_step(delta: float) -> void:
	if _panic_state == 1:
		_panic_timer -= delta
		var desired_yaw := atan2(-_panic_dir.x, -_panic_dir.z)
		var yaw_diff := absf(angle_difference(rotation.y, desired_yaw))
		rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 9.0, 0.0, 1.0))
		if _detailed_rig != null:
			_detailed_rig.set_aim_pitch(0.0)
		elif _pitch != null:
			_pitch.rotation.x = lerp_angle(_pitch.rotation.x, 0.0,
					clampf(delta * 4.0, 0.0, 1.0))
		if yaw_diff < 0.45:
			var forward := -global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				forward = forward.normalized()
			var step_dist := scatter_speed * delta
			if _can_step(forward, step_dist):
				global_position += forward * step_dist
			else:
				_panic_dir = _panic_dir.rotated(Vector3.UP, PI * 0.65)
		_snap_to_ground()
		_set_locomotion(delta, scatter_speed)
		if _panic_timer <= 0.0:
			_panic_state = 2
			_panic_timer = randf_range(3.0, 6.0)
		return
	# Prone: lie still until the drone moves on.
	_panic_timer -= delta
	_snap_to_ground()
	_set_locomotion(delta, 0.0)
	if _panic_timer <= 0.0:
		_panic_state = 0


func _snap_to_ground() -> void:
	if (Engine.get_physics_frames() + abs(get_instance_id())) % 3 != 0:
		return
	# Frontline maps have an analytic height field.  A downward ray from a
	# soldier standing next to a warehouse can hit its roof, which is why some
	# infantrymen were walking on top of buildings.
	var scene := get_tree().current_scene
	if scene != null and scene.get("frontline_map") != null:
		var map := String(scene.get("frontline_map"))
		if not map.is_empty():
			global_position.y = FrontlineTerrainScript.height_at(map,
					global_position.x, global_position.z)
			return
	var space := get_world_3d().direct_space_state
	var excl: Array[RID] = [get_rid()]
	if _drone is CollisionObject3D:
		excl.append((_drone as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("combat_target"):
		if node is CollisionObject3D:
			excl.append((node as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("vehicle"):
		if node is CollisionObject3D:
			excl.append((node as CollisionObject3D).get_rid())
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(global_position.x, global_position.y + 1.8, global_position.z),
			Vector3(global_position.x, global_position.y - 25.0, global_position.z))
	query.collision_mask = 1
	query.exclude = excl
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		global_position.y = (hit["position"] as Vector3).y


func _update_pose(delta: float) -> void:
	var target := 1.0 if _crouching else 0.0
	_prone_pose = move_toward(_prone_pose, target, delta * 3.5)
	if _detailed_rig != null:
		_detailed_rig.set_crouch(_crouching)
	elif _model != null:
		_model.rotation.x = -1.25 * _prone_pose


func _set_locomotion(delta: float, speed: float) -> void:
	var target_stride := clampf(speed / 2.2, 0.0, 1.35)
	_stride = lerpf(_stride, target_stride, clampf(delta * 6.0, 0.0, 1.0))
	if _mobile_visual_lod_enabled() and (_using_proxy \
			or (_distance > 125.0 and _model != null and not _model.visible)):
		return
	_walk_phase += delta * (2.0 + speed * 3.2)
	if _detailed_rig != null and not _using_proxy:
		_detailed_rig.set_walk(_walk_phase, _stride)
		return
	if _model == null or not is_instance_valid(_model):
		return
	if _stride <= 0.01:
		if _hip_l != null:
			_hip_l.rotation.x = 0.0
		if _hip_r != null:
			_hip_r.rotation.x = 0.0
		if _knee_l != null:
			_knee_l.rotation.x = 0.0
		if _knee_r != null:
			_knee_r.rotation.x = 0.0
		_model.position.y = 0.0
		return
	var swing := sin(_walk_phase)
	var amplitude := lerpf(0.0, 0.55, _stride)
	if _hip_l != null:
		_hip_l.rotation.x = swing * amplitude
	if _hip_r != null:
		_hip_r.rotation.x = -swing * amplitude
	# Lower leg bends backward (-rotation.x moves lower leg toward +Z) during swing recovery.
	if _knee_l != null:
		_knee_l.rotation.x = -maxf(0.0, -swing) * lerpf(0.0, 0.85, _stride)
	if _knee_r != null:
		_knee_r.rotation.x = -maxf(0.0, swing) * lerpf(0.0, 0.85, _stride)
	_model.position.y = absf(sin(_walk_phase)) * 0.045 * _stride * (1.0 - _prone_pose)


func _can_engage() -> bool:
	if _drone == null or not is_instance_valid(_drone):
		return false
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return false
	if _combat != null and _combat.has_method("can_take_damage"):
		if not bool(_combat.call("can_take_damage")):
			return false
	return _los_clear and _distance <= detect_range and _distance > 3.5


func _update_target() -> void:
	_los_clear = false
	if _drone == null:
		return
	_distance = global_position.distance_to(_drone.global_position)
	if _distance > detect_range:
		return
	var from := global_position + Vector3.UP * 2.15
	var target := _drone.global_position
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_los_clear = true
		return
	var collider = hit.get("collider")
	if collider == _drone:
		_los_clear = true
		return
	var point: Vector3 = hit.get("position", target)
	_los_clear = from.distance_to(point) >= from.distance_to(target) - 0.8


func _aim_at_drone(delta: float) -> bool:
	if _drone == null:
		return false
	var to := _drone.global_position - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length_squared() < 0.01:
		return false
	var desired_yaw := atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(delta * 7.5, 0.0, 1.0))
	var desired_pitch := clampf(atan2(to.y - 1.85, flat.length()), -0.18, 0.78)
	if _detailed_rig != null and not _using_proxy:
		_detailed_rig.set_aim_pitch(desired_pitch)
	elif _pitch != null:
		_pitch.rotation.x = lerp_angle(_pitch.rotation.x, desired_pitch,
				clampf(delta * 6.5, 0.0, 1.0))
	return absf(angle_difference(rotation.y, desired_yaw)) < 0.45


func _fire() -> void:
	if _muzzle == null:
		return
	if _detailed_rig != null:
		_detailed_rig.kick()
	if (not _mobile_visual_lod_enabled() or (not _using_proxy \
			and _model != null and _model.visible)) \
			and _anim != null and _anim.get_animation_list().has("Fire"):
		_anim.play("Fire")
	var muzzle_pos := _muzzle.global_position
	var target: Vector3 = muzzle_pos - global_transform.basis.z * 50.0
	if _drone != null and is_instance_valid(_drone):
		var lead := (_distance / tracer_speed) * 0.7
		target = _drone.global_position + _drone.linear_velocity * lead
	if _demo_miss:
		target += global_transform.basis.x.normalized() * 1.15
	var dir := (target - muzzle_pos).normalized()
	var spread := 0.012 + _distance * 0.00045
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * spread).normalized()
	var speed := tracer_speed
	var width := 1.15
	var color := Color(1.0, 0.72, 0.28)
	if _demo_visual:
		speed = 55.0
		width = 1.4
		color = Color(1.0, 0.88, 0.5)
	var tracer = TracerScript.new()
	tracer.tracer_color = color
	tracer.tracer_width = width
	get_parent().add_child(tracer)
	tracer.setup(muzzle_pos, dir, speed, tracer_damage, self)
	CombatSfxScript.play_rifle(get_parent(), muzzle_pos, -9.0)
	_muzzle_flash(muzzle_pos)
	_recoil = 0.065


func _apply_recoil(delta: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var target_z := _recoil
	_model.position.z = lerpf(_model.position.z, target_z, clampf(delta * 20.0, 0.0, 1.0))
	_recoil = move_toward(_recoil, 0.0, delta * 1.4)


func _muzzle_flash(position: Vector3) -> void:
	if DisplayServer.get_name() == "headless" or _muzzle == null:
		return
	var flash_scale := 1.25 if _demo_visual else 1.0
	var sphere := SphereMesh.new()
	sphere.radius = 0.07 * flash_scale
	sphere.height = 0.14 * flash_scale
	sphere.radial_segments = 8
	sphere.rings = 4
	var flash := MeshInstance3D.new()
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.72, 0.22, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.08)
	material.emission_energy_multiplier = 5.0
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = Vector3.ZERO
	_muzzle.add_child(flash)
	var life := 0.28 if _demo_visual else 0.07
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.3, life)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.4, 0.05, 0.0), life)
	tween.chain().tween_callback(flash.queue_free)


func take_damage(amount: float, hit_position: Vector3 = Vector3.ZERO) -> void:
	if is_destroyed:
		return
	health -= amount
	if hit_position != Vector3.ZERO and health > 0.0:
		ExplosionScript.spark_burst(get_parent(), hit_position)
	var now := Time.get_ticks_msec()
	if now - _last_hit_fx_ms > 110:
		_last_hit_fx_ms = now
		var fx_pos := hit_position if hit_position != Vector3.ZERO \
				else global_position + Vector3.UP * 1.15
		DestructionFxScript.hit(get_parent(), self, fx_pos, "infantry", 1.0)
	_suppress_timer = 2.6
	if _detailed_rig != null:
		_detailed_rig.hit_react(amount >= 20.0)
	_flash()
	_alert_group(global_position)
	if health <= 0.0:
		_destroy()


## Mobile-only squad reaction: nearby infantry notice a hit or a destroyed
## comrade. They briefly duck (suppression) and about a third of them break into
## a short scatter away from the impact. Deterministic distance gate keeps this
## cheap and local; the desktop combat behavior is untouched.
func _alert_group(source_pos: Vector3) -> void:
	if not _mobile_visual_lod_enabled() or is_destroyed:
		return
	for node in get_tree().get_nodes_in_group("enemy_infantry"):
		if node == self or not node is EnemyRifleman or not is_instance_valid(node):
			continue
		if (node as EnemyRifleman).global_position.distance_to(source_pos) < 42.0:
			(node as EnemyRifleman).call("_react_to_alert", source_pos)


func _react_to_alert(source_pos: Vector3) -> void:
	if is_destroyed or _disabled:
		return
	_suppress_timer = maxf(_suppress_timer, 2.0)
	if _panic_state == 0 and randf() < 0.35:
		var away := global_position - source_pos
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.FORWARD
		_panic_dir = away.normalized().rotated(Vector3.UP, randf_range(-0.5, 0.5))
		_panic_state = 1
		_panic_timer = randf_range(1.0, 2.0)


func _flash() -> void:
	if _meshes.is_empty():
		return
	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color(1.0, 0.72, 0.28, 0.65)
	_flash_token += 1
	var token := _flash_token
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = _flash_material
	await get_tree().create_timer(0.07).timeout
	if not is_instance_valid(self) or is_destroyed or token != _flash_token:
		return
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null


func _destroy() -> void:
	if is_destroyed:
		return
	is_destroyed = true
	remove_from_group("combat_target")
	collision_layer = 0
	collision_mask = 0
	_burst_left = 0
	_alert_group(global_position)
	if _label != null:
		_label.visible = false
	for mesh in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = null
	var parent := get_parent()
	if parent != null:
		ExplosionScript.spark_burst(parent, global_position + Vector3.UP * 1.1)
		ExplosionScript.smoke_column(parent, global_position + Vector3.UP * 0.3, 8.0)
		CombatSfxScript.play_soldier_death(parent,
				global_position + Vector3.UP * 1.0, -6.0)
	if _detailed_rig != null:
		if _using_proxy and _distance < 150.0 and _lod_proxy != null and _model != null:
			_using_proxy = false
			_lod_proxy.visible = false
			_model.visible = true
		_detailed_rig.play_death()
		if _lod_proxy != null:
			_lod_proxy.rotation.x = deg_to_rad(82.0)
			_lod_proxy.position.y = -0.12
	else:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "rotation:x", deg_to_rad(82.0), 0.42)
		tween.tween_property(self, "position:y", position.y - 0.12, 0.42)
	destroyed.emit(points)


## QA-only: force a burst (slightly off-target) for the screenshot preview.
func demo_warm_up() -> void:
	if is_destroyed or _disabled:
		return
	_demo_miss = true
	_demo_visual = true
	_recover = 0.0
	_burst_left = burst_shots
	_shot_cd = 0.0


func _qa_disabled() -> bool:
	if OS.has_environment("DRONE_INFANTRY_DEMO") or OS.has_environment("DRONE_AUTOTEST_INFANTRY") or OS.has_environment("DRONE_WALK_DEMO"):
		return false
	var qa := OS.has_environment("DRONE_AUTOTEST") or \
			OS.has_environment("DRONE_AUTOTEST_COMBAT") or \
			OS.has_environment("DRONE_SCREENSHOT") or \
			OS.has_environment("DRONE_SHOWCASE") or \
			OS.has_environment("DRONE_COMBAT_DEMO") or \
			OS.has_environment("DRONE_AA_DEMO") or \
			OS.has_environment("DRONE_RESULTS_DEMO") or \
			OS.has_environment("DRONE_CLEAR_RANGE")
	return qa
