## Detailed, skinned infantry model for EnemyRifleman / ChaosSoldier.
##
## Uses the high-resolution authored soldier (helmet, plate carrier, pouches,
## boots, M4) instead of the old 58-box figurine.  The GLB ships in a Sketchfab
## bind pose: we stand it upright, scale it to human height and drive the leg
## bones for a walk cycle.  The authored rifle is detached into a static prop so
## it can be aimed straight ahead; the old mesh is hidden.
class_name DetailedSoldierRig
extends Node3D

const MODEL_PATH := "res://Assets/combat/soldier_detailed_merged.glb"
const HEIGHT := 1.88
const EnemyMarkingsScript = preload("res://combat/enemy_markings.gd")

var model: Node3D = null
var skeleton: Skeleton3D = null
var muzzle: Marker3D = null
var rifle_pivot: Node3D = null

var _b_pelvis := -1
var _b_thigh_l := -1
var _b_thigh_r := -1
var _b_calf_l := -1
var _b_calf_r := -1
var _b_foot_l := -1
var _b_foot_r := -1
var _b_spine := -1
var _b_spine1 := -1
var _b_spine2 := -1
var _b_spine3 := -1
var _b_neck := -1
var _b_head := -1
var _b_support := -1
var _b_forearm_l := -1
var _b_arm_r := -1
var _b_forearm_r := -1
var _rest := {}
var _aim_pitch := 0.0
var _aim_smooth := 0.0
var _look_yaw := 0.0
var _look_yaw_smooth := 0.0
var _kick := 0.0
var _walk_phase := 0.0
var _walk_stride := 0.0
var _breath_phase := 0.0
var _crouch_target := 0.0
var _crouch := 0.0
var _reload_time := 0.0
var _reload_duration := 1.8
var _hit_flinch := 0.0
var _hit_dir := 1.0
var _dead := false
var _death_variant := 0
var _death_progress := 0.0
var _base_model_pos := Vector3.ZERO
var _base_model_rot := Vector3.ZERO
var _rifle_rest := Vector3.ZERO
var _rifle_basis := Basis()
var _ready_ok := false

# Measured principal axes of the authored M4 mesh (Object_57).  The mesh is
# authored diagonally in its own XY plane; these let us map the barrel to the
# node's -Z without guessing Euler angles.
const RIFLE_LONG := Vector3(0.832048, 0.511743, 0.214046)
const RIFLE_UP := Vector3(-0.495606, 0.859139, -0.127496)
const RIFLE_MUZZLE_OFFSET := 0.4867


func setup_rig(team_id: int = -1) -> bool:
	if _ready_ok:
		return true
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_warning("[DetailSoldier] missing " + MODEL_PATH)
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Soldier"
	# The authored file is authored lying on its back after the glTF axis
	# conversion.  Stand it up and turn it so its face follows the node's -Z
	# (the direction EnemyRifleman calls "forward").
	model.rotation_degrees = Vector3(90.0, 180.0, 0.0)
	add_child(model)

	var box := _bounds(model, self)
	if box.size.y < 0.001:
		return false
	model.scale = Vector3.ONE * (HEIGHT / box.size.y)
	box = _bounds(model, self)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	model.position.y += 0.01
	_base_model_pos = model.position
	_base_model_rot = model.rotation
	_breath_phase = randf() * TAU

	skeleton = _find_skeleton(model)
	if skeleton == null:
		return false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.extra_cull_margin = 300.0
	_cache_bones()
	_apply_base_pose()
	_build_rifle_prop()
	if team_id == 0:
		_build_team_patch(team_id)
	elif QualityManager.get_active_level() != QualityManager.Level.LOW:
		# The shoulder marking is a separate one-draw mesh per soldier.  On the
		# 60 FPS profiles the squad is seen from 20+ m, so skip it and keep the
		# draw budget for the body mesh.
		EnemyMarkingsScript.mark_infantry(self)
	scale = Vector3.ONE * 1.8
	_ready_ok = true
	return true


func _cache_bones() -> void:
	_b_pelvis = _bone("Bip01 Pelvis")
	_b_thigh_l = _bone("Bip01 L Thigh")
	_b_thigh_r = _bone("Bip01 R Thigh")
	_b_calf_l = _bone("Bip01 L Calf")
	_b_calf_r = _bone("Bip01 R Calf")
	_b_foot_l = _bone("Bip01 L Foot")
	_b_foot_r = _bone("Bip01 R Foot")
	_b_spine = _bone("Bip01 Spine")
	_b_spine1 = _bone("Bip01 Spine1")
	_b_spine2 = _bone("Bip01 Spine2")
	_b_spine3 = _bone("Bip01 Spine3")
	_b_neck = _bone("Bip01 Neck")
	_b_head = _bone("Bip01 Head")
	_b_support = _bone("Bip01 L UpperArm")
	_b_forearm_l = _bone("Bip01 L Forearm")
	_b_arm_r = _bone("Bip01 R UpperArm")
	_b_forearm_r = _bone("Bip01 R Forearm")
	for idx in [_b_pelvis, _b_thigh_l, _b_thigh_r, _b_calf_l, _b_calf_r,
			_b_foot_l, _b_foot_r, _b_spine, _b_spine1, _b_spine2, _b_spine3,
			_b_neck, _b_head, _b_support, _b_forearm_l, _b_arm_r, _b_forearm_r]:
		if idx >= 0:
			_rest[idx] = skeleton.get_bone_pose_rotation(idx)


func _apply_base_pose() -> void:
	# The bind pose leaves the support arm straight out (a T-pose).  Fold it
	# across the chest so both hands read as holding the rifle.
	if _b_support >= 0:
		skeleton.set_bone_pose_rotation(_b_support,
				Quaternion(Vector3.UP, deg_to_rad(90.0)))


func _build_rifle_prop() -> void:
	var rifle_mi := _find_rifle_mesh(model)
	if rifle_mi != null:
		var rbox: AABB = rifle_mi.get_aabb()
		var centre := rbox.get_center()
		rifle_mi.visible = false

		var copy := MeshInstance3D.new()
		copy.name = "RifleProp"
		copy.mesh = rifle_mi.mesh
		copy.position = -centre
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		rifle_pivot = Node3D.new()
		rifle_pivot.name = "RiflePivot"
		rifle_pivot.position = Vector3(-0.02, 1.33, -0.45)
		_rifle_basis = _make_rifle_basis()
		rifle_pivot.basis = _rifle_basis
		add_child(rifle_pivot)
		rifle_pivot.add_child(copy)
		_rifle_rest = rifle_pivot.position

		muzzle = Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = RIFLE_LONG.normalized() * RIFLE_MUZZLE_OFFSET
		copy.add_child(muzzle)
	else:
		muzzle = Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(-0.26, 1.10, -0.45)
		add_child(muzzle)


func _build_team_patch(team_id: int) -> void:
	var color := Color(0.95, 0.56, 0.12)
	if team_id == 0:
		color = Color(0.25, 0.55, 1.0)
	elif team_id == 1:
		color = Color(1.0, 0.28, 0.20)
	var patch := MeshInstance3D.new()
	patch.name = "TeamPatch"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.075, 0.040, 0.008)
	patch.mesh = mesh
	patch.position = Vector3(0.02, 1.34, -0.088)
	patch.rotation_degrees = Vector3(-6.0, 180.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	patch.material_override = mat
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)


func set_walk(phase: float, stride: float) -> void:
	_walk_phase = phase
	_walk_stride = clampf(stride, 0.0, 1.5)
	_update_pose(0.0)


func set_crouch(crouching: bool) -> void:
	_crouch_target = 1.0 if crouching else 0.0


func set_aim_pitch(pitch: float) -> void:
	_aim_pitch = clampf(pitch, -0.5, 0.9)


func set_look_yaw(yaw: float) -> void:
	_look_yaw = clampf(yaw, -0.65, 0.65)


func kick() -> void:
	_kick = 1.0


func start_reload(duration: float = 1.8) -> void:
	if _dead:
		return
	_reload_duration = maxf(duration, 0.4)
	_reload_time = _reload_duration


func is_reloading() -> bool:
	return _reload_time > 0.0


func hit_react(heavy: bool = false) -> void:
	if _dead:
		return
	_hit_flinch = 1.0 if heavy else 0.65
	_hit_dir = -1.0 if randf() < 0.5 else 1.0


func play_death(variant: int = -1) -> void:
	if _dead:
		return
	_dead = true
	_death_variant = variant if variant >= 0 else (abs(get_instance_id()) % 3)
	_death_progress = 0.0
	_reload_time = 0.0


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	_breath_phase += delta * (2.2 + _walk_stride * 2.4)
	_aim_smooth = lerpf(_aim_smooth, _aim_pitch, 1.0 - exp(-delta / 0.09))
	_look_yaw_smooth = lerpf(_look_yaw_smooth, _look_yaw, 1.0 - exp(-delta / 0.12))
	_crouch = move_toward(_crouch, _crouch_target, delta * 3.8)
	_kick = move_toward(_kick, 0.0, delta * 5.0)
	_hit_flinch = move_toward(_hit_flinch, 0.0, delta * 4.2)
	if _reload_time > 0.0:
		_reload_time = maxf(0.0, _reload_time - delta)
	if _dead:
		_death_progress = move_toward(_death_progress, 1.0, delta * 2.1)
	_update_pose(delta)


func _update_pose(_delta: float) -> void:
	if skeleton == null:
		return
	if _dead:
		_apply_death_pose()
		return
	var swing := sin(_walk_phase)
	var amp := 0.55 * _walk_stride * (1.0 - _crouch * 0.28)
	var crouch_hip := 0.58 * _crouch
	var crouch_knee := 0.95 * _crouch
	if _b_thigh_l >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_l,
				Quaternion(Vector3.FORWARD, swing * amp + crouch_hip) * _rest[_b_thigh_l])
	if _b_thigh_r >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_r,
				Quaternion(Vector3.FORWARD, -swing * amp + crouch_hip) * _rest[_b_thigh_r])
	if _b_calf_l >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_l,
				Quaternion(Vector3.BACK,
				maxf(0.0, -swing) * 0.85 * _walk_stride + crouch_knee) * _rest[_b_calf_l])
	if _b_calf_r >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_r,
				Quaternion(Vector3.BACK,
				maxf(0.0, swing) * 0.85 * _walk_stride + crouch_knee) * _rest[_b_calf_r])
	if _b_foot_l >= 0:
		skeleton.set_bone_pose_rotation(_b_foot_l,
				Quaternion(Vector3.BACK, -swing * 0.22 * _walk_stride + 0.32 * _crouch) * _rest[_b_foot_l])
	if _b_foot_r >= 0:
		skeleton.set_bone_pose_rotation(_b_foot_r,
				Quaternion(Vector3.BACK, swing * 0.22 * _walk_stride + 0.32 * _crouch) * _rest[_b_foot_r])

	var breath := sin(_breath_phase) * 0.025
	var flinch_pitch := _hit_flinch * 0.28
	var flinch_yaw := _hit_flinch * 0.22 * _hit_dir
	# Lean the upper body and head toward the target.  Positive aim_pitch is
	# above the horizon, so pitch the chest back a little and the head more.
	var lean := -_aim_smooth * 0.22 + 0.24 * _crouch + breath + flinch_pitch + 0.06 * _kick
	var head_pitch := -_aim_smooth * 0.38 - 0.14 * _crouch - breath * 0.5 - flinch_pitch * 0.6
	if _b_spine2 >= 0:
		skeleton.set_bone_pose_rotation(_b_spine2,
				Quaternion(Vector3.BACK, lean * 0.45) * Quaternion(Vector3.UP, flinch_yaw * 0.5) * _rest[_b_spine2])
	if _b_spine3 >= 0:
		skeleton.set_bone_pose_rotation(_b_spine3,
				Quaternion(Vector3.BACK, lean * 0.65) * Quaternion(Vector3.UP, flinch_yaw * 0.5) * _rest[_b_spine3])
	if _b_neck >= 0:
		skeleton.set_bone_pose_rotation(_b_neck,
				Quaternion(Vector3.BACK, head_pitch * 0.5) * Quaternion(Vector3.UP, _look_yaw_smooth * 0.45) * _rest[_b_neck])
	if _b_head >= 0:
		skeleton.set_bone_pose_rotation(_b_head,
				Quaternion(Vector3.BACK, head_pitch * 0.5) * Quaternion(Vector3.UP, _look_yaw_smooth * 0.55) * _rest[_b_head])

	var reload_blend := 0.0
	if _reload_time > 0.0 and _reload_duration > 0.0:
		var prog := 1.0 - (_reload_time / _reload_duration)
		reload_blend = sin(prog * PI)

	if _b_support >= 0:
		var sup_yaw := deg_to_rad(90.0 - 38.0 * reload_blend)
		var sup_pitch := -0.45 * reload_blend
		skeleton.set_bone_pose_rotation(_b_support,
				Quaternion(Vector3.UP, sup_yaw) * Quaternion(Vector3.RIGHT, sup_pitch))

	if model != null:
		var bob := absf(sin(_walk_phase)) * 0.038 * _walk_stride * (1.0 - _crouch * 0.45)
		model.position = _base_model_pos + Vector3(0.0, -0.34 * _crouch + bob, 0.0)
		model.rotation = _base_model_rot

	if rifle_pivot != null:
		rifle_pivot.position = _rifle_rest + Vector3(
				0.04 * reload_blend,
				-0.012 * _kick - 0.28 * _crouch - 0.06 * reload_blend + breath * 0.35,
				0.055 * _kick + 0.04 * reload_blend)
		var aim_tilt := -_aim_smooth * 0.55 + 0.035 * _kick + 0.42 * reload_blend
		var roll_tilt := 0.48 * reload_blend
		rifle_pivot.basis = Basis(Vector3.RIGHT, aim_tilt) * Basis(Vector3.FORWARD, roll_tilt) * _rifle_basis


func _apply_death_pose() -> void:
	var k := 1.0 - pow(1.0 - _death_progress, 2.4)
	# Articulated multi-bone collapse onto the ground (never a rigid T-pose plank)
	var knee_buckle := 1.15 * k
	var hip_fold := 0.72 * k if _death_variant != 1 else 0.38 * k
	if _b_thigh_l >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_l,
				Quaternion(Vector3.FORWARD, hip_fold) * _rest[_b_thigh_l])
	if _b_thigh_r >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_r,
				Quaternion(Vector3.FORWARD, hip_fold * 0.82) * _rest[_b_thigh_r])
	if _b_calf_l >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_l,
				Quaternion(Vector3.BACK, knee_buckle) * _rest[_b_calf_l])
	if _b_calf_r >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_r,
				Quaternion(Vector3.BACK, knee_buckle * 0.88) * _rest[_b_calf_r])
	if _b_spine2 >= 0:
		var sp_pitch := (0.42 if _death_variant == 0 else -0.28) * k
		skeleton.set_bone_pose_rotation(_b_spine2,
				Quaternion(Vector3.BACK, sp_pitch) * _rest[_b_spine2])
	if _b_spine3 >= 0:
		var sp3_pitch := (0.48 if _death_variant == 0 else -0.32) * k
		skeleton.set_bone_pose_rotation(_b_spine3,
				Quaternion(Vector3.BACK, sp3_pitch) * _rest[_b_spine3])
	if _b_head >= 0:
		skeleton.set_bone_pose_rotation(_b_head,
				Quaternion(Vector3.BACK, 0.45 * k) * Quaternion(Vector3.UP, 0.35 * k) * _rest[_b_head])
	if _b_support >= 0:
		skeleton.set_bone_pose_rotation(_b_support,
				Quaternion(Vector3.UP, deg_to_rad(90.0 - 52.0 * k)))
	if model != null:
		var drop_y := -0.78 * k
		model.position = _base_model_pos + Vector3(0.0, drop_y, 0.0)
		var pitch_fall := deg_to_rad(74.0) if _death_variant == 0 else (deg_to_rad(-68.0) if _death_variant == 1 else deg_to_rad(52.0))
		var roll_fall := deg_to_rad(64.0) if _death_variant == 2 else deg_to_rad(14.0)
		model.rotation = _base_model_rot + Vector3(pitch_fall * k, 0.0, roll_fall * k)
	if rifle_pivot != null:
		rifle_pivot.position = _rifle_rest.lerp(Vector3(0.24, 0.08, -0.32), k)
		rifle_pivot.basis = Basis(Vector3.FORWARD, deg_to_rad(82.0 * k)) * Basis(Vector3.RIGHT, deg_to_rad(24.0 * k)) * _rifle_basis


func _make_rifle_basis() -> Basis:
	var long := RIFLE_LONG.normalized()
	var up := (RIFLE_UP - long * RIFLE_UP.dot(long)).normalized()
	var side := long.cross(up).normalized()
	var source := Basis()
	source.x = long
	source.y = up
	source.z = side
	var desired := Basis()
	desired.x = Vector3(0.0, 0.0, -1.0)
	desired.y = Vector3(0.0, 1.0, 0.0)
	desired.z = Vector3(1.0, 0.0, 0.0)
	return desired * source.transposed()


func _bone(substr: String) -> int:
	if skeleton == null:
		return -1
	for i in range(skeleton.get_bone_count()):
		var bname := skeleton.get_bone_name(i)
		if bname == substr or bname.ends_with(substr):
			return i
	for i in range(skeleton.get_bone_count()):
		if skeleton.get_bone_name(i).contains(substr):
			return i
	return -1


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


func _find_rifle_mesh(node: Node) -> MeshInstance3D:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var mat := mi.mesh.surface_get_material(s)
			if mat != null and String(mat.resource_name).contains("w_val"):
				return mi
	return null


func _bounds(node: Node3D, relative_to: Node3D = null) -> AABB:
	var root := relative_to if relative_to != null else node
	var box := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var xf: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
