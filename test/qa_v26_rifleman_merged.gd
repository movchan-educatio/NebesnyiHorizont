## QA test for rifleman_merged.glb: verify mobile uses merged, desktop uses original
extends Node

const TEST_NAME := "qa_v26_rifleman_merged"

func _ready() -> void:
	var had_mobile := OS.has_environment("MOBILE_UI")
	OS.unset_environment("MOBILE_UI")
	
	# Desktop: should load original rifleman.glb
	var desktop_inf := EnemyRifleman.new()
	add_child(desktop_inf)
	await get_tree().process_frame
	var desktop_meshes := desktop_inf.get_node_or_null("Model")
	var desktop_mesh_count := 0
	if desktop_meshes:
		var meshes = desktop_meshes.find_children("*", "MeshInstance3D", true, false)
		desktop_mesh_count = meshes.size()
		print(f"[{TEST_NAME}] DESKTOP model meshes: {desktop_mesh_count}")
	desktop_inf.queue_free()
	
	if had_mobile:
		OS.set_environment("MOBILE_UI", "1")
	
	# Mobile: should load merged rifleman_merged.glb (1 mesh)
	OS.set_environment("MOBILE_UI", "1")
	var mobile_inf := EnemyRifleman.new()
	add_child(mobile_inf)
	await get_tree().process_frame
	var mobile_meshes := mobile_inf.get_node_or_null("Model")
	var mobile_mesh_count := 0
	if mobile_meshes:
		var meshes = mobile_meshes.find_children("*", "MeshInstance3D", true, false)
		mobile_mesh_count = meshes.size()
		print(f"[{TEST_NAME}] MOBILE model meshes: {mobile_mesh_count}")
	mobile_inf.queue_free()
	
	OS.unset_environment("MOBILE_UI")
	
	# Verify merged is smaller (should be 1 mesh, original >50)
	var merged_ok := mobile_mesh_count < desktop_mesh_count and mobile_mesh_count <= 2
	var result := "PASS" if merged_ok else "FAIL"
	print(f"[{TEST_NAME}] {result}: desktop={desktop_mesh_count} mobile={mobile_mesh_count}")
	
	get_tree().quit(0 if merged_ok else 1)
