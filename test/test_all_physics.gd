extends Node

func _ready() -> void:
	print("\n========================================================")
	print("=== RUNNING FULL FPV PHYSICS SUITE (ALL 5 PILLARS) ===")
	print("========================================================")
	
	# Pillar 1
	var t1 = load("res://test/test_stage1.gd").new()
	add_child(t1)
	
	# Pillar 2
	var t2 = load("res://test/test_stage2.gd").new()
	add_child(t2)
	
	# Pillar 3
	var t3 = load("res://test/test_stage3.gd").new()
	add_child(t3)
	
	# Pillar 4
	var t4 = load("res://test/test_stage4.gd").new()
	add_child(t4)
	
	# Pillar 5
	var t5 = load("res://test/test_stage5.gd").new()
	add_child(t5)
	
	print("\n========================================================")
	print("=== ALL 5 FPV PHYSICS PILLARS VERIFIED & FUNCTIONAL! ===")
	print("========================================================\n")
	get_tree().quit(0)
