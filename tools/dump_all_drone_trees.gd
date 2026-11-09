## Dump the imported node tree of every drone GLB, focusing on
## motor / propeller / rotor nodes, so we can see what geometry the model
## actually ships with.
extends SceneTree


const MODELS := [
	"holka.glb",
	"pinapipe.glb",
	"avata2.glb",
	"pisun_vtol.glb",
	"peleng.glb",
	"grim7.glb",
	"grim7m.glb",
	"strila8.glb",
	"falcon_x.glb",
	"quad5_custom.glb",
]


func _init() -> void:
	for file: String in MODELS:
		var path: String = "res://Assets/Drones/ua_norm/" + file
		var ps := load(path) as PackedScene
		if ps == null:
			print("!! FAILED ", path)
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		print("\n==================================================")
		print("MODEL: ", file)
		print("==================================================")
		_dump(inst, 0)
		inst.queue_free()
	quit()


func _dump(node: Node, depth: int) -> void:
	var name_l := String(node.name).to_lower()
	var interesting := name_l.contains("motor") or name_l.contains("prop") \
			or name_l.contains("rotor") or name_l.contains("spin") \
			or name_l.contains("blade") or name_l.contains("hub") \
			or name_l.contains("shaft") or name_l.contains("nacelle")
	if interesting or depth <= 1:
		var info := ""
		if node is Node3D:
			var n3d := node as Node3D
			info = " pos=%s rot=%s scale=%s" % [n3d.position, n3d.rotation_degrees, n3d.scale]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var aabb := mi.get_aabb()
				info += " mesh=%s aabb_c=%s aabb_s=%s" % [
					mi.mesh.get_class(), aabb.get_center(), aabb.size]
		print("  ".repeat(depth), "- ", node.name, " [", node.get_class(), "]", info)
	for c in node.get_children():
		_dump(c, depth + 1)
