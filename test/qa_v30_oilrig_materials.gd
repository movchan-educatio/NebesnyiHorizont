extends Node

var _fails := 0


func _check(ok: bool, label: String) -> void:
	if ok:
		print("[MAT-TEST] PASS ", label)
	else:
		_fails += 1
		print("[MAT-TEST] FAIL ", label)


func _ready() -> void:
	Global.menu_settings["selected_map"] = "oilrig"
	Global.play_mode = Global.PlayMode.TRAINING
	DroneCatalog.apply(0)
	var packed := load("res://sceneries/OilRigLevel.tscn") as PackedScene
	var level := packed.instantiate()
	add_child(level)
	for _i in range(30):
		await get_tree().physics_frame
	var inst := level.find_child("OilRigMap", true, false)
	print("[MAT-TEST] instance=", inst)
	_check(inst != null, "OilRigMap інстанційовано")
	if inst != null:
		var total := 0
		var overridden := 0
		var textured := 0
		var names := {}
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			total += 1
			var mat := (mi as MeshInstance3D).get_active_material(0)
			if mat == null:
				continue
			var nm := String(mat.resource_name)
			names[nm] = int(names.get(nm, 0)) + 1
			if (mi as MeshInstance3D).material_override != null or (mi as MeshInstance3D).get_surface_override_material_count() > 0:
				overridden += 1
			if mat is StandardMaterial3D and (mat as StandardMaterial3D).albedo_texture != null:
				textured += 1
		print("[MAT-TEST] meshes=", total, " overridden=", overridden, " textured=", textured)
		print("[MAT-TEST] names=", names)
		_check(textured >= 70, "текстуровані атлас-матеріали відновлено (%d)" % textured)
		var ocean := inst.find_child("Ocean", true, false) as MeshInstance3D
		_check(ocean != null, "Ocean вузол присутній")
		if ocean != null:
			var om = ocean.get_active_material(0)
			_check(om is ShaderMaterial, "Ocean використовує ShaderMaterial")
			if om is ShaderMaterial:
				var sm := om as ShaderMaterial
				_check(sm.get_shader_parameter("wave_a") != null, "wave_a зв'язаний")
				_check(sm.get_shader_parameter("wave_b") != null, "wave_b зв'язаний")
				_check(sm.get_shader_parameter("foam_mask") != null, "foam_mask зв'язаний")
				_check(sm.get_shader_parameter("foam_strength") == null, "без фіктивного override foam_strength")
				_check(sm.get_shader_parameter("deep_color") == null, "збережено авторський deep_color шейдера")
		var water_kill := inst.find_child("WaterKillZone", true, false)
		_check(water_kill != null, "WaterKillZone присутній")
		var p1 := inst.find_child("Platform_core_01", true, false) as Node3D
		var d2 := inst.find_child("Derrick_02", true, false) as Node3D
		_check(p1 != null and p1.scale.y >= 9.0,
				"Platform_core_01 вертикальний масштаб >= 9.0 (%s)" % [str(p1.scale) if p1 != null else "null"])
		_check(d2 != null and absf(d2.global_position.y - 364.8) < 1.0,
				"Derrick_02 спирається на палубу y=364.8 (%s)" % [str(d2.global_position.y) if d2 != null else "null"])
		var col_node := inst.find_child("MapColliders", true, false)
		var slab_ok := false
		if col_node != null:
			for ch in col_node.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape is BoxShape3D:
					var bs := ((ch as CollisionShape3D).shape as BoxShape3D).size
					if bs.x > 400.0 and bs.y < 20.0 and bs.z > 100.0:
						slab_ok = true
						break
		_check(slab_ok, "MapColliders deck_slab горизонтальний (x>400, y<20, z>100)")
	level.queue_free()
	for _f in range(3):
		await get_tree().process_frame
	print("[MAT-TEST] failures=", _fails)
	get_tree().quit(0 if _fails == 0 else 1)
