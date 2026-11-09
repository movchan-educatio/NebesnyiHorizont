extends Node


func _ready() -> void:
	var packed := load("res://Assets/sceneries/city/fpv_city.glb") as PackedScene
	var city := packed.instantiate() as Node3D
	add_child(city)
	await get_tree().process_frame
	var n := 0
	for child in city.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if n < 30:
			print("[CITYNAME] ", mi.name, " vis=", mi.visible)
		n += 1
	print("[CITYNAME] total=", n)
	get_tree().quit()
