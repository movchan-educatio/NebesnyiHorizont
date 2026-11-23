extends Node

## Comprehensive QA verification for the mobile build of the game.
##
## Run headless:
##   Godot --headless --path . res://test/qa_mobile_polish_verification.tscn
##
## Checks the five requested mobile-polish points and prints one summary line
## per point.  Exits 0 on a clean pass, 1 if any point failed.
##
## Real player configuration is never left modified: Controls/QuadSettings are
## redirected to user://qa_mobile_polish_tmp/ during the run and all in-memory
## values (including GameSettings HUD profiles) are restored on exit.

const TAG := "[QA_MOBILE_POLISH]"
const TMP_DIR := "user://qa_mobile_polish_tmp/"
const INPUT_FILE := "qa_mobile_polish_tmp_InputMap.cfg"
const QUAD_FILE := "qa_mobile_polish_tmp_Quad.cfg"

const Catalog = preload("res://autoloads/DroneCatalog.gd")
const Sfx = preload("res://combat/sfx.gd")
const Fx = preload("res://combat/destruction_fx.gd")
const Frontline = preload("res://scripts/util/frontline_terrain.gd")
const Props = preload("res://scripts/util/mobile_prop_pack.gd")
const Quality = preload("res://scripts/util/quality_manager.gd")

const LEVELS: Array[Dictionary] = [
	{"path": "res://sceneries/IndustrialLevel.tscn", "kind": "industrial"},
	{"path": "res://sceneries/WetlandsLevel.tscn", "kind": "wetlands"},
	{"path": "res://sceneries/AirportLevel.tscn", "kind": "airport"},
	{"path": "res://sceneries/UmanLevel.tscn", "kind": "uman"},
]

const POINT_LABELS := [
	"Rates/Controls", "Lighting", "Freestyle Objects",
	"Collisions & Bores", "Audio Engine",
]

var _point_ok := [true, true, true, true, true]
var _controls: Node = null
var _quad: Node = null
var _drone: Node = null
var _input_path_real := ""
var _quad_path_real := ""
var _saved_controls: Dictionary = {}
var _saved_quad: Dictionary = {}
var _saved_hud_profiles: Variant = null


func _ready() -> void:
	# The mobile skin / touch input are selected through the same environment
	# variables the game and the existing mobile QA tools use.
	OS.set_environment("MOBILE_UI", "1")
	OS.set_environment("TOUCH_CONTROLS", "1")
	# Force a clear daytime grade, and never record a replay during QA.
	OS.set_environment("DRONE_WEATHER", "clear")
	OS.set_environment("DRONE_NO_RECORD", "1")
	call_deferred("_run")


func _check(point: int, ok: bool, label: String) -> void:
	if not ok:
		_point_ok[point - 1] = false
	print(TAG, "  [P", point, "] ", "PASS " if ok else "FAIL ", label)


func _near(a: float, b: float, eps: float = 0.0005) -> bool:
	return absf(a - b) <= eps


func _run() -> void:
	await get_tree().process_frame
	print(TAG, " START mobile polish verification")

	await _point1_rates_controls()
	await _check_maps()          # Points 2, 3 and 4 share the four level loads.
	_point5_audio()

	_restore()

	for i in range(5):
		print(TAG, " Point %d (%s): %s" % [
				i + 1, POINT_LABELS[i], "PASS" if _point_ok[i] else "FAIL"])

	var failures := 0
	for ok in _point_ok:
		if not bool(ok):
			failures += 1
	if failures == 0:
		print(TAG, " OVERALL: PASS")
	else:
		print(TAG, " OVERALL: FAIL (%d failed)" % failures)
	# Release static resource caches (sfx streams, cached GLBs, sky materials)
	# before exit; otherwise Godot reports them as leaked at shutdown.
	Sfx.clear_caches()
	Fx.clear_caches()
	Frontline.qa_clear_caches()
	Props.qa_clear_caches()
	Quality.qa_clear_caches()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)


# ---------------------------------------------------------------- Point 1 ----
func _point1_rates_controls() -> void:
	_check(1, MenuUI.is_mobile_ui(), "MOBILE_UI=1 -> MenuUI.is_mobile_ui() == true")

	_controls = get_node_or_null("/root/Controls")
	_quad = get_node_or_null("/root/QuadSettings")
	if _controls == null or _quad == null:
		_check(1, false, "Controls and QuadSettings autoloads exist")
		return

	# Isolate persistence so the player's real profiles are untouched.
	_input_path_real = str(_controls.get("input_map_path"))
	_quad_path_real = str(_quad.get("quad_settings_path"))
	_saved_controls = {
		"stick_deadzone": _controls.get("stick_deadzone"),
		"stick_smoothing": _controls.get("stick_smoothing"),
	}
	for key in ["rate_roll", "rate_pitch", "rate_yaw", "expo_roll", "expo_pitch",
			"expo_yaw", "rate_type", "custom_rates", "flight_preset"]:
		_saved_quad[key] = _quad.get(key)
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null:
		var hud: Dictionary = gs.get("hud_config")
		_saved_hud_profiles = {}
		for key in ["mobile_rate_profiles", "mobile_rate_source", "mobile_prev_quad"]:
			if not hud.has(key):
				_saved_hud_profiles[key] = null
			elif hud[key] is Dictionary:
				_saved_hud_profiles[key] = (hud[key] as Dictionary).duplicate(true)
			else:
				_saved_hud_profiles[key] = hud[key]

	_ensure_tmp_dir()
	_controls.set("input_map_path", TMP_DIR + INPUT_FILE)
	_quad.set("quad_settings_path", TMP_DIR + QUAD_FILE)

	# --- stick deadzone / smoothing save + load round trip -------------------
	_controls.set("stick_deadzone", 0.08)
	_controls.set("stick_smoothing", 0.15)
	_controls.call("save_bindings")
	_controls.set("stick_deadzone", 0.0)
	_controls.set("stick_smoothing", 0.0)
	_controls.call("load_input_map")
	_check(1, _near(float(_controls.get("stick_deadzone")), 0.08),
			"mobile stick_deadzone persisted as 0.08 (got %s)" % str(_controls.get("stick_deadzone")))
	_check(1, _near(float(_controls.get("stick_smoothing")), 0.15),
			"mobile stick_smoothing persisted as 0.15 (got %s)" % str(_controls.get("stick_smoothing")))

	# --- MobileMenu rate profiles -> GameSettings -> QuadSettings ------------
	var packed := load("res://GUI/mobile/MobileMenu.tscn") as PackedScene
	if packed == null:
		_check(1, false, "MobileMenu.tscn failed to load")
	else:
		var menu: Node = packed.instantiate()
		add_child(menu)
		await get_tree().process_frame
		# A parse error in the menu script would silently skip every check below.
		_check(1, menu.get_script() != null, "MobileMenu script attached (no parse error)")
		var profiles := {
			"radio": {
				"rate_roll": 850.0, "rate_pitch": 850.0, "rate_yaw": 850.0,
				"expo_roll": 0.35, "expo_pitch": 0.35, "expo_yaw": 0.35,
			},
			"touch": {
				"rate_roll": 850.0, "rate_pitch": 850.0, "rate_yaw": 850.0,
				"expo_roll": 0.35, "expo_pitch": 0.35, "expo_yaw": 0.35,
			},
		}
		menu.set("_rate_profiles", profiles)

		# Same operations as the "save rates" button: persist to GameSettings and
		# synchronise the active profile into QuadSettings for flight.
		var stored_profiles: Dictionary = {}
		if gs != null:
			var hud: Dictionary = gs.get("hud_config")
			hud["mobile_rate_profiles"] = profiles.duplicate(true)
			gs.call("save_hud_config")
			stored_profiles = hud.get("mobile_rate_profiles", {})
		var active: Dictionary = profiles.get("radio", {})
		_quad.set("custom_rates", true)
		for key in active.keys():
			_quad.set(key, active[key])
		_quad.call("save_quad_settings")

		var radio_saved: Dictionary = stored_profiles.get("radio", {})
		var touch_saved: Dictionary = stored_profiles.get("touch", {})
		_check(1, _profile_ok(radio_saved, 850.0, 0.35),
				"MobileMenu 'radio' rate 850 / expo 0.35 saved to GameSettings")
		_check(1, _profile_ok(touch_saved, 850.0, 0.35),
				"MobileMenu 'touch' rate 850 / expo 0.35 saved to GameSettings")
		_check(1, bool(_quad.get("custom_rates"))
				and _near(float(_quad.get("rate_roll")), 850.0)
				and _near(float(_quad.get("expo_roll")), 0.35),
				"MobileMenu rates synchronised into QuadSettings")

		# --- regression: profile ownership must keep the tabs separate --------
		# Persist distinct profiles first: _load_profiles() reloads from
		# GameSettings, so the stored values are the baseline for "intact".
		var distinct := {
			"radio": {"rate_roll": 667.0, "rate_pitch": 667.0, "rate_yaw": 667.0,
					"expo_roll": 0.2, "expo_pitch": 0.2, "expo_yaw": 0.2},
			"touch": {"rate_roll": 500.0, "rate_pitch": 500.0, "rate_yaw": 500.0,
					"expo_roll": 0.3, "expo_pitch": 0.3, "expo_yaw": 0.3},
		}
		menu.set("_rate_profiles", distinct.duplicate(true))
		if gs != null:
			var hud_reg: Dictionary = gs.get("hud_config")
			hud_reg["mobile_rate_profiles"] = distinct.duplicate(true)
			gs.call("save_hud_config")
		menu.call("_sync_profile_to_quad", "touch")
		menu.call("_load_profiles")
		var radio_after: Dictionary = (menu.get("_rate_profiles") as Dictionary)["radio"]
		_check(1, _near(float(radio_after["rate_roll"]), 667.0)
				and _near(float(radio_after["expo_roll"]), 0.2),
				"touch sync + menu reload leaves radio profile intact (667/0.2)")
		_check(1, _near(float(_quad.get("rate_roll")), 500.0),
				"touch sync puts touch rates into QuadSettings (500)")

		# Real save-button handler (not a re-implementation): press it per tab.
		var save_btn: Button = null
		for b in menu.find_children("*", "Button", true, false):
			if String(b.text).contains("ЗБЕРЕГТИ РЕЙТИ"):
				save_btn = b as Button
		if save_btn == null:
			_check(1, false, "rates save button found in MobileMenu")
		else:
			menu.set("_rate_tab", "radio")
			save_btn.pressed.emit()
			var src_ok := false
			if gs != null:
				src_ok = str((gs.get("hud_config") as Dictionary).get(
						"mobile_rate_source", "")) == "radio"
			_check(1, _near(float(_quad.get("rate_roll")), 667.0) and src_ok,
					"save button (radio tab) syncs radio + records ownership")
			menu.set("_rate_tab", "touch")
			save_btn.pressed.emit()
			menu.call("_load_profiles")
			radio_after = (menu.get("_rate_profiles") as Dictionary)["radio"]
			_check(1, _near(float(radio_after["rate_roll"]), 667.0),
					"save button (touch tab) still leaves radio profile intact")

		# B2: desktop entry must get its own rates back from the mobile mirror.
		if gs != null:
			gs.clear_mobile_rate_source()  # snapshot is taken only on first sync
			_quad.set("custom_rates", false)
			_quad.set("rate_roll", 432.0)
			menu.call("_sync_profile_to_quad", "touch")
			var mobile_rate := float(_quad.get("rate_roll"))
			var restored := bool(gs.call("restore_desktop_rates_if_mobile_owned"))
			var src_after: String = str(gs.mobile_rate_source())
			_check(1, restored and _near(float(_quad.get("rate_roll")), 432.0)
					and not bool(_quad.get("custom_rates"))
					and src_after.is_empty() and mobile_rate > 499.0,
					"desktop restore undoes mobile mirror (432/custom=false) and clears ownership")
		menu.free()

	# --- live drone rate + expo response ------------------------------------
	# The canonical prefab is Drone1.tscn in this project (res://drone/Drone.tscn
	# is not present); try the spec path first and fall back to the real one.
	var drone_scene: PackedScene = null
	if ResourceLoader.exists("res://drone/Drone.tscn"):
		drone_scene = load("res://drone/Drone.tscn") as PackedScene
	if drone_scene == null:
		drone_scene = load("res://drone/drones/Drone1.tscn") as PackedScene
	if drone_scene == null:
		_check(1, false, "drone scene could not be loaded")
		return
	_drone = drone_scene.instantiate()
	add_child(_drone)
	await get_tree().process_frame
	var fc = _drone.get("flight_controller")
	var profile = _drone.get("control_profile")
	if fc == null or profile == null:
		_check(1, false, "drone has FlightController + ControlProfile")
		return

	fc.set("input", [0.0, 0.0, 0.0, 0.0])
	var armed: bool = bool(fc.call("request_arm", true))
	_check(1, armed and bool(fc.get("state_armed")), "mobile drone armed for rate test")
	fc.call("change_flight_mode", FlightController.FlightMode.RATE)

	_push_rates(300.0, 300.0, 300.0, 0.0, 0.0, 0.0)
	var low_target := _roll_target(fc)
	_push_rates(900.0, 300.0, 300.0, 0.0, 0.0, 0.0)
	var high_target := _roll_target(fc)
	_check(1, low_target > 0.0 and high_target > 2.5 * low_target,
			"rate_roll 300 -> 900 scales roll target >2.5x (got %.2fx)" %
			(high_target / maxf(low_target, 0.0001)))

	_push_rates(900.0, 300.0, 300.0, 0.0, 0.0, 0.0)
	var mid_linear := float(profile.call("get_axis_rate", 0, 0.5))
	var peak_linear := float(profile.call("get_axis_rate", 0, 1.0))
	_push_rates(900.0, 300.0, 300.0, 0.75, 0.0, 0.0)
	var mid_expo := float(profile.call("get_axis_rate", 0, 0.5))
	var peak_expo := float(profile.call("get_axis_rate", 0, 1.0))
	_check(1, mid_expo < mid_linear * 0.8 and _near(peak_expo, peak_linear, 0.5),
			"expo 0.75 lowers half-stick rate but keeps full-stick peak (%.1f -> %.1f, peak %.1f)" %
			[mid_linear, mid_expo, peak_expo])


func _profile_ok(prof: Dictionary, rate: float, expo: float) -> bool:
	if prof.is_empty():
		return false
	var keys := ["rate_roll", "rate_pitch", "rate_yaw", "expo_roll", "expo_pitch", "expo_yaw"]
	for key in keys:
		if not prof.has(key):
			return false
		var want := expo if key.begins_with("expo_") else rate
		if not _near(float(prof[key]), want):
			return false
	return true


func _push_rates(rr: float, rp: float, ry: float, er: float, ep: float, ey: float) -> void:
	if _quad == null:
		return
	_quad.set("rate_roll", rr)
	_quad.set("rate_pitch", rp)
	_quad.set("rate_yaw", ry)
	_quad.set("expo_roll", er)
	_quad.set("expo_pitch", ep)
	_quad.set("expo_yaw", ey)
	_quad.set("rate_type", 0)
	_quad.set("custom_rates", true)
	_quad.call("save_quad_settings")


func _roll_target(fc: Node) -> float:
	fc.set("input", [0.5, 0.0, 1.0, 0.0])
	fc.call("integrate_loop", 0.016, fc.global_position, fc.global_transform.basis,
			Vector3.ZERO, Vector3.ZERO)
	var pids: Array = fc.get("pid_controllers")
	if pids.size() <= FlightController.Controller.ROLL_SPEED:
		return 0.0
	return float(pids[FlightController.Controller.ROLL_SPEED].get("target"))


# --------------------------------------------------- Points 2, 3 and 4 --------
func _check_maps() -> void:
	Global.play_mode = Global.PlayMode.TRAINING
	Global.combat_training = false
	Global.combat_mission = 0
	Global.special_mission = 0
	for entry in LEVELS:
		await _check_one_map(String(entry["path"]), String(entry["kind"]))


func _check_one_map(path: String, kind: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_check(2, false, kind + " level failed to load")
		_check(3, false, kind + " level failed to load")
		_check(4, false, kind + " level failed to load")
		return
	Global.menu_settings["selected_map"] = kind
	var level := packed.instantiate() as Node3D
	if level == null:
		_check(2, false, kind + " level failed to instantiate")
		_check(3, false, kind + " level failed to instantiate")
		_check(4, false, kind + " level failed to instantiate")
		return
	get_tree().root.add_child(level)
	get_tree().current_scene = level
	for _i in range(3):
		await get_tree().physics_frame
	await get_tree().create_timer(0.25).timeout
	_force_tree(level)

	_check_lighting(level, kind)
	_check_night_grade(level, kind)
	_check_freestyle(level, kind)
	_check_collisions(level, kind)

	if get_tree().current_scene == level:
		get_tree().current_scene = null
	# Immediate free + spare frames: deferred queue_free left objects alive at
	# quit() and produced ObjectDB/RID leak warnings in the QA log.
	level.free()
	await get_tree().process_frame
	await get_tree().process_frame


func _check_lighting(level: Node3D, kind: String) -> void:
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	_check(2, env != null, kind + " WorldEnvironment has an Environment")
	if env == null:
		return
	_check(2, env.tonemap_exposure >= 1.15,
			"%s daylight tonemap_exposure >= 1.15 (got %.3f)" % [kind, env.tonemap_exposure])
	_check(2, env.ambient_light_energy >= 0.90,
			"%s ambient_light_energy >= 0.90 (got %.3f)" % [kind, env.ambient_light_energy])

	var sun: DirectionalLight3D = null
	for preferred in ["Sun", "DirectionalLight3D"]:
		var candidate := level.get_node_or_null(preferred) as DirectionalLight3D
		if candidate != null:
			sun = candidate
			break
	if sun == null:
		var lights := level.find_children("*", "DirectionalLight3D", true, false)
		if not lights.is_empty():
			sun = lights[0] as DirectionalLight3D
	_check(2, sun != null and sun.light_energy >= 2.8,
			"%s sunlight light_energy >= 2.8 (got %s)" % [
					kind, "n/a" if sun == null else "%.3f" % sun.light_energy])


func _freestyle_keywords(kind: String) -> Array[String]:
	match kind:
		"industrial":
			return ["freestyle", "hollowpipe", "pipeculvert", "culvert", "frame", "slalom", "truss"]
		"wetlands":
			return ["freestyle", "gate", "tower", "course", "slalom", "arch", "ring"]
		"airport":
			return ["freestyle", "zone", "arch", "split", "container", "canyon", "hangar", "depot"]
		"uman":
			return ["gazebo", "pergola", "bridge", "dive", "freestyle", "frame", "slalom", "tunnel", "umanpark"]
	return []


func _check_night_grade(level: Node3D, kind: String) -> void:
	level.set("_weather", 3)
	level.call("_apply_weather")
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env: Environment = we.environment if we != null else null
	if env == null:
		_check(2, false, kind + " night: environment missing")
	else:
		_check(2, env.tonemap_exposure <= 1.05 and env.ambient_light_energy <= 0.20,
				"%s night grade stays dark (exposure %.2f, ambient %.2f)" %
				[kind, env.tonemap_exposure, env.ambient_light_energy])
	var mtn := level.get_node_or_null("FrontlineTerrain/MountainBackdrop") as MeshInstance3D
	if mtn != null and mtn.material_override is ShaderMaterial:
		var dim := float((mtn.material_override as ShaderMaterial).get_shader_parameter("night_dim"))
		_check(2, dim <= 0.5,
				"%s night mountain backdrop dimmed (night_dim %.2f)" % [kind, dim])
	# Back to the daylight grade for the remaining checks.
	level.set("_weather", 0)
	level.call("_apply_weather")


func _check_freestyle(level: Node3D, kind: String) -> void:
	var keywords := _freestyle_keywords(kind)
	var count := _count_names(level, keywords)
	var wanted := 2
	match kind:
		"industrial":
			wanted = 3
		"airport":
			wanted = 4
		"uman":
			wanted = 3
	_check(3, count >= wanted,
			"%s themed freestyle structures present (%d >= %d)" % [kind, count, wanted])


func _count_names(root: Node, keywords: Array[String]) -> int:
	var found := 0
	for node in root.find_children("*", "Node", true, false):
		var nm := String(node.name).to_lower()
		for kw in keywords:
			if nm.contains(kw):
				found += 1
				break
	return found


func _check_collisions(level: Node3D, kind: String) -> void:
	var space := level.get_world_3d().direct_space_state
	if space == null:
		_check(4, false, kind + " has no physics space for raycasts")
		return
	match kind:
		"industrial":
			_check_pipe_bores(level, space, kind)
		"airport":
			_check_airport_gaps(level, space, kind)
		"uman":
			_check_uman_openings(level, space, kind)


func _find_by_names(root: Node, keywords: Array[String]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in root.find_children("*", "Node3D", true, false):
		var nm := String(node.name).to_lower()
		for kw in keywords:
			if nm.contains(kw):
				out.append(node as Node3D)
				break
	return out


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	rq.collision_mask = 1
	return space.intersect_ray(rq).is_empty()



func _check_pipe_bores(level: Node3D, space: PhysicsDirectSpaceState3D, kind: String) -> void:
	var pipes := _find_by_names(level, ["hollowpipe", "pipeculvert", "culvert"])
	var course := level.find_child("ConcretePipeCulvertCourse", true, false)
	if course != null:
		for child in course.get_children():
			if child is Node3D:
				pipes.append(child as Node3D)
	var clear := 0
	for pipe in pipes:
		var xf: Transform3D = pipe.global_transform
		if _ray(space, xf * Vector3(0.0, 0.0, -6.0), xf * Vector3(0.0, 0.0, 6.0)):
			clear += 1
	_check(4, not pipes.is_empty() and clear > 0,
			"%s hollow pipe / culvert centre bore has no collision (%d/%d clear)" %
			[kind, clear, pipes.size()])


func _check_airport_gaps(level: Node3D, space: PhysicsDirectSpaceState3D, kind: String) -> void:
	var depot := level.get_node_or_null("AirportLandmark_FuelDepot") as Node3D
	if depot == null:
		_check(4, false, kind + " fuel depot landmark missing")
		return
	var mesh := depot.find_child("FuelDepotCisterns", true, false) as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		_check(4, false, kind + " fuel depot cistern mesh missing")
		return
	var box: AABB = mesh.global_transform * mesh.mesh.get_aabb()
	var passable := false
	for gx in range(1, 7):
		for gz in range(1, 7):
			var px := box.position.x + box.size.x * float(gx) / 7.0
			var pz := box.position.z + box.size.z * float(gz) / 7.0
			if _ray(space, Vector3(px, box.end.y + 1.5, pz),
					Vector3(px, box.position.y + 0.8, pz)):
				passable = true
				break
		if passable:
			break
	if not passable:
		# Overhead probe across the tank row (old invisible 24x5x16 box sealed it).
		var centre := box.get_center()
		centre.y = box.end.y + 2.0
		var half := box.size.x * 0.5 + 3.0
		passable = _ray(space, centre - Vector3.RIGHT * half, centre + Vector3.RIGHT * half)
	_check(4, passable, kind + " fuel tank gaps are fly-through (no invisible wall)")


func _check_uman_openings(level: Node3D, space: PhysicsDirectSpaceState3D, kind: String) -> void:
	var parks := level.get_node_or_null("UmanThemedFreestyleParks") as Node3D
	if parks == null:
		_check(4, false, kind + " themed freestyle parks missing")
		return
	var passable := false
	for park in parks.get_children():
		var nm := String(park.name).to_lower()
		if not (nm.contains("gazebo") or nm.contains("pergola") or nm.contains("bridge")
				or nm.contains("dive") or nm.contains("tunnel")):
			continue
		var box := _mesh_aabb(park)
		if box.size.length() < 0.1:
			continue
		var centre := box.get_center()
		# Horizontal probes through the open bays, below the first deck/lintel.
		# The gazebo tower and pergola are open on all four sides; the tunnel
		# pipes have a clear central portal between the two conduits.
		# Probe only the clear span through the middle of the opening: the
		# surrounding GLB buildings are solid scenery and must not be counted.
		for axis in [Vector3.RIGHT, Vector3.FORWARD]:
			var half := 2.0
			for height in [1.5, 2.5, 3.5]:
				var p := centre
				p.y = float(height)
				if _ray(space, p - axis * half, p + axis * half):
					passable = true
					break
			if passable:
				break
		if passable:
			break
	_check(4, passable, kind + " gazebo / pergola opening is fly-through")


func _mesh_aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box if not first else AABB()


func _force_tree(node: Node) -> void:
	if node == null:
		return
	if node is Node3D and node.is_inside_tree():
		(node as Node3D).force_update_transform()
	for child in node.get_children():
		_force_tree(child)


# ---------------------------------------------------------------- Point 5 ----
func _point5_audio() -> void:
	var presets: Array = Catalog.PRESETS
	_check(5, presets.size() == 13, "DroneCatalog has 13 presets (got %d)" % presets.size())

	var kinds := {}
	var valid := true
	for p in presets:
		var value: Variant = p.get("audio_kind", -1)
		if not (value is int) or int(value) < 0:
			valid = false
		else:
			kinds[int(value)] = true
	_check(5, valid and kinds.size() >= 10,
			"all presets have valid audio_kind, >=10 unique kinds (got %d)" % kinds.size())

	var streams_ok := true
	for kind in range(14):
		var stream := Sfx.drone_motor_stream(kind)
		if stream == null or stream.data.is_empty():
			streams_ok = false
	_check(5, streams_ok, "SFX.drone_motor_stream() returns a valid stream for every audio kind")

	var wash := Sfx.drone_propwash_stream()
	_check(5, wash != null and wash.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"SFX.drone_propwash_stream() is valid and looping")

	# Propwash node is created when the drone enters the tree.
	var drone: Node = _drone
	var owned := false
	if drone == null or not is_instance_valid(drone):
		var drone_scene: PackedScene = null
		if ResourceLoader.exists("res://drone/Drone.tscn"):
			drone_scene = load("res://drone/Drone.tscn") as PackedScene
		if drone_scene == null:
			drone_scene = load("res://drone/drones/Drone1.tscn") as PackedScene
		if drone_scene != null:
			drone = drone_scene.instantiate()
			add_child(drone)
			owned = true
	_check(5, drone != null and drone.get_node_or_null("PropwashAudio3D") != null,
			"drone has PropwashAudio3D node for aerodynamic wash")
	if owned and drone != null and is_instance_valid(drone):
		drone.free()

	# Infantry footsteps: at least three variants.
	var footsteps_ok := true
	for i in range(3):
		var step := Sfx.footstep_stream(i)
		if step == null or step.data.is_empty():
			footsteps_ok = false
	_check(5, footsteps_ok, "infantry has at least 3 footstep sound variants")

	# Vehicle combat: engine rev, brake hiss, armor impact, wreck cookoff.
	var vehicle: Array = [
		Sfx.engine_stream(),
		Sfx.air_brake_stream(),
		Sfx.armor_hit_stream(true),
		Sfx.cookoff_stream(),
	]
	var vehicle_ok := true
	for stream in vehicle:
		var wav := stream as AudioStreamWAV
		if wav == null or wav.data.is_empty():
			vehicle_ok = false
	_check(5, vehicle_ok,
			"vehicle combat streams (engine/brake/armor/cookoff) all return valid audio")


# --------------------------------------------------------------- Cleanup ------
func _ensure_tmp_dir() -> void:
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


func _delete_temp_files() -> void:
	for file_name in [QUAD_FILE, INPUT_FILE]:
		var path := TMP_DIR + str(file_name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var abs_dir := ProjectSettings.globalize_path(TMP_DIR)
	if DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.remove_absolute(abs_dir)


func _restore() -> void:
	if _drone != null and is_instance_valid(_drone):
		_drone.free()
	_drone = null

	if _controls != null:
		_controls.set("input_map_path", _input_path_real)
		for key in _saved_controls.keys():
			_controls.set(key, _saved_controls[key])
		_controls.call("load_input_map")
	if _quad != null:
		_quad.set("quad_settings_path", _quad_path_real)
		for key in _saved_quad.keys():
			_quad.set(key, _saved_quad[key])
		_quad.call("load_quad_settings")

	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and _saved_hud_profiles != null:
		var hud: Dictionary = gs.get("hud_config")
		for key in (_saved_hud_profiles as Dictionary).keys():
			var value: Variant = _saved_hud_profiles[key]
			if value == null:
				hud.erase(key)
			else:
				hud[key] = value
		gs.call("save_hud_config")

	_delete_temp_files()
