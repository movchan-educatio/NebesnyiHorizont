extends Node3D
## Fills the repeated-prop MultiMesh pool at runtime. Godot does not serialise
## per-instance transforms in .tscn files. Neon gate rings were removed;
## FPVGates keeps only invisible Marker3D nodes for gameplay logic.
##
## The source package also ships scripts/oil_rig_materials.gd, but the authored
## .tscn never attaches it: the GLBs are exported WITHOUT embedded textures, so
## a plain instance is white. Restore the six authored atlas materials here on
## the same root node that the scene already uses (a Node can have one script).
## OilRigLevel.gd applies the same overrides; setting them twice is idempotent.

const MAT_DIR := "res://maps/oil_rig/materials/"
const SELECTED_GATE_INDICES: Array[int] = [
	0, 11, 22, 33,                 # 4 derrick_dive
	2, 3, 13, 14, 24, 25, 35, 36,  # 8 moonpool
	4, 5, 15, 16, 26, 27, 37, 38,  # 8 hangar
	7, 18, 20, 29, 40,             # 5 under_arch
	44, 45, 46, 47,                # 4 under_bridge
	48,                            # 1 tanker_deck
]

@onready var posts_mm: MultiMeshInstance3D = $InstancedDetails/RailPosts


func _ready() -> void:
	_restore_atlas_materials()
	_optimize_distant_shadows()
	call_deferred("_populate")


func _restore_atlas_materials() -> void:
	var flame_outer: Material = load(MAT_DIR + "flame_outer.tres")
	var shared := {
		"MAT_Structures": load(MAT_DIR + "structures.tres"),
		"MAT_Deck": load(MAT_DIR + "deck.tres"),
		"MAT_Emissive": load(MAT_DIR + "emissive.tres"),
		"MAT_FlameCore": load(MAT_DIR + "flame.tres"),
		"MAT_Light": load(MAT_DIR + "light.tres"),
	}
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for surface in range(mi.mesh.get_surface_count()):
			if mi.name == "MS_flare_emissive" and surface == 0 and flame_outer != null:
				mi.set_surface_override_material(surface, flame_outer)
				continue
			var src: Material = mi.get_surface_override_material(surface)
			if src == null:
				src = mi.mesh.surface_get_material(surface)
			if src == null:
				continue
			var key := String(src.resource_name)
			if shared.has(key):
				mi.set_surface_override_material(surface, shared[key])


func _optimize_distant_shadows() -> void:
	if posts_mm != null:
		posts_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var modules := get_node_or_null("Modules")
	if modules == null:
		return
	for ch in modules.get_children():
		var nm := String(ch.name)
		var is_distant := (nm in ["Platform_core_32", "Platform_core_33", "Platform_core_34",
				"Platform_core_35", "Platform_core_36", "Platform_core_37", "Tanker_38", "Tanker_39"])
		if not is_distant:
			continue
		for mi in ch.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _populate() -> void:
	_populate_posts()
	_populate_visible_rings()


func _populate_posts() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://maps/oil_rig/scripts/instancing_data.json"))
	if data == null or not data.has("posts"):
		push_warning("OilRigMap: instancing_data.json missing")
		return
	var mm := posts_mm.multimesh
	var pts: Array = data["posts"]
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		var p: Array = pts[i]
		mm.set_instance_transform(i,
			Transform3D(Basis.IDENTITY, Vector3(p[0], p[1], p[2])))


func _populate_visible_rings() -> void:
	var details := get_node_or_null("InstancedDetails")
	var gates_node := get_node_or_null("FPVGates")
	if details == null or gates_node == null:
		return
	var transforms: Array[Transform3D] = []
	for idx in SELECTED_GATE_INDICES:
		var marker := gates_node.get_node_or_null("Gate_%02d" % idx) as Marker3D
		if marker != null:
			transforms.append(marker.transform)
	if transforms.is_empty():
		return
	var existing := details.get_node_or_null("VisibleGateRings") as MultiMeshInstance3D
	if existing == null:
		existing = MultiMeshInstance3D.new()
		existing.name = "VisibleGateRings"
		details.add_child(existing)
	existing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	existing.visibility_range_end = 1800.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _build_industrial_ring_mesh()
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	existing.multimesh = mm
	print("[OILRIG] VisibleGateRings populated: %d industrial gates (1 MultiMesh, 0 colliders)" % mm.instance_count)


static func _build_industrial_ring_mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = "OilRigIndustrialRingMesh"
	var sides := 8
	var r_mid := 4.6

	# Surface 0: Beveled octagonal steel collar (atlas_structures tile i=2 grey steel [0.52..0.72, 0.02..0.22])
	var prof := [
		Vector2(r_mid + 0.30, 0.16),
		Vector2(r_mid + 0.16, 0.30),
		Vector2(r_mid - 0.14, 0.30),
		Vector2(r_mid - 0.24, 0.16),
		Vector2(r_mid - 0.24, -0.16),
		Vector2(r_mid - 0.14, -0.30),
		Vector2(r_mid + 0.16, -0.30),
		Vector2(r_mid + 0.30, -0.16),
	]
	_add_ring_band_surface(out, sides, prof, Rect2(0.52, 0.02, 0.20, 0.20),
			load(MAT_DIR + "structures.tres") as Material)

	# Surface 1: Inner glowing amber signal trim sitting clearly inside & along inner lip
	var glow_prof := [
		Vector2(r_mid - 0.20, 0.13),
		Vector2(r_mid - 0.36, 0.09),
		Vector2(r_mid - 0.36, -0.09),
		Vector2(r_mid - 0.20, -0.13),
	]
	_add_ring_band_surface(out, sides, glow_prof, Rect2(0.0, 0.0, 1.0, 1.0),
			load(MAT_DIR + "emissive.tres") as Material)
	return out


static func _add_ring_band_surface(mesh: ArrayMesh, sides: int, profile: Array,
		uv_rect: Rect2, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pcount := profile.size()
	for s in range(sides):
		var a0 := (float(s) / float(sides)) * TAU + TAU / float(sides * 2)
		var a1 := (float(s + 1) / float(sides)) * TAU + TAU / float(sides * 2)
		var dir0 := Vector2(cos(a0), sin(a0))
		var dir1 := Vector2(cos(a1), sin(a1))
		var u0 := uv_rect.position.x
		var u1 := uv_rect.position.x + uv_rect.size.x
		for pi in range(pcount):
			var p_cur: Vector2 = profile[pi]
			var p_nxt: Vector2 = profile[(pi + 1) % pcount]
			var v0 := uv_rect.position.y + (float(pi) / float(pcount)) * uv_rect.size.y
			var v1 := uv_rect.position.y + (float(pi + 1) / float(pcount)) * uv_rect.size.y
			var v00 := Vector3(dir0.x * p_cur.x, p_cur.y, dir0.y * p_cur.x)
			var v10 := Vector3(dir1.x * p_cur.x, p_cur.y, dir1.y * p_cur.x)
			var v11 := Vector3(dir1.x * p_nxt.x, p_nxt.y, dir1.y * p_nxt.x)
			var v01 := Vector3(dir0.x * p_nxt.x, p_nxt.y, dir0.y * p_nxt.x)

			st.set_uv(Vector2(u0, v0))
			st.add_vertex(v00)
			st.set_uv(Vector2(u1, v0))
			st.add_vertex(v10)
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(v11)

			st.set_uv(Vector2(u0, v0))
			st.add_vertex(v00)
			st.set_uv(Vector2(u1, v1))
			st.add_vertex(v11)
			st.set_uv(Vector2(u0, v1))
			st.add_vertex(v01)
	st.generate_normals()
	var s_idx := mesh.get_surface_count()
	st.commit(mesh)
	if mat != null and s_idx < mesh.get_surface_count():
		mesh.surface_set_material(s_idx, mat)
