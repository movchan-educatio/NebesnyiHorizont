extends SceneTree


func _initialize() -> void:
	for p in ["res://Assets/maps/map_combat.glb",
			"res://Assets/vehicles/low_poly_t-72_tank_-_game_ready_anim.glb",
			"res://Assets/vehicles/apache_hecu_half-life.glb",
			"res://Assets/BinbunVFX_Vol2/ExplosionFX/effects/ground/vfx_ground_explosion_01.tscn"]:
		var t := Time.get_ticks_msec()
		var res = load(p)
		print("[LOADTEST] ", p, " -> ", Time.get_ticks_msec() - t, " ms ok=", res != null)
	quit()
