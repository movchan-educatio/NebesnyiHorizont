class_name NavalSceneBuilder
extends RefCounted

## Builds the Black Sea naval combat environment:
## 1. Expansive open sea water basin with dynamic marine PBR water shader.
## 2. Sandy coastal embankment, breakwater piers, and navigation buoy markers.
## 3. High-detail Project 22160 guided missile corvette / patrol ship as primary target.
## 4. Sea swells and wake effects.

const VEHICLE := preload("res://combat/vehicle.gd")
const CombatTargetScript = preload("res://combat/combat_target.gd")
const ExplosionScript = preload("res://combat/explosion.gd")
const SFX = preload("res://combat/sfx.gd")
const WATER_SHADER := preload("res://Assets/water.gdshader")


## Builds the sea basin, shoreline breakwaters, and maritime atmosphere
static func build_sea_and_coast(parent: Node3D, water_y: float) -> Node3D:
	var naval_root := Node3D.new()
	naval_root.name = "NavalEnvironment"
	parent.add_child(naval_root)

	# 1. Vast Black Sea Water Basin (2400m x 2400m).  `water_y` is the actual
	#    sea surface, not the terrain height: the naval mission sits in a deep
	#    basin so the USV hull never scrapes the valley floor.
	var water_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400.0, 2400.0)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	water_mesh.mesh = plane
	water_mesh.position = Vector3(1400.0, water_y, 0.0)

	# Animated open sea: the same ripple/fresnel shader as the river and marsh,
	# tuned to the deep Black Sea palette.
	var water_mat := ShaderMaterial.new()
	water_mat.shader = WATER_SHADER
	water_mat.set_shader_parameter("deep_color", Color(0.012, 0.045, 0.080))
	water_mat.set_shader_parameter("shallow_color", Color(0.035, 0.135, 0.185))
	water_mat.set_shader_parameter("opacity", 0.95)
	water_mat.set_shader_parameter("ripple_scale", 0.020)
	water_mat.set_shader_parameter("ripple_speed", 0.85)
	water_mat.set_shader_parameter("ripple_strength", 0.50)
	water_mat.set_shader_parameter("wave_height", 0.09)
	# Same seamless noise normal as the inland water, scaled for open sea.
	var sea_noise := FastNoiseLite.new()
	sea_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sea_noise.frequency = 0.035
	sea_noise.fractal_octaves = 4
	sea_noise.fractal_gain = 0.55
	var sea_normal := NoiseTexture2D.new()
	sea_normal.width = 256
	sea_normal.height = 256
	sea_normal.seamless = true
	sea_normal.as_normal_map = true
	sea_normal.bump_strength = 8.0
	sea_normal.noise = sea_noise
	water_mat.set_shader_parameter("ripple_normal", sea_normal)
	water_mesh.material_override = water_mat
	naval_root.add_child(water_mesh)

	# Dark seabed just above the legacy valley floor: keeps the transparent
	# water from showing the green ground plane through it and gives the sea
	# real depth at the shoreline.
	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	var seabed_plane := PlaneMesh.new()
	seabed_plane.size = Vector2(2400.0, 2400.0)
	seabed.mesh = seabed_plane
	seabed.position = Vector3(1400.0, water_y - 2.9, 0.0)
	var seabed_mat := StandardMaterial3D.new()
	seabed_mat.albedo_color = Color(0.045, 0.070, 0.065)
	seabed_mat.roughness = 0.98
	seabed.material_override = seabed_mat
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	naval_root.add_child(seabed)

	# 2. Coastal Shoreline & Sandy Embankment (transition from valley terrain to sea at X = 150..220)
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.68, 0.62, 0.48)
	sand_mat.roughness = 0.92

	var coast_strip := MeshInstance3D.new()
	var coast_box := BoxMesh.new()
	coast_box.size = Vector3(60.0, 6.0, 1800.0)
	coast_strip.mesh = coast_box
	coast_strip.position = Vector3(175.0, water_y - 1.5, 0.0)
	coast_strip.material_override = sand_mat
	naval_root.add_child(coast_strip)

	# Static collision for shoreline
	var coast_body := StaticBody3D.new()
	var coast_col := CollisionShape3D.new()
	var coast_shape := BoxShape3D.new()
	coast_shape.size = coast_box.size
	coast_col.shape = coast_shape
	coast_body.position = coast_strip.position
	coast_body.add_child(coast_col)
	naval_root.add_child(coast_body)

	# 3. Naval Launch Pier & Quay (Concrete jetty where USV Magura-X starts)
	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.38, 0.40, 0.38)
	concrete_mat.roughness = 0.82

	var pier := MeshInstance3D.new()
	var pier_box := BoxMesh.new()
	pier_box.size = Vector3(12.0, 6.0, 50.0)
	pier.mesh = pier_box
	pier.position = Vector3(192.0, water_y - 1.2, 50.0)
	pier.material_override = concrete_mat
	naval_root.add_child(pier)

	var pier_body := StaticBody3D.new()
	var pier_col := CollisionShape3D.new()
	var p_shape := BoxShape3D.new()
	p_shape.size = pier_box.size
	p_col_shape_assign(pier_col, p_shape)
	pier_body.position = pier.position
	pier_body.add_child(pier_col)
	naval_root.add_child(pier_body)

	# 4. Coastal Tetrapods / Concrete Breakwater Blocks
	_spawn_breakwater_blocks(naval_root, water_y)

	# 5. Navigational Buoys with pulsing marine lanterns
	_spawn_nav_buoys(naval_root, water_y)

	return naval_root


static func p_col_shape_assign(col: CollisionShape3D, shape: Shape3D) -> void:
	col.shape = shape


static func _spawn_breakwater_blocks(root: Node3D, water_y: float) -> void:
	var block_mat := StandardMaterial3D.new()
	block_mat.albedo_color = Color(0.42, 0.44, 0.42)
	block_mat.roughness = 0.85

	for i in range(16):
		var z: float = -120.0 + float(i) * 18.0
		var x: float = 198.0 + sin(float(i) * 1.7) * 3.0
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.5, 3.0, 3.5)
		b.mesh = bm
		# Stand on the seabed instead of hanging in the water column.
		b.position = Vector3(x, water_y - 1.4, z)
		b.rotation = Vector3(sin(float(i)), cos(float(i)), 0.0) * 0.3
		b.material_override = block_mat
		root.add_child(b)


static func _spawn_nav_buoys(root: Node3D, water_y: float) -> void:
	var buoy_coords := [
		Vector3(230.0, water_y, 80.0),
		Vector3(230.0, water_y, 0.0),
		Vector3(230.0, water_y, -80.0),
		Vector3(380.0, water_y, -40.0),
	]

	for i in range(buoy_coords.size()):
		var bp: Vector3 = buoy_coords[i]
		var buoy := Node3D.new()
		buoy.position = bp
		root.add_child(buoy)

		# Float base
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.9
		cm.bottom_radius = 1.1
		cm.height = 1.6
		cyl.mesh = cm
		cyl.position = Vector3(0.0, 0.3, 0.0)
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.9, 0.2, 0.15) if (i % 2 == 0) else Color(0.15, 0.85, 0.3)
		cyl.material_override = b_mat
		buoy.add_child(cyl)

		# Signal light
		var light_mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		light_mesh.mesh = sm
		light_mesh.position = Vector3(0.0, 1.4, 0.0)
		var l_mat := StandardMaterial3D.new()
		l_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		l_mat.albedo_color = Color(1.0, 0.3, 0.2) if (i % 2 == 0) else Color(0.2, 1.0, 0.4)
		light_mesh.material_override = l_mat
		buoy.add_child(light_mesh)

		var omni := OmniLight3D.new()
		omni.light_energy = 2.0
		omni.light_color = l_mat.albedo_color
		omni.omni_range = 14.0
		omni.position = Vector3(0.0, 1.5, 0.0)
		buoy.add_child(omni)


## Builds the detailed Russian Project 22160 Corvette target («Сергій Котов»)
## Positioned out in open waters at X = 550m, Z = -80m
static func spawn_enemy_warship(parent: Node3D, pos: Vector3, on_destroyed_callback: Callable = Callable()) -> Node3D:
	var ship := Node3D.new()
	ship.name = "EnemyWarship_Project22160"
	ship.position = pos
	ship.rotation_degrees.y = 105.0 # Broadside / 3/4 aspect to incoming attack
	if on_destroyed_callback.is_valid():
		ship.set_meta("on_destroyed", on_destroyed_callback)
	parent.add_child(ship)

	# Materials
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.32, 0.35, 0.37) # Naval haze grey
	hull_mat.roughness = 0.65
	hull_mat.metallic = 0.40

	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color(0.22, 0.25, 0.24) # Dark non-skid deck
	deck_mat.roughness = 0.85

	var boottopping_mat := StandardMaterial3D.new()
	boottopping_mat.albedo_color = Color(0.48, 0.15, 0.12) # Antifouling red waterline
	boottopping_mat.roughness = 0.70

	var stealth_mat := StandardMaterial3D.new()
	stealth_mat.albedo_color = Color(0.28, 0.30, 0.32) # Angular radar absorbent grey
	stealth_mat.roughness = 0.50
	stealth_mat.metallic = 0.50

	# 1. Lower Submerged Hull (Red antifouling, 56m x 10m x 3.5m)
	var lower_hull := MeshInstance3D.new()
	var lh_box := BoxMesh.new()
	lh_box.size = Vector3(9.5, 3.0, 54.0)
	lower_hull.mesh = lh_box
	lower_hull.position = Vector3(0.0, -1.2, 0.0)
	lower_hull.material_override = boottopping_mat
	ship.add_child(lower_hull)

	# 2. Main Freeboard Hull (Grey, 56m x 10.5m x 4.5m)
	var main_hull := MeshInstance3D.new()
	var mh_box := BoxMesh.new()
	mh_box.size = Vector3(10.2, 4.2, 54.0)
	main_hull.mesh = mh_box
	main_hull.position = Vector3(0.0, 2.0, 0.0)
	main_hull.material_override = hull_mat
	ship.add_child(main_hull)

	# Bow wedge / flared stem
	var bow_wedge := MeshInstance3D.new()
	var bw_prism := PrismMesh.new()
	bw_prism.size = Vector3(10.2, 4.2, 14.0)
	bow_wedge.mesh = bw_prism
	bow_wedge.position = Vector3(0.0, 2.0, -32.0)
	bow_wedge.rotation_degrees.x = -90.0
	bow_wedge.material_override = hull_mat
	ship.add_child(bow_wedge)

	# 3. Main Stealth Bridge & Superstructure
	var bridge := MeshInstance3D.new()
	var b_box := BoxMesh.new()
	b_box.size = Vector3(8.5, 5.0, 20.0)
	bridge.mesh = b_box
	bridge.position = Vector3(0.0, 6.2, -6.0)
	bridge.material_override = stealth_mat
	ship.add_child(bridge)

	# Bridge windows band
	var win := MeshInstance3D.new()
	var w_box := BoxMesh.new()
	w_box.size = Vector3(8.6, 1.0, 5.0)
	win.mesh = w_box
	win.position = Vector3(0.0, 7.8, -14.0)
	var win_mat := StandardMaterial3D.new()
	win_mat.albedo_color = Color(0.05, 0.08, 0.12)
	win_mat.roughness = 0.1
	win_mat.metallic = 0.9
	win.material_override = win_mat
	ship.add_child(win)

	# 4. Integrated Stealth Main Mast with Radar Dome
	var mast := MeshInstance3D.new()
	var m_box := BoxMesh.new()
	m_box.size = Vector3(3.2, 8.5, 4.5)
	mast.mesh = m_box
	mast.position = Vector3(0.0, 11.5, -4.0)
	mast.material_override = stealth_mat
	ship.add_child(mast)

	# Pozitiv-ME / Mineral-ME Radar Dome
	var radome := MeshInstance3D.new()
	var r_sphere := SphereMesh.new()
	r_sphere.radius = 1.8
	r_sphere.height = 3.6
	radome.mesh = r_sphere
	radome.position = Vector3(0.0, 16.5, -4.0)
	var r_mat := StandardMaterial3D.new()
	r_mat.albedo_color = Color(0.92, 0.92, 0.94)
	radome.material_override = r_mat
	ship.add_child(radome)

	# 5. AK-176MA 76mm Stealth Naval Gun at the Bow
	var turret := MeshInstance3D.new()
	var t_box := BoxMesh.new()
	t_box.size = Vector3(3.4, 2.4, 4.2)
	turret.mesh = t_box
	turret.position = Vector3(0.0, 5.2, -22.0)
	turret.material_override = stealth_mat
	ship.add_child(turret)

	var barrel := MeshInstance3D.new()
	var bar_cyl := CylinderMesh.new()
	bar_cyl.top_radius = 0.14
	bar_cyl.bottom_radius = 0.18
	bar_cyl.height = 4.8
	barrel.mesh = bar_cyl
	barrel.position = Vector3(0.0, 5.4, -25.5)
	barrel.rotation_degrees.x = -85.0
	barrel.material_override = hull_mat
	ship.add_child(barrel)

	# 6. Helicopter Flight Deck at Stern with Tor-M2KM Container
	var heli_deck := MeshInstance3D.new()
	var hd_box := BoxMesh.new()
	hd_box.size = Vector3(9.8, 0.2, 18.0)
	heli_deck.mesh = hd_box
	heli_deck.position = Vector3(0.0, 4.2, 17.0)
	heli_deck.material_override = deck_mat
	ship.add_child(heli_deck)

	# Tor-M2KM SAM Module Container
	var sam := MeshInstance3D.new()
	var sam_box := BoxMesh.new()
	sam_box.size = Vector3(3.2, 2.6, 4.5)
	sam.mesh = sam_box
	sam.position = Vector3(0.0, 5.5, 14.0)
	var sam_mat := StandardMaterial3D.new()
	sam_mat.albedo_color = Color(0.25, 0.32, 0.26)
	sam.material_override = sam_mat
	ship.add_child(sam)

	# 7. Combat Collision Body & Hitbox
	var ship_body := StaticBody3D.new()
	ship_body.name = "ShipCollision"
	ship_body.collision_layer = 1
	ship_body.collision_mask = 1

	var c_hull := CollisionShape3D.new()
	var box_hull := BoxShape3D.new()
	box_hull.size = Vector3(12.0, 8.0, 58.0)
	c_hull.shape = box_hull
	c_hull.position = Vector3(0.0, 3.0, 0.0)
	ship_body.add_child(c_hull)

	var c_sup := CollisionShape3D.new()
	var box_sup := BoxShape3D.new()
	box_sup.size = Vector3(9.0, 10.0, 22.0)
	c_sup.shape = box_sup
	c_sup.position = Vector3(0.0, 9.0, -5.0)
	ship_body.add_child(c_sup)

	ship.add_child(ship_body)

	# 8. Interactive Destructible Combat Target
	var ct := CombatTargetScript.new()
	ct.name = "CombatTarget"
	ct.kind = CombatTargetScript.Kind.BUNKER
	ct.max_health = 600.0
	ct.points = 1000
	ship.add_child(ct)

	# Hitbox Area3D
	var area := Area3D.new()
	area.name = "HitboxArea"
	area.collision_layer = 4
	area.collision_mask = 4
	var a_col := CollisionShape3D.new()
	var a_shape := BoxShape3D.new()
	a_shape.size = Vector3(14.0, 12.0, 60.0)
	a_col.shape = a_shape
	a_col.position = Vector3(0.0, 5.0, 0.0)
	area.add_child(a_col)
	ship.add_child(area)

	area.body_entered.connect(func(body: Node):
		if body is RigidBody3D: # Drone (Magura-X) or payload
			_detonate_warship(ship, body.global_position)
	)

	return ship


## Massive Naval Explosion when Magura-X strikes the warship
static func _detonate_warship(ship: Node3D, impact_pos: Vector3) -> void:
	if not is_instance_valid(ship):
		return
	if ship.has_meta("destroyed"):
		return
	ship.set_meta("destroyed", true)
	
	if ship.has_meta("on_destroyed"):
		var cb = ship.get_meta("on_destroyed")
		if cb is Callable and cb.is_valid():
			cb.call(1000)

	var parent := ship.get_parent()
	if parent != null:
		# Multi-stage massive blast
		for k in range(3):
			var offset := Vector3(randf_range(-4, 4), randf_range(1, 4), randf_range(-8, 8))
			ExplosionScript.spawn(parent, impact_pos + offset, 24.0, 450.0)

	# List to starboard, smoke, and burn
	var tween := ship.create_tween()
	tween.tween_property(ship, "rotation_degrees:z", 28.0, 4.0)
	tween.parallel().tween_property(ship, "position:y", ship.position.y - 3.5, 6.0)


## ==============================================================================
## HYDROELECTRIC POWER STATION (ГІДРОЕЛЕКТРОСТАНЦІЯ / ГЕС)
## Monolithic concrete dam, 4-bay radial sluice spillway, turbine machine hall,
## outdoor 330 kV transformer yard, transmission towers, and floating defense booms.
## Strategic target for USV Magura-X naval attack mission.
## ==============================================================================
static func spawn_hydroelectric_power_station(parent: Node3D, pos: Vector3, on_destroyed_callback: Callable = Callable()) -> Node3D:
	var station := Node3D.new()
	station.name = "HydroelectricPowerStation_Dnipro"
	station.position = pos
	station.rotation_degrees.y = 150.0 # Faces the downstream machine hall & spillways towards the incoming Magura approach
	if on_destroyed_callback.is_valid():
		station.set_meta("on_destroyed", on_destroyed_callback)
	parent.add_child(station)

	# --- PBR Materials matching BigLevel scenery style ---
	var dam_mat := StandardMaterial3D.new()
	dam_mat.albedo_color = Color(0.44, 0.45, 0.44) # Monolithic hydro concrete
	dam_mat.roughness = 0.86

	var waterline_mat := StandardMaterial3D.new()
	waterline_mat.albedo_color = Color(0.24, 0.27, 0.26) # Wet stained concrete at water line
	waterline_mat.roughness = 0.45
	waterline_mat.metallic = 0.15

	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.20, 0.20, 0.22) # Asphalt crest roadway
	road_mat.roughness = 0.92

	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.80, 0.15) # Yellow road marking
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var gate_mat := StandardMaterial3D.new()
	gate_mat.albedo_color = Color(0.68, 0.22, 0.16) # Hydraulic oxide red steel
	gate_mat.metallic = 0.72
	gate_mat.roughness = 0.45

	var penstock_mat := StandardMaterial3D.new()
	penstock_mat.albedo_color = Color(0.18, 0.20, 0.22) # Heavy industrial steel conduits
	penstock_mat.metallic = 0.85
	penstock_mat.roughness = 0.40

	var hall_wall_mat := StandardMaterial3D.new()
	hall_wall_mat.albedo_color = Color(0.28, 0.32, 0.36) # Machine hall industrial siding
	hall_wall_mat.metallic = 0.35
	hall_wall_mat.roughness = 0.65

	var hall_roof_mat := StandardMaterial3D.new()
	hall_roof_mat.albedo_color = Color(0.22, 0.24, 0.26) # Dark metal roof
	hall_roof_mat.roughness = 0.75

	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(0.95, 0.82, 0.45) # Glowing amber turbine hall windows
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.76, 0.30)
	window_mat.emission_energy_multiplier = 2.4
	station.set_meta("window_mat", window_mat)

	var transformer_mat := StandardMaterial3D.new()
	transformer_mat.albedo_color = Color(0.25, 0.28, 0.25) # Dark olive transformer tank
	transformer_mat.metallic = 0.45
	transformer_mat.roughness = 0.60

	var insulator_mat := StandardMaterial3D.new()
	insulator_mat.albedo_color = Color(0.55, 0.28, 0.18) # Brown ceramic high-voltage bushings
	insulator_mat.roughness = 0.25

	var pylon_steel_mat := StandardMaterial3D.new()
	pylon_steel_mat.albedo_color = Color(0.50, 0.52, 0.54) # Galvanized steel lattice
	pylon_steel_mat.metallic = 0.80
	pylon_steel_mat.roughness = 0.40

	var churn_mat := StandardMaterial3D.new()
	churn_mat.albedo_color = Color(0.88, 0.94, 0.98, 0.85) # Churning spillway foam
	churn_mat.roughness = 0.15
	churn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var sign_gold_mat := StandardMaterial3D.new()
	sign_gold_mat.albedo_color = Color(0.98, 0.82, 0.20)
	sign_gold_mat.emission_enabled = true
	sign_gold_mat.emission = Color(0.95, 0.75, 0.15)
	sign_gold_mat.emission_energy_multiplier = 1.2

	# -------------------------------------------------------------------------
	# 1. MONOLITHIC DAM BODY & CREST ROADWAY (180m span, 30m height)
	# -------------------------------------------------------------------------
	# Monolithic Lower Base (submerged in water)
	var dam_base := MeshInstance3D.new()
	var db_box := BoxMesh.new()
	db_box.size = Vector3(180.0, 6.0, 24.0)
	dam_base.mesh = db_box
	dam_base.position = Vector3(0.0, 1.0, 0.0)
	dam_base.material_override = waterline_mat
	station.add_child(dam_base)

	# Main Dam Body Wall (Stepped concrete gravity section)
	var dam_main := MeshInstance3D.new()
	var dm_box := BoxMesh.new()
	dm_box.size = Vector3(180.0, 24.0, 16.0)
	dam_main.mesh = dm_box
	dam_main.position = Vector3(0.0, 15.0, 0.0)
	dam_main.material_override = dam_mat
	station.add_child(dam_main)

	# Sloped Downstream Face (Bevelled spillway slope)
	var dam_slope := MeshInstance3D.new()
	var ds_prism := PrismMesh.new()
	ds_prism.size = Vector3(180.0, 24.0, 10.0)
	dam_slope.mesh = ds_prism
	dam_slope.position = Vector3(0.0, 15.0, -13.0)
	dam_slope.rotation_degrees.x = 90.0
	dam_slope.material_override = dam_mat
	station.add_child(dam_slope)

	# Dam Crest Roadway (2-lane asphalt highway spanning the dam)
	var crest_road := MeshInstance3D.new()
	var cr_box := BoxMesh.new()
	cr_box.size = Vector3(184.0, 1.6, 9.6)
	crest_road.mesh = cr_box
	crest_road.position = Vector3(0.0, 27.8, 0.0)
	crest_road.material_override = road_mat
	station.add_child(crest_road)

	# Road Divider Center Stripe
	var stripe := MeshInstance3D.new()
	var str_box := BoxMesh.new()
	str_box.size = Vector3(180.0, 0.05, 0.35)
	stripe.mesh = str_box
	stripe.position = Vector3(0.0, 28.65, 0.0)
	stripe.material_override = line_mat
	station.add_child(stripe)

	# Crest Guardrails (concrete parapet walls)
	for side in [-4.6, 4.6]:
		var rail := MeshInstance3D.new()
		var r_box := BoxMesh.new()
		r_box.size = Vector3(184.0, 1.2, 0.4)
		rail.mesh = r_box
		rail.position = Vector3(0.0, 29.2, side)
		rail.material_override = dam_mat
		station.add_child(rail)

	# Highway Light Poles along dam crest
	for lp in range(-4, 5):
		var pole_x: float = float(lp) * 20.0
		var pole := MeshInstance3D.new()
		var p_cyl := CylinderMesh.new()
		p_cyl.top_radius = 0.08
		p_cyl.bottom_radius = 0.12
		p_cyl.height = 7.0
		pole.mesh = p_cyl
		pole.position = Vector3(pole_x, 32.5, 4.4)
		pole.material_override = pylon_steel_mat
		station.add_child(pole)

		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.light_energy = 1.4
		lamp.omni_range = 22.0
		lamp.position = Vector3(pole_x, 36.0, 4.0)
		station.add_child(lamp)

	# Left and Right Shore Abutment Anchor Rocks
	for sign_x in [-96.0, 96.0]:
		var abut := MeshInstance3D.new()
		var ab_box := BoxMesh.new()
		ab_box.size = Vector3(18.0, 34.0, 32.0)
		abut.mesh = ab_box
		abut.position = Vector3(sign_x, 15.0, 0.0)
		abut.material_override = dam_mat
		station.add_child(abut)

	# -------------------------------------------------------------------------
	# 2. SPILLWAY 4-BAY RADIAL SLUICE GATES
	# -------------------------------------------------------------------------
	for bay in range(4):
		var bay_x: float = -22.5 + float(bay) * 15.0
		# Concrete dividing pier
		if bay > 0:
			var pier := MeshInstance3D.new()
			var p_box := BoxMesh.new()
			p_box.size = Vector3(2.0, 18.0, 18.0)
			pier.mesh = p_box
			pier.position = Vector3(bay_x - 7.5, 17.0, -9.0)
			pier.material_override = dam_mat
			station.add_child(pier)

		# Radial Steel Gate
		var gate := MeshInstance3D.new()
		var g_box := BoxMesh.new()
		g_box.size = Vector3(12.5, 9.5, 2.0)
		gate.mesh = g_box
		gate.position = Vector3(bay_x, 13.0, -11.5)
		gate.rotation_degrees.x = 24.0
		gate.material_override = gate_mat
		station.add_child(gate)

		# Water froth / churning pool under sluices
		var churn := MeshInstance3D.new()
		var ch_box := BoxMesh.new()
		ch_box.size = Vector3(13.0, 0.4, 14.0)
		churn.mesh = ch_box
		churn.position = Vector3(bay_x, 0.3, -22.0)
		churn.material_override = churn_mat
		station.add_child(churn)

	# -------------------------------------------------------------------------
	# 3. TURBINE GENERATOR MACHINE HALL (МАШИННИЙ ЗАЛ ГЕС) - PRIMARY IMPACT ZONE
	# -------------------------------------------------------------------------
	var hall_root := Node3D.new()
	hall_root.name = "MachineHall"
	hall_root.position = Vector3(0.0, 0.0, -28.0)
	station.add_child(hall_root)
	station.set_meta("hall_root", hall_root)

	# Concrete Substructure (turbines underwater intake)
	var hall_sub := MeshInstance3D.new()
	var hs_box := BoxMesh.new()
	hs_box.size = Vector3(76.0, 5.0, 22.0)
	hall_sub.mesh = hs_box
	hall_sub.position = Vector3(0.0, 2.5, 0.0)
	hall_sub.material_override = waterline_mat
	hall_root.add_child(hall_sub)

	# Main Machine Hall Superstructure
	var hall_body := MeshInstance3D.new()
	var hb_box := BoxMesh.new()
	hb_box.size = Vector3(74.0, 13.0, 20.0)
	hall_body.mesh = hb_box
	hall_body.position = Vector3(0.0, 11.5, 0.0)
	hall_body.material_override = hall_wall_mat
	hall_root.add_child(hall_body)

	# Gabled Industrial Roof
	var hall_roof := MeshInstance3D.new()
	var hr_prism := PrismMesh.new()
	hr_prism.size = Vector3(20.4, 4.2, 74.4)
	hall_roof.mesh = hr_prism
	hall_roof.position = Vector3(0.0, 20.0, 0.0)
	hall_roof.rotation_degrees.y = 90.0
	hall_roof.material_override = hall_roof_mat
	hall_root.add_child(hall_roof)

	# 4 Glowing Amber Window Banks (revealing spinning generators inside)
	for w in range(4):
		var wx: float = -27.0 + float(w) * 18.0
		var win := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(13.0, 6.5, 0.3)
		win.mesh = wb
		win.position = Vector3(wx, 11.5, -10.15)
		win.material_override = window_mat
		hall_root.add_child(win)

		# Warm amber generator glow on the water
		var omni := OmniLight3D.new()
		omni.light_color = Color(1.0, 0.72, 0.32)
		omni.light_energy = 2.5
		omni.omni_range = 28.0
		omni.position = Vector3(wx, 6.0, -14.0)
		hall_root.add_child(omni)

	# 4 Heavy Steel Penstock Pipes (water conduits connecting dam to turbines)
	for p in range(4):
		var px: float = -27.0 + float(p) * 18.0
		var penstock := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.85
		cyl.bottom_radius = 1.85
		cyl.height = 24.0
		cyl.radial_segments = 14
		penstock.mesh = cyl
		penstock.position = Vector3(px, 14.0, 12.0)
		penstock.rotation_degrees.x = -48.0
		penstock.material_override = penstock_mat
		hall_root.add_child(penstock)

	# Overhead Gantry Crane on the Roof
	var crane := Node3D.new()
	crane.name = "GantryCrane"
	crane.position = Vector3(0.0, 22.5, 0.0)
	hall_root.add_child(crane)
	station.set_meta("crane", crane)

	var cr_beam := MeshInstance3D.new()
	var crb_box := BoxMesh.new()
	crb_box.size = Vector3(68.0, 2.2, 3.4)
	cr_beam.mesh = crb_box
	cr_beam.position = Vector3(0.0, 0.0, 0.0)
	cr_beam.material_override = gate_mat
	crane.add_child(cr_beam)

	# 3D Ukrainian Signage Panel on the Machine Hall Facade
	var sign_board := MeshInstance3D.new()
	var sgb_box := BoxMesh.new()
	sgb_box.size = Vector3(44.0, 3.2, 0.5)
	sign_board.mesh = sgb_box
	sign_board.position = Vector3(0.0, 16.5, -10.3)
	sign_board.material_override = waterline_mat
	hall_root.add_child(sign_board)

	var sign_strip := MeshInstance3D.new()
	var sgs_box := BoxMesh.new()
	sgs_box.size = Vector3(40.0, 1.8, 0.2)
	sign_strip.mesh = sgs_box
	sign_strip.position = Vector3(0.0, 16.5, -10.65)
	sign_strip.material_override = sign_gold_mat
	hall_root.add_child(sign_strip)

	# -------------------------------------------------------------------------
	# 4. HIGH-VOLTAGE TRANSFORMER SUBSTATION & TRANSMISSION PYLONS
	# -------------------------------------------------------------------------
	var tf_root := Node3D.new()
	tf_root.name = "TransformerYard"
	tf_root.position = Vector3(56.0, 0.0, -22.0)
	station.add_child(tf_root)
	station.set_meta("tf_root", tf_root)

	var tf_deck := MeshInstance3D.new()
	var tfd_box := BoxMesh.new()
	tfd_box.size = Vector3(34.0, 4.0, 22.0)
	tf_deck.mesh = tfd_box
	tf_deck.position = Vector3(0.0, 2.0, 0.0)
	tf_deck.material_override = dam_mat
	tf_root.add_child(tf_deck)

	# 3 Massive 330 kV Step-Up Power Transformers
	for t in range(3):
		var tx: float = -10.0 + float(t) * 10.0
		var tf := MeshInstance3D.new()
		var tfb := BoxMesh.new()
		tfb.size = Vector3(6.2, 5.5, 7.0)
		tf.mesh = tfb
		tf.position = Vector3(tx, 6.8, 0.0)
		tf.material_override = transformer_mat
		tf_root.add_child(tf)

		# Bushings / insulators
		for b in [-1.5, 1.5]:
			var ins := MeshInstance3D.new()
			var ic := CylinderMesh.new()
			ic.top_radius = 0.2
			ic.bottom_radius = 0.4
			ic.height = 2.4
			ins.mesh = ic
			ins.position = Vector3(tx + b, 10.5, 0.0)
			ins.material_override = insulator_mat
			tf_root.add_child(ins)

	# 2 Tall Steel Transmission Pylons (Опори ЛЕП, 38m high)
	for py in [-14.0, 14.0]:
		var pylon := Node3D.new()
		pylon.position = Vector3(py, 4.0, 8.0)
		tf_root.add_child(pylon)

		var tower := MeshInstance3D.new()
		var tw_box := BoxMesh.new()
		tw_box.size = Vector3(2.4, 34.0, 2.4)
		tower.mesh = tw_box
		tower.position = Vector3(0.0, 17.0, 0.0)
		tower.material_override = pylon_steel_mat
		pylon.add_child(tower)

		var arm := MeshInstance3D.new()
		var a_box := BoxMesh.new()
		a_box.size = Vector3(14.0, 1.2, 1.6)
		arm.mesh = a_box
		arm.position = Vector3(0.0, 31.0, 0.0)
		arm.material_override = pylon_steel_mat
		pylon.add_child(arm)

	# -------------------------------------------------------------------------
	# 5. DISPATCH CONTROL TOWER (ДИСПЕТЧЕРСЬКИЙ ПУНКТ ГЕС)
	# -------------------------------------------------------------------------
	var tower_root := Node3D.new()
	tower_root.position = Vector3(-48.0, 28.5, 0.0)
	station.add_child(tower_root)

	var tw_body := MeshInstance3D.new()
	var twb_box := BoxMesh.new()
	twb_box.size = Vector3(10.0, 12.0, 10.0)
	tw_body.mesh = twb_box
	tw_body.position = Vector3(0.0, 6.0, 0.0)
	tw_body.material_override = dam_mat
	tower_root.add_child(tw_body)

	var tw_glass := MeshInstance3D.new()
	var twg_box := BoxMesh.new()
	twg_box.size = Vector3(10.4, 3.4, 10.4)
	tw_glass.mesh = twg_box
	tw_glass.position = Vector3(0.0, 9.5, 0.0)
	tw_glass.material_override = window_mat
	tower_root.add_child(tw_glass)

	# Red Aviation Hazard Beacon
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.15, 0.1)
	beacon.light_energy = 3.5
	beacon.omni_range = 35.0
	beacon.position = Vector3(0.0, 14.5, 0.0)
	tower_root.add_child(beacon)

	# -------------------------------------------------------------------------
	# 6. MARITIME ANTI-SABOTAGE BOOM BARRIER (БОНОВІ ЗАГОРОДЖЕННЯ)
	# -------------------------------------------------------------------------
	# Positioned 115m downstream with a 26m navigable breached section in the center
	var boom_root := Node3D.new()
	boom_root.name = "BoomBarrier"
	station.add_child(boom_root)

	var boom_mat := StandardMaterial3D.new()
	boom_mat.albedo_color = Color(0.85, 0.45, 0.15) # Safety orange floats
	boom_mat.roughness = 0.50

	for b_idx in range(18):
		var bx: float = -80.0 + float(b_idx) * 9.5
		# Keep a 26m wide breached opening in the center for Magura attack path!
		if absf(bx) < 13.0:
			continue
		var b_float := MeshInstance3D.new()
		var bf_cyl := CylinderMesh.new()
		bf_cyl.top_radius = 0.75
		bf_cyl.bottom_radius = 0.75
		bf_cyl.height = 4.5
		b_float.mesh = bf_cyl
		b_float.position = Vector3(bx, 0.4, -95.0)
		b_float.rotation_degrees.z = 90.0
		b_float.material_override = boom_mat
		boom_root.add_child(b_float)

	# Breached opening hazard buoys (flashing markers on left and right edge of gap)
	for gap_x in [-14.0, 14.0]:
		var g_buoy := MeshInstance3D.new()
		var gb_cyl := CylinderMesh.new()
		gb_cyl.top_radius = 0.6
		gb_cyl.bottom_radius = 0.8
		gb_cyl.height = 1.6
		g_buoy.mesh = gb_cyl
		g_buoy.position = Vector3(gap_x, 0.5, -95.0)
		g_buoy.material_override = sign_gold_mat
		boom_root.add_child(g_buoy)

		var g_light := OmniLight3D.new()
		g_light.light_color = Color(1.0, 0.8, 0.1)
		g_light.light_energy = 2.0
		g_light.omni_range = 16.0
		g_light.position = Vector3(gap_x, 1.8, -95.0)
		boom_root.add_child(g_light)

	# -------------------------------------------------------------------------
	# 7. SOLID PHYSICS COLLISION (DAM BODY & MACHINE HALL)
	# -------------------------------------------------------------------------
	var dam_body := StaticBody3D.new()
	dam_body.name = "DamCollision"
	dam_body.collision_layer = 1
	dam_body.collision_mask = 1

	# Dam Wall collision
	var c_dam := CollisionShape3D.new()
	var box_dam := BoxShape3D.new()
	box_dam.size = Vector3(184.0, 30.0, 20.0)
	c_dam.shape = box_dam
	c_dam.position = Vector3(0.0, 15.0, 0.0)
	dam_body.add_child(c_dam)

	# Machine Hall collision
	var c_hall := CollisionShape3D.new()
	var box_hall := BoxShape3D.new()
	box_hall.size = Vector3(78.0, 20.0, 24.0)
	c_hall.shape = box_hall
	c_hall.position = Vector3(0.0, 10.0, -28.0)
	dam_body.add_child(c_hall)

	station.add_child(dam_body)

	# -------------------------------------------------------------------------
	# 8. DESTRUCTIBLE COMBAT TARGET & IMPACT TRIGGER AREA
	# -------------------------------------------------------------------------
	var ct := CombatTargetScript.new()
	ct.name = "CombatTarget"
	ct.kind = CombatTargetScript.Kind.BUNKER
	ct.max_health = 1000.0
	ct.points = 2500
	station.add_child(ct)

	# Impact Area3D detecting direct Magura-X ramming or dropped payload
	var impact_area := Area3D.new()
	impact_area.name = "HydroImpactArea"
	impact_area.collision_layer = 0xFFFFFFFF
	impact_area.collision_mask = 0xFFFFFFFF

	var a_col := CollisionShape3D.new()
	var a_shape := BoxShape3D.new()
	a_shape.size = Vector3(92.0, 26.0, 36.0)
	a_col.shape = a_shape
	a_col.position = Vector3(0.0, 10.0, -26.0)
	impact_area.add_child(a_col)
	station.add_child(impact_area)

	impact_area.body_entered.connect(func(body: Node):
		if body is RigidBody3D: # USV Magura-X ramming impact
			_detonate_hydro_station(station, body, (body as Node3D).global_position)
	)

	impact_area.area_entered.connect(func(area_node: Area3D):
		_detonate_hydro_station(station, null, area_node.global_position)
	)

	ct.destroyed.connect(func(pts: int):
		_detonate_hydro_station(station, null, station.global_position + Vector3(0, 10, -28))
	)

	return station


## ==============================================================================
## CATASTROPHIC SIMULTANEOUS EXPLOSION SEQUENCE
## When Magura-X rams the hydroelectric power station, BOTH explode together!
## Multi-stage turbine breaches, transformer oil blasts, water geysers, screen shake.
## ==============================================================================
static func _detonate_hydro_station(station: Node3D, drone_body: Node, impact_pos: Vector3) -> void:
	if not is_instance_valid(station):
		return
	if station.has_meta("destroyed"):
		return
	station.set_meta("destroyed", true)

	print("[NavalSceneBuilder] CATASTROPHIC DETONATION: Hydroelectric Power Station destroyed by USV Magura-X!")

	var parent := station.get_parent()

	# 1. Destroy Magura-X instantly at point of impact (detonating 320 kg HE warhead)
	if drone_body != null and is_instance_valid(drone_body):
		if drone_body is RigidBody3D:
			var rb := drone_body as RigidBody3D
			rb.freeze = true
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
		var dm := drone_body.get_node_or_null("DroneModel") as Node3D
		if dm != null:
			dm.visible = false

	# 2. Initial colossal warhead blast at impact point (radius 38m, 950 damage)
	if parent != null:
		ExplosionScript.spawn(parent, impact_pos, 38.0, 950.0)

	# 3. Visual destruction of the Machine Hall
	var win_mat = station.get_meta("window_mat")
	if win_mat is StandardMaterial3D:
		win_mat.emission_enabled = false
		win_mat.albedo_color = Color(0.08, 0.08, 0.08)

	var crane := station.get_meta("crane") as Node3D
	if crane != null and is_instance_valid(crane):
		var ctween: Tween = crane.create_tween()
		if ctween != null:
			ctween.tween_property(crane, "rotation_degrees:z", -18.0, 1.2)
			ctween.parallel().tween_property(crane, "position:y", crane.position.y - 2.5, 1.2)

	# 4. Multi-stage chain-reaction explosions across generator turbines and transformers
	if parent != null:
		var scene_tree := parent.get_tree()
		if scene_tree != null:
			# t+0.18s: Turbine Generator #1 & #2 breach
			scene_tree.create_timer(0.18).timeout.connect(func():
				if is_instance_valid(station) and is_instance_valid(parent):
					var p1 := station.to_global(Vector3(-22.0, 8.0, -28.0))
					ExplosionScript.spawn(parent, p1, 28.0, 500.0)
			)
			# t+0.36s: Turbine Generator #3 & #4 breach + water geyser
			scene_tree.create_timer(0.36).timeout.connect(func():
				if is_instance_valid(station) and is_instance_valid(parent):
					var p2 := station.to_global(Vector3(18.0, 8.0, -28.0))
					ExplosionScript.spawn(parent, p2, 30.0, 500.0)
			)
			# t+0.55s: 330 kV Transformer Substation catastrophic rupture (huge arc fireball)
			scene_tree.create_timer(0.55).timeout.connect(func():
				if is_instance_valid(station) and is_instance_valid(parent):
					var p3 := station.to_global(Vector3(56.0, 10.0, -22.0))
					ExplosionScript.spawn(parent, p3, 34.0, 700.0)
			)
			# t+0.85s: Spillway radial gate collapse
			scene_tree.create_timer(0.85).timeout.connect(func():
				if is_instance_valid(station) and is_instance_valid(parent):
					var p4 := station.to_global(Vector3(0.0, 14.0, -12.0))
					ExplosionScript.spawn(parent, p4, 32.0, 600.0)
			)

	# 5. Notify BigLevel mission completion callback
	if station.has_meta("on_destroyed"):
		var cb = station.get_meta("on_destroyed")
		if cb is Callable and cb.is_valid():
			cb.call(2500)

