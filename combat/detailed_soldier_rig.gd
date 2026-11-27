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
const SPETSNAZ_MODEL_PATH := "res://Assets/combat/spetsnaz_soldier.glb"
const HEIGHT := 2.26
const EnemyMarkingsScript = preload("res://combat/enemy_markings.gd")
const WEAPON_BONE_NAME := "Line01_028"

static var _stripped_mesh_cache: Dictionary = {}

var variant: String = ""
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
var _rig_axes := {}
var _aim_pitch := 0.0
var _aim_smooth := 0.0
var _look_yaw := 0.0
var _look_yaw_smooth := 0.0
var _kick := 0.0
var _walk_phase := 0.0
var _walk_stride := 0.0
var _run_blend := 0.0
var _breath_phase := 0.0
var _sway_phase := 0.0
var _crouch_target := 0.0
var _crouch_t := 0.0
var _crouch := 0.0
var _rest_foot_y := 0.0
var _rest_spine3_y := 0.0
var _reload_time := 0.0
var _reload_duration := 1.8
var _hit_flinch := 0.0
var _hit_dir := 1.0
var _dead := false
var _death_variant := 0
var _death_progress := 0.0
var _mobile_animation_hz := -1.0
var _mobile_animation_accumulator := 0.0
var clip_player: AnimationPlayer = null
var _base_model_pos := Vector3.ZERO
var _base_model_rot := Vector3.ZERO
var _rifle_rest := Vector3.ZERO
var _rifle_basis := Basis()
var _ready_ok := false

## An owner may mirror its destroyed state here. `_dead` drives the collapse
## animation; once that has settled (or `dead` is set) the corpse is static and
## `_process` no longer needs to touch the skeleton at all.
var dead: bool = false

## Measuring foot/chest height forces a full bone-transform pass every time, so
## idle soldiers reuse the last measurement. The live `_crouch` value is always
## checked, including when a caller writes the blend directly and invokes
## `_update_pose()` without going through `set_crouch()` / `_process()`.
var _last_crouch := -1.0
var _last_foot_crouch := -1.0
var _last_foot_walk_phase := -1.0
var _last_foot_walk_stride := -1.0
var _last_foot_aim := 0.0
var _last_foot_flinch := 0.0
var _foot_cache_valid := false
var _cached_foot_correction := 0.0
var _cached_chest_dy := 0.0

# Measured principal axes of the authored M4 mesh (Object_57).  The mesh is
# authored diagonally in its own XY plane; these let us map the barrel to the
# node's -Z without guessing Euler angles.
const RIFLE_LONG := Vector3(0.832048, 0.511743, 0.214046)
const RIFLE_UP := Vector3(-0.495606, 0.859139, -0.127496)
const RIFLE_MUZZLE_OFFSET := 0.4867


func setup_rig(team_id: int = -1, model_variant: String = "") -> bool:
	if _ready_ok:
		return true
	variant = model_variant
	var use_spetsnaz := (variant == "spetsnaz" and ResourceLoader.exists(SPETSNAZ_MODEL_PATH))
	var path := SPETSNAZ_MODEL_PATH if use_spetsnaz else MODEL_PATH
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[DetailSoldier] missing " + path)
		return false
	model = packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Soldier"
	if use_spetsnaz:
		# spetsnaz_soldier.glb is baked upright facing -Z at 1.88 m in Blender.
		model.rotation_degrees = Vector3.ZERO
	else:
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
		# A huge margin kept skinned meshes alive offscreen; the rig re-anchors
		# its feet in local space, so the normal small margin is safe.
		mi.extra_cull_margin = 2.5
	_cache_bones()
	_apply_base_pose()
	_build_rifle_prop()
	_capture_rest_heights()
	if team_id == 0:
		_build_team_patch(team_id)
	elif variant != "spetsnaz" and QualityManager.get_active_level() != QualityManager.Level.LOW:
		# The shoulder marking is a separate one-draw mesh per soldier.  On the
		# 60 FPS profiles the squad is seen from 20+ m, so skip it and keep the
		# draw budget for the body mesh.  Spetsnaz carries authored shoulder patches.
		EnemyMarkingsScript.mark_infantry(self)
	scale = Vector3.ONE * 1.8
	_ready_ok = true
	if OS.get_name() == "iOS" or OS.has_feature("mobile") \
			or OS.has_environment("MOBILE_UI"):
		_ensure_clip_preview()
	return true


func _cache_bones() -> void:
	if variant == "spetsnaz":
		_b_pelvis = _bone("Bip01_Pelvis")
		_b_thigh_l = _bone("Bip01_L_Thigh")
		_b_thigh_r = _bone("Bip01_R_Thigh")
		_b_calf_l = _bone("Bip01_L_Calf")
		_b_calf_r = _bone("Bip01_R_Calf")
		_b_foot_l = _bone("Bip01_L_Foot")
		_b_foot_r = _bone("Bip01_R_Foot")
		_b_spine = _bone("Bip01_Spine_")
		_b_spine1 = _bone("Bip01_Spine1")
		_b_spine2 = _bone("Bip01_Spine2")
		_b_spine3 = _bone("Bip01_Spine4")
		_b_neck = _bone("Bip01_Neck1")
		_b_head = _bone("Bip01_Head1")
		_b_support = _bone("Bip01_L_UpperArm")
		_b_forearm_l = _bone("Bip01_L_Forearm")
		_b_arm_r = _bone("Bip01_R_UpperArm")
		_b_forearm_r = _bone("Bip01_R_Forearm")
	else:
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
	_rig_axes.clear()
	var skel_to_rig := (global_transform.affine_inverse() * skeleton.global_transform).basis
	for idx in [_b_pelvis, _b_thigh_l, _b_thigh_r, _b_calf_l, _b_calf_r,
			_b_foot_l, _b_foot_r, _b_spine, _b_spine1, _b_spine2, _b_spine3,
			_b_neck, _b_head, _b_support, _b_forearm_l, _b_arm_r, _b_forearm_r]:
		if idx >= 0:
			_rest[idx] = skeleton.get_bone_pose_rotation(idx)
			var p_idx := skeleton.get_bone_parent(idx)
			var p_basis := skel_to_rig * (skeleton.get_bone_global_rest(p_idx).basis if p_idx >= 0 else Basis.IDENTITY)
			var inv_p := p_basis.inverse()
			_rig_axes[idx] = {
				"x": (inv_p * Vector3.RIGHT).normalized(),
				"y": (inv_p * Vector3.UP).normalized(),
				"z": (inv_p * Vector3.BACK).normalized(),
			}


func _rot_rig(idx: int, axis_key: String, angle: float) -> Quaternion:
	if not _rig_axes.has(idx):
		return Quaternion.IDENTITY
	var ax: Vector3 = _rig_axes[idx].get(axis_key, Vector3.RIGHT)
	return Quaternion(ax, angle)


func _set_spetsnaz_arms(reload_blend: float = 0.0, aim_pitch: float = 0.0) -> void:
	if _b_arm_r >= 0:
		skeleton.set_bone_pose_rotation(_b_arm_r,
				_rot_rig(_b_arm_r, "x", deg_to_rad(8.0) + aim_pitch * 0.35)
				* _rot_rig(_b_arm_r, "y", deg_to_rad(12.0))
				* _rot_rig(_b_arm_r, "z", deg_to_rad(-22.0))
				* _rest[_b_arm_r])
	if _b_forearm_r >= 0:
		skeleton.set_bone_pose_rotation(_b_forearm_r,
				_rot_rig(_b_forearm_r, "x", deg_to_rad(42.0))
				* _rot_rig(_b_forearm_r, "y", deg_to_rad(14.0))
				* _rest[_b_forearm_r])
	if _b_support >= 0:
		skeleton.set_bone_pose_rotation(_b_support,
				_rot_rig(_b_support, "x", deg_to_rad(38.0 - 20.0 * reload_blend) + aim_pitch * 0.35)
				* _rot_rig(_b_support, "y", deg_to_rad(-38.0 + 20.0 * reload_blend))
				* _rot_rig(_b_support, "z", deg_to_rad(24.0))
				* _rest[_b_support])
	if _b_forearm_l >= 0:
		skeleton.set_bone_pose_rotation(_b_forearm_l,
				_rot_rig(_b_forearm_l, "x", deg_to_rad(6.0 - 14.0 * reload_blend))
				* _rot_rig(_b_forearm_l, "y", deg_to_rad(-24.0 + 16.0 * reload_blend))
				* _rest[_b_forearm_l])


func _apply_base_pose() -> void:
	if variant == "spetsnaz":
		# Fold arms down and forward from A-pose into a combat rifle-ready hold.
		_set_spetsnaz_arms(0.0, 0.0)
		return
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
		_strip_baked_weapon_mesh(model, skeleton, WEAPON_BONE_NAME)
		_build_procedural_rifle()


## The merged mobile GLB has no authored rifle mesh (one body primitive with a
## single atlas material), so soldiers would otherwise be visibly unarmed.  A
## cheap box-built carbine gives the rig a real weapon to aim, sway, kick and
## drop: six primitives, one shared material, plus the muzzle marker.
func _build_procedural_rifle() -> void:
	var grip_pos := Vector3(0.303, 1.235, -0.090)
	var b_r_hand := _bone("Bip01_R_Hand" if variant == "spetsnaz" else "Bip01 R Hand")
	if skeleton != null and b_r_hand >= 0:
		skeleton.force_update_all_bone_transforms()
		grip_pos = to_local(skeleton.to_global(skeleton.get_bone_global_pose(b_r_hand).origin))
	elif variant == "spetsnaz":
		grip_pos = Vector3(0.14, 1.25, -0.34)
	rifle_pivot = Node3D.new()
	rifle_pivot.name = "RiflePivot"
	# Place RifleGrip (local (0, -0.08, -0.015)) right in the trigger hand bone.
	rifle_pivot.position = grip_pos + Vector3(0.0, 0.08, 0.015)
	# Procedural carbine parts already use local -Z forward and +Y up.
	_rifle_basis = Basis.IDENTITY
	rifle_pivot.basis = _rifle_basis
	add_child(rifle_pivot)
	_rifle_rest = rifle_pivot.position
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.17)
	mat.roughness = 0.42
	mat.metallic = 0.35
	# Layout along the pivot's local -Z, the forward/aim axis.
	var parts := {
		"RifleReceiver": [Vector3(0.0, 0.0, -0.16), Vector3(0.055, 0.09, 0.30)],
		"RifleHandguard": [Vector3(0.0, 0.0, -0.36), Vector3(0.045, 0.075, 0.16)],
		"RifleBarrel": [Vector3(0.0, 0.0, -0.50), Vector3(0.02, 0.02, 0.18)],
		"RifleStock": [Vector3(0.0, 0.0, 0.12), Vector3(0.05, 0.075, 0.16)],
		"RifleMag": [Vector3(0.0, -0.105, -0.10), Vector3(0.038, 0.13, 0.07)],
		"RifleGrip": [Vector3(0.0, -0.08, -0.015), Vector3(0.034, 0.085, 0.05)],
	}
	for part in parts:
		var box := BoxMesh.new()
		box.size = parts[part][1]
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = box
		mi.material_override = mat
		mi.position = parts[part][0]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		rifle_pivot.add_child(mi)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0.0, 0.0, -0.60)
	rifle_pivot.add_child(muzzle)


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
	var next_stride := clampf(stride, 0.0, 1.5)
	var changed := not is_equal_approx(phase, _walk_phase) \
			or not is_equal_approx(next_stride, _walk_stride)
	_walk_phase = phase
	_walk_stride = next_stride
	_run_blend = clampf((_walk_stride - 0.78) / 0.57, 0.0, 1.0)
	# Mobile LOD applies the latest walk parameters on its next pose tick. Calling
	# this from every physics frame would otherwise bypass the 30/15 Hz cap.
	# On the desktop path an idle caller passes the same values every frame, so
	# only re-pose when the gait actually changed.
	if changed and _mobile_animation_hz < 0.0:
		_update_pose(0.0)


func set_crouch(crouching: bool) -> void:
	_crouch_target = 1.0 if crouching else 0.0


func is_crouching_blend() -> float:
	return _crouch


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


## Mobile-only procedural animation LOD. A rate of 0 suspends pose updates while
## the owner is hidden; -1 restores normal per-frame processing (desktop path).
func set_mobile_animation_lod(distance: float) -> void:
	var next_hz := 30.0 if distance < 95.0 else (15.0 if distance < 260.0 else 0.0)
	if not is_equal_approx(next_hz, _mobile_animation_hz):
		var was_suspended := is_zero_approx(_mobile_animation_hz)
		_mobile_animation_hz = next_hz
		_mobile_animation_accumulator = 0.0
		if was_suspended and next_hz > 0.0 and _ready_ok:
			_crouch_t = _crouch_target
			_crouch = _crouch_t * _crouch_t * (3.0 - 2.0 * _crouch_t)
			_update_pose(0.0)


## Reference/preview clips baked from the procedural poses. Gameplay stays
## procedural; this player only hosts the exported .tres resources so they can
## be QA'd and later swapped into an AnimationTree without changing the rig.
func _ensure_clip_preview() -> void:
	if clip_player != null:
		return
	clip_player = AnimationPlayer.new()
	clip_player.name = "ClipPreview"
	add_child(clip_player)
	var library := AnimationLibrary.new()
	for clip_name in ["Idle", "Walk", "Run", "Aim", "Fire", "Reload", "Hit", "Death"]:
		var path := "res://Assets/combat/animations/soldier_%s.tres" % clip_name
		if ResourceLoader.exists(path):
			var clip := load(path) as Animation
			if clip != null:
				library.add_animation(clip_name, clip)
	clip_player.add_animation_library("soldier", library)


func preview_clip(clip_name: String, speed: float = 1.0) -> bool:
	if clip_player == null:
		_ensure_clip_preview()
	if clip_player == null or not clip_player.has_animation("soldier/" + clip_name):
		return false
	clip_player.play("soldier/" + clip_name)
	clip_player.speed_scale = speed
	return true


func stop_preview() -> void:
	if clip_player != null:
		clip_player.stop()


func _process(delta: float) -> void:
	if not _ready_ok:
		return
	if dead:
		return
	# Play the collapse once, then stop driving the skeleton entirely: a settled
	# corpse has no breathing, sway, aim or gait to update.
	if _dead and _death_progress >= 1.0:
		return
	if _mobile_animation_hz == 0.0:
		return
	var pose_delta := delta
	if _mobile_animation_hz > 0.0:
		_mobile_animation_accumulator += delta
		var interval := 1.0 / _mobile_animation_hz
		if _mobile_animation_accumulator < interval:
			return
		pose_delta = _mobile_animation_accumulator
		_mobile_animation_accumulator = 0.0
	_breath_phase += pose_delta * (2.2 + _walk_stride * 2.4)
	_sway_phase += pose_delta * (0.9 + _walk_stride * 0.5)
	_aim_smooth = lerpf(_aim_smooth, _aim_pitch, 1.0 - exp(-pose_delta / 0.09))
	_look_yaw_smooth = lerpf(_look_yaw_smooth, _look_yaw, 1.0 - exp(-pose_delta / 0.12))
	_crouch_t = move_toward(_crouch_t, _crouch_target, pose_delta * 3.8)
	_crouch = _crouch_t * _crouch_t * (3.0 - 2.0 * _crouch_t)
	_kick = move_toward(_kick, 0.0, pose_delta * 5.0)
	_hit_flinch = move_toward(_hit_flinch, 0.0, pose_delta * 4.2)
	if _reload_time > 0.0:
		_reload_time = maxf(0.0, _reload_time - pose_delta)
	if _dead:
		_death_progress = move_toward(_death_progress, 1.0, pose_delta * 2.1)
	_update_pose(pose_delta)
	if _dead and _death_progress >= 1.0:
		set_process(false)


func _update_pose(_delta: float) -> void:
	if skeleton == null:
		return
	if _dead:
		_apply_death_pose()
		return
	var swing := sin(_walk_phase)
	var walk_w := _walk_stride * (1.0 - _crouch * 0.9)
	var amp := (0.55 + 0.16 * _run_blend) * walk_w
	var crouch_hip := 0.72 * _crouch
	var crouch_knee := 1.25 * _crouch
	var crouch_foot := crouch_hip - crouch_knee
	# Heel-toe roll: the stance foot rocks from heel strike (toe up, phase=PI)
	# through a flat plant to toe-off (toe down, phase=0/TAU).  The legs are
	# anti-phased, so the right foot uses the mirrored sign.  Amplitude fades
	# out when crouching or standing still.
	var heel_toe := 0.15 * cos(_walk_phase) * clampf(walk_w, 0.0, 1.0)
	var breath := sin(_breath_phase) * 0.025
	var flinch_pitch := _hit_flinch * 0.28
	var flinch_yaw := _hit_flinch * 0.22 * _hit_dir
	# Lean the upper body and head toward the target.  Positive aim_pitch is
	# above the horizon, so pitch the chest back a little and the head more.
	var lean := -_aim_smooth * 0.22 + 0.24 * _crouch + breath + flinch_pitch \
			+ 0.06 * _kick - 0.10 * _run_blend
	var head_pitch := -_aim_smooth * 0.38 - 0.14 * _crouch - breath * 0.5 - flinch_pitch * 0.6
	var reload_blend := 0.0
	if _reload_time > 0.0 and _reload_duration > 0.0:
		var prog := 1.0 - (_reload_time / _reload_duration)
		reload_blend = sin(prog * PI)

	if variant == "spetsnaz":
		_apply_spetsnaz_bones(swing, walk_w, amp, crouch_hip, crouch_knee,
				crouch_foot, heel_toe, lean, head_pitch, flinch_yaw, reload_blend)
	else:
		if _b_thigh_l >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_l,
					Quaternion(Vector3.FORWARD, swing * amp + crouch_hip) * _rest[_b_thigh_l])
		if _b_thigh_r >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_r,
					Quaternion(Vector3.FORWARD, -swing * amp + crouch_hip) * _rest[_b_thigh_r])
		if _b_calf_l >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_l,
					Quaternion(Vector3.FORWARD,
					maxf(0.0, -swing) * 0.85 * walk_w + crouch_knee) * _rest[_b_calf_l])
		if _b_calf_r >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_r,
					Quaternion(Vector3.FORWARD,
					maxf(0.0, swing) * 0.85 * walk_w + crouch_knee) * _rest[_b_calf_r])
		if _b_foot_l >= 0:
			skeleton.set_bone_pose_rotation(_b_foot_l,
					Quaternion(Vector3.FORWARD, swing * 0.22 * walk_w
					- heel_toe + crouch_foot) * _rest[_b_foot_l])
		if _b_foot_r >= 0:
			skeleton.set_bone_pose_rotation(_b_foot_r,
					Quaternion(Vector3.FORWARD, -swing * 0.22 * walk_w
					+ heel_toe + crouch_foot) * _rest[_b_foot_r])
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
		if _b_support >= 0:
			var sup_yaw := deg_to_rad(90.0 - 38.0 * reload_blend)
			var sup_pitch := -0.45 * reload_blend
			skeleton.set_bone_pose_rotation(_b_support,
					Quaternion(Vector3.UP, sup_yaw) * Quaternion(Vector3.RIGHT, sup_pitch))

	var foot_correction := 0.0
	var chest_dy := -0.28 * _crouch
	if model != null:
		var bob := absf(sin(_walk_phase)) * (0.038 + 0.022 * _run_blend) \
				* _walk_stride * (1.0 - _crouch)
		model.position = _base_model_pos
		model.rotation = _base_model_rot
		if _b_foot_l >= 0 or _b_foot_r >= 0:
			# The full bone-transform pass is only needed when the geometry that
			# decides foot/chest height changed. Idle soldiers reuse the cached
			# measurement; a direct write to `_crouch` is always caught by the
			# live comparisons below, so foot anchoring still works when the
			# blend is set by hand and `_update_pose(0.0)` is called directly.
			var remeasure := not _foot_cache_valid \
					or not is_equal_approx(_crouch, _last_crouch) \
					or not is_equal_approx(_crouch, _last_foot_crouch) \
					or not is_equal_approx(_walk_phase, _last_foot_walk_phase) \
					or not is_equal_approx(_walk_stride, _last_foot_walk_stride) \
					or not is_equal_approx(_aim_smooth, _last_foot_aim) \
					or not is_equal_approx(_hit_flinch, _last_foot_flinch)
			if remeasure:
				skeleton.force_update_all_bone_transforms()
				_cached_foot_correction = _rest_foot_y - _lowest_foot_rig_y()
				var measure_bone := _b_spine3 if _b_spine3 >= 0 else _b_pelvis
				if measure_bone >= 0:
					_cached_chest_dy = (_rig_local_bone_y(measure_bone) + _cached_foot_correction) - _rest_spine3_y
				_last_crouch = _crouch
				_last_foot_crouch = _crouch
				_last_foot_walk_phase = _walk_phase
				_last_foot_walk_stride = _walk_stride
				_last_foot_aim = _aim_smooth
				_last_foot_flinch = _hit_flinch
				_foot_cache_valid = true
			foot_correction = _cached_foot_correction
			var chest_bone := _b_spine3 if _b_spine3 >= 0 else _b_pelvis
			if chest_bone >= 0:
				chest_dy = _cached_chest_dy
		model.position = _base_model_pos + Vector3(0.0, foot_correction + bob, 0.0)

	# Idle weapon sway: a slow, low-amplitude drift that dies down while the
	# soldier walks, aims or crouches, so steady aiming stays steady.
	var sway_amp := clampf(1.0 - 0.55 * clampf(_walk_stride, 0.0, 1.0)
			- 0.55 * absf(_aim_smooth) - 0.5 * _crouch, 0.0, 1.0)
	var sway_yaw := sin(_sway_phase) * 0.022 * sway_amp
	var sway_pitch := sin(_sway_phase * 1.37 + 1.7) * 0.015 * sway_amp
	var sway_roll := sin(_sway_phase * 0.71 + 0.6) * 0.013 * sway_amp
	var sway_pos := Vector3(
			0.014 * sway_amp * sin(_sway_phase * 0.83),
			0.012 * sway_amp * sin(_sway_phase * 1.13 + 2.0),
			0.0)

	if rifle_pivot != null:
		rifle_pivot.position = _rifle_rest + Vector3(
				0.04 * reload_blend,
				chest_dy - 0.012 * _kick - 0.06 * reload_blend + breath * 0.35,
				0.055 * _kick + 0.04 * reload_blend) + sway_pos
		var aim_tilt := _aim_smooth * 0.55 + 0.035 * _kick + 0.42 * reload_blend
		var roll_tilt := 0.48 * reload_blend
		rifle_pivot.basis = Basis(Vector3.UP, sway_yaw) \
				* Basis(Vector3.RIGHT, aim_tilt + sway_pitch) \
				* Basis(Vector3.FORWARD, roll_tilt + sway_roll) * _rifle_basis


func _apply_spetsnaz_bones(swing: float, walk_w: float, amp: float,
		crouch_hip: float, crouch_knee: float, crouch_foot: float, heel_toe: float,
		lean: float, head_pitch: float, flinch_yaw: float, reload_blend: float) -> void:
	if _b_thigh_l >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_l,
				_rot_rig(_b_thigh_l, "x", swing * amp + crouch_hip) * _rest[_b_thigh_l])
	if _b_thigh_r >= 0:
		skeleton.set_bone_pose_rotation(_b_thigh_r,
				_rot_rig(_b_thigh_r, "x", -swing * amp + crouch_hip) * _rest[_b_thigh_r])
	if _b_calf_l >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_l,
				_rot_rig(_b_calf_l, "x", -(maxf(0.0, -swing) * 0.85 * walk_w + crouch_knee)) * _rest[_b_calf_l])
	if _b_calf_r >= 0:
		skeleton.set_bone_pose_rotation(_b_calf_r,
				_rot_rig(_b_calf_r, "x", -(maxf(0.0, swing) * 0.85 * walk_w + crouch_knee)) * _rest[_b_calf_r])
	if _b_foot_l >= 0:
		skeleton.set_bone_pose_rotation(_b_foot_l,
				_rot_rig(_b_foot_l, "x", -swing * 0.22 * walk_w + heel_toe - crouch_foot) * _rest[_b_foot_l])
	if _b_foot_r >= 0:
		skeleton.set_bone_pose_rotation(_b_foot_r,
				_rot_rig(_b_foot_r, "x", swing * 0.22 * walk_w - heel_toe - crouch_foot) * _rest[_b_foot_r])
	if _b_spine2 >= 0:
		skeleton.set_bone_pose_rotation(_b_spine2,
				_rot_rig(_b_spine2, "x", -lean * 0.45) * _rot_rig(_b_spine2, "y", flinch_yaw * 0.5) * _rest[_b_spine2])
	if _b_spine3 >= 0:
		skeleton.set_bone_pose_rotation(_b_spine3,
				_rot_rig(_b_spine3, "x", -lean * 0.65) * _rot_rig(_b_spine3, "y", flinch_yaw * 0.5) * _rest[_b_spine3])
	if _b_neck >= 0:
		skeleton.set_bone_pose_rotation(_b_neck,
				_rot_rig(_b_neck, "x", -head_pitch * 0.5) * _rot_rig(_b_neck, "y", _look_yaw_smooth * 0.45) * _rest[_b_neck])
	if _b_head >= 0:
		skeleton.set_bone_pose_rotation(_b_head,
				_rot_rig(_b_head, "x", -head_pitch * 0.5) * _rot_rig(_b_head, "y", _look_yaw_smooth * 0.55) * _rest[_b_head])
	_set_spetsnaz_arms(reload_blend, _aim_smooth)


func _apply_death_pose() -> void:
	var k := 1.0 - pow(1.0 - _death_progress, 2.4)
	# Articulated multi-bone collapse onto the ground (never a rigid T-pose plank)
	var knee_buckle := 1.15 * k
	var hip_fold := 0.72 * k if _death_variant != 1 else 0.38 * k
	var sp_pitch := (0.42 if _death_variant == 0 else -0.28) * k
	var sp3_pitch := (0.48 if _death_variant == 0 else -0.32) * k
	if variant == "spetsnaz":
		if _b_thigh_l >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_l,
					_rot_rig(_b_thigh_l, "x", hip_fold) * _rest[_b_thigh_l])
		if _b_thigh_r >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_r,
					_rot_rig(_b_thigh_r, "x", hip_fold * 0.82) * _rest[_b_thigh_r])
		if _b_calf_l >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_l,
					_rot_rig(_b_calf_l, "x", -knee_buckle) * _rest[_b_calf_l])
		if _b_calf_r >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_r,
					_rot_rig(_b_calf_r, "x", -knee_buckle * 0.88) * _rest[_b_calf_r])
		if _b_spine2 >= 0:
			skeleton.set_bone_pose_rotation(_b_spine2,
					_rot_rig(_b_spine2, "x", -sp_pitch) * _rest[_b_spine2])
		if _b_spine3 >= 0:
			skeleton.set_bone_pose_rotation(_b_spine3,
					_rot_rig(_b_spine3, "x", -sp3_pitch) * _rest[_b_spine3])
		if _b_head >= 0:
			skeleton.set_bone_pose_rotation(_b_head,
					_rot_rig(_b_head, "x", -0.45 * k) * _rot_rig(_b_head, "y", 0.35 * k) * _rest[_b_head])
		if _b_support >= 0:
			skeleton.set_bone_pose_rotation(_b_support,
					_rot_rig(_b_support, "x", deg_to_rad(38.0 - 30.0 * k))
					* _rot_rig(_b_support, "y", deg_to_rad(-38.0 + 28.0 * k))
					* _rot_rig(_b_support, "z", deg_to_rad(24.0 - 18.0 * k))
					* _rest[_b_support])
		if _b_arm_r >= 0:
			skeleton.set_bone_pose_rotation(_b_arm_r,
					_rot_rig(_b_arm_r, "x", deg_to_rad(8.0 - 6.0 * k))
					* _rot_rig(_b_arm_r, "y", deg_to_rad(12.0 - 8.0 * k))
					* _rot_rig(_b_arm_r, "z", deg_to_rad(-22.0 + 18.0 * k))
					* _rest[_b_arm_r])
	else:
		if _b_thigh_l >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_l,
					Quaternion(Vector3.FORWARD, hip_fold) * _rest[_b_thigh_l])
		if _b_thigh_r >= 0:
			skeleton.set_bone_pose_rotation(_b_thigh_r,
					Quaternion(Vector3.FORWARD, hip_fold * 0.82) * _rest[_b_thigh_r])
		if _b_calf_l >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_l,
					Quaternion(Vector3.FORWARD, knee_buckle) * _rest[_b_calf_l])
		if _b_calf_r >= 0:
			skeleton.set_bone_pose_rotation(_b_calf_r,
					Quaternion(Vector3.FORWARD, knee_buckle * 0.88) * _rest[_b_calf_r])
		if _b_spine2 >= 0:
			skeleton.set_bone_pose_rotation(_b_spine2,
					Quaternion(Vector3.BACK, sp_pitch) * _rest[_b_spine2])
		if _b_spine3 >= 0:
			skeleton.set_bone_pose_rotation(_b_spine3,
					Quaternion(Vector3.BACK, sp3_pitch) * _rest[_b_spine3])
		if _b_head >= 0:
			skeleton.set_bone_pose_rotation(_b_head,
					Quaternion(Vector3.BACK, 0.45 * k) * Quaternion(Vector3.UP, 0.35 * k) * _rest[_b_head])
		if _b_support >= 0:
			skeleton.set_bone_pose_rotation(_b_support,
					Quaternion(Vector3.UP, deg_to_rad(90.0 - 52.0 * k)))
	if model != null:
		var drop_y := (-0.14 if variant == "spetsnaz" else -0.78) * k
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


func _capture_rest_heights() -> void:
	if skeleton == null or model == null:
		return
	model.position = _base_model_pos
	model.rotation = _base_model_rot
	skeleton.force_update_all_bone_transforms()
	_rest_foot_y = _lowest_foot_rig_y()
	var chest_bone := _b_spine3 if _b_spine3 >= 0 else _b_pelvis
	if chest_bone >= 0:
		_rest_spine3_y = _rig_local_bone_y(chest_bone)


func _lowest_foot_rig_y() -> float:
	if _b_foot_l >= 0 and _b_foot_r >= 0:
		return minf(_rig_local_bone_y(_b_foot_l), _rig_local_bone_y(_b_foot_r))
	if _b_foot_l >= 0:
		return _rig_local_bone_y(_b_foot_l)
	if _b_foot_r >= 0:
		return _rig_local_bone_y(_b_foot_r)
	return 0.0


func _rig_local_bone_y(bone_idx: int) -> float:
	if bone_idx < 0 or skeleton == null:
		return 0.0
	var pos := skeleton.get_bone_global_pose(bone_idx).origin
	var n: Node = skeleton
	while n != null and n != self:
		if n is Node3D:
			pos = (n as Node3D).transform * pos
		n = n.get_parent()
	return pos.y


## Removes triangles skinned predominantly to `bone_name` (such as the baked M4
## weapon inside soldier_detailed_merged.glb) so procedural RiflePivot is sole gun.
func _strip_baked_weapon_mesh(root: Node, sk: Skeleton3D, bone_name: String) -> void:
	if root == null or sk == null:
		return
	var bone_idx := sk.find_bone(bone_name)
	if bone_idx < 0:
		bone_idx = _bone(bone_name)
	if bone_idx < 0:
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var cache_key := "%d:%d" % [mi.mesh.get_rid().get_id(), bone_idx]
		if _stripped_mesh_cache.has(cache_key):
			mi.mesh = _stripped_mesh_cache[cache_key] as Mesh
			continue
		var stripped := _build_stripped_mesh(mi.mesh, bone_idx)
		_stripped_mesh_cache[cache_key] = stripped
		mi.mesh = stripped


static func _build_stripped_mesh(src_mesh: Mesh, weapon_bone: int) -> Mesh:
	var any_removed := false
	var rebuilt := ArrayMesh.new()
	for s in range(src_mesh.get_surface_count()):
		var arrays := src_mesh.surface_get_arrays(s)
		var mat := src_mesh.surface_get_material(s)
		var prim := Mesh.PRIMITIVE_TRIANGLES
		if src_mesh is ArrayMesh:
			prim = (src_mesh as ArrayMesh).surface_get_primitive_type(s)
		var stripped_arrays: Array = []
		var flags := 0
		if prim == Mesh.PRIMITIVE_TRIANGLES and not arrays.is_empty():
			var verts = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if verts is PackedVector3Array and bones is PackedInt32Array \
					and weights is PackedFloat32Array and verts.size() > 0:
				var vert_count := (verts as PackedVector3Array).size()
				var stride := (bones as PackedInt32Array).size() / vert_count
				if stride > 0 and (weights as PackedFloat32Array).size() == vert_count * stride:
					var is_weapon := PackedByteArray()
					is_weapon.resize(vert_count)
					var has_weapon := false
					for v in range(vert_count):
						var w_sum := 0.0
						var base := v * stride
						for k in range(stride):
							if bones[base + k] == weapon_bone:
								w_sum += weights[base + k]
						if w_sum > 0.5:
							is_weapon[v] = 1
							has_weapon = true
					if has_weapon:
						var orig_indices = arrays[Mesh.ARRAY_INDEX]
						var kept_indices := PackedInt32Array()
						if orig_indices is PackedInt32Array and (orig_indices as PackedInt32Array).size() >= 3:
							var src_idx := orig_indices as PackedInt32Array
							for ti in range(0, src_idx.size() - 2, 3):
								var ia := src_idx[ti]
								var ib := src_idx[ti + 1]
								var ic := src_idx[ti + 2]
								if is_weapon[ia] == 0 and is_weapon[ib] == 0 and is_weapon[ic] == 0:
									kept_indices.append(ia)
									kept_indices.append(ib)
									kept_indices.append(ic)
								else:
									any_removed = true
						else:
							for ti in range(0, vert_count - 2, 3):
								if is_weapon[ti] == 0 and is_weapon[ti + 1] == 0 and is_weapon[ti + 2] == 0:
									kept_indices.append(ti)
									kept_indices.append(ti + 1)
									kept_indices.append(ti + 2)
								else:
									any_removed = true
						var used := PackedByteArray()
						used.resize(vert_count)
						for idx_val in kept_indices:
							used[idx_val] = 1
						var remap := PackedInt32Array()
						remap.resize(vert_count)
						remap.fill(-1)
						var kept_verts := PackedInt32Array()
						for v in range(vert_count):
							if used[v] != 0:
								remap[v] = kept_verts.size()
								kept_verts.append(v)
						if not kept_verts.is_empty():
							stripped_arrays.resize(Mesh.ARRAY_MAX)
							for ai in range(Mesh.ARRAY_MAX):
								if ai == Mesh.ARRAY_INDEX:
									var new_idx := PackedInt32Array()
									new_idx.resize(kept_indices.size())
									for k in range(kept_indices.size()):
										new_idx[k] = remap[kept_indices[k]]
									stripped_arrays[ai] = new_idx
									continue
								var src_arr = arrays[ai]
								if src_arr == null:
									continue
								var elem_stride: int = src_arr.size() / vert_count
								if elem_stride <= 0 or elem_stride * vert_count != src_arr.size():
									continue
								var dst_arr = src_arr.duplicate()
								dst_arr.resize(kept_verts.size() * elem_stride)
								for nv in range(kept_verts.size()):
									var ov := kept_verts[nv]
									var s_off := ov * elem_stride
									var d_off := nv * elem_stride
									for j in range(elem_stride):
										dst_arr[d_off + j] = src_arr[s_off + j]
								stripped_arrays[ai] = dst_arr
							if stride == 8:
								flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		if not stripped_arrays.is_empty():
			rebuilt.add_surface_from_arrays(prim, stripped_arrays, [], {}, flags)
		else:
			if prim == Mesh.PRIMITIVE_TRIANGLES and not arrays.is_empty():
				var fallback_bones = arrays[Mesh.ARRAY_BONES]
				var fallback_verts = arrays[Mesh.ARRAY_VERTEX]
				if fallback_bones is PackedInt32Array and fallback_verts is PackedVector3Array and fallback_verts.size() > 0:
					if (fallback_bones as PackedInt32Array).size() / (fallback_verts as PackedVector3Array).size() == 8:
						flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
			rebuilt.add_surface_from_arrays(prim, arrays, [], {}, flags)
		var out_s := rebuilt.get_surface_count() - 1
		if mat != null:
			rebuilt.surface_set_material(out_s, mat)
		if src_mesh is ArrayMesh:
			rebuilt.surface_set_name(out_s, (src_mesh as ArrayMesh).surface_get_name(s))
	return rebuilt if any_removed and rebuilt.get_surface_count() > 0 else src_mesh
