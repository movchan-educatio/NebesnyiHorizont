@tool
extends SceneTree

func _init() -> void:
	print("--- TEST DRONE PARTS IMPORT & JSON ---")
	var json_path := "res://Assets/drone_parts/drone_parts_data.json"
	if not FileAccess.file_exists(json_path):
		printerr("FAIL: JSON does not exist: ", json_path)
		quit(1)
		return
	
	var file := FileAccess.open(json_path, FileAccess.READ)
	var text := file.get_as_text()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		printerr("FAIL: JSON parse error: ", json.get_error_message())
		quit(1)
		return
	
	var data: Dictionary = json.data
	var parts: Array = data.get("parts", [])
	print("Loaded ", parts.size(), " parts from JSON.")
	
	var all_ok := true
	for p in parts:
		var id: String = p.get("id", "")
		var mesh_path: String = p.get("mesh_path", "")
		print("Checking part: ", id, " -> ", mesh_path)
		if not ResourceLoader.exists(mesh_path):
			printerr("  FAIL: ResourceLoader cannot find: ", mesh_path)
			all_ok = false
			continue
		var packed := load(mesh_path) as PackedScene
		if packed == null:
			printerr("  FAIL: PackedScene is null: ", mesh_path)
			all_ok = false
			continue
		var inst := packed.instantiate()
		if inst == null:
			printerr("  FAIL: instantiate() returned null: ", mesh_path)
			all_ok = false
			continue
		print("  OK: Instantiated ", inst.get_class(), " (name=", inst.name, ", children=", inst.get_child_count(), ")")
		inst.free()
	
	if all_ok:
		print("--- ALL 16 PARTS LOADED AND INSTANTIATED SUCCESSFULLY! ---")
		quit(0)
	else:
		printerr("--- ERRORS OCCURRED LOADING PARTS ---")
		quit(1)
