extends Node3D


var pause_menu = preload("res://GUI/PauseMenu.tscn")
const VisualEnhancer = preload("res://scripts/util/visual_enhancer.gd")

var cameras := []
var camera_index := 0
var camera: Camera3D = null

@onready var drone := $Drone
@onready var radio_controller := $RadioController

var tracks := []


func _ready() -> void:
	# Standardize lighting, ACES tonemap, SSAO, soft shadows, ground shader, and SuperView FOV
	VisualEnhancer.apply_to_scene(self)

	# Apply the saved radio/gamepad mapping in every level, not only BigLevel;
	# without this a direct scene launch kept the project's default bindings.
	Controls.load_input_map()
	var radio := get_node_or_null("RadioController")
	if radio != null and radio.has_method("refresh_bindings"):
		radio.call("refresh_bindings")

	if drone != null:
		DroneCatalog.apply_to_drone(drone, Global.drone_preset)

	cameras = get_cameras(self)
	# First-person only: keep the drone's FPV camera and discard every
	# external chase/orbit/front camera.  The cockpit view is the game.
	var fpv_only: Array = []
	for c in cameras:
		if c != null and c.name == "FPVCamera":
			fpv_only.append(c)
	if fpv_only.is_empty() and not cameras.is_empty():
		fpv_only.append(cameras[0])
	cameras = fpv_only
	if not cameras.is_empty():
		camera_index = 0
		camera = cameras[0]
		change_camera()
	
	for c in get_children():
		if c is Track:
			tracks.append(c)
	var _discard = Global.connect("game_mode_changed", Callable(self, "_on_game_mode_changed"))
	
	if drone != null:
		_discard = drone.connect("respawned", Callable(self, "_on_drone_reset"))
	
	var pause_canvas := CanvasLayer.new()
	pause_canvas.name = "PauseCanvasLayer"
	pause_canvas.layer = 100
	pause_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_canvas)

	pause_menu = pause_menu.instantiate()
	pause_canvas.add_child(pause_menu)
	pause_menu.visible = false
	_discard = pause_menu.connect("resumed", Callable(self, "_on_resume"))
	_discard = pause_menu.connect("menu", Callable(self, "_on_return_to_menu"))

	# Touch sticks are available in every level, not only BigLevel.  The
	# overlay also owns the on-screen ARM button, so City/Course levels get
	# the same phone control scheme.
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		touch.call("begin", get_instance_id())


func _exit_tree() -> void:
	if Global != null and Global.game_mode_changed.is_connected(_on_game_mode_changed):
		Global.game_mode_changed.disconnect(_on_game_mode_changed)
	var touch := get_node_or_null("/root/TouchControls")
	if touch != null:
		touch.call("end", get_instance_id())


func _input(event: InputEvent) -> void:
	if Controls.is_action_edge(event, "respawn"):
		request_respawn()
		get_viewport().set_input_as_handled()

	# Keep arming in the common level handler so training, city and BigLevel all
	# react to the same keyboard, button and synthetic axis-switch events.
	var key_event := event as InputEventKey
	var space_pressed: bool = key_event != null and key_event.pressed \
			and not key_event.echo and (key_event.keycode == KEY_SPACE or key_event.physical_keycode == KEY_SPACE)
	var toggle_arm: bool = space_pressed or Controls.is_action_edge(event, "toggle_arm")
	var arm_pressed: bool = event.is_action_pressed("arm")
	var arm_released: bool = event.is_action_released("arm")
	var active_drone := get_node_or_null("Drone") as Drone
	if active_drone != null:
		if toggle_arm:
			if active_drone.flight_controller.state_armed:
				active_drone.flight_controller.request_disarm()
			else:
				active_drone.flight_controller.request_arm()
			get_viewport().set_input_as_handled()
		elif arm_pressed:
			active_drone.flight_controller.request_arm()
			get_viewport().set_input_as_handled()
		elif arm_released:
			active_drone.flight_controller.request_disarm()
			get_viewport().set_input_as_handled()
	
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var ke := event as InputEventKey
		if camera != null and camera.name == "FPVCamera":
			if ke.keycode == KEY_V:
				_adjust_camera_tilt(2.5)
				get_viewport().set_input_as_handled()
				return
			elif ke.keycode == KEY_C and not ke.ctrl_pressed and not ke.alt_pressed:
				_adjust_camera_tilt(-2.5)
				get_viewport().set_input_as_handled()
				return
	
	if event.is_action("pause_menu") and event.is_pressed() and not event.is_echo():
		if !get_tree().paused:
			get_tree().paused = true
			if pause_menu.has_method("show_menu"):
				pause_menu.show_menu(true)
			else:
				pause_menu.visible = true
			if pause_menu.has_method("_set_drone_frozen"):
				pause_menu._set_drone_frozen(true)
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif pause_menu.visible and pause_menu.can_resume:
			pause_menu.emit_signal("resumed")


func _adjust_camera_tilt(delta_deg: float) -> void:
	var fpv := camera as Camera3D
	if fpv == null or fpv.name != "FPVCamera":
		return
	var current_tilt: float = -fpv.rotation_degrees.x
	var new_tilt: float = clampf(current_tilt + delta_deg, 0.0, 60.0)
	fpv.rotation_degrees.x = -new_tilt
	_on_camera_tilt_changed(new_tilt)


func _on_camera_tilt_changed(_tilt_deg: float) -> void:
	pass


func get_cameras(node: Node) -> Array:
	var cams := []
	for child in node.get_children():
		if child is Camera3D:
			cams.append(child)
		if not child is FPVCamera:
			cams += get_cameras(child)
	return cams


func change_camera() -> void:
	camera.visible = false
	camera.current = false
	if camera is FPVCamera and Graphics.graphics_settings["fisheye_mode"] != Graphics.FisheyeMode.OFF:
		camera.render_quad.visible = false
	camera = cameras[camera_index]
	camera.current = true
	if camera is FPVCamera and Graphics.graphics_settings["fisheye_mode"] != Graphics.FisheyeMode.OFF:
		camera.render_quad.visible = true
	camera.visible = true
	
	var is_fpv := (camera.name == "FPVCamera")
	_configure_drone_visuals_for_camera(is_fpv)
	
	if is_fpv:
		drone.hud.visible = true
	else:
		drone.hud.visible = false


func _configure_drone_visuals_for_camera(is_fpv: bool) -> void:
	if drone == null:
		return
	var p := DroneCatalog.preset(Global.drone_preset)
	var fpv := drone.get_node_or_null("FPVCamera") as Camera3D
	if fpv != null:
		fpv.near = float(p.get("fpv_cam_near", 0.05))
		var cam_pos = p.get("fpv_cam_pos", null)
		if cam_pos is Vector3:
			fpv.position = cam_pos
		var cam_pitch = p.get("fpv_cam_pitch", null)
		if cam_pitch != null:
			fpv.transform.basis = Basis.IDENTITY.rotated(Vector3.RIGHT, deg_to_rad(float(cam_pitch)))
	var model_root := drone.get_node_or_null("DroneModel") as Node3D
	if model_root != null:
		var show_airframe := bool(p.get("fpv_show_airframe", false))
		var hide_props := bool(p.get("fpv_hide_props", false))
		var hide_whole: bool = (bool(p.get("fpv_hide_model", false)) and not show_airframe) \
				or bool(p.get("heavy_bomber", false))
		if hide_whole:
			model_root.visible = not is_fpv
		else:
			model_root.visible = true
			_hide_props_recursive(model_root, is_fpv and hide_props, show_airframe and not hide_props)
			if not (is_fpv and show_airframe):
				_hide_fpv_obstructions_recursive(model_root, model_root, fpv, is_fpv)
			else:
				_hide_fpv_obstructions_recursive(model_root, model_root, fpv, false)


func _hide_props_recursive(node: Node, hide_props: bool, keep_front: bool = false) -> void:
	if node == null:
		return
	var lower := String(node.name).to_lower()
	if node.is_in_group("drone_prop_pivot") or lower.contains("propeller") \
			or node.name == "PropellerAssembly":
		if node is Node3D:
			var front := lower.contains("fl") or lower.contains("fr") \
					or lower.ends_with("_0") or lower.ends_with("_1")
			(node as Node3D).visible = (not hide_props) or (keep_front and front)
	for child in node.get_children():
		_hide_props_recursive(child, hide_props, keep_front)


func _hide_fpv_obstructions_recursive(node: Node, model_root: Node3D, fpv: Camera3D, is_fpv: bool) -> void:
	if node == null:
		return
	var lower := String(node.name).to_lower()
	var is_obstruction := lower.contains("camera") or lower.contains("gimbal") \
			or lower.contains("lens") or lower.contains("warhead") \
			or lower.contains("payload") or lower.contains("fuze") \
			or lower.contains("bomb") or lower.contains("battery") \
			or lower.contains("lipo") or lower.contains("antenna") \
			or lower.contains("bumper") or lower.contains("skid")
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if not is_fpv:
			if mi.has_meta("_fpv_culled"):
				mi.visible = true
				mi.remove_meta("_fpv_culled")
		else:
			var near_cam := false
			var drone_3d := drone as Node3D
			if fpv != null and drone_3d != null:
				var inv_drone: Transform3D = drone_3d.global_transform.affine_inverse() if drone_3d.is_inside_tree() else Transform3D.IDENTITY
				var cam_local: Vector3 = fpv.position
				var mi_local_xform: Transform3D = (inv_drone * mi.global_transform) if mi.is_inside_tree() else mi.transform
				var box: AABB = mi_local_xform * mi.get_aabb()
				var center: Vector3 = box.get_center()
				var dist: float = center.distance_to(cam_local)
				# Anything sitting directly inside or slightly forward of the lens
				# blocks center-screen sightlines and touch controls.
				near_cam = dist < 0.14 or (center.z < cam_local.z + 0.04 and absf(center.x - cam_local.x) < 0.08 and absf(center.y - cam_local.y) < 0.08)
			if is_obstruction or near_cam:
				mi.visible = false
				mi.set_meta("_fpv_culled", true)
	for child in node.get_children():
		_hide_fpv_obstructions_recursive(child, model_root, fpv, is_fpv)


## Respawn entry point. Subclasses may extend it (BigLevel re-arms the drone).
func request_respawn() -> void:
	if drone != null:
		drone._on_reset()


func _on_drone_reset() -> void:
	for track in tracks:
		track.reset_track()
	if Global.game_mode == Global.GameMode.RACE and Global.active_track:
		Global.active_track.initialize_replay(drone)
		Global.active_track.load_replays()
		Global.active_track.start_countdown()


func _on_resume() -> void:
	if pause_menu.can_resume:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		pause_menu.visible = false
		get_tree().paused = false
		if pause_menu.has_method("_set_drone_frozen"):
			pause_menu._set_drone_frozen(false)


## City/Course sit on the shared flat Ground plane.  VisualEnhancer replaces
## its material with the huge-wavelength grass shader, which reads as a flat
## green sheet at street level.  Use a tiled asphalt texture instead.
func use_urban_ground() -> void:
	var ground := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if ground == null:
		return
	var ft = load("res://scripts/util/frontline_terrain.gd")
	if ft != null:
		ground.material_override = ft._pbr("asphalt", Color(0.42, 0.42, 0.40), 0.10)


func _on_return_to_menu() -> void:
	get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var target_menu := "res://GUI/mobile/MobileMenu.tscn" if MenuUI.is_mobile_ui() else "res://GUI/MainMenu.tscn"
	get_tree().change_scene_to_file(target_menu)


func _on_game_mode_changed(mode: int) -> void:
	if mode == Global.GameMode.FREE or tracks.is_empty():
		if Global.active_track:
			Global.active_track.stop_race()
			Global.active_track.stop_recording_replay()
		Global.active_track = null
	elif mode == Global.GameMode.RACE:
		Global.active_track = get_closest_track()
		drone.reset()


func get_closest_track() -> Track:
	var has_launchpad := false
	var closest_idx := 0
	var new_idx := -1
	var closest_distance := 9999.9
	var new_distance := 0.0
	if tracks.is_empty():
		return null
	for track in tracks:
		new_idx += 1
		if not track.has_launchpad:
			continue
		has_launchpad = true
		for launch_pos in track.launch_areas:
			new_distance = (launch_pos.global_transform.origin - drone.global_transform.origin).length()
			if new_distance < closest_distance:
				closest_distance = new_distance
				closest_idx = new_idx
	if has_launchpad:
		return tracks[closest_idx]
	return null
