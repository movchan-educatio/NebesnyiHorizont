## QA: audit every drone preset on the MainMenu pedestal.
## Reports the lowest visual point (should sit just above the pedestal top)
## and any flag meshes still attached to the model.
extends Node

const OUT_DIR := "C:/Users/USER_UA/AppData/Local/Temp/opencode/menu_platform_qa"
const PLATFORM_TOP_Y := -0.37


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var packed := load("res://GUI/MainMenu.tscn") as PackedScene
	var menu: Variant = packed.instantiate()
	add_child(menu)
	for i in range(10):
		await get_tree().process_frame
	menu._auto_orbit = false
	var rows: Array[String] = []
	for idx in range(DroneCatalog.count()):
		Global.drone_preset = idx
		menu._update_drone_intel()
		menu._load_drone_model()
		for f in range(14):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var holder: Node3D = menu.get("_model_holder")
		var model := holder.get_node_or_null("DroneModel") as Node3D
		if model == null:
			rows.append("%02d\t%s\tNO_MODEL" % [idx, DroneCatalog.preset(idx).get("name", "?")])
			continue
		var bounds := _visual_bounds(model)
		var gap := bounds.position.y - PLATFORM_TOP_Y
		var flags: Array[String] = []
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if String(mi.name).to_lower().contains("flag") \
					or String(mi.name).to_lower().contains("ukrainemark"):
				flags.append(String(mi.name))
		rows.append("%02d\t%s\tmin_y=%.4f gap=%+.4f max_y=%.4f flags=%s" % [
			idx, DroneCatalog.preset(idx).get("name", "?"),
			bounds.position.y, gap, bounds.end.y, str(flags)])
		print("[PADQA] ", rows[rows.size() - 1])
		# Capture the full menu for visual review of the stage framing.
		var img := get_viewport().get_texture().get_image()
		if img != null:
			img.save_png("%s/preset_%02d.png" % [OUT_DIR, idx])
	var f := FileAccess.open("%s/audit.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		for row in rows:
			f.store_line(row)
		f.close()
	print("[PADQA] done -> ", OUT_DIR)
	get_tree().quit()


func _visual_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var visuals: Array = []
	if root is VisualInstance3D:
		visuals.append(root)
	for n in root.find_children("*", "VisualInstance3D", true, false):
		visuals.append(n)
	for visual in visuals:
		var vi := visual as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var box: AABB = vi.global_transform * vi.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result
