## QA-only: renders any Control scene inside an offscreen SubViewport and saves
## exact-size PNGs.  This avoids the root-viewport capture crash on menu scenes
## and the Windows DPI crop that affects PrintWindow screenshots.
##
## Env:
##   UI_SHOT_SCENE   res:// path to a Control scene
##   UI_SHOT_SIZE    WIDTHxHEIGHT (e.g. 1280x590)
##   UI_SHOT_PATH    output PNG; when UI_SHOT_METHODS is set this is a folder
##   UI_SHOT_METHODS comma-separated method calls, e.g. "show_main:main,show_play:play"
##   UI_SHOT_WAIT    seconds to wait after each method (default 0.35)
extends Node

var _viewport: SubViewport
var _screen: Control


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_path := OS.get_environment("UI_SHOT_SCENE")
	var size_text := OS.get_environment("UI_SHOT_SIZE")
	var out_path := OS.get_environment("UI_SHOT_PATH")
	if scene_path.is_empty() or size_text.is_empty() or out_path.is_empty():
		print("[UISHOT] missing UI_SHOT_SCENE/SIZE/PATH")
		get_tree().quit(2)
		return
	var size := _parse_size(size_text)
	if size.x < 32 or size.y < 32:
		print("[UISHOT] bad size ", size_text)
		get_tree().quit(2)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		print("[UISHOT] cannot load ", scene_path)
		get_tree().quit(2)
		return
	_viewport = SubViewport.new()
	_viewport.name = "UiShotViewport"
	_viewport.size = size
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.handle_input_locally = false
	add_child(_viewport)
	_screen = packed.instantiate() as Control
	if _screen == null:
		print("[UISHOT] scene root is not a Control")
		get_tree().quit(2)
		return
	_viewport.add_child(_screen)
	await get_tree().create_timer(0.8).timeout
	await get_tree().process_frame
	await get_tree().process_frame

	var methods := OS.get_environment("UI_SHOT_METHODS")
	var wait_time := maxf(0.15, float(OS.get_environment("UI_SHOT_WAIT")) if not OS.get_environment("UI_SHOT_WAIT").is_empty() else 0.35)
	if methods.is_empty():
		await _capture(out_path)
	else:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path))
		for spec in methods.split(","):
			var parts := spec.split(":", true, 1)
			if parts.size() < 2:
				continue
			var method_name := parts[0]
			var file_stem := parts[1]
			if _screen.has_method(method_name):
				_screen.call(method_name)
			else:
				print("[UISHOT] no method ", method_name)
			await get_tree().create_timer(wait_time).timeout
			await get_tree().process_frame
			await _capture(out_path.path_join(file_stem + ".png"))
	get_tree().quit()


func _parse_size(text: String) -> Vector2i:
	var parts := text.to_lower().split("x")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	if image == null:
		print("[UISHOT] no image for ", path)
		return
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err := image.save_png(path)
	print("[UISHOT] ", path, " size=", image.get_size(), " err=", err)
