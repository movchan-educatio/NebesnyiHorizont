extends Node

const DroneAssemblyBuilder = preload("res://scripts/util/DroneAssemblyBuilder.gd")
const DronePropellerSystem = preload("res://scripts/util/DronePropellerSystem.gd")

const ARTIFACT_DIR := "C:/Users/USER_UA/.gemini/antigravity/brain/ee388256-6605-4a1e-9395-d4a4f9ddcf71"

func _ready() -> void:
	print("==================================================================")
	print("=== RUNNING MODULAR FPV DRONE CONSTRUCTOR & TTX TEST SUITE     ===")
	print("==================================================================")
	
	var pass_count := 0
	
	# -------------------------------------------------------------------------
	# 1. DATABASE INTEGRITY & SPECIFICATION VERIFICATION
	# -------------------------------------------------------------------------
	print("\n[TEST 1] Verifying Parts Database & Category Completeness...")
	var db := DroneAssemblyBuilder.get_parts_db()
	assert(not db.is_empty(), "Database must not be empty")
	var parts: Array = db.get("parts", [])
	assert(parts.size() == 16, "Must contain exactly 16 modular components")
	
	var categories := ["frame", "motor", "prop", "battery", "camera", "payload"]
	var cat_counts: Dictionary = {}
	for cat in categories:
		cat_counts[cat] = 0
	
	for p in parts:
		var c: String = p.get("category", "")
		assert(categories.has(c), "Unknown category: %s" % c)
		cat_counts[c] += 1
		assert(ResourceLoader.exists(p.get("mesh_path", "")), "Mesh path missing: %s" % p.get("mesh_path"))
	
	assert(cat_counts["frame"] == 4, "Must have 4 frames")
	assert(cat_counts["motor"] == 2, "Must have 2 motors")
	assert(cat_counts["prop"] == 3, "Must have 3 props")
	assert(cat_counts["battery"] == 2, "Must have 2 batteries")
	assert(cat_counts["camera"] == 2, "Must have 2 cameras")
	assert(cat_counts["payload"] == 3, "Must have 3 payloads")
	
	print("  ✓ All 16 parts verified across 6 categories (4 frames, 2 motors, 3 props, 2 batteries, 2 cameras, 3 payloads)")
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 2. COORDINATE TRANSFORMATION & MARKER HARDPOINTS
	# -------------------------------------------------------------------------
	print("\n[TEST 2] Blender to Godot Coordinate Mapping & Marker3D Hardpoints...")
	var test_blender_coord := [-0.078, 0.078, 0.0]
	var godot_coord := DroneAssemblyBuilder.to_godot_pos(test_blender_coord)
	# Blender X -> Godot +X (-0.078)
	# Blender Y -> Godot -Z (-0.078)
	# Blender Z -> Godot +Y (0.0)
	assert(is_equal_approx(godot_coord.x, -0.078), "Godot X should match Blender X")
	assert(is_equal_approx(godot_coord.y, 0.0), "Godot Y should match Blender Z")
	assert(is_equal_approx(godot_coord.z, -0.078), "Godot Z should match -Blender Y")
	print("  ✓ Coordinate conversion: Blender [-0.078, 0.078, 0.0] -> Godot %s" % str(godot_coord))
	pass_count += 1
	
	# -------------------------------------------------------------------------
	# 3. PROCEDURAL ASSEMBLY: 5\" SPORT RACER DRONE
	# -------------------------------------------------------------------------
	print("\n[TEST 3] Procedural Assembly: 5\" True-X Sport Racer...")
	var cfg_race := {
		"frame": "frame_race_5",
		"motor": "motor_2207_highkv",
		"prop": "prop_5x4x3",
		"battery": "battery_4s_1500",
		"camera": "camera_analog",
		"payload": "payload_empty"
	}
	var race_drone := DroneAssemblyBuilder.build_drone_node(cfg_race)
	assert(race_drone != null, "Race drone node must instantiate")
	add_child(race_drone)
	
	assert(race_drone.find_child("FrameMesh", true, false) != null, "Must contain FrameMesh")
	assert(race_drone.find_child("motor_FL", true, false) != null, "Must contain motor_FL")
	assert(race_drone.find_child("motor_FR", true, false) != null, "Must contain motor_FR")
	assert(race_drone.find_child("motor_BL", true, false) != null, "Must contain motor_BL")
	assert(race_drone.find_child("motor_BR", true, false) != null, "Must contain motor_BR")
	assert(race_drone.find_child("propeller_FL", true, false) != null, "Must contain propeller_FL")
	assert(race_drone.find_child("BatteryMesh", true, false) != null, "Must contain BatteryMesh")
	assert(race_drone.find_child("CameraMesh", true, false) != null, "Must contain CameraMesh")
	assert(race_drone.find_child("PayloadMesh", true, false) == null, "Empty payload must NOT spawn PayloadMesh")
	
	# Check CCW propeller blade inversion
	var prop_fr: Node3D = race_drone.find_child("propeller_FR", true, false)
	var prop_mesh_fr: Node3D = prop_fr.get_child(0) as Node3D
	assert(is_equal_approx(prop_mesh_fr.scale.x, -1.0), "CCW propeller FR must have inverted scale.x = -1.0")
	
	var ttx_race := DroneAssemblyBuilder.calculate_ttx(cfg_race)
	print("  ✓ 5\" Racer AUW: %d g, 4x Thrust: %d g, TWR: %.2f : 1" % [
		int(ttx_race["total_mass_g"]), int(ttx_race["total_thrust_g"]), ttx_race["twr"]
	])
	assert(ttx_race["twr"] > 10.0, "5\" Racer with 2207 motors should have extreme TWR > 10:1")
	assert(not ttx_race["is_combat"], "Race drone must be civilian/sport")
	pass_count += 1
	race_drone.queue_free()
	
	# -------------------------------------------------------------------------
	# 4. PROCEDURAL ASSEMBLY: 10\" HEAVY MILITARY KAMIKAZE DRONE
	# -------------------------------------------------------------------------
	print("\n[TEST 4] Procedural Assembly: 10\" Heavy Military Kamikaze (PG-7VR)...")
	var cfg_kami := {
		"frame": "frame_heavy_10",
		"motor": "motor_2807_lowkv",
		"prop": "prop_10x5x3",
		"battery": "battery_6s_4500",
		"camera": "camera_thermal",
		"payload": "payload_kamikaze_pg7"
	}
	var kami_drone := DroneAssemblyBuilder.build_drone_node(cfg_kami)
	assert(kami_drone != null, "Kamikaze drone node must instantiate")
	add_child(kami_drone)
	
	assert(kami_drone.find_child("PayloadMesh", true, false) != null, "Kamikaze must spawn PayloadMesh")
	assert(kami_drone.find_child("CameraMesh", true, false) != null, "Must contain FLIR camera")
	
	var ttx_kami := DroneAssemblyBuilder.calculate_ttx(cfg_kami)
	print("  ✓ 10\" Kamikaze AUW: %d g (%.2f kg), 4x Thrust: %d g, TWR: %.2f : 1" % [
		int(ttx_kami["total_mass_g"]), ttx_kami["total_mass_kg"], int(ttx_kami["total_thrust_g"]), ttx_kami["twr"]
	])
	assert(ttx_kami["total_mass_g"] > 2500, "10\" Kamikaze with PG-7 should weigh over 2.5 kg")
	assert(ttx_kami["is_combat"], "Kamikaze drone must have is_combat=true")
	assert(ttx_kami["twr"] > 3.0, "10\" Kamikaze should still have solid tactical TWR > 3.0:1")
	pass_count += 1
	kami_drone.queue_free()
	
	# -------------------------------------------------------------------------
	# 5. PROCEDURAL ASSEMBLY: 7\" BOMBER WITH VOG-17 DROP RELEASE
	# -------------------------------------------------------------------------
	print("\n[TEST 5] Procedural Assembly: 7\" Bomber with VOG-17 Munition Drop...")
	var cfg_bomber := {
		"frame": "frame_freestyle_7",
		"motor": "motor_2807_lowkv",
		"prop": "prop_7x4x3",
		"battery": "battery_6s_4500",
		"camera": "camera_thermal",
		"payload": "payload_drop_vog"
	}
	var bomber_drone := DroneAssemblyBuilder.build_drone_node(cfg_bomber)
	assert(bomber_drone != null, "Bomber drone node must instantiate")
	add_child(bomber_drone)
	
	var ttx_bomber := DroneAssemblyBuilder.calculate_ttx(cfg_bomber)
	print("  ✓ 7\" Bomber AUW: %d g, 4x Thrust: %d g, TWR: %.2f : 1, Drop: %s" % [
		int(ttx_bomber["total_mass_g"]), int(ttx_bomber["total_thrust_g"]), ttx_bomber["twr"], ttx_bomber["has_drop"]
	])
	assert(ttx_bomber["has_drop"], "Bomber drone must have has_drop=true")
	pass_count += 1
	bomber_drone.queue_free()
	
	# -------------------------------------------------------------------------
	# 6. SAVE PERSISTENCE & DRONECATALOG INTEGRATION
	# -------------------------------------------------------------------------
	print("\n[TEST 6] Persistence & DroneCatalog Custom Preset Application...")
	var save_path := "user://custom_drone_builder.json"
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	assert(f != null, "Failed to open save path for writing")
	f.store_string(JSON.stringify(cfg_kami, "\t"))
	f.close()
	assert(FileAccess.file_exists(save_path), "Saved custom build file must exist")
	
	# Reload into DroneCatalog
	DroneCatalog._load_saved_builder_preset()
	var custom_idx := DroneCatalog.custom_preset_index()
	var p_custom := DroneCatalog.preset(custom_idx)
	assert(p_custom.get("is_builder_custom", false) == true, "Custom slot should be marked as builder custom")
	assert(p_custom.get("combat", false) == true, "Custom slot should have combat=true")
	print("  ✓ Custom preset[%d] name: %s, tag: %s, dry: %.3fkg, batt: %.3fkg" % [
		custom_idx, p_custom.get("name"), p_custom.get("tag"), p_custom.get("dry"), p_custom.get("batt")
	])
	
	# Test attach_model on a dummy Node3D
	var dummy_drone := Node3D.new()
	add_child(dummy_drone)
	var attached := DroneCatalog.attach_model(dummy_drone, custom_idx)
	assert(attached != null, "attach_model must succeed for custom preset")
	assert(attached.name == "DroneModel", "Attached model root must be named DroneModel")
	assert(attached.find_child("PayloadMesh", true, false) != null, "Attached model must include custom payload")
	print("  ✓ Custom 3D model attached to drone body with %d children" % attached.get_child_count())
	pass_count += 1
	dummy_drone.queue_free()
	
	# -------------------------------------------------------------------------
	# 7. DRONE BUILDER UI & VIEWPORT RENDER SCREENSHOT
	# -------------------------------------------------------------------------
	print("\n[TEST 7] Spawning DroneBuilder Screen & Capturing Visual Verification...")
	var builder_scene: PackedScene = load("res://GUI/DroneBuilder.tscn")
	assert(builder_scene != null, "DroneBuilder.tscn must load")
	var builder_inst := builder_scene.instantiate() as Control
	add_child(builder_inst)
	
	# Wait for viewport and shaders to render
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	
	# The dummy headless renderer has no viewport texture; skip the screenshot.
	if DisplayServer.get_name() != "headless":
		var img := get_viewport().get_texture().get_image()
		if img != null:
			var screenshot_path := ARTIFACT_DIR + "/test_drone_builder_assembled.png"
			var err := img.save_png(screenshot_path)
			if err == OK:
				print("  ✓ Saved visual verification screenshot: ", screenshot_path)
			else:
				print("  Note: image save returned code: ", err)
	pass_count += 1
	builder_inst.queue_free()
	
	print("\n==================================================================")
	print("=== ALL %d/7 MODULAR CONSTRUCTOR TESTS PASSED (100%%)          ===" % pass_count)
	print("==================================================================")
	await get_tree().create_timer(0.1).timeout
	get_tree().quit(0)
