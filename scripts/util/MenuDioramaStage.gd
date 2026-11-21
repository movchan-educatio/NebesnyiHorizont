extends Node3D

## Modular Blender-sculpted 3D military backdrop diorama & interactive brass
## shell casing physics controller for drone showcase SubViewports.
##
## Attached directly to the preview SubViewport as a SIBLING of the drone
## model holder so drone AABB measurements, framing, and QA bounds tests stay
## completely isolated.

const GlbMaterialUtilsScript = preload("res://scripts/util/glb_material_utils.gd")

const DIR_ASSETS := "res://Assets/Drones/hangar_diorama/"
const GLB_CRATE_WOOD := DIR_ASSETS + "ammo_crate_wood.glb"
const GLB_AMMO_CAN := DIR_ASSETS + "ammo_can_m2a1.glb"
const GLB_PELICAN := DIR_ASSETS + "pelican_fpv_case.glb"
const GLB_SANDBAGS := DIR_ASSETS + "sandbag_cluster.glb"
const GLB_RADIO := DIR_ASSETS + "tactical_radio.glb"
const GLB_ORDNANCE := DIR_ASSETS + "ordnance_tube.glb"
const GLB_WORKBENCH := DIR_ASSETS + "workbench_deck.glb"
const GLB_SHELL := DIR_ASSETS + "brass_shell_casing.glb"

# Normalized dimensions exported by tools/blender_build_hangar_diorama.py
const BASE_SHELL_LEN := 0.072
const BASE_SHELL_RAD := 0.0092

# Turntable state machine for each shell casing
enum ShellState {
	ON_DECK = 0,
	FALLING = 1,
	ON_WORKBENCH = 2,
	RESPAWN_WAIT = 3,
	DROPPING_IN = 4,
}

static var _scene_cache: Dictionary = {}

var _top_y: float = -0.2045
var _pedestal_radius: float = 0.50
var _scale_k: float = 1.0
var _workbench_top_y: float = -0.250
var _workbench_center: Vector2 = Vector2.ZERO  # XZ offset in world space
var _workbench_basis_back: Vector2 = Vector2(0.0, -1.0)
var _workbench_basis_right: Vector2 = Vector2(1.0, 0.0)
var _workbench_half_extents: Vector2 = Vector2(0.90, 0.70)  # (half_right, half_back)
var _orbit_360: bool = false

var _props_root: Node3D = null
var _shells_root: Node3D = null
var _shells: Array[Dictionary] = []

var _pending_swipe_rad: float = 0.0
var _spin_omega: float = 0.0
var _pad_yaw: float = 0.0
var _prop_count: int = 0
var _total_fallen_events: int = 0
var _total_roll_rad: float = 0.0
var _rng := RandomNumberGenerator.new()


static func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed != null:
		_scene_cache[path] = packed
	return packed


static func attach(
	viewport: Node,
	top_y: float,
	pedestal_radius: float,
	cam_dir_xz: Vector2,
	orbit_360: bool = false
) -> Node3D:
	if viewport == null:
		return null
	var existing := viewport.get_node_or_null("MenuDioramaStage")
	if existing != null:
		existing.queue_free()

	var script_res := load("res://scripts/util/MenuDioramaStage.gd") as GDScript
	if script_res == null:
		return null
	var stage := script_res.new() as Node3D
	if stage == null:
		return null
	stage.name = "MenuDioramaStage"
	stage.call("_setup", top_y, pedestal_radius, cam_dir_xz, orbit_360)
	viewport.add_child(stage)
	return stage


func _setup(top_y: float, pedestal_radius: float, cam_dir_xz: Vector2, orbit_360: bool) -> void:
	_rng.seed = 20261121
	_top_y = top_y
	_pedestal_radius = maxf(pedestal_radius, 0.15)
	_scale_k = _pedestal_radius / 0.50
	_orbit_360 = orbit_360

	# Derive viewer-relative ground basis (Y-up)
	var fwd_cam := Vector3(cam_dir_xz.x, 0.0, cam_dir_xz.y)
	if fwd_cam.length_squared() < 1e-5:
		fwd_cam = Vector3(0.48, 0.0, 0.76)
	fwd_cam = fwd_cam.normalized()
	var back := -fwd_cam
	var right := Vector3(fwd_cam.z, 0.0, -fwd_cam.x).normalized()

	_workbench_basis_back = Vector2(back.x, back.z)
	_workbench_basis_right = Vector2(right.x, right.z)

	# Seat bunker workbench slightly below turntable disc so horizon behind pad
	# reveals props from base to top AND rolling casings clatter onto the table.
	_workbench_top_y = _top_y - 0.048 * _scale_k

	_props_root = Node3D.new()
	_props_root.name = "DioramaProps"
	add_child(_props_root)

	_shells_root = Node3D.new()
	_shells_root.name = "BrassShellCasings"
	add_child(_shells_root)

	_build_lighting(fwd_cam, back, right)
	_build_props(fwd_cam, back, right)
	_spawn_brass_casings(fwd_cam, back, right)


func _build_lighting(fwd_cam: Vector3, back: Vector3, right: Vector3) -> void:
	# Warm tungsten workshop key accent so brass casings gleam against dark deck
	var warm_lamp := OmniLight3D.new()
	warm_lamp.name = "DioramaWarmKey"
	warm_lamp.light_color = Color(1.0, 0.87, 0.66)
	warm_lamp.light_energy = 1.15
	warm_lamp.omni_range = 3.2 * _scale_k
	warm_lamp.omni_attenuation = 1.45
	warm_lamp.position = (
		Vector3(0.0, _top_y + 0.72 * _scale_k, 0.0)
		+ fwd_cam * (0.24 * _scale_k)
		+ right * (0.18 * _scale_k)
	)
	add_child(warm_lamp)

	# Cool green-slate rim accent from back-left to outline crate & radio edges
	var cool_rim := OmniLight3D.new()
	cool_rim.name = "DioramaCoolRim"
	cool_rim.light_color = Color(0.55, 0.82, 0.74)
	cool_rim.light_energy = 0.75
	cool_rim.omni_range = 2.8 * _scale_k
	cool_rim.omni_attenuation = 1.5
	cool_rim.position = (
		Vector3(0.0, _top_y + 0.54 * _scale_k, 0.0)
		+ back * (0.90 * _scale_k)
		- right * (0.46 * _scale_k)
	)
	add_child(cool_rim)


func _spawn_prop(
	glb_path: String,
	node_name: String,
	world_pos: Vector3,
	yaw_rad: float,
	prop_scale: Vector3 = Vector3.ONE
) -> Node3D:
	var packed := _load_scene(glb_path)
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = node_name
	inst.position = world_pos
	inst.rotation = Vector3(0.0, yaw_rad, 0.0)
	inst.scale = prop_scale * _scale_k
	_props_root.add_child(inst)
	GlbMaterialUtilsScript.ensure_pbr(inst)
	_prop_count += 1
	return inst


func _build_props(fwd_cam: Vector3, back: Vector3, right: Vector3) -> void:
	var base_y := _workbench_top_y
	# World angle facing toward camera (+Z in prop local faces camera when yaw = cam_yaw)
	var face_cam_yaw := atan2(-back.x, -back.z)

	if not _orbit_360:
		# Workbench armored slab shifted rearward so front rim still lets shells drop off-screen
		var wb_offset := back * (0.34 * _scale_k)
		_workbench_center = Vector2(wb_offset.x, wb_offset.z)
		var wb_scale := Vector3(0.95, 1.0, 0.82)
		_workbench_half_extents = Vector2(0.86 * wb_scale.x * _scale_k, 0.66 * wb_scale.z * _scale_k)

		# 1. Armored bunker workbench table base
		_spawn_prop(
			GLB_WORKBENCH,
			"WorkbenchDeck",
			Vector3(wb_offset.x, base_y, wb_offset.z),
			face_cam_yaw,
			wb_scale
		)

		# 2. Right-Rear Hero Stack: Slatted Olive Crate + Compact M2A1 Steel Can + Tactical Radio
		var crate_pos := back * (0.84 * _scale_k) + right * (0.31 * _scale_k)
		crate_pos.y = base_y
		var crate_scale := 0.74
		_spawn_prop(
			GLB_CRATE_WOOD,
			"AmmoCrateWood",
			crate_pos,
			face_cam_yaw - deg_to_rad(22.0),
			Vector3.ONE * crate_scale
		)

		var top_can_pos := crate_pos + Vector3(0.0, 0.273 * crate_scale * _scale_k, 0.0)
		_spawn_prop(
			GLB_AMMO_CAN,
			"AmmoCanTop",
			top_can_pos,
			face_cam_yaw + deg_to_rad(52.0),
			Vector3.ONE * 0.72
		)

		var radio_pos := back * (0.50 * _scale_k) + right * (0.47 * _scale_k)
		radio_pos.y = base_y
		_spawn_prop(
			GLB_RADIO,
			"TacticalRadio",
			radio_pos,
			face_cam_yaw - deg_to_rad(32.0),
			Vector3.ONE * 0.74
		)

		# 3. Center-Rear Tactical Parapet: Organic Burlap Sandbag Berm + Ribbed Ordnance Tube
		var sand_pos := back * (0.86 * _scale_k) - right * (0.04 * _scale_k)
		sand_pos.y = base_y
		_spawn_prop(
			GLB_SANDBAGS,
			"SandbagBerm",
			sand_pos,
			face_cam_yaw + deg_to_rad(4.0),
			Vector3.ONE * 0.86
		)

		var tube_pos := back * (0.62 * _scale_k) + right * (0.04 * _scale_k)
		tube_pos.y = base_y
		_spawn_prop(
			GLB_ORDNANCE,
			"OrdnanceTube",
			tube_pos,
			face_cam_yaw + deg_to_rad(14.0),
			Vector3.ONE * 0.80
		)

		# 4. Left-Rear Cluster (kept lower profile so top-left text «КВАД-5» stays clear)
		var peli_pos := back * (0.74 * _scale_k) - right * (0.42 * _scale_k)
		peli_pos.y = base_y
		_spawn_prop(
			GLB_PELICAN,
			"PelicanFpvCase",
			peli_pos,
			face_cam_yaw + deg_to_rad(28.0),
			Vector3.ONE * 0.80
		)

		var side_can_pos := back * (0.52 * _scale_k) - right * (0.56 * _scale_k)
		side_can_pos.y = base_y
		_spawn_prop(
			GLB_AMMO_CAN,
			"AmmoCanSide",
			side_can_pos,
			face_cam_yaw + deg_to_rad(72.0),
			Vector3.ONE * 0.82
		)
	else:
		# Desktop 360-degree MainMenu: rear-and-flank perimeter arc (keeps front approach unobstructed)
		_workbench_center = Vector2.ZERO
		var wb_scale_360 := Vector3(1.12, 1.0, 1.24)
		_workbench_half_extents = Vector2(0.86 * wb_scale_360.x * _scale_k, 0.66 * wb_scale_360.z * _scale_k)
		_spawn_prop(
			GLB_WORKBENCH,
			"WorkbenchDeck",
			Vector3(0.0, base_y, 0.0),
			face_cam_yaw,
			wb_scale_360
		)

		var crate_p := back * (0.80 * _scale_k) + right * (0.44 * _scale_k)
		crate_p.y = base_y
		_spawn_prop(GLB_CRATE_WOOD, "AmmoCrateWood", crate_p, face_cam_yaw - deg_to_rad(22.0), Vector3.ONE * 0.74)
		_spawn_prop(
			GLB_AMMO_CAN,
			"AmmoCanTop",
			crate_p + Vector3(0.0, 0.273 * 0.74 * _scale_k, 0.0),
			face_cam_yaw + deg_to_rad(56.0),
			Vector3.ONE * 0.72
		)
		_spawn_prop(
			GLB_SANDBAGS,
			"SandbagBerm",
			back * (0.86 * _scale_k) - right * (0.10 * _scale_k) + Vector3(0.0, base_y, 0.0),
			face_cam_yaw,
			Vector3.ONE * 0.80
		)
		_spawn_prop(
			GLB_PELICAN,
			"PelicanFpvCase",
			back * (0.72 * _scale_k) - right * (0.54 * _scale_k) + Vector3(0.0, base_y, 0.0),
			face_cam_yaw + deg_to_rad(32.0),
			Vector3.ONE * 0.76
		)
		_spawn_prop(
			GLB_ORDNANCE,
			"OrdnanceTube",
			back * (0.62 * _scale_k) - right * (0.04 * _scale_k) + Vector3(0.0, base_y, 0.0),
			face_cam_yaw + deg_to_rad(14.0),
			Vector3.ONE * 0.76
		)
		_spawn_prop(
			GLB_RADIO,
			"TacticalRadio",
			back * (0.48 * _scale_k) + right * (0.70 * _scale_k) + Vector3(0.0, base_y, 0.0),
			face_cam_yaw - deg_to_rad(42.0),
			Vector3.ONE * 0.74
		)


func _spawn_brass_casings(fwd_cam: Vector3, back: Vector3, right: Vector3) -> void:
	var shell_packed := _load_scene(GLB_SHELL)
	if shell_packed == null:
		return

	# Bias angular placement so many gleaming shells sit in front/side outer track
	# of the circular pad (outside inner drone footprint) plus a few near back/bench.
	var cam_angle := atan2(fwd_cam.x, fwd_cam.z)
	var deck_angles_deg: Array[float] = [
		-72.0, -48.0, -32.0, -18.0, -4.0, 12.0, 26.0, 42.0,
		58.0, 76.0, 102.0, 132.0, -104.0, -136.0, -158.0, 164.0,
	]
	var deck_r_fracs: Array[float] = [
		0.78, 0.88, 0.66, 0.91, 0.74, 0.86, 0.69, 0.92,
		0.80, 0.72, 0.85, 0.76, 0.89, 0.71, 0.84, 0.79,
	]

	for i in range(deck_angles_deg.size()):
		var inst := shell_packed.instantiate() as Node3D
		if inst == null:
			continue
		inst.name = "BrassShell_%02d" % i
		_shells_root.add_child(inst)
		GlbMaterialUtilsScript.ensure_pbr(inst)

		# Sleek 7.62mm (hero scale ~0.84) and .50-cal hero scale (~1.00)
		var size_mult := (1.00 if (i % 4 == 0) else 0.84) * _scale_k
		inst.scale = Vector3.ONE * size_mult
		var rad := BASE_SHELL_RAD * size_mult
		var length := BASE_SHELL_LEN * size_mult

		var theta := cam_angle + deg_to_rad(deck_angles_deg[i])
		var r := _pedestal_radius * deck_r_fracs[i]
		var px := sin(theta) * r
		var pz := cos(theta) * r
		# Tangential + slightly scattered yaw orientation for natural cartridge scatter
		var yaw := theta + deg_to_rad(_rng.randf_range(-38.0, 38.0)) + (PI * 0.5 if (i % 2 == 0) else -PI * 0.5)

		var entry := {
			"node": inst,
			"state": ShellState.ON_DECK,
			"pos": Vector3(px, _top_y + rad, pz),
			"vel": Vector3.ZERO,
			"axis_yaw": yaw,
			"roll_angle": _rng.randf_range(0.0, TAU),
			"tip_pitch": 0.0,
			"tip_roll": 0.0,
			"ang_vel": Vector3.ZERO,
			"radius": rad,
			"length": length,
			"scale_mult": size_mult,
			"slot_theta": theta,
			"slot_r": r,
			"slot_yaw": yaw,
			"bench_pos": Vector3.ZERO,
			"timer": 0.0,
			"home_deck": true,
		}
		_shells.append(entry)
		_sync_shell_transform(entry)

	# 4 additional casings resting visibly on the bunker workbench surface near side cans/tube
	var bench_offsets: Array[Vector2] = [
		Vector2(-0.58, 0.34),
		Vector2(-0.50, 0.42),
		Vector2(0.56, 0.32),
		Vector2(0.64, 0.24),
	]
	for j in range(bench_offsets.size()):
		var inst := shell_packed.instantiate() as Node3D
		if inst == null:
			continue
		inst.name = "BrassShellBench_%02d" % j
		_shells_root.add_child(inst)
		GlbMaterialUtilsScript.ensure_pbr(inst)
		var size_mult := (0.98 if j == 1 else 0.82) * _scale_k
		inst.scale = Vector3.ONE * size_mult
		var rad := BASE_SHELL_RAD * size_mult
		var off := bench_offsets[j]
		var wpos := right * (off.x * _scale_k) + back * (off.y * _scale_k)
		var yaw := cam_angle + _rng.randf_range(-1.8, 1.8)
		var entry := {
			"node": inst,
			"state": ShellState.ON_WORKBENCH,
			"pos": Vector3(wpos.x, _workbench_top_y + rad, wpos.z),
			"vel": Vector3.ZERO,
			"axis_yaw": yaw,
			"roll_angle": _rng.randf_range(0.0, TAU),
			"tip_pitch": 0.0,
			"tip_roll": 0.0,
			"ang_vel": Vector3.ZERO,
			"radius": rad,
			"length": BASE_SHELL_LEN * size_mult,
			"scale_mult": size_mult,
			"slot_theta": 0.0,
			"slot_r": 0.0,
			"slot_yaw": yaw,
			"bench_pos": Vector3(wpos.x, _workbench_top_y + rad, wpos.z),
			"timer": 0.0,
			"home_deck": false,
		}
		_shells.append(entry)
		_sync_shell_transform(entry)


func apply_swipe_spin(delta_yaw: float) -> void:
	_pending_swipe_rad = clampf(_pending_swipe_rad + delta_yaw, -0.75, 0.75)


func sync_idle_spin(delta_yaw: float) -> void:
	# Gentle idle rotation rotates deck casings silently with the turntable
	_pad_yaw += delta_yaw
	if absf(delta_yaw) < 1e-6:
		return
	var c := cos(delta_yaw)
	var s := sin(delta_yaw)
	for entry in _shells:
		if int(entry["state"]) != ShellState.ON_DECK:
			continue
		var p: Vector3 = entry["pos"]
		var nx := p.x * c + p.z * s
		var nz := -p.x * s + p.z * c
		entry["pos"] = Vector3(nx, p.y, nz)
		entry["axis_yaw"] = float(entry["axis_yaw"]) + delta_yaw
		var v: Vector3 = entry["vel"]
		if v.length_squared() > 1e-6:
			entry["vel"] = Vector3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
		_sync_shell_transform(entry)


func reset_shells() -> void:
	for entry in _shells:
		var rad := float(entry["radius"])
		entry["vel"] = Vector3.ZERO
		entry["tip_pitch"] = 0.0
		entry["tip_roll"] = 0.0
		entry["ang_vel"] = Vector3.ZERO
		entry["timer"] = 0.0
		if bool(entry["home_deck"]):
			var theta := float(entry["slot_theta"]) + _pad_yaw
			var r := float(entry["slot_r"])
			entry["state"] = ShellState.ON_DECK
			entry["pos"] = Vector3(sin(theta) * r, _top_y + rad, cos(theta) * r)
			entry["axis_yaw"] = float(entry["slot_yaw"]) + _pad_yaw
		else:
			entry["state"] = ShellState.ON_WORKBENCH
			entry["pos"] = entry["bench_pos"]
		(entry["node"] as Node3D).visible = true
		_sync_shell_transform(entry)


func _is_over_workbench(xz: Vector2) -> bool:
	var rel := xz - _workbench_center
	var u := absf(rel.dot(_workbench_basis_right))
	var v := absf(rel.dot(_workbench_basis_back))
	return u <= _workbench_half_extents.x and v <= _workbench_half_extents.y


func step(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if dt <= 0.0001:
		return

	var swipe_rad := _pending_swipe_rad
	_pending_swipe_rad = 0.0

	if absf(swipe_rad) > 0.0004:
		var inst_omega := clampf(swipe_rad / maxf(dt, 0.010), -18.0, 18.0)
		_spin_omega = lerpf(_spin_omega, inst_omega, 0.60)
	else:
		_spin_omega *= exp(-6.8 * dt)

	var active_swipe := absf(swipe_rad) > 0.0006 or absf(_spin_omega) > 0.40
	var inner_r_min := _pedestal_radius * 0.56
	var rim_drop_r := _pedestal_radius - 0.010 * _scale_k

	# 1. Inject tangential + centrifugal + scatter impulses on swipe
	if active_swipe:
		for i in range(_shells.size()):
			var e := _shells[i]
			if int(e["state"]) != ShellState.ON_DECK:
				continue
			var p: Vector3 = e["pos"]
			var xz := Vector2(p.x, p.z)
			var r := maxf(xz.length(), 0.04)
			# +Y rotation in Godot moves (x, z) along tangent (z, -x)
			var tan_dir := Vector3(p.z / r, 0.0, -p.x / r)
			var rad_dir := Vector3(p.x / r, 0.0, p.z / r)

			var v: Vector3 = e["vel"]
			var jitter := _rng.randf_range(0.60, 1.38)
			# Physical tangential swirl + centrifugal drift so shells cascade smoothly over rim
			var v_xz_in := Vector2(v.x, v.z)
			var tan2 := Vector2(tan_dir.x, tan_dir.z)
			var rad2 := Vector2(rad_dir.x, rad_dir.z)
			var v_tan := v_xz_in.dot(tan2)
			var v_rad := v_xz_in.dot(rad2)

			var v_tan_target := clampf(_spin_omega * r * 0.42 * jitter, -1.65, 1.65)
			v_tan = lerpf(v_tan, v_tan_target, 1.0 - exp(-10.0 * dt))
			var edge_bias := clampf((r / _pedestal_radius - 0.56) / 0.36, 0.25, 1.0)
			var cent_acc := (absf(_spin_omega) * 0.22 + (_spin_omega * _spin_omega) * r * 0.042) * jitter * edge_bias
			v_rad = minf(v_rad + cent_acc * dt, 1.25)

			var new_xz := tan2 * v_tan + rad2 * v_rad
			v.x = new_xz.x
			v.z = new_xz.y
			# Slight rotational yaw torque nudging long axis perpendicular to motion for clean rolling
			var motion_ang := atan2(v.x, v.z)
			var perp_diff := wrapf((motion_ang + PI * 0.5) - float(e["axis_yaw"]), -PI, PI)
			if absf(perp_diff) > PI * 0.5:
				perp_diff = wrapf((motion_ang - PI * 0.5) - float(e["axis_yaw"]), -PI, PI)
			e["axis_yaw"] = float(e["axis_yaw"]) + perp_diff * minf(dt * 6.5, 0.5)
			e["vel"] = v

	# 2. Integrate ON_DECK and ON_WORKBENCH rolling/sliding + edge drop triggers
	for i in range(_shells.size()):
		var e := _shells[i]
		var st := int(e["state"])
		var rad := float(e["radius"])

		if st == ShellState.ON_DECK or st == ShellState.ON_WORKBENCH:
			var p: Vector3 = e["pos"]
			var v: Vector3 = e["vel"]
			var yaw := float(e["axis_yaw"])
			var long_dir := Vector3(sin(yaw), 0.0, cos(yaw))
			var roll_dir := Vector3(cos(yaw), 0.0, -sin(yaw))

			var v_xz := Vector3(v.x, 0.0, v.z)
			var v_long := v_xz.dot(long_dir)
			var v_roll := v_xz.dot(roll_dir)

			# Low friction perpendicular to casing axis (rolls freely), high friction along length
			var roll_damp := exp((-0.90 if st == ShellState.ON_DECK else -1.45) * dt)
			var slide_damp := exp(-4.2 * dt)
			v_roll *= roll_damp
			v_long *= slide_damp
			v_xz = roll_dir * v_roll + long_dir * v_long

			p += v_xz * dt
			var d_roll := (v_roll / maxf(rad, 0.004)) * dt
			e["roll_angle"] = float(e["roll_angle"]) + d_roll
			_total_roll_rad += absf(d_roll)
			# Bottleneck taper subtly curves the casing's path while rolling
			e["axis_yaw"] = yaw + v_roll * 0.62 * dt

			if st == ShellState.ON_DECK:
				p.y = _top_y + rad
				var r_now := Vector2(p.x, p.z).length()
				# Keep outer shells out of the center drone footprint
				if r_now < inner_r_min and r_now > 0.001:
					var out_n := Vector2(p.x, p.z) / r_now
					p.x = out_n.x * inner_r_min
					p.z = out_n.y * inner_r_min
					var vn := v_xz.x * out_n.x + v_xz.z * out_n.y
					if vn < 0.0:
						v_xz -= Vector3(out_n.x, 0.0, out_n.y) * (vn * 1.35)
				elif r_now > rim_drop_r:
					# Rolled over circular rim -> tip over lip and fall!
					var rad_n := Vector3(p.x / r_now, 0.0, p.z / r_now)
					v_xz += rad_n * 0.24
					v = Vector3(v_xz.x, -0.10, v_xz.z)
					e["state"] = ShellState.FALLING
					e["ang_vel"] = Vector3(
						_rng.randf_range(-9.0, 9.0),
						_rng.randf_range(-7.0, 7.0),
						_rng.randf_range(-10.0, 10.0)
					)
					_total_fallen_events += 1
				else:
					v = Vector3(v_xz.x, 0.0, v_xz.z)
			else:
				p.y = _workbench_top_y + rad
				v = Vector3(v_xz.x, 0.0, v_xz.z)
				if not _is_over_workbench(Vector2(p.x, p.z)):
					e["state"] = ShellState.FALLING
					e["ang_vel"] = Vector3(
						_rng.randf_range(-8.0, 8.0),
						_rng.randf_range(-5.0, 5.0),
						_rng.randf_range(-9.0, 9.0)
					)
				elif bool(e["home_deck"]):
					e["timer"] = float(e["timer"]) + dt
					if float(e["timer"]) > 3.2 and v.length_squared() < 0.004:
						e["state"] = ShellState.RESPAWN_WAIT
						e["timer"] = _rng.randf_range(0.8, 1.8)
						(e["node"] as Node3D).visible = false

			e["pos"] = p
			e["vel"] = v

		elif st == ShellState.FALLING:
			var p: Vector3 = e["pos"]
			var v: Vector3 = e["vel"]
			var av: Vector3 = e["ang_vel"]
			var prev_y := p.y

			v.y -= 4.8 * dt
			p += v * dt
			e["tip_pitch"] = float(e["tip_pitch"]) + av.x * dt
			e["tip_roll"] = float(e["tip_roll"]) + av.z * dt
			var d_spin := av.y * dt
			e["roll_angle"] = float(e["roll_angle"]) + d_spin
			_total_roll_rad += absf(av.length() * dt)

			# Bounce/clatter onto lower armored workbench if landing over rear/side table surface
			var surf_y := _workbench_top_y + rad
			if v.y < 0.0 and prev_y >= surf_y and p.y <= surf_y and _is_over_workbench(Vector2(p.x, p.z)):
				p.y = surf_y
				v.y = -v.y * 0.34
				v.x *= 0.78
				v.z *= 0.78
				if absf(v.y) < 0.22:
					# Settle onto workbench steel mat and roll smoothly
					v.y = 0.0
					e["state"] = ShellState.ON_WORKBENCH
					e["tip_pitch"] = 0.0
					e["tip_roll"] = 0.0
					e["timer"] = 0.0
				else:
					e["ang_vel"] = av * 0.65

			# Dropped below bottom of showcase frame -> schedule smooth replenish back onto deck
			if p.y < _top_y - 0.85 * _scale_k:
				if bool(e["home_deck"]):
					e["state"] = ShellState.RESPAWN_WAIT
					e["timer"] = _rng.randf_range(0.9, 1.9)
					(e["node"] as Node3D).visible = false
				else:
					e["state"] = ShellState.RESPAWN_WAIT
					e["timer"] = _rng.randf_range(1.2, 2.2)
					(e["node"] as Node3D).visible = false

			e["pos"] = p
			e["vel"] = v

		elif st == ShellState.RESPAWN_WAIT:
			var t := float(e["timer"]) - dt
			e["timer"] = t
			if t <= 0.0 and absf(_spin_omega) < 3.0:
				e["state"] = ShellState.DROPPING_IN
				e["tip_pitch"] = 0.0
				e["tip_roll"] = 0.0
				e["ang_vel"] = Vector3.ZERO
				if bool(e["home_deck"]):
					var theta := float(e["slot_theta"]) + _pad_yaw
					var r := float(e["slot_r"])
					e["pos"] = Vector3(sin(theta) * r, _top_y + 0.14 * _scale_k, cos(theta) * r)
					e["axis_yaw"] = float(e["slot_yaw"]) + _pad_yaw + _rng.randf_range(-0.25, 0.25)
				else:
					var bp: Vector3 = e["bench_pos"]
					e["pos"] = Vector3(bp.x, _workbench_top_y + 0.14 * _scale_k, bp.z)
				e["vel"] = Vector3(_rng.randf_range(-0.04, 0.04), -0.35, _rng.randf_range(-0.04, 0.04))
				(e["node"] as Node3D).visible = true

		elif st == ShellState.DROPPING_IN:
			var p: Vector3 = e["pos"]
			var v: Vector3 = e["vel"]
			v.y -= 9.8 * dt
			p += v * dt
			var target_y := (_top_y if bool(e["home_deck"]) else _workbench_top_y) + rad
			if p.y <= target_y:
				p.y = target_y
				v.y = -v.y * 0.22
				if absf(v.y) < 0.14:
					v.y = 0.0
					e["state"] = ShellState.ON_DECK if bool(e["home_deck"]) else ShellState.ON_WORKBENCH
			e["pos"] = p
			e["vel"] = v

	# 3. Pairwise shell-to-shell soft collision & knock impulse on same surface
	var n_shells := _shells.size()
	for i in range(n_shells):
		var a := _shells[i]
		var st_a := int(a["state"])
		if st_a != ShellState.ON_DECK and st_a != ShellState.ON_WORKBENCH:
			continue
		for j in range(i + 1, n_shells):
			var b := _shells[j]
			if int(b["state"]) != st_a:
				continue
			var pa: Vector3 = a["pos"]
			var pb: Vector3 = b["pos"]
			var diff := Vector2(pb.x - pa.x, pb.z - pa.z)
			var min_sep := (float(a["radius"]) + float(b["radius"])) * 1.85
			var d_sq := diff.length_squared()
			if d_sq < min_sep * min_sep and d_sq > 1e-7:
				var d := sqrt(d_sq)
				var n2 := diff / d
				var push := (min_sep - d) * 0.5
				pa.x -= n2.x * push
				pa.z -= n2.y * push
				pb.x += n2.x * push
				pb.z += n2.y * push
				a["pos"] = pa
				b["pos"] = pb

				var va: Vector3 = a["vel"]
				var vb: Vector3 = b["vel"]
				var rel_n := (vb.x - va.x) * n2.x + (vb.z - va.z) * n2.y
				if rel_n < 0.0:
					var imp := -0.78 * rel_n
					va.x -= n2.x * imp
					va.z -= n2.y * imp
					vb.x += n2.x * imp
					vb.z += n2.y * imp
					a["vel"] = va
					b["vel"] = vb

	# 4. Sync final 3D transforms cleanly
	for entry in _shells:
		if int(entry["state"]) != ShellState.RESPAWN_WAIT:
			_sync_shell_transform(entry)


func _sync_shell_transform(entry: Dictionary) -> void:
	var n := entry["node"] as Node3D
	if n == null:
		return
	n.position = entry["pos"]
	var yaw := float(entry["axis_yaw"])
	var roll := float(entry["roll_angle"])
	var pitch := float(entry["tip_pitch"])
	var bank := float(entry["tip_roll"])
	# Yaw on plane -> optional 3D tumble pitch/bank -> axial roll around local cartridge Z!
	var b := Basis(Vector3.UP, yaw)
	if absf(pitch) > 0.001 or absf(bank) > 0.001:
		b = b * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.UP, bank)
	b = b * Basis(Vector3.BACK, roll)
	n.transform.basis = b.scaled(Vector3.ONE * float(entry["scale_mult"]))


func get_debug_stats() -> Dictionary:
	var on_deck := 0
	var on_bench := 0
	var falling := 0
	var min_y := 999.0
	for e in _shells:
		var st := int(e["state"])
		var py := (e["pos"] as Vector3).y
		if st == ShellState.ON_DECK:
			on_deck += 1
		elif st == ShellState.ON_WORKBENCH:
			on_bench += 1
		elif st == ShellState.FALLING:
			falling += 1
		if py < min_y and st != ShellState.RESPAWN_WAIT:
			min_y = py
	return {
		"prop_count": _prop_count,
		"shell_count": _shells.size(),
		"on_deck_count": on_deck,
		"on_bench_count": on_bench,
		"falling_count": falling,
		"total_fallen_events": _total_fallen_events,
		"total_roll_rad": _total_roll_rad,
		"min_shell_y": min_y,
		"top_y": _top_y,
		"workbench_top_y": _workbench_top_y,
	}
