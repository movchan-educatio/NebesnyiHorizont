extends SceneTree

const DroneCatalogScript = preload("res://autoloads/DroneCatalog.gd")
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")

func _init() -> void:
	print("Checking propeller rotation frame by frame...")
	var catalog = DroneCatalogScript.new()
	var list: Array[int] = [0, 1, 2, 3, 4, 8, 9] # Holka, PinaPipe, Avata2, Pisun, Peleng, Falcon-X, Quad-5
	for idx in list:
		var p: Dictionary = catalog.preset(idx)
		var p_name: String = str(p.get("name", "Unknown"))
		var path: String = str(p.get("model", ""))
		var scn: PackedScene = load(path) as PackedScene
		if scn == null:
			continue
		var model: Node3D = scn.instantiate() as Node3D
		var pivots: Array[Node3D] = DronePropellerSystem.setup_propellers(model, idx,
				float(p.get("prop_d", 5.0)), int(p.get("blades", 3)))
		print("\n--- Preset %d: %s (%s) ---" % [idx, p_name, path.get_file()])
		print("Pivots found: %d" % pivots.size())
		for frame in range(3):
			catalog.animate_propellers(model, 0.016)
			var rots: Array[String] = []
			for piv in pivots:
				rots.append("%.2f deg" % rad_to_deg(piv.rotation.y))
			print("  Frame %d rots: %s" % [frame, ", ".join(rots)])
	quit(0)
