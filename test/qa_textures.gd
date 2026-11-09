extends Node

## QA helper: audit untextured StandardMaterial3D surfaces on a real level.
## Reports which authored buildings/props still render as flat colour so the
## material pass can target them instead of guessing.

const LEVELS := {
	"village": "res://sceneries/VillageLevel.tscn",
	"industrial": "res://sceneries/IndustrialLevel.tscn",
	"steppe": "res://sceneries/SteppeLevel.tscn",
	"wetlands": "res://sceneries/WetlandsLevel.tscn",
	"city": "res://sceneries/CityLevel.tscn",
	"course": "res://sceneries/CourseLevel.tscn",
}


func _ready() -> void:
	var only := OS.get_environment("QA_TEX_MAP")
	var wait := 4.0
	var failed := false
	for key in LEVELS:
		if not only.is_empty() and key != only:
			continue
		var path: String = LEVELS[key]
		var packed := load(path) as PackedScene
		if packed == null:
			print("[TEX] cannot load ", path)
			failed = true
			continue
		var level := packed.instantiate()
		add_child(level)
		await get_tree().create_timer(wait).timeout
		_audit(key, level)
		level.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	print("[TEX] RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(0 if not failed else 1)


func _audit(tag: String, level: Node) -> void:
	var flat := {}
	var total_surfaces := 0
	var flat_surfaces := 0
	for node in level.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var top := _top_name(mi, level)
		for s in range(mi.mesh.get_surface_count()):
			total_surfaces += 1
			var mat := mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			var sm := mat as StandardMaterial3D
			if sm == null:
				continue
			if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if sm.emission_enabled or sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				continue
			if sm.albedo_texture != null:
				continue
			flat_surfaces += 1
			var key := top + " | " + String(mi.name)
			flat[key] = int(flat.get(key, 0)) + 1
	var rows: Array = []
	for key in flat:
		rows.append([int(flat[key]), key])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[TEX] %s surfaces=%d untextured=%d unique=%d" % [
			tag, total_surfaces, flat_surfaces, rows.size()])
	for i in range(mini(rows.size(), 40)):
		print("[TEX]   %3d  %s" % [rows[i][0], rows[i][1]])


func _top_name(node: Node, level: Node) -> String:
	var chain: Array[Node] = []
	var cur := node
	while cur != null and cur != level:
		chain.push_front(cur)
		cur = cur.get_parent()
	if chain.is_empty():
		return "level"
	var top := String(chain[0].name)
	if top.begins_with("@"):
		top = "procedural"
	return top
