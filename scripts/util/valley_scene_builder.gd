class_name ValleySceneBuilder
extends RefCounted

const OPEN_TOWER := preload("res://scripts/util/open_tower.gd")

## Builds photorealistic FPV simulator valley landmarks inspired by FeelFPV / TRYP:
## 1. Surrounding valley mountain ring & rolling grassy hills.
## 2. Detailed abandoned industrial factory complex (arched hangar, 5-story open
##    concrete frame building, multi-window factory wing, 3 tall smokestacks).
## 3. Curved railway embankment with a yellow diesel locomotive, blue gondola
##    car, and red-brown freight boxcars.
## 4. Multi-species silver birch (with white bark & green/lime/gold/autumn
##    foliage), pine conifers, and trackside shrubs.


static func _make_pbr_mat(albedo: Color, roughness: float = 0.88, metallic: float = 0.0,
		tex_path: String = "", normal_path: String = "", triplanar_scale: float = 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	if not tex_path.is_empty() and ResourceLoader.exists(tex_path):
		m.albedo_texture = load(tex_path)
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(triplanar_scale, triplanar_scale, triplanar_scale)
	if not normal_path.is_empty() and ResourceLoader.exists(normal_path):
		m.normal_enabled = true
		m.normal_texture = load(normal_path)
	return m


static func _add_static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material,
		rot_rad: Vector3 = Vector3.ZERO, with_collision: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot_rad
	mi.material_override = mat
	if not with_collision:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if with_collision:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 1
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


static func _add_static_cyl(parent: Node3D, top_r: float, bot_r: float, height: float,
		pos: Vector3, mat: Material, rot_rad: Vector3 = Vector3.ZERO,
		segments: int = 16, with_collision: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bot_r
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	mi.mesh = cm
	mi.position = pos
	mi.rotation = rot_rad
	mi.material_override = mat
	if not with_collision:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if with_collision:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 1
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = maxf(top_r, bot_r)
		shape.height = height
		cs.shape = shape
		sb.add_child(cs)
		mi.add_child(sb)
	return mi


static func _add_torus(parent: Node3D, pos: Vector3, radius: float,
		tube: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(radius - tube, 0.05)
	torus.outer_radius = radius + tube
	torus.rings = 28
	torus.ring_segments = 10
	mi.mesh = torus
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## 1. Surrounding valley hills & mountains built as a continuous organic 3D
## displaced mountain ring with multi-octave ridged noise and vertex-colored
## grass-to-rock blending (no flat-topped cylinders!).
static func build_valley_mountains(scene_root: Node3D, base_y: float = 0.0,
		r_inner: float = 235.0, r_outer: float = 1350.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ValleyMountains"
	scene_root.add_child(holder)

	var ridge_noise := FastNoiseLite.new()
	ridge_noise.seed = 4901
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.fractal_octaves = 4
	ridge_noise.frequency = 0.0022

	var detail_noise := FastNoiseLite.new()
	detail_noise.seed = 8812
	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.fractal_octaves = 3
	detail_noise.frequency = 0.0065

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ang_steps := 144
	var rad_steps := 36

	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var cols: Array[Color] = []

	var meadow_col := Color(0.28, 0.36, 0.14)
	var slope_grass := Color(0.32, 0.38, 0.18)
	var scree_blend := Color(0.46, 0.45, 0.38)
	var peak_rock := Color(0.56, 0.55, 0.51)

	for ir in range(rad_steps + 1):
		var tr := float(ir) / float(rad_steps)
		# Non-linear radial spacing for finer detail near the valley floor edge
		var r := lerpf(r_inner, r_outer, pow(tr, 1.15))
		# Smoothly rise from 0 at valley edge, peak around tr=0.65, taper at outer horizon
		var env := sin(clampf(tr * 1.18, 0.0, 1.0) * PI * 0.82)
		env = pow(maxf(0.0, env), 1.45)
		for ia in range(ang_steps + 1):
			var a := (float(ia) / float(ang_steps)) * TAU
			var x := cos(a) * r
			var z := sin(a) * r
			var n1 := ridge_noise.get_noise_2d(x, z) * 0.5 + 0.5 # 0..1
			var n2 := detail_noise.get_noise_2d(x, z) * 0.5 + 0.5
			# Sculpt dramatic framing peaks on the left (-X, -Z) and right (+X, -Z)
			# of the valley while keeping a gentle saddle pass behind the factory
			var pass_mask := 1.0 - 0.32 * exp(-pow((a - PI * 1.52) / 0.38, 2.0))
			var h := env * pass_mask * (32.0 + n1 * 135.0 + n2 * 36.0)
			if tr < 0.08:
				h *= (tr / 0.08)
			var y := base_y - 0.6 + h
			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(x * 0.018, z * 0.018))

			var h_norm := clampf(h / 135.0, 0.0, 1.0)
			var c: Color
			if h_norm < 0.28:
				c = meadow_col.lerp(slope_grass, h_norm / 0.28)
			elif h_norm < 0.62:
				c = slope_grass.lerp(scree_blend, (h_norm - 0.28) / 0.34)
			else:
				c = scree_blend.lerp(peak_rock, (h_norm - 0.62) / 0.38)
			cols.append(c)

	var stride := ang_steps + 1
	for ir in range(rad_steps):
		for ia in range(ang_steps):
			var i00 := ir * stride + ia
			var i10 := (ir + 1) * stride + ia
			var i01 := ir * stride + (ia + 1)
			var i11 := (ir + 1) * stride + (ia + 1)

			# Upward (+Y) normal winding order in Godot right-handed coordinates:
			st.set_color(cols[i00])
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])

			st.set_color(cols[i11])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])

			st.set_color(cols[i10])
			st.set_uv(uvs[i10])
			st.add_vertex(verts[i10])

			st.set_color(cols[i00])
			st.set_uv(uvs[i00])
			st.add_vertex(verts[i00])

			st.set_color(cols[i01])
			st.set_uv(uvs[i01])
			st.add_vertex(verts[i01])

			st.set_color(cols[i11])
			st.set_uv(uvs[i11])
			st.add_vertex(verts[i11])

	st.generate_normals()
	var m_mesh := st.commit()

	var m_mat := StandardMaterial3D.new()
	m_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m_mat.vertex_color_use_as_albedo = true
	m_mat.albedo_color = Color(1.0, 1.0, 1.0)
	m_mat.roughness = 0.94
	if ResourceLoader.exists("res://Assets/Textures/2.png"):
		m_mat.albedo_texture = load("res://Assets/Textures/2.png")
		m_mat.uv1_world_triplanar = true
		m_mat.uv1_scale = Vector3(0.035, 0.035, 0.035)
	if ResourceLoader.exists("res://Assets/Textures/NormalMap-2.png"):
		m_mat.normal_enabled = true
		m_mat.normal_texture = load("res://Assets/Textures/NormalMap-2.png")
		m_mat.normal_scale = 0.85

	var mi := MeshInstance3D.new()
	mi.name = "MountainRingMesh"
	mi.mesh = m_mesh
	mi.material_override = m_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)

	return holder


## 2. Detailed Abandoned Industrial Factory Complex + Curved Railway & Freight Train.
static func build_industrial_complex(scene_root: Node3D, origin: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "IndustrialComplex"
	scene_root.add_child(root)
	root.global_position = origin

	var concrete_light := _make_pbr_mat(Color(0.66, 0.65, 0.62), 0.90, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.22)
	var concrete_weathered := _make_pbr_mat(Color(0.54, 0.53, 0.50), 0.92, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.18)
	var concrete_dark := _make_pbr_mat(Color(0.38, 0.38, 0.36), 0.94, 0.05,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.25)
	var roof_metal := _make_pbr_mat(Color(0.44, 0.45, 0.47), 0.65, 0.35)
	var chimney_band_red := _make_pbr_mat(Color(0.76, 0.32, 0.18), 0.85, 0.0)
	var dark_interior := _make_pbr_mat(Color(0.14, 0.15, 0.16), 0.95, 0.0)
	var asphalt_mat := _make_pbr_mat(Color(0.36, 0.36, 0.35), 0.92, 0.0,
			"res://Assets/Textures/2.png", "res://Assets/Textures/NormalMap-2.png", 0.15)

	# Concrete industrial yard apron and deep subterranean bedrock plinth
	# Prevents drone from ever clipping beneath the foundation on undulating terrain
	_add_static_box(root, Vector3(190.0, 8.0, 150.0), Vector3(0.0, -3.95, -12.0),
			concrete_dark, Vector3.ZERO, true)
	_add_static_box(root, Vector3(180.0, 0.22, 140.0), Vector3(0.0, 0.05, -12.0),
			asphalt_mat, Vector3.ZERO, true)
	_add_static_box(root, Vector3(16.0, 8.0, 190.0), Vector3(-68.0, -3.95, 24.0),
			concrete_dark, Vector3(0.0, deg_to_rad(18.0), 0.0), true)
	_add_static_box(root, Vector3(14.0, 0.20, 180.0), Vector3(-68.0, 0.05, 24.0),
			asphalt_mat, Vector3(0.0, deg_to_rad(18.0), 0.0), true)

	# --- A. Left Arched-Roof Main Factory Hangar (fly-through capable!) ---
	var hangar := Node3D.new()
	hangar.name = "ArchedHangar"
	hangar.position = Vector3(-34.0, 0.0, -14.0)
	hangar.rotation.y = deg_to_rad(14.0)
	root.add_child(hangar)

	var h_len := 44.0
	var h_wid := 20.0
	var h_wall_h := 11.5
	# Deep basement foundation under hangar
	_add_static_box(hangar, Vector3(h_wid + 4.0, 8.0, h_len + 4.0), Vector3(0.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)
	# Side walls with pilasters & window bands
	for side in [-1.0, 1.0]:
		var sx: float = side * (h_wid * 0.5)
		# Lower wall
		_add_static_box(hangar, Vector3(0.75, 4.2, h_len), Vector3(sx, 2.1, 0.0), concrete_light)
		# Upper wall band
		_add_static_box(hangar, Vector3(0.75, 2.6, h_len), Vector3(sx, 10.2, 0.0), concrete_weathered)
		# Vertical columns between open windows
		for p in range(-5, 6):
			var pz := float(p) * 4.0
			_add_static_box(hangar, Vector3(1.05, h_wall_h, 1.15),
					Vector3(sx, h_wall_h * 0.5, pz), concrete_weathered)
	# Front & back gable walls with wide open drone fly-through portals
	for end_s in [-1.0, 1.0]:
		var ez: float = end_s * (h_len * 0.5)
		_add_static_box(hangar, Vector3(5.5, h_wall_h, 0.8), Vector3(-7.25, h_wall_h * 0.5, ez), concrete_light)
		_add_static_box(hangar, Vector3(5.5, h_wall_h, 0.8), Vector3(7.25, h_wall_h * 0.5, ez), concrete_light)
		_add_static_box(hangar, Vector3(9.0, 3.5, 0.8), Vector3(0.0, h_wall_h - 1.75, ez), concrete_weathered)
	# Arched barrel-vault roof built from 7 angled roof segments
	var arch_segs := 7
	for s in range(arch_segs):
		var frac := (float(s) / float(arch_segs - 1)) * 2.0 - 1.0 # -1 to +1
		var angle := frac * 0.62
		var rx := frac * (h_wid * 0.48)
		var ry := h_wall_h + cos(frac * PI * 0.48) * 3.4 - 0.4
		_add_static_box(hangar, Vector3(3.6, 0.42, h_len + 1.2),
				Vector3(rx, ry, 0.0), roof_metal, Vector3(0.0, 0.0, -angle))

	# Front-left low workshop Annex (fly-through hollow workshop!)
	var annex := Node3D.new()
	annex.name = "WorkshopAnnex"
	annex.position = Vector3(-36.0, 0.0, 12.5)
	annex.rotation.y = deg_to_rad(14.0)
	root.add_child(annex)
	# Subterranean basement foundation under annex
	_add_static_box(annex, Vector3(20.0, 8.0, 11.5), Vector3(0.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)
	# Floor and roof
	_add_static_box(annex, Vector3(18.0, 0.3, 9.5), Vector3(0.0, 0.15, 0.0), concrete_weathered)
	_add_static_box(annex, Vector3(18.6, 0.45, 10.2), Vector3(0.0, 5.5, 0.0), concrete_dark)
	# Back wall (toward arched hangar): corner walls + open service door
	_add_static_box(annex, Vector3(6.5, 5.4, 0.6), Vector3(-5.75, 2.7, -4.45), concrete_weathered)
	_add_static_box(annex, Vector3(6.5, 5.4, 0.6), Vector3(5.75, 2.7, -4.45), concrete_weathered)
	_add_static_box(annex, Vector3(5.0, 1.8, 0.6), Vector3(0.0, 4.5, -4.45), concrete_weathered)
	# Left & right side walls with real open fly-through window portals
	for side in [-1.0, 1.0]:
		var ax: float = side * 8.7
		_add_static_box(annex, Vector3(0.6, 1.8, 9.5), Vector3(ax, 0.9, 0.0), concrete_weathered)
		_add_static_box(annex, Vector3(0.6, 1.4, 9.5), Vector3(ax, 4.7, 0.0), concrete_weathered)
		_add_static_box(annex, Vector3(0.65, 2.2, 1.2), Vector3(ax, 2.9, -3.2), concrete_light)
		_add_static_box(annex, Vector3(0.65, 2.2, 1.2), Vector3(ax, 2.9, 0.0), concrete_light)
		_add_static_box(annex, Vector3(0.65, 2.2, 1.2), Vector3(ax, 2.9, 3.2), concrete_light)
	# Front wall: open garage bay door (5.8m wide x 4.0m tall) for high-speed fly-in
	_add_static_box(annex, Vector3(5.8, 5.4, 0.6), Vector3(-6.1, 2.7, 4.45), concrete_weathered)
	_add_static_box(annex, Vector3(5.8, 5.4, 0.6), Vector3(6.1, 2.7, 4.45), concrete_weathered)
	_add_static_box(annex, Vector3(6.4, 1.4, 0.6), Vector3(0.0, 4.7, 4.45), concrete_dark)

	# --- B. Central Multi-Window Industrial Wing (Fly-Through Windows & Skylight!) ---
	var wing := Node3D.new()
	wing.name = "CentralFactoryWing"
	wing.position = Vector3(2.0, 0.0, -18.0)
	wing.rotation.y = deg_to_rad(8.0)
	root.add_child(wing)

	# Subterranean basement foundation under wing
	_add_static_box(wing, Vector3(40.0, 8.0, 16.5), Vector3(0.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)

	# 1. Base floor slab
	_add_static_box(wing, Vector3(38.0, 0.35, 15.0), Vector3(0.0, 0.17, 0.0), concrete_light)

	# 2. Roof perimeter slabs & massive open central skylight dive-hole (30m x 8.2m)
	_add_static_box(wing, Vector3(38.0, 0.45, 3.4), Vector3(0.0, 13.1, -5.8), concrete_dark)
	_add_static_box(wing, Vector3(38.0, 0.45, 3.4), Vector3(0.0, 13.1, 5.8), concrete_dark)
	_add_static_box(wing, Vector3(4.0, 0.45, 8.2), Vector3(-17.0, 13.1, 0.0), concrete_dark)
	_add_static_box(wing, Vector3(4.0, 0.45, 8.2), Vector3(17.0, 13.1, 0.0), concrete_dark)
	# Roof truss cross-ties across the skylight gap
	for tx in [-12.0, -6.0, 0.0, 6.0, 12.0]:
		_add_static_box(wing, Vector3(0.35, 0.55, 8.2), Vector3(tx, 13.0, 0.0), concrete_dark)

	# 3. End walls (Left X = -19.0, Right X = +19.0) with wide 6m x 6m cargo gateways
	for end_s in [-1.0, 1.0]:
		var ex: float = end_s * 18.6
		_add_static_box(wing, Vector3(0.8, 13.0, 4.5), Vector3(ex, 6.5, -5.25), concrete_light)
		_add_static_box(wing, Vector3(0.8, 13.0, 4.5), Vector3(ex, 6.5, 5.25), concrete_light)
		_add_static_box(wing, Vector3(0.8, 7.0, 6.0), Vector3(ex, 9.5, 0.0), concrete_weathered)

	# 4. Front (Z = +7.2) and Back (Z = -7.2) facades with 18 real fly-through windows
	# Window dimensions: 2.8m wide x 2.4m tall at floor 1 (Y ~ 3.75) and floor 2 (Y ~ 8.15)
	for fz in [-7.2, 7.2]:
		# Lower wall sill: Y = 0 to 2.4
		_add_static_box(wing, Vector3(38.0, 2.4, 0.6), Vector3(0.0, 1.2, fz), concrete_light)
		# Intermediate floor lintel band: Y = 5.1 to 6.8
		_add_static_box(wing, Vector3(38.0, 1.7, 0.6), Vector3(0.0, 5.95, fz), concrete_light)
		# Upper parapet roof band: Y = 9.5 to 13.0
		_add_static_box(wing, Vector3(38.0, 3.5, 0.6), Vector3(0.0, 11.25, fz), concrete_dark)
		# Vertical structural piers between each window column
		for col_p in range(-4, 4):
			var px := float(col_p) * 4.0 + 2.0
			_add_static_box(wing, Vector3(1.2, 2.7, 0.65), Vector3(px, 3.75, fz), concrete_weathered)
			_add_static_box(wing, Vector3(1.2, 2.7, 0.65), Vector3(px, 8.15, fz), concrete_weathered)
		# Corner solid wall caps
		_add_static_box(wing, Vector3(1.1, 7.1, 0.65), Vector3(-18.45, 5.95, fz), concrete_weathered)
		_add_static_box(wing, Vector3(1.1, 7.1, 0.65), Vector3(18.45, 5.95, fz), concrete_weathered)
		# Window ledges around openings
		for col_x in range(-4, 5):
			var wx := float(col_x) * 4.0
			_add_static_box(wing, Vector3(2.8, 0.12, 0.8), Vector3(wx, 2.4, fz), concrete_dark, Vector3.ZERO, false)
			_add_static_box(wing, Vector3(2.8, 0.12, 0.8), Vector3(wx, 6.8, fz), concrete_dark, Vector3.ZERO, false)

	# 5. Interior factory space: support columns & elevated catwalk
	for ix in [-10.0, 0.0, 10.0]:
		for iz in [-3.2, 3.2]:
			_add_static_box(wing, Vector3(0.85, 12.8, 0.85), Vector3(ix, 6.4, iz), concrete_weathered)
	# Catwalk at Y = 5.8m along the back wall with open railings
	_add_static_box(wing, Vector3(32.0, 0.22, 2.2), Vector3(0.0, 5.8, -4.5), concrete_dark)
	_add_static_box(wing, Vector3(32.0, 0.85, 0.08), Vector3(0.0, 6.35, -3.4), concrete_dark, Vector3.ZERO, false)

	# --- C. Right 5-Story Open Concrete Skeleton Building (fly-through floors!) ---
	var skel := Node3D.new()
	skel.name = "OpenFramePlant"
	skel.position = Vector3(28.0, 0.0, -10.0)
	skel.rotation.y = deg_to_rad(8.0)
	root.add_child(skel)

	var floors := 5
	var floor_h := 4.2
	var b_w := 22.0
	var b_d := 16.0
	# Subterranean basement foundation under skel
	_add_static_box(skel, Vector3(b_w + 2.0, 8.0, b_d + 2.0), Vector3(0.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)
	# Floor slabs
	for f in range(floors + 1):
		var fy := float(f) * floor_h
		_add_static_box(skel, Vector3(b_w, 0.45, b_d), Vector3(0.0, fy + 0.22, 0.0), concrete_light)
	# Open grid of reinforced concrete pillars so FPV drones can weave through any floor
	for ix in [-10.2, -5.1, 0.0, 5.1]:
		for iz in [-7.4, -2.5, 2.5, 7.4]:
			_add_static_box(skel, Vector3(0.75, floors * floor_h, 0.75),
					Vector3(ix, floors * floor_h * 0.5, iz), concrete_weathered)
	# Solid weathered concrete shear-wall core on the right side (just like the reference image!)
	_add_static_box(skel, Vector3(6.5, floors * floor_h + 1.8, b_d - 0.4),
			Vector3(7.6, (floors * floor_h + 1.8) * 0.5, 0.0), concrete_weathered)
	# Penthouse mechanical frame on top
	_add_static_box(skel, Vector3(12.0, 2.8, 10.0),
			Vector3(-2.5, floors * floor_h + 1.4, 0.0), concrete_dark)

	# --- D. Three Tall Tapered Industrial Smokestacks (Chimneys) ---
	# Subterranean basement foundation under smokestack plinths
	_add_static_box(root, Vector3(38.0, 8.0, 16.0), Vector3(-7.0, -3.95, -33.0), concrete_dark, Vector3.ZERO, true)
	var stacks := [
		{"pos": Vector3(-24.0, 0.0, -32.0), "h": 38.0, "r0": 2.15, "r1": 1.15},
		{"pos": Vector3(-11.0, 0.0, -35.0), "h": 35.0, "r0": 1.95, "r1": 1.05},
		{"pos": Vector3(10.0, 0.0, -34.0), "h": 24.0, "r0": 1.55, "r1": 0.90},
	]
	for st in stacks:
		var sp: Vector3 = st["pos"]
		var sh: float = st["h"]
		var r0: float = st["r0"]
		var r1: float = st["r1"]
		# Hollow tapered shell, open top with a thick sooty rim.  The player can
		# dive straight down the bore and leave through the base arch.  A solid
		# CylinderMesh here was exactly the capped "chimney" from the report.
		var open_min := 0.4
		var open_max := 4.2
		var r_open_min: float = lerpf(r0, r1, open_min / sh)
		var r_open_max: float = lerpf(r0, r1, open_max / sh)
		var profile: Array[Vector2] = [
			Vector2(r0, 0.0), Vector2(r_open_min, open_min),
			Vector2(r_open_max, open_max), Vector2(r1, sh),
		]
		OPEN_TOWER.build_profile(root, sp, profile, 0.30, concrete_light,
				concrete_dark,
				{"deg": 70.0, "min_h": open_min, "max_h": open_max, "count": 2},
				32, "Smokestack%d" % int(stacks.find(st)))
		# Warning bands and soot rim are toruses: solid discs would seal the bore.
		_add_torus(root, sp + Vector3(0.0, sh - 1.6, 0.0), r1 * 1.06,
				0.14, chimney_band_red)
		_add_torus(root, sp + Vector3(0.0, sh - 6.2, 0.0), r1 * 1.12,
				0.14, chimney_band_red)
		_add_torus(root, sp + Vector3(0.0, sh - 0.28, 0.0), r1 * 1.04,
				0.20, concrete_dark)

	# Small outbuildings on the right yard with deep subterranean foundation
	_add_static_box(root, Vector3(30.0, 8.0, 22.0), Vector3(44.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)
	_add_static_box(root, Vector3(9.5, 4.2, 7.0), Vector3(36.0, 2.1, 8.0), concrete_weathered, Vector3(0, deg_to_rad(8.0), 0))
	_add_static_box(root, Vector3(11.0, 4.8, 7.5), Vector3(52.0, 2.4, -8.0), concrete_light, Vector3(0, deg_to_rad(8.0), 0))

	return root


static func _make_track_multimesh(parent: Node3D, mesh_size: Vector3, mat: Material,
		transforms: Array[Transform3D]) -> void:
	var bm := BoxMesh.new()
	bm.size = mesh_size
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 1500.0
	mmi.ignore_occlusion_culling = true
	parent.add_child(mmi)


static func _track_point(t: float, y_elev: float = 0.0) -> Vector3:
	var u := fmod(fmod(t, 1.0) + 1.0, 1.0)
	var theta := u * TAU
	var x := 165.0 * cos(theta) - 15.0 * sin(2.0 * theta)
	var z := -70.0 + 140.0 * sin(theta) + 18.0 * cos(2.0 * theta)
	return Vector3(x, y_elev, z)


## Builds the complete 972m closed railway loop around the valley and spawns
## the autonomous moving freight train with headlights, exhaust, and solid car collision.
static func build_railway_loop_and_train(scene_root: Node3D, base_y: float = 0.0) -> Node3D:
	var holder := Node3D.new()
	holder.name = "RailwaySystem"
	scene_root.add_child(holder)

	var ballast_mat := _make_pbr_mat(Color(0.24, 0.22, 0.21), 0.96, 0.0)
	var sleeper_mat := _make_pbr_mat(Color(0.18, 0.13, 0.09), 0.94, 0.0)
	var steel_rail_mat := _make_pbr_mat(Color(0.42, 0.44, 0.46), 0.45, 0.75)

	var ballast_xf: Array[Transform3D] = []
	var rail_xf: Array[Transform3D] = []
	var sleeper_xf: Array[Transform3D] = []

	var segs := 160
	for i in range(segs):
		var t0 := float(i) / float(segs)
		var t1 := float(i + 1) / float(segs)
		var p0 := _track_point(t0, base_y)
		var p1 := _track_point(t1, base_y)
		var mid := (p0 + p1) * 0.5
		var dir := (p1 - p0)
		var seg_len := dir.length()
		var yaw := atan2(-dir.x, -dir.z)
		var b_rot := Basis(Vector3.UP, yaw)
		var scale_z := seg_len / 5.0
		# Deep ballast embankment embedding down into terrain along local track tangent
		var xf_ballast := Transform3D(b_rot, mid + Vector3(0.0, 0.16, 0.0)).scaled_local(Vector3(1.0, 1.0, scale_z))
		ballast_xf.append(xf_ballast)
		for r_side in [-0.76, 0.76]:
			var xf_rail := Transform3D(b_rot, mid + b_rot.x * r_side + Vector3(0.0, 0.40, 0.0)).scaled_local(Vector3(1.0, 1.0, scale_z))
			rail_xf.append(xf_rail)
		for sub in [0.15, 0.40, 0.65, 0.90]:
			var sp := p0.lerp(p1, sub)
			sleeper_xf.append(Transform3D(b_rot, sp + Vector3(0.0, 0.33, 0.0)))

	_make_track_multimesh(holder, Vector3(4.0, 0.65, 5.25), ballast_mat, ballast_xf)
	_make_track_multimesh(holder, Vector3(0.12, 0.16, 5.15), steel_rail_mat, rail_xf)
	_make_track_multimesh(holder, Vector3(2.6, 0.10, 0.28), sleeper_mat, sleeper_xf)

	# Moving Train Controller
	var train_node := MovingTrain.new()
	train_node.name = "MovingTrainController"
	train_node.base_y = base_y
	holder.add_child(train_node)

	# Train materials:
	var loco_yellow := _make_pbr_mat(Color(0.84, 0.58, 0.12), 0.68, 0.15)
	var loco_dark := _make_pbr_mat(Color(0.16, 0.17, 0.18), 0.78, 0.25)
	var glass_dark := _make_pbr_mat(Color(0.08, 0.11, 0.14), 0.25, 0.40)
	var gondola_blue := _make_pbr_mat(Color(0.14, 0.42, 0.52), 0.75, 0.15)
	var boxcar_red := _make_pbr_mat(Color(0.64, 0.26, 0.16), 0.80, 0.12)

	# Spawn cars
	var loco_node := _spawn_locomotive(train_node, 0.40, loco_yellow, loco_dark, glass_dark, base_y)
	var gondola1 := _spawn_gondola_car(train_node, 0.40 - 0.0165, gondola_blue, loco_dark, base_y)
	var gondola2 := _spawn_gondola_car(train_node, 0.40 - 0.0330, gondola_blue, loco_dark, base_y)
	var boxcar1 := _spawn_boxcar(train_node, 0.40 - 0.0495, boxcar_red, loco_dark, base_y, false)
	var boxcar2 := _spawn_boxcar(train_node, 0.40 - 0.0660, boxcar_red, loco_dark, base_y, true)

	train_node.loco = loco_node
	var car_list: Array[Node3D] = [gondola1, gondola2, boxcar1, boxcar2]
	train_node.cars = car_list

	return holder


## 7. Operational Railway Station with passenger platform, canopy roof,
## waiting hall, platform lampposts, station clock, and tactical Ukrainian signage.
static func build_railway_station(scene_root: Node3D, origin: Vector3, yaw_rad: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "RailwayStation"
	scene_root.add_child(root)
	root.global_position = origin
	root.rotation.y = yaw_rad

	var concrete_light := _make_pbr_mat(Color(0.70, 0.69, 0.66), 0.88, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.22)
	var concrete_weathered := _make_pbr_mat(Color(0.56, 0.55, 0.52), 0.92, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.18)
	var concrete_dark := _make_pbr_mat(Color(0.36, 0.36, 0.34), 0.94, 0.05,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.25)
	var asphalt_mat := _make_pbr_mat(Color(0.32, 0.32, 0.31), 0.92, 0.0,
			"res://Assets/Textures/2.png", "res://Assets/Textures/NormalMap-2.png", 0.15)
	var steel_dark := _make_pbr_mat(Color(0.20, 0.22, 0.25), 0.70, 0.50)
	var roof_metal := _make_pbr_mat(Color(0.38, 0.40, 0.44), 0.65, 0.40)
	var wood_mat := _make_pbr_mat(Color(0.42, 0.30, 0.18), 0.92, 0.0)
	var glass_mat := _make_pbr_mat(Color(0.12, 0.18, 0.24), 0.20, 0.60)
	var warning_yellow := _make_pbr_mat(Color(0.92, 0.72, 0.10), 0.70, 0.0)
	var sign_glow_mat := StandardMaterial3D.new()
	sign_glow_mat.albedo_color = Color(1.0, 0.78, 0.24)
	sign_glow_mat.emission_enabled = true
	sign_glow_mat.emission = Color(1.0, 0.74, 0.20)
	sign_glow_mat.emission_energy_multiplier = 2.4

	# Deep subterranean foundation plinth sealing any curvature gap under platform & building
	_add_static_box(root, Vector3(96.0, 8.0, 42.0), Vector3(0.0, -3.95, 12.0),
			concrete_dark, Vector3.ZERO, true)

	# --- A. Passenger Platform (88m long x 8m wide x 1.15m tall) ---
	var platform := Node3D.new()
	platform.name = "PassengerPlatform"
	root.add_child(platform)
	_add_static_box(platform, Vector3(88.0, 1.15, 8.0), Vector3(0.0, 0.575, 5.3), asphalt_mat, Vector3.ZERO, true)
	# Platform curb edge facing the tracks (Z = 1.3)
	_add_static_box(platform, Vector3(88.0, 1.15, 0.3), Vector3(0.0, 0.575, 1.35), concrete_weathered, Vector3.ZERO, true)
	# Yellow tactile warning safety stripe along track edge
	_add_static_box(platform, Vector3(88.0, 0.03, 0.35), Vector3(0.0, 1.16, 1.55), warning_yellow, Vector3.ZERO, false)
	# Access ramps on east and west ends
	_add_static_box(platform, Vector3(7.0, 1.15, 8.0), Vector3(-47.5, 0.45, 5.3), concrete_weathered, Vector3(0, 0, deg_to_rad(10.0)), true)
	_add_static_box(platform, Vector3(7.0, 1.15, 8.0), Vector3(47.5, 0.45, 5.3), concrete_weathered, Vector3(0, 0, deg_to_rad(-10.0)), true)

	# Steel Canopy Roof over the platform
	var canopy_len := 74.0
	_add_static_box(platform, Vector3(canopy_len, 0.35, 7.6), Vector3(0.0, 4.85, 5.5), roof_metal, Vector3.ZERO, true)
	# Canopy support columns with angled braces
	for px in [-30.0, -15.0, 0.0, 15.0, 30.0]:
		for pz in [2.6, 8.2]:
			_add_static_box(platform, Vector3(0.32, 3.7, 0.32), Vector3(px, 3.0, pz), steel_dark, Vector3.ZERO, true)
			_add_static_box(platform, Vector3(0.20, 1.4, 0.20), Vector3(px, 4.4, pz + (0.5 if pz < 5.0 else -0.5)), steel_dark, Vector3(0.35 if pz < 5.0 else -0.35, 0, 0), false)

	# 6 Platform Lampposts with warm glowing lanterns
	for lx in [-32.0, -19.0, -6.0, 7.0, 20.0, 33.0]:
		var post := Node3D.new()
		post.position = Vector3(lx, 1.15, 2.8)
		platform.add_child(post)
		_add_static_cyl(post, 0.09, 0.12, 3.2, Vector3(0.0, 1.6, 0.0), steel_dark, Vector3.ZERO, 8, true)
		_add_static_box(post, Vector3(0.38, 0.45, 0.38), Vector3(0.0, 3.3, 0.0), sign_glow_mat, Vector3.ZERO, false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0.0, 3.3, 0.0)
		lamp.omni_range = 14.0
		lamp.light_energy = 1.85
		lamp.light_color = Color(1.0, 0.88, 0.68)
		post.add_child(lamp)

	# Platform Waiting Benches
	for bx in [-22.0, -8.0, 8.0, 22.0]:
		_add_static_box(platform, Vector3(2.6, 0.12, 0.7), Vector3(bx, 1.55, 6.2), wood_mat, Vector3.ZERO, true)
		_add_static_box(platform, Vector3(2.6, 0.55, 0.10), Vector3(bx, 1.85, 6.55), wood_mat, Vector3.ZERO, false)
		_add_static_box(platform, Vector3(0.12, 0.40, 0.65), Vector3(bx - 1.1, 1.35, 6.2), steel_dark, Vector3.ZERO, false)
		_add_static_box(platform, Vector3(0.12, 0.40, 0.65), Vector3(bx + 1.1, 1.35, 6.2), steel_dark, Vector3.ZERO, false)

	# Platform Electronic Timetable Boards («РОЗКЛАД РУХУ»)
	for sx in [-12.0, 12.0]:
		var board := Node3D.new()
		board.position = Vector3(sx, 4.2, 5.3)
		platform.add_child(board)
		_add_static_box(board, Vector3(4.8, 1.1, 0.28), Vector3.ZERO, steel_dark, Vector3.ZERO, true)
		_add_static_box(board, Vector3(4.6, 0.9, 0.32), Vector3.ZERO, sign_glow_mat, Vector3.ZERO, false)
		var t_lbl := Label3D.new()
		t_lbl.text = "РОЗКЛАД РУХУ\nПОТЯГ № 042: ПРИБУТТЯ"
		t_lbl.font_size = 32
		t_lbl.pixel_size = 0.007
		t_lbl.modulate = Color(0.08, 0.12, 0.15)
		t_lbl.outline_size = 0
		t_lbl.position = Vector3(0.0, 0.0, 0.18)
		board.add_child(t_lbl)

	# --- B. Station Terminal Building (34m wide x 14m deep x 11.5m high) ---
	var term := Node3D.new()
	term.name = "StationTerminal"
	term.position = Vector3(0.0, 0.0, 19.5)
	root.add_child(term)

	var b_w := 34.0
	var b_d := 14.0
	var b_h := 11.5

	# Subterranean basement slab
	_add_static_box(term, Vector3(b_w + 2.0, 8.0, b_d + 2.0), Vector3(0.0, -3.95, 0.0), concrete_dark, Vector3.ZERO, true)
	# Floor and Roof
	_add_static_box(term, Vector3(b_w, 0.35, b_d), Vector3(0.0, 0.18, 0.0), concrete_weathered, Vector3.ZERO, true)
	_add_static_box(term, Vector3(b_w + 1.5, 0.65, b_d + 1.5), Vector3(0.0, b_h + 0.32, 0.0), concrete_dark, Vector3.ZERO, true)

	# Side Exterior Walls (East X = +17, West X = -17)
	for side in [-1.0, 1.0]:
		var sx: float = side * (b_w * 0.5)
		_add_static_box(term, Vector3(0.85, b_h, b_d), Vector3(sx, b_h * 0.5, 0.0), concrete_light, Vector3.ZERO, true)

	# Front Facade (South Z = +7.0, street side) and Rear Facade (North Z = -7.0, platform side)
	# Both have wide open fly-through portals so drones can fly completely through the station!
	for fz in [-b_d * 0.5, b_d * 0.5]:
		# Left and Right solid wall flanks
		_add_static_box(term, Vector3(12.5, b_h, 0.8), Vector3(-10.2, b_h * 0.5, fz), concrete_light, Vector3.ZERO, true)
		_add_static_box(term, Vector3(12.5, b_h, 0.8), Vector3(10.2, b_h * 0.5, fz), concrete_light, Vector3.ZERO, true)
		# Upper arch lintel above portal (portal width 7.0m, height 6.0m)
		_add_static_box(term, Vector3(7.4, b_h - 6.0, 0.8), Vector3(0.0, 6.0 + (b_h - 6.0) * 0.5, fz), concrete_weathered, Vector3.ZERO, true)
		# Classical pilasters framing the entrance
		_add_static_box(term, Vector3(1.2, b_h, 1.1), Vector3(-4.2, b_h * 0.5, fz), concrete_weathered, Vector3.ZERO, true)
		_add_static_box(term, Vector3(1.2, b_h, 1.1), Vector3(4.2, b_h * 0.5, fz), concrete_weathered, Vector3.ZERO, true)

	# Grand Waiting Hall Interior Chandeliers
	for cz in [-3.0, 3.0]:
		var ch := OmniLight3D.new()
		ch.position = Vector3(0.0, 8.5, cz)
		ch.omni_range = 16.0
		ch.light_energy = 2.2
		ch.light_color = Color(1.0, 0.90, 0.72)
		term.add_child(ch)

	# Central Roof Pediment & Station Clock Tower
	var tower := Node3D.new()
	tower.position = Vector3(0.0, b_h + 0.65, 0.0)
	term.add_child(tower)
	_add_static_box(tower, Vector3(10.0, 4.2, 5.0), Vector3(0.0, 2.1, 0.0), concrete_light, Vector3.ZERO, true)
	# Clock dials on both North and South faces
	for fz in [-2.55, 2.55]:
		_add_static_cyl(tower, 1.35, 1.35, 0.15, Vector3(0.0, 2.1, fz), sign_glow_mat, Vector3(PI * 0.5, 0, 0), 16, false)
		# Clock hands
		_add_static_box(tower, Vector3(0.10, 0.85, 0.08), Vector3(0.0, 2.35, fz + (0.1 if fz > 0 else -0.1)), steel_dark, Vector3.ZERO, false)
		_add_static_box(tower, Vector3(0.65, 0.10, 0.08), Vector3(0.25, 2.1, fz + (0.1 if fz > 0 else -0.1)), steel_dark, Vector3.ZERO, false)

	# Illuminated Ukrainian Station Sign above Entrance Portal (« СТАНЦІЯ ТАКТИЧНА »)
	for fz in [-b_d * 0.5 - 0.45, b_d * 0.5 + 0.45]:
		var sign_box := Node3D.new()
		sign_box.position = Vector3(0.0, 6.8, fz)
		term.add_child(sign_box)
		_add_static_box(sign_box, Vector3(9.2, 1.2, 0.25), Vector3.ZERO, steel_dark, Vector3.ZERO, true)
		_add_static_box(sign_box, Vector3(8.8, 1.0, 0.28), Vector3.ZERO, sign_glow_mat, Vector3.ZERO, false)
		var s_lbl := Label3D.new()
		s_lbl.text = "« СТАНЦІЯ ТАКТИЧНА »"
		s_lbl.font_size = 44
		s_lbl.pixel_size = 0.009
		s_lbl.modulate = Color(0.06, 0.04, 0.01)
		s_lbl.outline_size = 0
		s_lbl.position = Vector3(0.0, 0.0, 0.16 if fz > 0 else -0.16)
		if fz < 0:
			s_lbl.rotation.y = PI
		sign_box.add_child(s_lbl)

	# --- C. Trackside Entrance Signal Semaphore (X = -48, Z = -2.8) ---
	var sema := Node3D.new()
	sema.position = Vector3(-48.0, 0.0, -2.8)
	root.add_child(sema)
	_add_static_cyl(sema, 0.14, 0.18, 6.8, Vector3(0.0, 3.4, 0.0), steel_dark, Vector3.ZERO, 8, true)
	var sema_head := Node3D.new()
	sema_head.position = Vector3(0.0, 6.2, 0.0)
	sema.add_child(sema_head)
	_add_static_box(sema_head, Vector3(0.6, 1.6, 0.4), Vector3.ZERO, steel_dark, Vector3.ZERO, false)
	# Green light
	var green_mat := StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.1, 1.0, 0.25)
	green_mat.emission_enabled = true
	green_mat.emission = Color(0.1, 1.0, 0.25)
	green_mat.emission_energy_multiplier = 3.0
	_add_static_cyl(sema_head, 0.18, 0.18, 0.12, Vector3(0.0, 0.45, 0.22), green_mat, Vector3(PI * 0.5, 0, 0), 12, false)
	var green_light := OmniLight3D.new()
	green_light.position = Vector3(0.0, 0.45, 0.45)
	green_light.omni_range = 8.0
	green_light.light_energy = 2.0
	green_light.light_color = Color(0.1, 1.0, 0.3)
	sema_head.add_child(green_light)

	# --- D. Overhead Hazard/Catenary Gantry spanning the track at X = -40 ---
	var gantry := Node3D.new()
	gantry.position = Vector3(-40.0, 0.0, 0.0)
	root.add_child(gantry)
	for gz in [-3.2, 3.2]:
		_add_static_cyl(gantry, 0.16, 0.16, 6.5, Vector3(0.0, 3.25, gz), steel_dark, Vector3.ZERO, 8, true)
	_add_static_box(gantry, Vector3(0.45, 0.45, 6.6), Vector3(0.0, 6.4, 0.0), warning_yellow, Vector3.ZERO, true)

	return root


static func _pose_on_track(node: Node3D, t: float, base_y: float = 0.0) -> void:
	var t_fwd := fmod(fmod(t + 0.004, 1.0) + 1.0, 1.0)
	var t_bwd := fmod(fmod(t - 0.004, 1.0) + 1.0, 1.0)
	var p0 := _track_point(t_bwd, base_y)
	var p1 := _track_point(t_fwd, base_y)
	var pos := _track_point(t, base_y)
	var dir := (p1 - p0).normalized()
	node.position = pos + Vector3(0.0, 0.46, 0.0)
	if dir.length_squared() > 0.001:
		node.rotation = Vector3(0.0, atan2(-dir.x, -dir.z), 0.0)


static func _add_bogies(car: Node3D, z_off: float, dark_mat: Material) -> void:
	for bz in [-z_off, z_off]:
		_add_static_box(car, Vector3(2.2, 0.45, 2.4), Vector3(0.0, 0.42, bz), dark_mat, Vector3.ZERO, false)
		for wx in [-0.82, 0.82]:
			for wz in [-0.75, 0.75]:
				_add_static_cyl(car, 0.44, 0.44, 0.18,
						Vector3(wx, 0.44, bz + wz), dark_mat, Vector3(0.0, 0.0, PI * 0.5), 12, false)


static func _spawn_locomotive(parent: Node3D, t: float, yellow: Material,
		dark: Material, glass: Material, base_y: float = 0.0) -> Node3D:
	var loco := Node3D.new()
	loco.name = "DieselLocomotive"
	parent.add_child(loco)
	_pose_on_track(loco, t, base_y)

	# Heavy underframe & walkways
	_add_static_box(loco, Vector3(3.05, 0.55, 15.2), Vector3(0.0, 0.85, 0.0), dark)
	_add_static_box(loco, Vector3(2.2, 0.65, 6.2), Vector3(0.0, 0.48, 0.0), dark, Vector3.ZERO, false)
	# Short nose hood (-Z front)
	_add_static_box(loco, Vector3(2.45, 1.85, 3.2), Vector3(0.0, 2.05, -5.4), yellow)
	# Elevated cab
	_add_static_box(loco, Vector3(2.85, 2.55, 2.8), Vector3(0.0, 2.40, -2.5), yellow)
	_add_static_box(loco, Vector3(2.90, 0.25, 3.0), Vector3(0.0, 3.72, -2.5), dark, Vector3.ZERO, false)
	# Cab windows
	_add_static_box(loco, Vector3(2.4, 0.65, 0.12), Vector3(0.0, 3.05, -3.91), glass, Vector3.ZERO, false)
	_add_static_box(loco, Vector3(2.92, 0.65, 1.6), Vector3(0.0, 3.05, -2.5), glass, Vector3.ZERO, false)
	# Long engine hood (+Z rear)
	_add_static_box(loco, Vector3(2.45, 2.35, 8.2), Vector3(0.0, 2.30, 2.9), yellow)
	_add_static_box(loco, Vector3(2.50, 0.32, 8.3), Vector3(0.0, 3.55, 2.9), dark, Vector3.ZERO, false)
	# Side radiator grilles on the hood
	for gz in [0.5, 2.8, 5.2]:
		_add_static_box(loco, Vector3(2.52, 0.65, 1.45), Vector3(0.0, 2.75, gz), dark, Vector3.ZERO, false)
	_add_bogies(loco, 4.8, dark)

	# Dual high-intensity forward headlights
	for hx in [-0.65, 0.65]:
		var hl := SpotLight3D.new()
		hl.position = Vector3(hx, 2.15, -6.8)
		hl.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
		hl.spot_range = 65.0
		hl.spot_angle = 32.0
		hl.light_energy = 3.6
		hl.light_color = Color(1.0, 0.95, 0.85)
		loco.add_child(hl)
		var hl_mat := StandardMaterial3D.new()
		hl_mat.albedo_color = Color(1.0, 0.95, 0.8)
		hl_mat.emission_enabled = true
		hl_mat.emission = Color(1.0, 0.95, 0.8)
		hl_mat.emission_energy_multiplier = 4.0
		_add_static_cyl(loco, 0.22, 0.22, 0.12, Vector3(hx, 2.15, -6.8), hl_mat, Vector3(PI * 0.5, 0, 0), 12, false)

	# Cab interior warm light
	var cab_light := OmniLight3D.new()
	cab_light.position = Vector3(0.0, 3.2, -2.5)
	cab_light.omni_range = 5.0
	cab_light.light_energy = 1.6
	cab_light.light_color = Color(1.0, 0.88, 0.68)
	loco.add_child(cab_light)

	# Exhaust smoke particle emitter
	var smoke := CPUParticles3D.new()
	smoke.position = Vector3(0.0, 3.85, 2.2)
	smoke.amount = 16
	smoke.lifetime = 1.2
	smoke.speed_scale = 1.0
	smoke.direction = Vector3(0.0, 1.0, 0.3)
	smoke.spread = 18.0
	smoke.gravity = Vector3(0.0, 2.5, 0.0)
	smoke.initial_velocity_min = 2.5
	smoke.initial_velocity_max = 5.0
	smoke.color = Color(0.22, 0.22, 0.22, 0.45)
	loco.add_child(smoke)

	return loco


static func _spawn_gondola_car(parent: Node3D, t: float, blue: Material, dark: Material, base_y: float = 0.0) -> Node3D:
	var car := Node3D.new()
	car.name = "GondolaCar"
	parent.add_child(car)
	_pose_on_track(car, t, base_y)

	_add_static_box(car, Vector3(2.95, 0.42, 13.8), Vector3(0.0, 0.85, 0.0), dark)
	_add_static_box(car, Vector3(2.95, 2.35, 13.4), Vector3(0.0, 2.22, 0.0), blue)
	# Dark interior recess at top of open gondola
	_add_static_box(car, Vector3(2.55, 0.25, 12.8), Vector3(0.0, 3.32, 0.0), dark, Vector3.ZERO, false)
	# Vertical reinforcing ribs along the sides
	for rz in range(-5, 6):
		_add_static_box(car, Vector3(3.08, 2.30, 0.16), Vector3(0.0, 2.22, float(rz) * 1.15), blue, Vector3.ZERO, false)
	_add_bogies(car, 4.5, dark)
	return car


static func _spawn_boxcar(parent: Node3D, t: float, red: Material, dark: Material, base_y: float = 0.0, is_caboose: bool = false) -> Node3D:
	var car := Node3D.new()
	car.name = "Boxcar"
	parent.add_child(car)
	_pose_on_track(car, t, base_y)

	_add_static_box(car, Vector3(2.95, 0.42, 14.0), Vector3(0.0, 0.85, 0.0), dark)
	_add_static_box(car, Vector3(2.95, 2.65, 13.6), Vector3(0.0, 2.38, 0.0), red)
	# Pitched/curved roof cap
	_add_static_box(car, Vector3(2.45, 0.35, 13.6), Vector3(0.0, 3.82, 0.0), red, Vector3.ZERO, false)
	for rz in range(-5, 6):
		_add_static_box(car, Vector3(3.06, 2.55, 0.16), Vector3(0.0, 2.38, float(rz) * 1.18), red, Vector3.ZERO, false)
	_add_bogies(car, 4.6, dark)

	if is_caboose:
		# Rear red marker tail lights
		for lx in [-1.1, 1.1]:
			var rl := OmniLight3D.new()
			rl.position = Vector3(lx, 2.4, 7.1)
			rl.omni_range = 6.0
			rl.light_energy = 2.4
			rl.light_color = Color(1.0, 0.15, 0.10)
			car.add_child(rl)
			var red_mat := StandardMaterial3D.new()
			red_mat.albedo_color = Color(1.0, 0.1, 0.1)
			red_mat.emission_enabled = true
			red_mat.emission = Color(1.0, 0.1, 0.1)
			red_mat.emission_energy_multiplier = 3.5
			_add_static_cyl(car, 0.15, 0.15, 0.12, Vector3(lx, 2.4, 7.05), red_mat, Vector3(PI * 0.5, 0, 0), 10, false)

	return car
	for rz in range(-5, 6):
		_add_static_box(car, Vector3(3.06, 2.55, 0.16), Vector3(0.0, 2.38, float(rz) * 1.18), red, Vector3.ZERO, false)
	_add_bogies(car, 4.6, dark)


## 3. High-altitude Construction Tower Crane for dives, power-loops and mast fly-throughs.
static func build_construction_crane(scene_root: Node3D, origin: Vector3, yaw_rad: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ConstructionTowerCrane"
	scene_root.add_child(root)
	root.global_position = origin
	root.rotation.y = yaw_rad

	var crane_yellow := _make_pbr_mat(Color(0.92, 0.65, 0.08), 0.55, 0.35)
	var crane_dark := _make_pbr_mat(Color(0.20, 0.22, 0.24), 0.70, 0.40)
	var crane_concrete := _make_pbr_mat(Color(0.55, 0.54, 0.52), 0.94, 0.0)
	var glass_mat := _make_pbr_mat(Color(0.12, 0.22, 0.28), 0.20, 0.60)
	var cable_mat := _make_pbr_mat(Color(0.15, 0.15, 0.15), 0.90, 0.80)

	# Concrete foundation base slab with deep subterranean anchor plinth
	_add_static_box(root, Vector3(14.0, 8.0, 14.0), Vector3(0.0, -3.4, 0.0), crane_concrete, Vector3.ZERO, true)
	_add_static_box(root, Vector3(8.0, 1.2, 8.0), Vector3(0.0, 0.6, 0.0), crane_concrete)

	# 44m tall lattice mast (3.2m x 3.2m square footprint)
	var mast_h := 44.0
	var leg_w := 0.35
	for lx in [-1.45, 1.45]:
		for lz in [-1.45, 1.45]:
			_add_static_box(root, Vector3(leg_w, mast_h, leg_w), Vector3(lx, mast_h * 0.5 + 1.2, lz), crane_yellow)

	# Mast horizontal frame collars and diagonal cross-lacings every 4m
	for fi in range(1, 11):
		var fy := 1.2 + float(fi) * 4.0
		# 4 horizontal collar beams
		_add_static_box(root, Vector3(3.2, 0.22, 0.25), Vector3(0.0, fy, -1.45), crane_yellow, Vector3.ZERO, false)
		_add_static_box(root, Vector3(3.2, 0.22, 0.25), Vector3(0.0, fy, 1.45), crane_yellow, Vector3.ZERO, false)
		_add_static_box(root, Vector3(0.25, 0.22, 3.2), Vector3(-1.45, fy, 0.0), crane_yellow, Vector3.ZERO, false)
		_add_static_box(root, Vector3(0.25, 0.22, 3.2), Vector3(1.45, fy, 0.0), crane_yellow, Vector3.ZERO, false)
		# Interior ladder spine running up the mast
		_add_static_box(root, Vector3(0.45, 4.0, 0.1), Vector3(0.0, fy - 2.0, -1.2), crane_dark, Vector3.ZERO, false)

	# Slewing turntable ring & machinery deck at Y = 45.2m
	var deck_y := mast_h + 1.2
	_add_static_box(root, Vector3(4.2, 0.8, 6.0), Vector3(0.0, deck_y + 0.4, 0.0), crane_dark)

	# Operator Cab on left-front
	var cab := Node3D.new()
	cab.position = Vector3(-2.6, deck_y + 1.6, -1.8)
	root.add_child(cab)
	_add_static_box(cab, Vector3(1.9, 2.4, 2.5), Vector3.ZERO, crane_yellow)
	_add_static_box(cab, Vector3(1.95, 1.2, 1.4), Vector3(0.0, 0.3, -0.6), glass_mat, Vector3.ZERO, false)

	# A-Frame / Cathead apex tower rising 8m above deck
	_add_static_box(root, Vector3(0.4, 8.2, 0.4), Vector3(-1.2, deck_y + 4.5, 0.4), crane_yellow, Vector3(0.12, 0, 0.14))
	_add_static_box(root, Vector3(0.4, 8.2, 0.4), Vector3(1.2, deck_y + 4.5, 0.4), crane_yellow, Vector3(0.12, 0, -0.14))
	_add_static_box(root, Vector3(0.4, 8.2, 0.4), Vector3(0.0, deck_y + 4.5, -1.4), crane_yellow, Vector3(-0.20, 0, 0))

	# Horizontal Jib (Front Boom) extending 48m along -Z
	var jib_len := 48.0
	for jx in [-1.1, 1.1]:
		_add_static_box(root, Vector3(0.28, 0.28, jib_len), Vector3(jx, deck_y + 1.2, -jib_len * 0.5), crane_yellow)
	_add_static_box(root, Vector3(0.28, 0.28, jib_len), Vector3(0.0, deck_y + 3.2, -jib_len * 0.5), crane_yellow)
	# Jib walkway in between bottom chords
	_add_static_box(root, Vector3(1.8, 0.08, jib_len), Vector3(0.0, deck_y + 1.25, -jib_len * 0.5), crane_dark, Vector3.ZERO, false)
	# Jib cross-truss web chords every 4m
	for ji in range(1, 12):
		var jz := -float(ji) * 4.0
		_add_static_box(root, Vector3(2.2, 0.18, 0.18), Vector3(0.0, deck_y + 1.2, jz), crane_yellow, Vector3.ZERO, false)
		_add_static_box(root, Vector3(0.18, 2.0, 0.18), Vector3(-1.1, deck_y + 2.2, jz), crane_yellow, Vector3.ZERO, false)
		_add_static_box(root, Vector3(0.18, 2.0, 0.18), Vector3(1.1, deck_y + 2.2, jz), crane_yellow, Vector3.ZERO, false)

	# Counter-Jib (Rear Boom) extending 16m along +Z
	var r_len := 16.0
	_add_static_box(root, Vector3(2.4, 1.8, r_len), Vector3(0.0, deck_y + 1.8, r_len * 0.5), crane_yellow)
	# 4 Heavy concrete ballast counterweights at rear
	for bi in range(4):
		var bz := 10.0 + float(bi) * 1.4
		_add_static_box(root, Vector3(3.2, 2.4, 1.15), Vector3(0.0, deck_y + 2.2, bz), crane_concrete)

	# Suspended load: trolley on jib at Z = -24m with wire rope and dangling bucket at Y = 20m!
	var tz := -24.0
	_add_static_box(root, Vector3(1.8, 0.5, 1.8), Vector3(0.0, deck_y + 0.8, tz), crane_dark)
	var rope_h := 24.0
	_add_static_cyl(root, 0.06, 0.06, rope_h, Vector3(0.0, deck_y - rope_h * 0.5 + 0.5, tz), cable_mat, Vector3.ZERO, 6, false)
	# Dangling heavy concrete skip / hopper (perfect for power-loops!)
	var hopper := Node3D.new()
	hopper.position = Vector3(0.0, deck_y - rope_h + 1.2, tz)
	root.add_child(hopper)
	_add_static_box(hopper, Vector3(2.6, 2.2, 2.6), Vector3.ZERO, crane_yellow)
	_add_static_box(hopper, Vector3(2.2, 0.2, 2.2), Vector3(0.0, 0.9, 0.0), crane_dark, Vector3.ZERO, false)

	return root


## 4. Concrete Culvert Pipe Park for high-speed knife-edge tunnels, slides and dives.
static func build_concrete_pipe_park(scene_root: Node3D, origin: Vector3, yaw_rad: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ConcretePipePark"
	scene_root.add_child(root)
	root.global_position = origin
	root.rotation.y = yaw_rad

	var concrete_mat := _make_pbr_mat(Color(0.60, 0.59, 0.56), 0.92, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.20)
	var dirt_mat := _make_pbr_mat(Color(0.35, 0.28, 0.20), 0.98, 0.0)

	# Gravel ground apron with subterranean bedrock foundation plinth
	_add_static_box(root, Vector3(45.0, 8.0, 45.0), Vector3(0.0, -3.95, 0.0), concrete_mat, Vector3.ZERO, true)
	_add_static_box(root, Vector3(32.0, 0.2, 26.0), Vector3(0.0, 0.1, 0.0), dirt_mat, Vector3.ZERO, false)

	# Helper to build a hollow concrete pipe with 12 radial collision slabs
	var pipe_fn = func(parent: Node3D, pos: Vector3, rot: Vector3) -> Node3D:
		var p := Node3D.new()
		p.position = pos
		p.rotation = rot
		parent.add_child(p)
		var segs := 12
		var r := 1.9
		var seg_w := 2.0 * r * tan(PI / float(segs)) * 1.05
		var seg_thick := 0.32
		var pipe_len := 14.0
		for i in range(segs):
			var a := float(i) * (TAU / float(segs))
			var sp := Vector3(cos(a) * r, sin(a) * r, 0.0)
			var s_rot := Vector3(0.0, 0.0, a + PI * 0.5)
			_add_static_box(p, Vector3(seg_w, seg_thick, pipe_len), sp, concrete_mat, s_rot)
		for fz in [-pipe_len * 0.5, pipe_len * 0.5]:
			for i in range(segs):
				var a := float(i) * (TAU / float(segs))
				var sp := Vector3(cos(a) * (r + 0.12), sin(a) * (r + 0.12), fz)
				var s_rot := Vector3(0.0, 0.0, a + PI * 0.5)
				_add_static_box(p, Vector3(seg_w * 1.1, seg_thick * 1.4, 0.7), sp, concrete_mat, s_rot, false)
		return p

	# Stacked Culverts: bottom pair + top pyramid
	pipe_fn.call(root, Vector3(-2.25, 1.95, 0.0), Vector3.ZERO)
	pipe_fn.call(root, Vector3(2.25, 1.95, 0.0), Vector3.ZERO)
	pipe_fn.call(root, Vector3(0.0, 5.25, 0.0), Vector3.ZERO)

	# Angled dive pipe off to the right (tilted 20 degrees for high-speed dive entry!)
	pipe_fn.call(root, Vector3(10.5, 3.4, 3.0), Vector3(deg_to_rad(20.0), deg_to_rad(15.0), 0.0))

	# Standalone horizontal culvert near the entrance
	pipe_fn.call(root, Vector3(-9.5, 1.95, -4.0), Vector3(0.0, deg_to_rad(35.0), 0.0))

	return root


## 5. Modern Stacked Shipping Container Freestyle Complex with hollow fly-through containers.
static func build_container_freestyle_park(scene_root: Node3D, origin: Vector3, yaw_rad: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "ContainerFreestylePark"
	scene_root.add_child(root)
	root.global_position = origin
	root.rotation.y = yaw_rad

	var col_orange := _make_pbr_mat(Color(0.88, 0.40, 0.10), 0.65, 0.15)
	var col_blue := _make_pbr_mat(Color(0.12, 0.35, 0.65), 0.70, 0.20)
	var col_red := _make_pbr_mat(Color(0.60, 0.18, 0.15), 0.75, 0.15)
	var col_green := _make_pbr_mat(Color(0.18, 0.42, 0.24), 0.70, 0.15)
	var col_dark := _make_pbr_mat(Color(0.20, 0.21, 0.22), 0.85, 0.25)
	var wood_mat := _make_pbr_mat(Color(0.65, 0.48, 0.28), 0.90, 0.0)

	# Helper to build a hollow 40ft container with fly-through open ends
	var hollow_fn = func(parent: Node3D, pos: Vector3, rot: Vector3, mat: Material) -> Node3D:
		var c := Node3D.new()
		c.position = pos
		c.rotation = rot
		parent.add_child(c)
		var cw := 2.6
		var ch := 2.6
		var cl := 12.2
		# Floor and roof
		_add_static_box(c, Vector3(cw, 0.18, cl), Vector3(0.0, 0.09, 0.0), col_dark)
		_add_static_box(c, Vector3(cw, 0.18, cl), Vector3(0.0, ch - 0.09, 0.0), mat)
		# Side walls
		_add_static_box(c, Vector3(0.16, ch, cl), Vector3(-cw * 0.5 + 0.08, ch * 0.5, 0.0), mat)
		_add_static_box(c, Vector3(0.16, ch, cl), Vector3(cw * 0.5 - 0.08, ch * 0.5, 0.0), mat)
		# Corrugation ribs
		for rz in range(-5, 6):
			var z_pos := float(rz) * 1.15
			_add_static_box(c, Vector3(cw + 0.12, ch, 0.14), Vector3(0.0, ch * 0.5, z_pos), mat, Vector3.ZERO, false)
		return c

	# Helper to build a standard solid container
	var solid_fn = func(parent: Node3D, pos: Vector3, rot: Vector3, length: float, mat: Material) -> Node3D:
		var c := Node3D.new()
		c.position = pos
		c.rotation = rot
		parent.add_child(c)
		var cw := 2.6
		var ch := 2.6
		_add_static_box(c, Vector3(cw, ch, length), Vector3(0.0, ch * 0.5, 0.0), mat)
		for rz in range(-int(length * 0.38), int(length * 0.38) + 1):
			var z_pos := float(rz) * 1.15
			_add_static_box(c, Vector3(cw + 0.12, ch, 0.14), Vector3(0.0, ch * 0.5, z_pos), mat, Vector3.ZERO, false)
		return c

	# Subterranean bedrock foundation plinth
	_add_static_box(root, Vector3(36.0, 8.0, 36.0), Vector3(0.0, -3.95, 0.0), col_dark, Vector3.ZERO, true)

	# Base Ground Tier: hollow fly-through container + 2 solid containers
	hollow_fn.call(root, Vector3(0.0, 0.0, 0.0), Vector3.ZERO, col_orange)
	solid_fn.call(root, Vector3(3.2, 0.0, 0.0), Vector3.ZERO, 12.2, col_blue)
	solid_fn.call(root, Vector3(-3.2, 0.0, -1.0), Vector3.ZERO, 12.2, col_red)

	# Second Tier (Y = 2.6m): Cantilevered overhangs
	solid_fn.call(root, Vector3(1.6, 2.6, 2.0), Vector3(0.0, deg_to_rad(90.0), 0.0), 12.2, col_green)
	hollow_fn.call(root, Vector3(-1.6, 2.6, -3.0), Vector3(0.0, deg_to_rad(15.0), 0.0), col_blue)

	# Third Tier (Y = 5.2m): Angled gap container
	solid_fn.call(root, Vector3(0.0, 5.2, 0.0), Vector3(0.0, deg_to_rad(-25.0), 0.0), 6.1, col_orange)

	# Giant wooden cable spools (reels)
	for spool in [
		{"pos": Vector3(7.5, 1.6, -4.0), "r": 1.6, "h": 1.8, "rot": Vector3(PI * 0.5, 0, 0.4)},
		{"pos": Vector3(-7.0, 1.6, 3.5), "r": 1.6, "h": 1.8, "rot": Vector3(PI * 0.5, 0, -0.6)},
		{"pos": Vector3(7.5, 0.9, 3.0), "r": 1.8, "h": 1.8, "rot": Vector3.ZERO}
	]:
		_add_static_cyl(root, spool["r"], spool["r"], spool["h"], spool["pos"], wood_mat, spool["rot"], 16)
		_add_static_cyl(root, 0.35, 0.35, spool["h"] + 0.05, spool["pos"], col_dark, spool["rot"], 12, false)

	# Wooden kicker ramp
	_add_static_box(root, Vector3(3.6, 0.25, 5.5), Vector3(0.0, 1.1, 8.5), wood_mat, Vector3(deg_to_rad(-24.0), 0, 0))

	return root


## 6. Fortified Combat Sector: Concrete Pillbox Bunker with fly-through firing slits,
## Czech hedgehogs, defensive trench revetments, and guard watchtower.
static func build_combat_fortifications(scene_root: Node3D, origin: Vector3, yaw_rad: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CombatFortifications"
	scene_root.add_child(root)
	root.global_position = origin
	root.rotation.y = yaw_rad

	var concrete_bunker := _make_pbr_mat(Color(0.48, 0.47, 0.44), 0.94, 0.0,
			"res://Assets/Textures/4.png", "res://Assets/Textures/NormalMap-1.png", 0.22)
	var sandbag_mat := _make_pbr_mat(Color(0.58, 0.52, 0.38), 0.96, 0.0)
	var steel_rail_mat := _make_pbr_mat(Color(0.32, 0.33, 0.35), 0.65, 0.65)
	var wood_mat := _make_pbr_mat(Color(0.42, 0.32, 0.22), 0.95, 0.0)

	# --- A. Reinforced Concrete Pillbox Bunker with Fly-Through Firing Slits ---
	var bunker := Node3D.new()
	bunker.name = "PillboxBunker"
	root.add_child(bunker)
	# Subterranean bunker bedrock foundation
	_add_static_box(bunker, Vector3(18.0, 8.0, 14.0), Vector3(0.0, -3.8, 0.0), concrete_bunker, Vector3.ZERO, true)
	_add_static_box(bunker, Vector3(14.0, 0.4, 10.0), Vector3(0.0, 0.2, 0.0), concrete_bunker)
	_add_static_box(bunker, Vector3(15.2, 0.8, 11.2), Vector3(0.0, 4.2, 0.0), concrete_bunker)
	_add_static_box(bunker, Vector3(5.2, 3.6, 0.8), Vector3(-4.4, 2.0, 4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(5.2, 3.6, 0.8), Vector3(4.4, 2.0, 4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(3.6, 1.4, 0.8), Vector3(0.0, 3.1, 4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(0.8, 3.6, 10.0), Vector3(-6.6, 2.0, 0.0), concrete_bunker)
	_add_static_box(bunker, Vector3(0.8, 3.6, 10.0), Vector3(6.6, 2.0, 0.0), concrete_bunker)
	# Front firing slits (бійниці): open 2.8m x 1.4m slots
	_add_static_box(bunker, Vector3(14.0, 1.4, 0.8), Vector3(0.0, 0.9, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(14.0, 1.0, 0.8), Vector3(0.0, 3.3, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(1.2, 1.2, 0.85), Vector3(-2.8, 2.0, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(1.2, 1.2, 0.85), Vector3(2.8, 2.0, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(1.2, 1.2, 0.85), Vector3(-6.4, 2.0, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(1.2, 1.2, 0.85), Vector3(6.4, 2.0, -4.6), concrete_bunker)
	_add_static_box(bunker, Vector3(16.0, 1.1, 1.2), Vector3(0.0, 0.55, -6.8), sandbag_mat)

	# --- B. Czech Hedgehogs (Tank Traps) ---
	var hedgehog_holder := Node3D.new()
	hedgehog_holder.name = "CzechHedgehogs"
	root.add_child(hedgehog_holder)
	for hi in range(8):
		var h_pos := Vector3(float(hi) * 4.2 - 14.7, 0.85, -14.0 + sin(float(hi) * 1.2) * 1.5)
		var h := Node3D.new()
		h.position = h_pos
		h.rotation.y = float(hi) * 0.7
		hedgehog_holder.add_child(h)
		_add_static_box(h, Vector3(0.18, 0.18, 2.2), Vector3.ZERO, steel_rail_mat, Vector3(0.65, 0, 0))
		_add_static_box(h, Vector3(0.18, 0.18, 2.2), Vector3.ZERO, steel_rail_mat, Vector3(-0.65, 0, 0))
		_add_static_box(h, Vector3(2.2, 0.18, 0.18), Vector3.ZERO, steel_rail_mat, Vector3(0, 0, 0.65))

	# --- C. Military Watchtower (12m steel frame) ---
	var tower := Node3D.new()
	tower.name = "MilitaryWatchtower"
	tower.position = Vector3(22.0, 0.0, -6.0)
	root.add_child(tower)
	# Subterranean foundation plinth under tower
	_add_static_box(tower, Vector3(6.0, 8.0, 6.0), Vector3(0.0, -3.95, 0.0), concrete_bunker, Vector3.ZERO, true)
	var t_h := 12.0
	for tx in [-1.6, 1.6]:
		for tz in [-1.6, 1.6]:
			_add_static_box(tower, Vector3(0.28, t_h, 0.28), Vector3(tx, t_h * 0.5, tz), steel_rail_mat)
	_add_static_box(tower, Vector3(4.4, 0.35, 4.4), Vector3(0.0, t_h + 0.18, 0.0), wood_mat)
	_add_static_box(tower, Vector3(3.2, 2.4, 3.2), Vector3(0.0, t_h + 1.5, 0.0), wood_mat)
	_add_static_box(tower, Vector3(3.6, 0.3, 3.6), Vector3(0.0, t_h + 2.8, 0.0), steel_rail_mat)

	# --- D. Defensive Trench Line with Duckboards ---
	var trench := Node3D.new()
	trench.name = "TrenchRevetment"
	trench.position = Vector3(-18.0, 0.0, 6.0)
	root.add_child(trench)
	_add_static_box(trench, Vector3(18.0, 1.35, 0.9), Vector3(0.0, 0.68, 0.0), sandbag_mat)
	_add_static_box(trench, Vector3(0.9, 1.35, 12.0), Vector3(9.0, 0.68, 6.0), sandbag_mat)
	_add_static_box(trench, Vector3(14.0, 1.35, 0.9), Vector3(2.0, 0.68, 12.0), sandbag_mat)
	_add_static_box(trench, Vector3(16.0, 0.12, 1.8), Vector3(0.0, 0.06, 1.4), wood_mat, Vector3.ZERO, false)

	return root
