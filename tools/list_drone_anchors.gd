extends SceneTree

const MODELS := [
	["holka", "res://Assets/Drones/ua_norm/holka.glb"],
	["pinapipe", "res://Assets/Drones/ua_norm/pinapipe.glb"],
	["avata2", "res://Assets/Drones/ua_norm/avata2.glb"],
	["pisun_vtol", "res://Assets/Drones/ua_norm/pisun_vtol.glb"],
	["peleng", "res://Assets/Drones/ua_norm/peleng.glb"],
	["grim7", "res://Assets/Drones/ua_norm/grim7.glb"],
	["grim7m", "res://Assets/Drones/ua_norm/grim7m.glb"],
	["strila8", "res://Assets/Drones/ua_norm/strila8.glb"],
	["falcon_x", "res://Assets/Drones/ua_norm/falcon_x.glb"],
	["quad5_custom", "res://Assets/Drones/ua_norm/quad5_custom.glb"],
	["magura_x", "res://Assets/Drones/ua_norm/magura_x.glb"],
	["baba_yaga", "res://Assets/Drones/ua_norm/baba_yaga.glb"],
	["leleka_100", "res://Assets/Drones/ua_norm/leleka_100.glb"],
	["furia_a1sm", "res://Assets/Drones/ua_norm/furia_a1sm.glb"],
	["chaklun_jet", "res://Assets/Drones/ua_norm/chaklun_jet.glb"],
]

func _init() -> void:
	for entry in MODELS:
		var path: String = entry[1]
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		var model := packed.instantiate() as Node3D
		var items := []
		_collect(model, items)
		items.sort_custom(func(a, b): return a["d"] > b["d"])
		print("\n==== ", entry[0], " meshes=", items.size(), " ====")
		for k in range(mini(14, items.size())):
			var it: Dictionary = items[k]
			print("  ", it["name"], " size=", it["size"], " center=", it["center"], " d=", snappedf(it["d"], 0.001))
		# Named anchors
		for it in items:
			var n := String(it["name"]).to_lower()
			if n.contains("wing") or n.contains("body") or n.contains("fuselage") \
					or n.contains("deck") or n.contains("hull") or n.contains("spine") \
					or n.contains("frame_top") or n.contains("top_plate") or n.contains("plate"):
				print("  ANCHOR? ", it["name"], " size=", it["size"], " center=", it["center"])
		model.free()
	quit()

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.visible:
			var aabb := mi.get_aabb()
			out.append({
				"name": String(mi.name),
				"size": aabb.size,
				"center": aabb.get_center(),
				"d": maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)),
			})
	for c in n.get_children():
		_collect(c, out)
