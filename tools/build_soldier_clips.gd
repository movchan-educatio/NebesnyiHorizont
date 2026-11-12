extends SceneTree

## One-shot asset builder: bakes the procedural DetailedSoldierRig poses into
## separate Animation resources and saves them as .tres clips.
##
## Run: godot --headless --path . --script res://tools/build_soldier_clips.gd
## Output: Assets/combat/animations/soldier_<Idle|Walk|Run|Aim|Fire|Reload|Hit|Death>.tres

const OUTPUT_DIR := "res://Assets/combat/animations"
const FPS := 30.0

const STATES := {
	"Idle": {"frames": 36, "mode": "loop"},
	"Walk": {"frames": 36, "mode": "loop"},
	"Run": {"frames": 30, "mode": "loop"},
	"Aim": {"frames": 30, "mode": "loop"},
	"Fire": {"frames": 14, "mode": "clamp"},
	"Reload": {"frames": 54, "mode": "clamp"},
	"Hit": {"frames": 24, "mode": "clamp"},
	"Death": {"frames": 48, "mode": "clamp"},
}


func _initialize() -> void:
	var rig: DetailedSoldierRig = (load("res://combat/detailed_soldier_rig.gd") as GDScript).new()
	root.add_child(rig)
	if not rig.setup_rig(-1):
		push_error("[CLIPS] rig setup failed")
		quit(1)
		return
	var skeleton: Skeleton3D = rig.skeleton
	var path_base: NodePath = rig.get_path_to(skeleton)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for state_name in STATES:
		var spec: Dictionary = STATES[state_name]
		var frames: int = spec["frames"]
		var anim := Animation.new()
		anim.length = float(frames) / FPS
		if String(spec["mode"]) == "loop":
			anim.loop_mode = Animation.LOOP_LINEAR
		var tracks := {}
		for bone_idx in range(skeleton.get_bone_count()):
			tracks[bone_idx] = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(tracks[bone_idx],
					"%s:%s" % [path_base, skeleton.get_bone_name(bone_idx)])
		var dt := 1.0 / FPS
		_prepare_state(rig, state_name)
		for frame in range(frames):
			var time := float(frame) / FPS
			_step_state(rig, state_name, frame, dt)
			rig._process(dt)
			for bone_idx in tracks:
				anim.rotation_track_insert_key(tracks[bone_idx], time,
						skeleton.get_bone_pose_rotation(bone_idx))
		var err := ResourceSaver.save(anim, "%s/soldier_%s.tres" % [OUTPUT_DIR, state_name])
		print("[CLIPS] %s frames=%d length=%.2f tracks=%d err=%s" % [
				state_name, frames, anim.length, anim.get_track_count(), str(err)])
	rig.queue_free()
	quit(0)


func _prepare_state(rig: DetailedSoldierRig, state_name: String) -> void:
	rig.set_walk(0.0, 0.0)
	rig.set_crouch(false)
	rig.set_aim_pitch(0.0)
	rig.set_look_yaw(0.0)
	match state_name:
		"Aim":
			rig.set_aim_pitch(0.45)
		"Fire":
			rig.kick()
		"Reload":
			rig.start_reload(1.75)
		"Hit":
			rig.hit_react(true)
		"Death":
			rig.play_death(0)


func _step_state(rig: DetailedSoldierRig, state_name: String, frame: int, dt: float) -> void:
	match state_name:
		"Walk":
			var phase := float(frame) * dt * (2.0 + 2.2 * 3.2)
			rig.set_walk(phase, 1.0)
		"Run":
			var phase := float(frame) * dt * (2.0 + 3.4 * 3.2)
			rig.set_walk(phase, 1.35)
		"Fire":
			# kick decays inside _process; refresh only the first frame.
			pass
