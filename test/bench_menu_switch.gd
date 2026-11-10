extends Node

## Measures the main-menu Next/Previous path with the threaded model cache.
## Run headless:
##   godot --headless --path . res://test/bench_menu_switch.tscn

var _menu: Control
var _max_frame_ms := 0.0
var _frames := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	Global.drone_preset = 0
	_menu = load("res://GUI/mobile/MobileMenu.tscn").instantiate()
	add_child(_menu)
	await get_tree().create_timer(1.0).timeout
	print("[MENUSWITCH] cache_before=", DroneCatalog._model_scene_cache.size())
	await get_tree().create_timer(5.0).timeout
	print("[MENUSWITCH] cache_after_prefetch=", DroneCatalog._model_scene_cache.size(),
			"/", DroneCatalog.count())
	# Warm the next/prev path and measure every frame while switching.
	var last := Time.get_ticks_usec()
	for i in range(8):
		_menu.call("_select_next_drone")
		for f in range(4):
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			_max_frame_ms = maxf(_max_frame_ms, (now - last) / 1000.0)
			last = now
			_frames += 1
		await get_tree().create_timer(0.12).timeout
		last = Time.get_ticks_usec()
	print("[MENUSWITCH] frames=", _frames, " max_frame_ms=%.1f" % _max_frame_ms)
	get_tree().quit()
