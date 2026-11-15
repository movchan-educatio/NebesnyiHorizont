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
@export var variant: String = ""

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
var _ai_accum := 0.0
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
var _flank_timer := 0.0
var _flank_dir := 1.0
var _alert_forwarded := false
var _collision_node: CollisionShape3D = null
var _collision_box: BoxShape3D = null
var _convoy_target: Node3D = null


func _ready() -> void:
	health = max_health
	add_to_group("combat_target")
	add_to_group("enemy_infantry")
	collision_layer = 1
	collision_mask = 1
	_disabled = _qa_disabled()
	_ai_low = QualityManager.get_active_level() == QualityManager.Level.LOW
	_strafe_dir = -1.0 if (abs(get_instance_id()) % 2 == 0) else 1.0
	# Deterministic per-soldier gait offset so squads never march in lockstep.
	_walk_phase = fmod(float(abs(get_instance_id())) * 0.6180339, TAU)
	_build()
	_build_lod_proxy()
	var scene := _find_level_scene()
	_drone = scene.get_node_or_null("Drone") as Drone if scene != null else null
	_combat = scene.get_node_or_null("CombatSystem") if scene != null else null
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
	if rig.setup_rig(team_id, variant):
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
	_collision_box = shape
	_collision_node = collision


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
	_clamp_to_map_bounds()
	# Visual LOD follows the camera independently of AI distance throttling or
	# the presence of a drone. Use every frame's delta for its 0.25 s timer.
	if _mobile_visual_lod_enabled():
		_update_lod(delta)
	if _drone == null or not is_instance_valid(_drone):
		var lvl := _find_level_scene()
		if lvl != null:
			_drone = lvl.get_node_or_null("Drone") as Drone
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
			_ai_accum = minf(_ai_accum + delta, 0.25)
			return
	delta = minf(delta + _ai_accum, 0.25)
	_ai_accum = 0.0

	_apply_recoil(delta)
	if _reload_timer > 0.0:
		_reload_timer = maxf(0.0, _reload_timer - delta)
	if _suppress_timer > 0.0:
		_suppress_timer = maxf(0.0, _suppress_timer - delta)
	else:
		_alert_forwarded = false
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.12
		_update_target()

	_crouching = (_panic_state == 2) or (_reload_timer > 0.0) or (_suppress_timer > 0.0) or _tactical_knee
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
	var crouched := _is_crouched_or_settling()
	if not aligned:
		_set_locomotion(delta, 0.0 if crouched else 1.2)
		return

	if _burst_left > 0:
		_set_locomotion(delta, 0.0)
		if not crouched:
			# Flanking: while a burst is walked onto the drone, the shooter
			# sidesteps so squads spread out instead of bunching on one line.
			_flank_timer -= delta
			if _flank_timer <= 0.0:
				_flank_timer = randf_range(0.9, 1.8)
				_flank_dir = _strafe_dir if randf() < 0.6 else -_strafe_dir
			var side := global_transform.basis.x * _flank_dir
			side.y = 0.0
			var step := 1.4 * delta
			if _can_step(side, step):
				global_position += side * step
				_snap_to_ground()
				_set_locomotion(delta, 0.9)
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
		if _strafe_timer > 0.0 and not crouched and not _demo_visual:
			_strafe_timer -= delta
			var side := global_transform.basis.x * _strafe_dir
			side.y = 0.0
			var moved := false
			if side.length_squared() > 0.001:
				side = side.normalized()
				var step_d := 2.15 * delta
				if _can_step(side, step_d):
					global_position += side * step_d
					moved = true
				else:
					_strafe_dir = -_strafe_dir
			_snap_to_ground()
			_set_locomotion(delta, 2.15 if moved else 0.0)
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
	if absf(to.x) > INFANTRY_MAP_BOUND or absf(to.z) > INFANTRY_MAP_BOUND:
		return false
	var scene := _find_level_scene()
	if scene != null and scene.get("frontline_map") != null:
		var map := String(scene.get("frontline_map"))
		if not map.is_empty():
			var cur_h := FrontlineTerrainScript.height_at(map, global_position.x, global_position.z)
			var next_h := FrontlineTerrainScript.height_at(map, to.x, to.z)
			var on_bridge := false
			if map == "industrial":
				on_bridge = absf(to.x) < 16.5 and absf(to.z + 170.0) < 22.0
				var riv_z := -170.0 + 10.0 * sin(to.x * 0.015)
				if not on_bridge and absf(to.z - riv_z) < 14.5 and next_h < -1.9 and next_h <= cur_h:
					return false
			elif map == "village":
				var rx40 := -140.0 + 18.0 * sin(40.0 * 0.011)
				var rx140 := -140.0 + 18.0 * sin(140.0 * 0.011)
				on_bridge = (absf(to.z - 40.0) < 8.5 and absf(to.x - rx40) < 28.0) \
						or (absf(to.z - 140.0) < 7.0 and absf(to.x - rx140) < 24.0)
			var wl := FrontlineTerrainScript.water_level(map)
			if not on_bridge and wl > -100.0:
				if next_h < wl + 0.34 and next_h <= cur_h:
					return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		return false
	# Probe both shoulder lines so thin posts, walls, and fences do not trap soldiers.
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
		_set_locomotion(delta, 0.0)
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var step := 3.4 * delta
	var moved := false
	if _can_step(forward, step):
		global_position += forward * step
		moved = true
	else:
		# Sidestep around the obstacle instead of walking into the wall.
		var side := global_transform.basis.x * _strafe_dir
		side.y = 0.0
		side = side.normalized()
		if _can_step(side, step):
			global_position += side * step
			moved = true
		else:
			_strafe_dir = -_strafe_dir
	_snap_to_ground()
	_set_locomotion(delta, 3.4 if moved else 0.0)
	return true


func _patrol_step(delta: float) -> void:
	if _is_crouched_or_settling():
		_set_locomotion(delta, 0.0)
		_snap_to_ground()
		return
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
		_set_locomotion(delta, 0.0)
		_snap_to_ground()
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = step_dir
	var step_dist := _patrol_speed * delta
	var moved := false
	if _can_step(forward, step_dist):
		global_position += forward * step_dist
		moved = true
	else:
		_patrol_dir = -_patrol_dir
	_snap_to_ground()
	_set_locomotion(delta, _patrol_speed if moved else 0.0)


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
		if _is_crouched_or_settling():
			_snap_to_ground()
			_set_locomotion(delta, 0.0)
		else:
			var moved := false
			if yaw_diff < 0.45:
				var forward := -global_transform.basis.z
				forward.y = 0.0
				if forward.length_squared() > 0.0001:
					forward = forward.normalized()
				var step_dist := scatter_speed * delta
				if _can_step(forward, step_dist):
					global_position += forward * step_dist
					moved = true
				else:
					_panic_dir = _panic_dir.rotated(Vector3.UP, PI * 0.65)
			_snap_to_ground()
			_set_locomotion(delta, scatter_speed if moved else 0.0)
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


const INFANTRY_MAP_BOUND := 152.0


func _find_level_scene() -> Node:
	var cur := get_parent()
	while cur != null:
		if cur.get("frontline_map") != null or cur.get_node_or_null("Drone") != null:
			return cur
		cur = cur.get_parent()
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene
	return null


func _clamp_to_map_bounds() -> void:
	if absf(global_position.x) > INFANTRY_MAP_BOUND or absf(global_position.z) > INFANTRY_MAP_BOUND:
		global_position.x = clampf(global_position.x, -INFANTRY_MAP_BOUND, INFANTRY_MAP_BOUND)
		global_position.z = clampf(global_position.z, -INFANTRY_MAP_BOUND, INFANTRY_MAP_BOUND)
		_patrol_dir = -_patrol_dir
		_strafe_dir = -_strafe_dir
		_flank_dir = -_flank_dir
		_panic_dir = -_panic_dir


func _snap_to_ground() -> void:
	_clamp_to_map_bounds()
	# Frontline maps have an analytic height field.  A downward ray from a
	# soldier standing next to a warehouse can hit its roof, which is why some
	# infantrymen were walking on top of buildings.
	var scene := _find_level_scene()
	if scene != null and scene.get("frontline_map") != null:
		var map := String(scene.get("frontline_map"))
		if not map.is_empty():
			global_position.y = FrontlineTerrainScript.height_at(map,
					global_position.x, global_position.z)
			return
	if (Engine.get_physics_frames() + abs(get_instance_id())) % 3 != 0:
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


func _is_crouched_or_settling() -> bool:
	if _crouching or _prone_pose > 0.08:
		return true
	return _detailed_rig != null and _detailed_rig.is_crouching_blend() > 0.08


func _update_pose(delta: float) -> void:
	var target := 1.0 if _crouching else 0.0
	_prone_pose = move_toward(_prone_pose, target, delta * 3.5)
	if _collision_box != null and _collision_node != null:
		_collision_box.size.y = lerpf(2.75, 1.55, _prone_pose)
		_collision_node.position.y = lerpf(1.68, 0.92, _prone_pose)
	if _using_proxy:
		return
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
	if _stride > 0.01 or target_stride > 0.01:
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
	if _combat != null and _combat.has_method("can_take_damage"):
		if not bool(_combat.call("can_take_damage")):
			return false
	if _convoy_target != null and is_instance_valid(_convoy_target) \
			and not bool(_convoy_target.get("is_destroyed")):
		return _los_clear and _distance <= detect_range and _distance > 3.5
	if _drone == null or not is_instance_valid(_drone):
		return false
	var controller := _drone.get_node_or_null("FlightController") as FlightController
	if controller == null or not controller.state_armed:
		return false
	return _los_clear and _distance <= detect_range and _distance > 3.5


func _has_clear_los(from: Vector3, target: Vector3, target_node: Node) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, target)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	if hit.get("collider") == target_node:
		return true
	var point: Vector3 = hit.get("position", target)
	return from.distance_to(point) >= from.distance_to(target) - 0.8


func _update_target() -> void:
	_los_clear = false
	_convoy_target = null
	var eye_h := lerpf(2.15, 1.15, _prone_pose)
	var from := global_position + Vector3.UP * eye_h
	if _drone != null and is_instance_valid(_drone):
		_distance = global_position.distance_to(_drone.global_position)
		if _distance <= detect_range and _has_clear_los(from, _drone.global_position, _drone):
			var fc := _drone.get_node_or_null("FlightController") as FlightController
			if fc != null and fc.state_armed:
				_los_clear = true
				return
	else:
		_distance = 1e9
	if get_tree() != null:
		for node in get_tree().get_nodes_in_group("escort_convoy"):
			var convoy := node as Node3D
			if convoy == null or not is_instance_valid(convoy) \
					or bool(convoy.get("is_destroyed")):
				continue
			var d := global_position.distance_to(convoy.global_position)
			if d <= detect_range and _has_clear_los(from, convoy.global_position + Vector3.UP * 1.1, convoy):
				_convoy_target = convoy
				_distance = d
				_los_clear = true
				return


func _aim_at_drone(delta: float) -> bool:
	var tgt := _convoy_target if (_convoy_target != null and is_instance_valid(_convoy_target)) else _drone
	if tgt == null or not is_instance_valid(tgt):
		return false
	var target_pos := tgt.global_position + (Vector3.UP * 1.1 if tgt == _convoy_target else Vector3.ZERO)
	var to := target_pos - global_position
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
	var shooting_convoy := _convoy_target != null and is_instance_valid(_convoy_target) \
			and not bool(_convoy_target.get("is_destroyed"))
	if shooting_convoy:
		target = _convoy_target.global_position + Vector3.UP * 1.1
	elif _drone != null and is_instance_valid(_drone):
		var lead := (_distance / tracer_speed) * 0.7
		target = _drone.global_position + _drone.linear_velocity * lead
	if _demo_miss:
		target += global_transform.basis.x.normalized() * 1.15
	var dir := (target - muzzle_pos).normalized()
	var spread := 0.012 + _distance * 0.00045
	dir = (dir + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)) * spread).normalized()
	var speed := tracer_speed
	var width := 1.65
	var color := Color(1.0, 0.58, 0.16)
	if _demo_visual:
		speed = 55.0
		width = 1.85
		color = Color(1.0, 0.88, 0.45)
	var tracer = TracerScript.new()
	tracer.tracer_color = color
	tracer.tracer_width = width
	tracer.add_to_group("aa_tracer")
	get_parent().add_child(tracer)
	tracer.setup(muzzle_pos, dir, speed, 0.0 if shooting_convoy else tracer_damage, self)
	if shooting_convoy:
		var q := PhysicsRayQueryParameters3D.create(muzzle_pos, target)
		q.collision_mask = 1
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.get("collider") == _convoy_target \
				and _convoy_target.has_method("take_damage"):
			_convoy_target.call("take_damage", tracer_damage * 0.40, hit.get("position"))
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
	var flash_scale := 1.35 if _demo_visual else 1.15
	var sphere := SphereMesh.new()
	sphere.radius = 0.13 * flash_scale
	sphere.height = 0.26 * flash_scale
	sphere.radial_segments = 8
	sphere.rings = 4
	var flash := MeshInstance3D.new()
	flash.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 0.78, 0.26, 0.96)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.55, 0.10)
	material.emission_energy_multiplier = 7.5
	flash.material_override = material
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = Vector3.ZERO
	_muzzle.add_child(flash)
	# Hot white inner star so gunfire pops against grass/sky from FPV altitude.
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.06 * flash_scale
	core_mesh.height = 0.12 * flash_scale
	core_mesh.radial_segments = 6
	core_mesh.rings = 3
	var core := MeshInstance3D.new()
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.96, 0.75)
	core.material_override = core_mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(core)
	var life := 0.28 if _demo_visual else 0.10
	var tween := flash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * 2.6, life)
	tween.tween_property(material, "albedo_color", Color(1.0, 0.42, 0.05, 0.0), life)
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


## Squad reaction: nearby infantry notice a hit, blast, or destroyed comrade.
## They duck briefly (suppression) and about a third scatter away from impact.
func _alert_group(source_pos: Vector3) -> void:
	if is_destroyed:
		return
	for node in get_tree().get_nodes_in_group("enemy_infantry"):
		if node == self or not node is EnemyRifleman or not is_instance_valid(node):
			continue
		if (node as EnemyRifleman).global_position.distance_to(source_pos) < 42.0:
			(node as EnemyRifleman).call("_react_to_alert", source_pos)


func notify_blast(source_pos: Vector3, blast_radius: float) -> void:
	if is_destroyed or _disabled:
		return
	if global_position.distance_to(source_pos) <= blast_radius:
		_react_to_alert(source_pos)


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
	# One-hop squad suppression: a soldier who ducks can pass the alarm to a
	# nearby mate, so a hit ripples through a tight squad without cascading
	# across the whole map.
	if not _alert_forwarded and randf() < 0.45:
		_alert_forwarded = true
		_alert_group(source_pos)


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
	remove_from_group("primary_combat_target")
	remove_from_group("bonus_combat_target")
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
