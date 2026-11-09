## QA: print the world AABB of every mesh in a hit FX GLB after animation.
extends Node3D

func _ready() -> void:
	var model := (load("res://Assets/combat/hit_vehicle.glb") as PackedScene).instantiate() as Node3D
	add_child(model)
	for apn in model.find_children("*", "AnimationPlayer", true, false):
		var ap := apn as AnimationPlayer
		print("[FXDUMP] anim=", ap.get_animation_list())
		if ap.get_animation_list().has("Hit"):
			ap.play("Hit")
			ap.seek(0.2, true)
	await get_tree().create_timer(0.2).timeout
	var box := AABB()
	var first := true
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		print("[FXDUMP] ", mi.name, " global_scale=", mi.global_transform.basis.get_scale(),
				" aabb=", b.position, " size=", b.size)
		box = b if first else box.merge(b)
		first = false
	print("[FXDUMP] total size=", box.size, " center=", box.get_center())
	get_tree().quit(0)
