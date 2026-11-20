extends Node3D

## QA probe for the new collision/props/destruction features:
##  * tree and roof colliders exist
##  * 20 Blender prop types are instanced
##  * a window is actually open (a ray passes through both facades)
##  * a destructible landmark hides its meshes and reports destroyed

const TERRAIN := preload("res://scripts/util/frontline_terrain.gd")


func _ready() -> void:
	# Isolated window test: yaw 0, 8 m wide, 7 m deep, 4 m tall.
	var house_root := Node3D.new()
	add_child(house_root)
	var mat := StandardMaterial3D.new()
	TERRAIN._add_house_shell(house_root, Vector2.ZERO, 0.0, 8.0, 7.0, 4.0,
			0.0, mat)
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1.9, -9),
			Vector3(0, 1.9, 9))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	print("[NEW] window_ray_pass=", hit.is_empty(), " hit=",
			"-" if hit.is_empty() else str(hit.get("collider")))

	# Full village terrain.
	var root := Node3D.new()
	add_child(root)
	TERRAIN.build_terrain(root, "village", 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var troot := root.get_node("FrontlineTerrain")
	var tree_tiles := 0
	for child in troot.get_children():
		if child is StaticBody3D and String(child.name).begins_with("TreeCollision"):
			tree_tiles += 1
	print("[NEW] tree_collision_tiles=", tree_tiles)
	print("[NEW] prop_collision=", troot.get_node_or_null("PropCollision") != null)
	var props := 0
	for child in troot.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with("Prop_"):
			props += 1
	print("[NEW] prop_types=", props)
	var marks := get_tree().get_nodes_in_group("destructible")
	print("[NEW] destructible_nodes=", marks.size())
	if not marks.is_empty():
		var lm = marks[0]
		lm.take_damage(999999.0, (lm as Node3D).global_position)
		await get_tree().process_frame
		print("[NEW] landmark_destroyed=", lm.get("is_destroyed") == true)
	var all_combat := DroneCatalog.count() >= 13
	for ci in range(10):
		all_combat = all_combat and DroneCatalog.is_combat(ci)
	for ci in range(10, DroneCatalog.count()):
		all_combat = all_combat and DroneCatalog.is_uman(ci) and not DroneCatalog.is_combat(ci)
	assert(all_combat and DroneCatalog.first_combat_index() == 0,
			"Fleet must contain 10 combat FPV drones + 3 Uman freestyle drones")
	print("[NEW] combat_filter count=", DroneCatalog.count(),
			" all_combat=", all_combat, " first=", DroneCatalog.first_combat_index())
	get_tree().quit()
