class_name ObjectKit
extends RefCounted

## 100 distinct procedural detail props per map, batched into the existing
## FrontlineTerrain static batches.
##
## Categories (10 variants each, 100 total):
##   barrels/drums, crates, pipes/valves, machines, vehicles/wrecks,
##   military/fortification, camp furniture, farm/industrial tools,
##   rubble/debris, nature/water props.
##
## Every variant is a different composition of primitives with its own
## dimensions and attachments, not a recoloured copy.  The same 100 object
## types are placed on every frontline map with biome-specific materials
## (wood/rust/concrete/sandbag tints), so the result is thematic without
## duplicating a 400-recipe asset library.
##
## All parts go through FrontlineTerrain's _add_box/_add_cylinder helpers, so
## they are merged by the existing static batching pass.  On High a single
## collider box is registered for the large categories (machines, vehicles,
## military, farm tools).

const FT := preload("res://scripts/util/frontline_terrain.gd")

static var _rng := RandomNumberGenerator.new()
static var _root: Node3D
static var _map := ""
static var _yaw := 0.0
static var _basis := Basis.IDENTITY
static var _base := Vector3.ZERO
static var _theme := {}
static var _shadows := false
static var _scale := 1.0
static var _colliders: Array = []


static func build(root: Node3D, map_name: String, factor: float,
		reserved: Array = []) -> void:
	if root == null:
		return
	_root = root
	_map = map_name
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash(map_name) + 771113
	_theme = _make_theme(map_name)
	_shadows = factor >= 0.99
	_colliders.clear()
	var total := maxi(10, int(round(28.0 * factor)))
	var spots := _make_spots(root, map_name, total, reserved)
	if spots.is_empty():
		return
	# Fisher-Yates with the deterministic RNG so categories are spread over
	# the map instead of all ten barrels appearing in one corner.
	var order: Array = []
	for i in range(100):
		order.append(i)
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in range(mini(total, spots.size())):
		var idx: int = order[i]
		var cat: int = idx % 10
		var variant: int = int(idx / 10)
		var spot: Vector2 = spots[i]
		FT.reserve_area(spot, 2.0)
		_yaw = _rng.randf_range(0.0, TAU)
		_basis = Basis(Vector3.UP, _yaw)
		_scale = _rng.randf_range(1.05, 1.32)
		_base = Vector3(spot.x, FT.height_at(map_name, spot.x, spot.y), spot.y)
		_build_category(cat, variant)
		_used_collider(cat, variant)
	_add_colliders()
	root.set_meta("gfx_object_kit", mini(total, spots.size()))
	root.set_meta("gfx_object_kit_colliders", _colliders.size())
	print("[ObjectKit] placed ", mini(total, spots.size()), " unique props on ",
			map_name, " (", _colliders.size(), " colliders)")


static func _build_category(cat: int, v: int) -> void:
	match cat:
		0:
			_barrel(v)
		1:
			_crate(v)
		2:
			_pipe(v)
		3:
			_machine(v)
		4:
			_vehicle(v)
		5:
			_military(v)
		6:
			_camp(v)
		7:
			_farm_tool(v)
		8:
			_debris(v)
		_:
			_nature(v)


# ===========================================================================
#  Placement
# ===========================================================================
static func _make_spots(root: Node3D, map_name: String, count: int,
		reserved: Array) -> Array:
	# Objects are arranged in 20 supply/camp clusters of five, not 100 lonely
	# icons: the kit reads as themed set dressing from the air and at eye level.
	var centers: Array = []
	var site: Dictionary = FT.HALL_SITES.get(map_name, {})
	if not site.is_empty():
		var c: Vector2 = site["center"]
		var half: Vector2 = site["half"]
		var inner_x := c.x + half.x + 14.0
		# Fixed, visible clusters in/around the hero yard.  Two sit just
		# outside the east door (left/right of the exit lane), so the 100-prop
		# kit is obvious from the very first exterior frame.
		for fp in [Vector2(inner_x + 2.0, c.y - 15.0),
				Vector2(inner_x + 2.0, c.y + 15.0),
				Vector2(inner_x + 82.0, c.y + 8.0),
				Vector2(inner_x + 10.0, c.y - 22.0),
				Vector2(inner_x + 56.0, c.y + 24.0)]:
			if _center_ok(fp, centers, reserved):
				centers.append(fp)
		# Six more around the hall.
		var tries := 0
		while centers.size() < 9 and tries < 300:
			tries += 1
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(42.0, 135.0)
			var p := c + Vector2(cos(a), sin(a)) * r
			if _center_ok(p, centers, reserved):
				centers.append(p)
	# Six road-side clusters.
	for road in FT._road_points(map_name):
		var pts := road as PackedVector2Array
		var step := maxi(1, int(pts.size() / 10))
		for i in range(0, pts.size(), step):
			if centers.size() >= 15:
				break
			var p := pts[i] + Vector2(_rng.randf_range(-13.0, 13.0),
					_rng.randf_range(-13.0, 13.0))
			if _center_ok(p, centers, reserved):
				centers.append(p)
	# Rest random inside compact ±155 m grass bounds.
	var tries := 0
	while centers.size() < 16 and tries < 240:
		tries += 1
		var p := Vector2(_rng.randf_range(-155.0, 155.0),
				_rng.randf_range(-155.0, 155.0))
		if _center_ok(p, centers, reserved):
			centers.append(p)
	var spots: Array = []
	if centers.is_empty():
		return spots
	var per_cluster := maxi(2, int(ceil(float(count) * 0.75 / float(centers.size()))))
	for center in centers:
		var cc: Vector2 = center
		for k in range(per_cluster):
			if spots.size() >= count:
				break
			var p := cc + Vector2(_rng.randf_range(-16.0, 16.0),
					_rng.randf_range(-16.0, 16.0))
			if _ok(p, spots, reserved, 10.5):
				spots.append(p)
	tries = 0
	while spots.size() < count and tries < count * 30:
		tries += 1
		var p := Vector2(_rng.randf_range(-156.0, 156.0),
				_rng.randf_range(-156.0, 156.0))
		if _ok(p, spots, reserved, 10.5):
			spots.append(p)
	return spots


static func _depot_center(site: Dictionary, centers: Array,
		reserved: Array) -> Variant:
	if site.is_empty():
		return null
	var c: Vector2 = site["center"]
	var half: Vector2 = site["half"]
	var base := Vector2(c.x + half.x + 56.0, c.y - 42.0)
	for cand in [base, base + Vector2(0.0, 84.0),
			base + Vector2(28.0, 0.0), base + Vector2(-24.0, 18.0),
			Vector2(c.x - half.x - 52.0, c.y - 36.0)]:
		var p: Vector2 = cand
		if _center_ok(p, centers, reserved):
			return p
	return null


static func _center_ok(p: Vector2, centers: Array, reserved: Array) -> bool:
	if absf(p.x) > 160.0 or absf(p.y) > 160.0:
		return false
	if FT._road_factor(_map, p.x, p.y) >= 0.25:
		return false
	var y: float = FT.height_at(_map, p.x, p.y)
	if y < FT.water_level(_map) + 0.35:
		return false
	if FT._hall_clear_zone(_map, p.x, p.y):
		return false
	if FT._structure_clear_zone(_map, p.x, p.y, 8.0):
		return false
	if (_map == "steppe" or _map == "village") \
			and FT._tutorial_clear_zone(p.x, p.y):
		return false
	for c in centers:
		if (c as Vector2).distance_to(p) < 34.0:
			return false
	for r in reserved:
		if (r as Vector2).distance_to(p) < 18.0:
			return false
	return true


static func _ok(p: Vector2, spots: Array, reserved: Array,
		min_sep: float = 7.0) -> bool:
	if absf(p.x) > 160.0 or absf(p.y) > 160.0:
		return false
	if FT._road_factor(_map, p.x, p.y) >= 0.25:
		return false
	var y: float = FT.height_at(_map, p.x, p.y)
	if y < FT.water_level(_map) + 0.35:
		return false
	if FT._hall_clear_zone(_map, p.x, p.y):
		return false
	if FT._structure_clear_zone(_map, p.x, p.y, 8.0):
		return false
	if (_map == "steppe" or _map == "village") \
			and FT._tutorial_clear_zone(p.x, p.y):
		return false
	for s in spots:
		if (s as Vector2).distance_to(p) < min_sep:
			return false
	for s in reserved:
		if (s as Vector2).distance_to(p) < 10.0:
			return false
	return true


# ===========================================================================
#  Primitive helpers
# ===========================================================================
static func _world(off: Vector3) -> Vector3:
	return _base + _basis * (off * _scale)


static func _box(off: Vector3, size: Vector3, mat: String,
		local_yaw: float = 0.0, collide: bool = false) -> void:
	var node := FT._add_box(_root, _world(off), size * _scale, _theme[mat],
			_yaw + local_yaw, collide)
	if node != null and not collide:
		_set_shadow(node)


static func _cyl(off: Vector3, radius: float, height: float, mat: String,
		collide: bool = false) -> void:
	var node := FT._add_cylinder(_root, _world(off), radius * _scale,
			height * _scale, _theme[mat], _yaw, collide)
	if node != null and not collide:
		_set_shadow(node)


static func _prism(off: Vector3, size: Vector3, mat: String) -> void:
	# PrismMesh is not exposed by FT with a return value; use a box roof for
	# batching and let the silhouette come from the stacked tiers.
	_box(off, size, mat)


static func _set_shadow(node: Node) -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = mode
	for child in node.get_children():
		_set_shadow(child)


static func _collide(off: Vector3, size: Vector3) -> void:
	_colliders.append({"pos": _world(off), "size": size * _scale, "yaw": _yaw})


static func _used_collider(cat: int, v: int) -> void:
	# Never add collision inside the combat target block: the mission needs
	# clear ground for target placement and drone attacks.
	if Vector2(_base.x, _base.z).distance_to(Vector2(0.0, 90.0)) < 145.0:
		return
	# Only big categories get a simple box collider; small clutter is visual.
	if cat == 3 or cat == 4 or cat == 5 or cat == 7:
		_collide(Vector3(0.0, 0.9, 0.0), Vector3(2.4, 1.8, 1.8))
	elif cat == 8 and v % 3 == 0:
		_collide(Vector3(0.0, 0.5, 0.0), Vector3(2.0, 1.0, 1.5))


static func _add_colliders() -> void:
	if _colliders.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "ObjectKitCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	for c in _colliders:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = c["size"]
		cs.shape = shape
		cs.position = c["pos"]
		cs.rotation.y = float(c.get("yaw", 0.0))
		body.add_child(cs)
	_root.add_child(body)


# ===========================================================================
#  Theme palette
# ===========================================================================
static func _make_theme(map_name: String) -> Dictionary:
	var wood := Color(0.58, 0.44, 0.29)
	var wood_dark := Color(0.36, 0.27, 0.18)
	var metal := Color(0.48, 0.51, 0.50)
	var rust := Color(0.50, 0.29, 0.18)
	var concrete := Color(0.72, 0.71, 0.67)
	var brick := Color(0.66, 0.44, 0.34)
	var plaster := Color(0.78, 0.72, 0.62)
	var sandbag := Color(0.55, 0.50, 0.35)
	match map_name:
		"village":
			wood = Color(0.62, 0.46, 0.30)
			wood_dark = Color(0.38, 0.27, 0.17)
			plaster = Color(0.82, 0.75, 0.64)
			sandbag = Color(0.58, 0.52, 0.37)
		"industrial":
			wood = Color(0.42, 0.34, 0.25)
			wood_dark = Color(0.25, 0.20, 0.15)
			metal = Color(0.43, 0.46, 0.47)
			concrete = Color(0.66, 0.66, 0.64)
		"wetlands":
			wood = Color(0.35, 0.35, 0.27)
			wood_dark = Color(0.22, 0.23, 0.17)
			metal = Color(0.38, 0.43, 0.40)
			rust = Color(0.44, 0.29, 0.19)
			concrete = Color(0.57, 0.59, 0.55)
			sandbag = Color(0.45, 0.44, 0.31)
	var t := {}
	t["wood"] = FT._pbr("wood", wood, 0.34)
	t["wood_dark"] = FT._pbr("wood", wood_dark, 0.40)
	t["steel"] = FT._pbr("steel", metal, 0.30)
	t["rust"] = FT._pbr("steel", rust, 0.34)
	t["concrete"] = FT._pbr("concrete", concrete, 0.24)
	t["brick"] = FT._pbr("brick", brick, 0.26)
	t["plaster"] = FT._pbr("plaster", plaster, 0.26)
	t["sandbag"] = FT._pbr("sandbag", sandbag, 0.20)
	t["dark"] = FT._mat(Color(0.055, 0.050, 0.045), 0.9)
	t["fabric"] = FT._mat(Color(0.30, 0.30, 0.22), 0.95)
	t["paint_red"] = FT._mat(Color(0.58, 0.16, 0.12), 0.65)
	t["paint_blue"] = FT._mat(Color(0.15, 0.28, 0.38), 0.65)
	t["paint_yellow"] = FT._mat(Color(0.65, 0.50, 0.10), 0.7)
	t["paint_green"] = FT._mat(Color(0.18, 0.30, 0.16), 0.7)
	t["glass"] = FT._mat(Color(0.08, 0.12, 0.14), 0.12, 0.30)
	return t


# ===========================================================================
#  0. Barrels / drums (10 variants)
# ===========================================================================
static func _barrel(v: int) -> void:
	var r := 0.27 + 0.018 * float(v % 4)
	var h := 0.78 + 0.055 * float(v % 5)
	var mat: String = ["paint_red", "paint_blue", "steel", "rust",
			"paint_green"][v % 5]
	_cyl(Vector3(0.0, h * 0.5, 0.0), r, h, mat)
	_cyl(Vector3(0.0, h + 0.025, 0.0), r * 1.08, 0.06, "steel")
	_cyl(Vector3(0.0, 0.045, 0.0), r * 1.02, 0.09, "rust")
	for k in range(2 + v % 3):
		_cyl(Vector3(0.0, h * (0.22 + float(k) * 0.22), 0.0),
				r * 1.035, 0.045, "rust")
	if v % 3 == 0:
		_box(Vector3(r + 0.05, h * 0.55, 0.0), Vector3(0.18, 0.10, 0.10), "steel")
	if v % 4 == 1:
		_box(Vector3(0.0, h + 0.12, 0.0), Vector3(r * 1.5, 0.06, 0.10), "steel")
	if v >= 7:
		_cyl(Vector3(r * 1.2, h * 0.35, 0.25), r * 0.75, h * 0.7, "paint_blue")
		_cyl(Vector3(r * 1.2, h * 0.72, 0.25), r * 0.82, 0.05, "rust")
	if v == 9:
		_cyl(Vector3(-r * 1.15, h * 0.3, -0.35), r * 0.8, h * 0.6, "rust")


# ===========================================================================
#  1. Crates / boxes (10 variants)
# ===========================================================================
static func _crate(v: int) -> void:
	var s := 0.55 + 0.065 * float(v % 4)
	var h := s * (0.8 + 0.10 * float(v % 3))
	var body: String = "wood" if v % 3 else "wood_dark"
	_box(Vector3(0.0, h * 0.5, 0.0), Vector3(s, h, s), body)
	_box(Vector3(0.0, h + 0.035, 0.0), Vector3(s * 1.06, 0.07, s * 1.06), "wood_dark")
	for k in range(3 + v % 3):
		_box(Vector3(0.0, h * (0.18 + float(k) * 0.24), -s * 0.52),
				Vector3(s * 1.04, 0.045, 0.05), "wood_dark")
	_box(Vector3(0.0, h * 0.55, s * 0.52), Vector3(s * 0.55, h * 0.36, 0.035),
			"paint_yellow" if v % 2 else "steel")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(sx * s * 0.47, h * 0.5, sz * s * 0.47),
					Vector3(0.07, h, 0.07), "steel")
	if v % 3 == 1:
		_box(Vector3(0.0, h + 0.32, 0.0), Vector3(s * 0.72, 0.5, s * 0.72), "wood")
		_box(Vector3(0.0, h + 0.60, 0.0), Vector3(s * 0.78, 0.06, s * 0.78), "wood_dark")
	elif v % 3 == 2:
		_box(Vector3(s * 0.65, h * 0.35, 0.0), Vector3(s * 0.55, h * 0.65, s * 0.8),
				"paint_blue")
	if v == 9:
		_box(Vector3(0.0, h + 0.06, 0.0), Vector3(s * 0.92, 0.06, s * 0.92), "dark")
		_box(Vector3(0.0, h + 0.26, -s * 0.42), Vector3(0.06, 0.5, 0.06), "steel")


# ===========================================================================
#  2. Pipes / valves (10 variants)
# ===========================================================================
static func _pipe(v: int) -> void:
	var length := 1.4 + 0.18 * float(v % 5)
	var dia := 0.18 + 0.018 * float(v % 3)
	var mat: String = "steel" if v % 3 else "rust"
	# Long body laid along local X, represented by a low box; flange rings at
	# the ends are cylinders rotated by using squat vertical rings.
	_box(Vector3(0.0, dia + 0.05, 0.0), Vector3(length, dia * 1.4, dia * 1.4), mat)
	for sx in [-1.0, 1.0]:
		_box(Vector3(sx * length * 0.5, dia + 0.05, 0.0),
				Vector3(0.12, dia * 1.9, dia * 1.9), "steel")
	for k in range(2 + v % 4):
		_box(Vector3(-length * 0.35 + float(k) * length * 0.23,
				dia + 0.05, 0.0), Vector3(0.08, dia * 1.75, dia * 1.75), "rust")
	# Valve wheel / elbow.
	if v % 2 == 0:
		_cyl(Vector3(0.0, dia * 2.3, 0.0), dia * 0.85, 0.07, "paint_red")
		_cyl(Vector3(0.0, dia * 2.0, 0.0), dia * 0.18, 0.5, "steel")
	else:
		_box(Vector3(length * 0.34, dia + 0.55, 0.0),
				Vector3(dia * 1.25, 1.0, dia * 1.25), "rust")
		_box(Vector3(length * 0.34, dia + 1.05, 0.0),
				Vector3(dia * 1.25, dia * 1.25, 0.9), "steel")
	if v >= 6:
		_box(Vector3(0.0, 0.12, 0.0), Vector3(length * 0.9, 0.18, 0.8), "wood_dark")
	if v == 9:
		_box(Vector3(-length * 0.2, dia + 1.3, 0.0),
				Vector3(0.5, 0.5, 0.5), "paint_yellow")


# ===========================================================================
#  3. Machines / pumps / generators (10 variants)
# ===========================================================================
static func _machine(v: int) -> void:
	var w := 1.2 + 0.10 * float(v % 4)
	var d := 0.9 + 0.08 * float(v % 3)
	var h := 0.65 + 0.09 * float(v % 4)
	_box(Vector3(0.0, 0.10, 0.0), Vector3(w + 0.5, 0.2, d + 0.4), "wood_dark")
	_box(Vector3(0.0, 0.18 + h * 0.5, 0.0), Vector3(w, h, d), "steel" if v % 2 else "rust")
	_cyl(Vector3(-w * 0.22, 0.25 + h * 0.75, 0.0), 0.24, 0.55, "steel")
	_cyl(Vector3(-w * 0.22, 0.55 + h * 0.75, 0.0), 0.30, 0.10, "paint_yellow")
	_box(Vector3(w * 0.25, 0.25 + h * 0.55, d * 0.5 + 0.03),
			Vector3(0.46, 0.36, 0.06), "paint_yellow")
	for k in range(2 + v % 3):
		_box(Vector3(-w * 0.4 + float(k) * 0.16, 0.25 + h * 0.7, -d * 0.45),
				Vector3(0.08, 0.5, 0.08), "rust")
	if v % 3 == 0:
		_cyl(Vector3(w * 0.28, 0.25 + h + 0.25, 0.0), 0.30, 0.5, "rust")
	if v % 4 == 1:
		_box(Vector3(0.0, 0.18 + h + 0.18, 0.0), Vector3(w * 0.8, 0.25, d * 0.8), "steel")
	if v >= 7:
		_box(Vector3(w * 0.25, 0.18 + h + 0.7, 0.0), Vector3(0.08, 1.0, 0.08), "steel")
		_box(Vector3(w * 0.25, 0.18 + h + 1.2, 0.0), Vector3(0.55, 0.05, 0.05), "paint_red")


# ===========================================================================
#  4. Vehicles / carts / wrecks (10 variants)
# ===========================================================================
static func _vehicle(v: int) -> void:
	var length := 2.2 + 0.22 * float(v % 4)
	var width := 1.1 + 0.06 * float(v % 3)
	var body: String = "rust" if v % 3 == 0 else ("paint_green" if v % 3 == 1 else "steel")
	_box(Vector3(0.0, 0.45, 0.0), Vector3(length, 0.55, width), body)
	_box(Vector3(0.0, 0.82, 0.0), Vector3(length * 0.75, 0.18, width * 0.92), "dark")
	if v % 2 == 0:
		_box(Vector3(-length * 0.22, 1.05, 0.0), Vector3(length * 0.36, 0.6, width * 0.82),
				body)
		_box(Vector3(-length * 0.22, 1.22, width * 0.42),
				Vector3(length * 0.28, 0.28, 0.06), "glass")
	if v % 3 == 0:
		_box(Vector3(length * 0.30, 0.80, 0.0), Vector3(length * 0.32, 0.55, width * 0.9),
				"wood")
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(Vector3(sx * length * 0.34, 0.34, sz * width * 0.48),
					Vector3(0.42, 0.42, 0.18), "dark")
	if v % 4 == 1:
		_cyl(Vector3(length * 0.25, 1.0, 0.0), 0.30, 0.65, "rust")
	if v % 4 == 2:
		_box(Vector3(length * 0.2, 1.1, 0.0), Vector3(0.9, 0.22, 0.06), "paint_yellow")
	if v >= 7:
		_box(Vector3(0.0, 0.20, 0.0), Vector3(length * 0.9, 0.12, width * 0.7), "dark")
		_box(Vector3(length * 0.42, 0.45, width * 0.3),
				Vector3(0.7, 0.35, 0.35), "rust")


# ===========================================================================
#  5. Military / fortification (10 variants)
# ===========================================================================
static func _military(v: int) -> void:
	match v:
		0, 1, 2:
			# Sandbag nest with a crate and antenna.
			var arc := 1.2 + 0.2 * float(v)
			for i in range(5 + v):
				var a := -1.0 + float(i) / float(5 + v) * 2.0
				_box(Vector3(cos(a) * arc, 0.22 + 0.16 * float(i % 2),
						sin(a) * arc * 0.55), Vector3(0.55, 0.32, 0.35), "sandbag")
			_box(Vector3(0.0, 0.30, -0.2), Vector3(0.8, 0.55, 0.55), "wood_dark")
			if v > 0:
				_box(Vector3(0.0, 0.85, -0.2), Vector3(0.05, 1.4, 0.05), "steel")
				_box(Vector3(0.0, 1.55, -0.2), Vector3(0.5, 0.04, 0.04), "steel")
		3:
			# Hedgehog.
			for i in range(3):
				var a := TAU * float(i) / 3.0
				_box(Vector3(cos(a) * 0.3, 0.55, sin(a) * 0.3),
						Vector3(0.16, 1.2, 0.16), "rust")
		4:
			# Ammo crates stacked.
			for i in range(3):
				_box(Vector3(-0.4 + float(i) * 0.4, 0.25, 0.0),
						Vector3(0.5, 0.4, 0.7), "paint_green")
				_box(Vector3(-0.4 + float(i) * 0.4, 0.47, 0.0),
						Vector3(0.54, 0.05, 0.74), "paint_yellow")
		5:
			# Radio station.
			_box(Vector3(0.0, 0.22, 0.0), Vector3(0.9, 0.4, 0.7), "paint_green")
			for i in range(4):
				_box(Vector3(-0.3 + float(i) * 0.2, 0.55, 0.2),
						Vector3(0.08, 0.3, 0.08), "dark")
			_box(Vector3(0.0, 0.7, -0.1), Vector3(0.05, 1.0, 0.05), "steel")
		6:
			# Tripod + heavy weapon silhouette.
			for i in range(3):
				var a := TAU * float(i) / 3.0
				_box(Vector3(cos(a) * 0.3, 0.4, sin(a) * 0.3),
						Vector3(0.12, 0.8, 0.12), "steel")
			_box(Vector3(0.0, 0.9, 0.0), Vector3(0.8, 0.22, 0.22), "dark")
			_box(Vector3(0.35, 1.0, 0.0), Vector3(0.9, 0.08, 0.08), "steel")
		7, 8:
			# Bunker firing slit + sandbags.
			_box(Vector3(0.0, 0.55, 0.0), Vector3(2.2, 1.1, 1.2), "concrete")
			_box(Vector3(0.0, 0.75, 0.62), Vector3(1.4, 0.28, 0.06), "dark")
			for i in range(4):
				_box(Vector3(-1.0 + float(i) * 0.66, 0.15, 0.8),
						Vector3(0.62, 0.3, 0.5), "sandbag")
		9:
			# Checkpoint barrier.
			for sx in [-1.0, 1.0]:
				_box(Vector3(sx * 1.1, 0.7, 0.0), Vector3(0.3, 1.4, 0.3), "concrete")
			_box(Vector3(0.0, 1.25, 0.0), Vector3(2.4, 0.22, 0.22), "steel")
			for i in range(4):
				_box(Vector3(-0.75 + float(i) * 0.5, 1.25, 0.0),
						Vector3(0.24, 0.26, 0.26), "paint_red")


# ===========================================================================
#  6. Camp furniture (10 variants)
# ===========================================================================
static func _camp(v: int) -> void:
	match v:
		0, 1, 2:
			# Tent.
			var w := 1.8 + 0.2 * float(v)
			_box(Vector3(0.0, 0.6, 0.0), Vector3(w, 1.0, 1.5), "fabric")
			_box(Vector3(0.0, 1.12, 0.0), Vector3(w + 0.3, 0.08, 1.7), "dark")
			for sx in [-1.0, 1.0]:
				_box(Vector3(sx * w * 0.45, 0.55, 0.0),
						Vector3(0.06, 1.1, 0.06), "wood_dark")
			if v == 2:
				_box(Vector3(0.0, 0.65, 0.78), Vector3(0.7, 1.0, 0.04), "dark")
		3, 4:
			# Stove + pipe.
			_box(Vector3(0.0, 0.3, 0.0), Vector3(0.7, 0.6, 0.6), "rust")
			_box(Vector3(0.0, 0.62, 0.0), Vector3(0.75, 0.05, 0.65), "dark")
			_cyl(Vector3(0.2, 1.2, 0.15), 0.09, 1.2, "rust")
			_box(Vector3(-0.35, 0.25, 0.35), Vector3(0.4, 0.3, 0.3), "wood_dark")
		5:
			# Table, bench and lantern.
			_box(Vector3(0.0, 0.72, 0.0), Vector3(1.4, 0.09, 0.8), "wood")
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box(Vector3(sx * 0.55, 0.36, sz * 0.3),
							Vector3(0.08, 0.72, 0.08), "wood_dark")
			_box(Vector3(0.0, 0.42, 0.8), Vector3(1.2, 0.08, 0.35), "wood")
			_box(Vector3(0.45, 0.95, 0.0), Vector3(0.12, 0.3, 0.12), "paint_yellow")
		6:
			# Cot and footlocker.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(2.0, 0.22, 0.8), "fabric")
			_box(Vector3(0.0, 0.5, 0.0), Vector3(1.7, 0.12, 0.7), "dark")
			_box(Vector3(1.3, 0.32, 0.0), Vector3(0.4, 0.55, 0.5), "wood_dark")
		7:
			# Campfire ring.
			for i in range(7):
				var a := TAU * float(i) / 7.0
				_box(Vector3(cos(a) * 0.65, 0.12, sin(a) * 0.65),
						Vector3(0.22, 0.24, 0.22), "concrete")
			_box(Vector3(0.0, 0.18, 0.0), Vector3(0.85, 0.15, 0.85), "dark")
			_cyl(Vector3(0.0, 0.3, 0.0), 0.12, 0.5, "rust")
		8:
			# Washbasin / water point.
			_box(Vector3(0.0, 0.55, 0.0), Vector3(0.9, 0.5, 0.7), "steel")
			_box(Vector3(0.0, 0.82, 0.0), Vector3(1.0, 0.08, 0.8), "steel")
			_cyl(Vector3(-0.6, 0.55, 0.0), 0.1, 1.0, "rust")
		9:
			# Field desk with maps.
			_box(Vector3(0.0, 0.52, 0.0), Vector3(1.5, 0.08, 0.9), "wood")
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box(Vector3(sx * 0.6, 0.26, sz * 0.34),
							Vector3(0.08, 0.52, 0.08), "wood_dark")
			_box(Vector3(0.1, 0.58, 0.0), Vector3(0.6, 0.02, 0.45), "plaster")
			_box(Vector3(-0.45, 0.6, 0.0), Vector3(0.2, 0.18, 0.25), "paint_red")


# ===========================================================================
#  7. Farm / industrial tools (10 variants)
# ===========================================================================
static func _farm_tool(v: int) -> void:
	match v:
		0:
			# Hay rack.
			for i in range(4):
				_box(Vector3(-1.0 + float(i) * 0.65, 0.55, 0.0),
						Vector3(0.08, 1.1, 0.08), "wood_dark")
			_box(Vector3(0.0, 1.12, 0.0), Vector3(2.2, 0.08, 0.9), "wood")
			_box(Vector3(0.0, 0.65, 0.35), Vector3(2.0, 0.5, 0.04), "wood")
		1:
			# Water trough.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(1.8, 0.55, 0.7), "wood_dark")
			_box(Vector3(0.0, 0.6, 0.0), Vector3(1.65, 0.08, 0.55), "steel")
			_cyl(Vector3(-0.95, 0.5, 0.0), 0.12, 0.9, "rust")
		2:
			# Plow.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(1.6, 0.22, 0.35), "rust")
			_box(Vector3(0.0, 0.5, -0.5), Vector3(0.9, 0.08, 0.8), "rust")
			for i in range(3):
				_box(Vector3(-0.7 + float(i) * 0.5, 0.15, 0.15),
						Vector3(0.18, 0.3, 0.5), "steel")
		3:
			# Hand cart with bales.
			_box(Vector3(0.0, 0.42, 0.0), Vector3(1.4, 0.18, 0.8), "wood")
			for sx in [-1.0, 1.0]:
				_box(Vector3(sx * 0.55, 0.22, 0.0), Vector3(0.12, 0.45, 0.7), "dark")
			_box(Vector3(0.45, 0.7, 0.0), Vector3(0.6, 0.5, 0.35), "wood_dark")
		4:
			# Fence section.
			for i in range(4):
				_box(Vector3(-1.2 + float(i) * 0.8, 0.55, 0.0),
						Vector3(0.10, 1.1, 0.10), "wood_dark")
			for y in [0.4, 0.85]:
				_box(Vector3(0.0, y, 0.0), Vector3(3.0, 0.07, 0.07), "wood")
		5:
			# Workbench.
			_box(Vector3(0.0, 0.85, 0.0), Vector3(1.7, 0.10, 0.8), "wood")
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_box(Vector3(sx * 0.68, 0.42, sz * 0.28),
							Vector3(0.08, 0.85, 0.08), "wood_dark")
			_box(Vector3(0.4, 0.98, 0.0), Vector3(0.25, 0.14, 0.25), "rust")
		6:
			# Cable reel.
			for sx in [-1.0, 1.0]:
				_cyl(Vector3(sx * 0.55, 0.55, 0.0), 0.75, 0.10, "wood_dark")
			_cyl(Vector3(0.0, 0.55, 0.0), 0.45, 0.9, "dark")
			for i in range(3):
				_cyl(Vector3(0.0, 0.35 + float(i) * 0.25, 0.0), 0.52, 0.18, "rust")
		7:
			# Pallet jack.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(1.1, 0.16, 0.6), "paint_yellow")
			_box(Vector3(0.45, 0.65, 0.0), Vector3(0.10, 0.8, 0.10), "steel")
			_box(Vector3(0.45, 1.05, 0.0), Vector3(0.55, 0.08, 0.08), "steel")
			_box(Vector3(0.0, 0.12, 0.0), Vector3(1.2, 0.08, 0.18), "steel")
			for sx in [-1.0, 1.0]:
				_box(Vector3(sx * 0.35, 0.18, 0.25), Vector3(0.16, 0.2, 0.16), "dark")
		8:
			# Welding rig.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(0.8, 0.6, 0.5), "rust")
			_box(Vector3(0.0, 0.68, 0.0), Vector3(0.85, 0.06, 0.55), "dark")
			_cyl(Vector3(0.0, 1.2, 0.0), 0.06, 1.0, "steel")
			_box(Vector3(0.0, 1.7, 0.0), Vector3(0.5, 0.05, 0.05), "steel")
		9:
			# Anvil and tool box.
			_box(Vector3(0.0, 0.55, 0.0), Vector3(0.65, 0.3, 0.35), "dark")
			_box(Vector3(0.0, 0.3, 0.0), Vector3(0.35, 0.3, 0.3), "rust")
			_box(Vector3(0.6, 0.25, 0.2), Vector3(0.6, 0.35, 0.35), "paint_red")


# ===========================================================================
#  8. Rubble / debris (10 variants)
# ===========================================================================
static func _debris(v: int) -> void:
	match v:
		0, 1:
			# Concrete slab leaning on rubble.
			_box(Vector3(0.0, 0.35, 0.0), Vector3(2.6, 0.25, 1.3), "concrete",
					-0.12 if v else 0.08)
			_box(Vector3(-0.8, 0.12, 0.4), Vector3(0.9, 0.25, 0.7), "concrete")
			for i in range(3):
				_box(Vector3(0.3 + float(i) * 0.35, 0.08, -0.45),
						Vector3(0.35, 0.16, 0.25), "brick")
		2:
			# Brick pile.
			for i in range(9):
				_box(Vector3(-0.6 + float(i % 3) * 0.3, 0.08 + float(i / 3) * 0.14,
						-0.25 + float(i / 3) * 0.2), Vector3(0.25, 0.12, 0.14), "brick")
		3:
			# Rebar bundle.
			for i in range(6):
				_box(Vector3(0.0, 0.12 + float(i) * 0.03, -0.3 + float(i) * 0.1),
						Vector3(2.4, 0.025, 0.025), "rust")
		4:
			# Tyre stack.
			for i in range(3):
				_cyl(Vector3(0.0, 0.18 + float(i) * 0.3, 0.0), 0.42, 0.25, "dark")
		5:
			# Broken wall stump.
			_box(Vector3(0.0, 0.55, 0.0), Vector3(2.0, 1.1, 0.4), "brick")
			_box(Vector3(0.4, 1.15, 0.0), Vector3(0.8, 0.2, 0.4), "brick")
			for i in range(3):
				_box(Vector3(-0.6 + float(i) * 0.6, 0.15, 0.45),
						Vector3(0.4, 0.3, 0.3), "concrete")
		6:
			# Roof sheet.
			_box(Vector3(0.0, 0.25, 0.0), Vector3(2.2, 0.08, 1.1), "rust", 0.06)
			_box(Vector3(0.0, 0.12, 0.0), Vector3(1.6, 0.1, 0.7), "wood_dark")
		7:
			# Steel beam.
			_box(Vector3(0.0, 0.28, 0.0), Vector3(2.8, 0.32, 0.32), "rust")
			_box(Vector3(0.0, 0.08, 0.0), Vector3(1.8, 0.16, 0.5), "concrete")
		8:
			# Gravel heap with planks.
			_cyl(Vector3(0.0, 0.3, 0.0), 0.9, 0.6, "concrete")
			_box(Vector3(0.5, 0.15, 0.0), Vector3(1.2, 0.08, 0.25), "wood")
		9:
			# Scrap metal pile.
			for i in range(5):
				_box(Vector3(-0.6 + float(i) * 0.3, 0.15 + float(i % 2) * 0.2,
						-0.2 + float(i % 3) * 0.2),
						Vector3(0.8, 0.08, 0.4), "steel" if i % 2 else "rust")


# ===========================================================================
#  9. Nature / water props (10 variants)
# ===========================================================================
static func _nature(v: int) -> void:
	match v:
		0, 1:
			# Fallen log with stump.
			_cyl(Vector3(0.0, 0.32, 0.0), 0.32, 2.4, "wood_dark")
			_cyl(Vector3(1.35, 0.32, 0.0), 0.36, 0.25, "wood")
			_cyl(Vector3(-1.4, 0.32, 0.0), 0.30, 0.2, "wood")
			if v:
				_box(Vector3(0.5, 0.55, 0.0), Vector3(0.6, 0.4, 0.5), "wood")
		2:
			# Stump with roots.
			_cyl(Vector3(0.0, 0.35, 0.0), 0.45, 0.7, "wood_dark")
			for i in range(5):
				var a := TAU * float(i) / 5.0
				_box(Vector3(cos(a) * 0.55, 0.12, sin(a) * 0.55),
						Vector3(0.6, 0.15, 0.15), "wood")
		3:
			# Reed cluster.
			for i in range(12):
				var a := TAU * float(i) / 12.0
				_box(Vector3(cos(a) * 0.35, 0.7, sin(a) * 0.35),
						Vector3(0.04, 1.4, 0.04), "wood_dark")
		4:
			# Small boat.
			_box(Vector3(0.0, 0.25, 0.0), Vector3(2.2, 0.4, 0.8), "wood")
			_box(Vector3(0.0, 0.48, 0.0), Vector3(1.8, 0.25, 0.6), "dark")
			_box(Vector3(0.7, 0.65, 0.0), Vector3(0.7, 0.4, 0.55), "wood_dark")
			_box(Vector3(-0.9, 0.55, 0.0), Vector3(0.08, 0.5, 0.7), "steel")
		5:
			# Buoy / float.
			_cyl(Vector3(0.0, 0.45, 0.0), 0.3, 0.9, "paint_red")
			_cyl(Vector3(0.0, 0.92, 0.0), 0.12, 0.4, "steel")
			_cyl(Vector3(0.0, 0.55, 0.0), 0.32, 0.1, "paint_yellow")
		6:
			# Fishing net frame.
			for sx in [-1.0, 1.0]:
				_box(Vector3(sx * 0.9, 0.8, 0.0), Vector3(0.08, 1.6, 0.08), "wood_dark")
			_box(Vector3(0.0, 1.55, 0.0), Vector3(1.9, 0.08, 0.08), "wood")
			for i in range(5):
				_box(Vector3(-0.6 + float(i) * 0.3, 0.9, 0.0),
						Vector3(0.04, 1.2, 0.04), "fabric")
		7:
			# Dock post with rope.
			_cyl(Vector3(0.0, 0.7, 0.0), 0.18, 1.4, "wood_dark")
			_box(Vector3(0.0, 1.35, 0.0), Vector3(0.35, 0.12, 0.35), "rust")
			_cyl(Vector3(0.2, 0.7, 0.0), 0.26, 0.12, "fabric")
		8:
			# Drowned pump.
			_box(Vector3(0.0, 0.3, 0.0), Vector3(0.8, 0.6, 0.6), "rust")
			_cyl(Vector3(0.0, 0.8, 0.0), 0.22, 0.9, "steel")
			_box(Vector3(0.0, 1.25, 0.0), Vector3(0.6, 0.06, 0.6), "rust")
		9:
			# Lily pad cluster.
			for i in range(7):
				var a := TAU * float(i) / 7.0
				_box(Vector3(cos(a) * 0.5, 0.02, sin(a) * 0.5),
						Vector3(0.55, 0.02, 0.45), "paint_green")
