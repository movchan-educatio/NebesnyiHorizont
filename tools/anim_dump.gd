## QA: inspect animations on a GLB.
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := OS.get_environment("MODEL_PATH")
	var holder := Node3D.new()
	root.add_child(holder)
	current_scene = holder
	var model := (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	await process_frame
	for n in model.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		print("[ANIM] player=", ap.get_path(), " list=", ap.get_animation_list(), " autoplay=", ap.autoplay)
		for name in ap.get_animation_list():
			var a := ap.get_animation(name)
			print("  name=", name, " len=", a.length, " loop=", a.loop_mode, " tracks=", a.get_track_count())
			for i in range(mini(a.get_track_count(), 6)):
				print("    track ", i, " path=", a.track_get_path(i), " type=", a.track_get_type(i), " keys=", a.track_get_key_count(i))
	quit(0)
