class_name DestructionFx
extends RefCounted

## Reusable hit / explosion / burning presentation for ground vehicles, aerial
## targets and infantry.
##
## The gallery in `test/destruction_gallery.tscn` previews it on the real GLB
## models.  Nothing here is wired into gameplay yet: the live `Vehicle._destroy`
## keeps its own path until the look is approved.
##
## Stages
##   hit()      sparks, metal flash, dust, a short physical jolt;
##   destroy()  fireball, shockwave, debris, charred hull, secondary cook-off,
##              persistent fire + smoke on the wreck;
##   aerial     the same, but the target spins down and impacts the ground
##              instead of freezing at the hit altitude.

const CHAR_COLOR := Color(0.11, 0.10, 0.09)
const FIRE_COLOR := Color(1.0, 0.48, 0.10, 1.0)
const SMOKE_COLOR := Color(0.20, 0.19, 0.18, 0.55)
const DUST_COLOR := Color(0.55, 0.46, 0.33, 0.55)

static var _char_mat: StandardMaterial3D = null
static var _spark_tex: GradientTexture2D = null
static var _smoke_tex: GradientTexture2D = null
static var _dust_tex: GradientTexture2D = null
static var _flame_tex: ImageTexture = null
## Cap simultaneous burning wrecks; a large chaos battle must not end up with
## dozens of continuous particle systems and lights.
const MAX_ACTIVE_BURNS := 10
static var _active_burns := 0


static func _low_quality() -> bool:
	return QualityManager.get_active_level() == QualityManager.Level.LOW


static func _char_material() -> StandardMaterial3D:
	if _char_mat == null:
		_char_mat = StandardMaterial3D.new()
		_char_mat.albedo_color = Color(0.12, 0.105, 0.09)
		_char_mat.roughness = 0.98
		_char_mat.metallic = 0.06
	return _char_mat


static func _texture(kind: String) -> Texture2D:
	match kind:
		"spark":
			if _spark_tex == null:
				_spark_tex = _radial([
					Color(1.0, 1.0, 0.92, 1.0),
					Color(1.0, 0.58, 0.12, 0.9),
					Color(1.0, 0.20, 0.02, 0.0),
				])
			return _spark_tex
		"flame":
			return _flame_texture()
		"dust":
			if _dust_tex == null:
				_dust_tex = _radial([
					Color(0.82, 0.70, 0.50, 0.65),
					Color(0.48, 0.38, 0.25, 0.25),
					Color(0.20, 0.15, 0.10, 0.0),
				])
			return _dust_tex
		_:
			if _smoke_tex == null:
				_smoke_tex = _radial([
					Color(0.72, 0.70, 0.66, 0.62),
					Color(0.38, 0.37, 0.35, 0.28),
					Color(0.12, 0.12, 0.12, 0.0),
				])
			return _smoke_tex


## Soft flame sprite: a bright yellow-white base fading through orange into a
## dark red tip.  Far cheaper than an animated flipbook and it reads correctly
## when dozens overlap in a plume.
static func _flame_texture() -> ImageTexture:
	if _flame_tex != null:
		return _flame_tex
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		# t = 0 at the wide bright base, 1 at the pointed dark-red tip.
		var t := 1.0 - float(y) / float(size - 1)
		var half_w := pow(1.0 - t, 0.62) * 0.86 + 0.04
		for x in range(size):
			var u := absf((float(x) - 31.5) / 31.5)
			var a := 1.0 - smoothstep(half_w * 0.45, half_w, u)
			a *= pow(1.0 - t, 0.30)
			var col := Color(1.0, 0.96, 0.70).lerp(Color(1.0, 0.20, 0.02), t)
			col.a = a
			img.set_pixel(x, y, col)
	_flame_tex = ImageTexture.create_from_image(img)
	return _flame_tex


static func _radial(colors: Array) -> GradientTexture2D:
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in range(colors.size()):
		offsets.append(float(i) / float(maxi(colors.size() - 1, 1)))
		cols.append(colors[i] as Color)
	grad.offsets = offsets
	grad.colors = cols
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## ------------------------------- hit ---------------------------------------
static func hit(parent: Node, unit: Node3D, pos: Vector3, kind: String = "vehicle",
		power: float = 1.0) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	# Infantry: the proper rig already has a flinch animation; keep the hit
	# readable with a small ground puff instead of a fireball-sized spark halo.
	if kind == "infantry":
		if unit.has_method("hit_react"):
			unit.hit_react(true)
		_jolt(unit, 0.45)
		var foot := unit.global_position
		_dust(parent, Vector3(foot.x, foot.y + 0.12, foot.z), 3)
		return
	_sparks(parent, pos, int(10.0 * (0.6 + 0.4 * power)))
	_flash(parent, pos, 0.8 * power, Color(1.0, 0.72, 0.30))
	_jolt(unit, 0.9 * power)
	_hit_overlay(unit)
	if unit.has_method("hit_react"):
		unit.hit_react(true)
	# A tank hit throws more metal; a truck hit burns with a dirtier flash.
	if kind == "tank":
		_sparks(parent, pos, 10)
	elif kind == "truck":
		_flash(parent, pos, 0.6, Color(1.0, 0.46, 0.12))


## Short additive flash on the hull itself so the player sees *what* was hit,
## not only a spark burst in the air next to it.
static func _hit_overlay(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.88, 0.62, 0.16)
	var meshes: Array[MeshInstance3D] = []
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			mi.material_overlay = mat
			meshes.append(mi)
	var timer := unit.get_tree().create_timer(0.14)
	timer.timeout.connect(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == mat:
				mi.material_overlay = null)


static func _jolt(unit: Node3D, power: float) -> void:
	if not is_instance_valid(unit):
		return
	var base_rot := unit.rotation
	var tw := unit.create_tween()
	tw.tween_property(unit, "rotation:z", base_rot.z + 0.055 * power, 0.06)
	tw.tween_property(unit, "rotation:z", base_rot.z, 0.16)
	tw.parallel().tween_property(unit, "position", unit.position + Vector3(
			randf_range(-0.08, 0.08), 0.03, randf_range(-0.08, 0.08)) * power, 0.06)
	tw.tween_property(unit, "position", unit.position, 0.18)


## ----------------------------- destruction ---------------------------------
## kind: tank/bmp/apc/truck/sam/heli/shahed/infantry/vehicle
static func destroy(parent: Node, unit: Node3D, kind: String = "vehicle",
		ground_y: float = 0.0, options: Dictionary = {}) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	var do_char: bool = bool(options.get("char_unit", true))
	var do_move: bool = bool(options.get("move_unit", true))
	var do_burn: bool = bool(options.get("burn", true))
	var do_debris: bool = bool(options.get("debris", true))
	var pos := unit.global_position
	if kind == "infantry":
		pos += Vector3.UP * 1.0
	elif kind == "heli" or kind == "shahed":
		pos += Vector3.UP * 0.8
	else:
		pos += Vector3.UP * 1.2
	if do_char:
		_char(unit)
	_flash(parent, pos, 4.2, Color(1.0, 0.62, 0.18))
	_shockwave(parent, Vector3(pos.x, maxf(ground_y + 0.08, pos.y - 1.0), pos.z),
			2.0 if kind == "infantry" else 9.0)
	_fireball(parent, pos, kind)
	if do_debris:
		_spawn_debris(parent, pos, kind)
	# Secondary cook-off: ammunition / fuel cooking a moment after the hit.
	for delay in [0.32, 0.78]:
		var t := parent.get_tree().create_timer(delay)
		t.timeout.connect(func() -> void:
			if is_instance_valid(parent):
				var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.2, 1.0),
						randf_range(-1.2, 1.2))
				_flash(parent, pos + off, 1.8, Color(1.0, 0.55, 0.12))
				_sparks(parent, pos + off, 10)
				_dust(parent, pos + off, 5))

	if kind == "heli" or kind == "shahed":
		if do_move:
			_aerial_fall(parent, unit, kind, ground_y, pos)
		if do_burn:
			burn(unit, pos, kind, 22.0)
	elif kind == "infantry":
		# Use the proper rigged soldier model, but fall the whole rig instead
		# of the rig's internal death pose (the latter clips through the floor
		# in this standalone preview).
		if do_move:
			_collapse_infantry(unit)
		if do_burn:
			burn(unit, pos, kind, 5.0)
	else:
		if do_move:
			_collapse(unit)
		if do_burn:
			burn(unit, pos, kind, 22.0)


## Burning trail attached to a falling airframe.  Used by the live Vehicle
## crash path so the approved preview look matches the game.
static func trail(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_emitter(unit, "CrashTrail", 30, 0.65, Color(1.0, 0.72, 0.30, 1.0),
			_texture("flame"), 0.9, 2.6, Vector3(0, 2.0, 0), 0.20, 0.55, false)
	_emitter(unit, "CrashSmoke", 18, 1.9, SMOKE_COLOR,
			_texture("smoke"), 0.5, 1.5, Vector3(0, 1.2, 0), 0.7, 1.6, false)


static func stop_trail(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	for n in unit.find_children("CrashTrail", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = false
	for n in unit.find_children("CrashSmoke", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = false


## Impact of an already-falling airframe: char, fireball, debris, burning
## wreck.  Does not move the unit; the live Vehicle keeps its physics fall.
static func impact(parent: Node, unit: Node3D, kind: String,
		ground_y: float) -> void:
	if parent == null or not is_instance_valid(parent) or unit == null:
		return
	var pos := unit.global_position + Vector3.UP * 0.9
	_char(unit)
	_flash(parent, pos, 5.0, Color(1.0, 0.58, 0.14))
	_shockwave(parent, Vector3(pos.x, ground_y + 0.08, pos.z), 10.0)
	_fireball(parent, pos, kind)
	_spawn_debris(parent, pos, kind)
	burn(unit, pos, kind, 22.0)


static func _char(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var mat := _char_material()
	for node in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi != null:
			# A dark charred override guarantees the burned-out look on every
			# imported material (some GLBs ignore material_overlay).
			mi.material_overlay = null
			mi.material_override = mat


static func _collapse(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "position:y", unit.position.y - 0.34, 0.55)
	tw.tween_property(unit, "rotation:x", deg_to_rad(10.0), 0.55)
	tw.tween_property(unit, "rotation:z", deg_to_rad(-7.0), 0.55)
	tw.tween_property(unit, "scale", Vector3(1.03, 0.82, 1.03), 0.55)


static func _collapse_infantry(unit: Node3D) -> void:
	if not is_instance_valid(unit):
		return
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "rotation:x", deg_to_rad(84.0), 0.45)
	tw.tween_property(unit, "position:y", unit.position.y - 0.05, 0.45)


static func _aerial_fall(parent: Node, unit: Node3D, kind: String, ground_y: float,
		impact_pos: Vector3) -> void:
	if not is_instance_valid(unit):
		return
	var fall := maxf(0.9, minf(3.2, (unit.global_position.y - ground_y) / 9.5))
	# Burning trail while the wreck falls.
	var trail := _emitter(unit, "CrashTrail", 30, 0.65, Color(1.0, 0.72, 0.30, 1.0),
			_texture("flame"), 0.9, 2.6, Vector3(0, 2.0, 0), 0.20, 0.55, false)
	var smoke := _emitter(unit, "CrashSmoke", 18, 1.9, SMOKE_COLOR,
			_texture("smoke"), 0.5, 1.5, Vector3(0, 1.2, 0), 0.7, 1.6, false)
	var tw := unit.create_tween()
	tw.set_parallel(true)
	tw.tween_property(unit, "global_position:y", ground_y + 0.22, fall)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(unit, "rotation:x", deg_to_rad(38.0), fall)
	tw.tween_property(unit, "rotation:y", unit.rotation.y + randf_range(4.0, 8.0), fall)
	tw.tween_property(unit, "rotation:z", deg_to_rad(randf_range(-24.0, 24.0)), fall)
	tw.finished.connect(func() -> void:
		if not is_instance_valid(unit):
			return
		if is_instance_valid(trail):
			trail.emitting = false
		if is_instance_valid(smoke):
			smoke.emitting = false
		var p := unit.global_position + Vector3.UP * 0.5
		_flash(parent, p, 5.0, Color(1.0, 0.58, 0.14))
		_shockwave(parent, Vector3(p.x, ground_y + 0.08, p.z), 10.0)
		_fireball(parent, p, kind)
		_spawn_debris(parent, p, kind)
		burn(unit, p, kind, 22.0)
		print("[DESTRUCTION] ", kind, " impacted at ", p))
	# The wreck keeps a little forward drift even with the tween.
	unit.rotation.y += 0.01


## ------------------------------- fire --------------------------------------
static func burn(unit: Node3D, pos: Vector3, kind: String, duration: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _active_burns >= MAX_ACTIVE_BURNS:
		return
	_active_burns += 1
	# Infantry: a small smoke wisp next to the body, not a bonfire that hides
	# the death pose.  Vehicles get the full burning wreck.
	if kind == "infantry":
		var wisp := Node3D.new()
		wisp.name = "BurnAnchor"
		wisp.position = Vector3(0.0, 0.10, 0.0)
		unit.add_child(wisp)
		var smoke := _emitter(wisp, "WreckSmoke", 5, 1.8, SMOKE_COLOR,
				_texture("smoke"), 0.2, 0.7, Vector3(0, 0.8, 0),
				0.12, 0.30, false)
		var timer := unit.get_tree().create_timer(2.2)
		timer.timeout.connect(func() -> void:
			_active_burns = maxi(0, _active_burns - 1)
			if is_instance_valid(smoke):
				smoke.emitting = false
			if is_instance_valid(wisp):
				wisp.queue_free())
		return
	var s := 1.0
	var anchor := Node3D.new()
	anchor.name = "BurnAnchor"
	var host: Node = unit.get_parent() if unit.get_parent() != null else unit
	if kind == "heli" or kind == "shahed":
		# A crashed airframe lies on its side; a local-space flame would be
		# buried inside the hull.  Anchor the plume above the wreck in world
		# space instead.
		host.add_child(anchor)
		anchor.global_position = unit.global_position + Vector3.UP * (
				2.0 if kind == "heli" else 0.7)
	else:
		unit.add_child(anchor)
		anchor.position = Vector3(0.0, 1.25, 0.0)
	var fire := _emitter(anchor, "WreckFire", int(56 * (0.55 if _low_quality() else 1.0)),
			0.62, Color(1.0, 0.86, 0.42, 1.0), _texture("flame"), 1.6, 4.0,
			Vector3(0, 3.0, 0), 0.22 * s, 0.62 * s, false)
	var smoke := _emitter(anchor, "WreckSmoke", int(22 * (0.55 if _low_quality() else 1.0)),
			2.4, SMOKE_COLOR, _texture("smoke"), 0.4, 1.4, Vector3(0, 1.8, 0),
			0.9 * s, 2.2 * s, false)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.48, 0.12)
	light.light_energy = 1.6 * s
	light.omni_range = 9.0 * s
	light.shadow_enabled = false
	light.position = Vector3(0, 1.0, 0)
	anchor.add_child(light)
	var flick := anchor.create_tween().set_loops(int(maxf(1.0, duration / 0.18)))
	flick.tween_property(light, "light_energy", 0.75 * s, 0.09)
	flick.tween_property(light, "light_energy", 1.55 * s, 0.09)
	var timer := unit.get_tree().create_timer(maxf(1.0, duration))
	timer.timeout.connect(func() -> void:
		_active_burns = maxi(0, _active_burns - 1)
		if is_instance_valid(fire):
			fire.emitting = false
		if is_instance_valid(smoke):
			smoke.emitting = false
		if is_instance_valid(anchor):
			anchor.queue_free())


## ----------------------------- particles -----------------------------------
static func _emitter(parent: Node3D, name: String, amount: int, lifetime: float,
		color: Color, tex: Texture2D, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float,
		additive: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = name
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.45
	p.fixed_fps = 30
	p.local_coords = false
	p.emitting = true
	p.visibility_aabb = AABB(Vector3(-24, -24, -24), Vector3(48, 48, 48))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.45
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 26.0
	mat.initial_velocity_min = speed_min
	mat.initial_velocity_max = speed_max
	mat.gravity = gravity
	mat.damping_min = 1.0
	mat.damping_max = 2.6
	mat.scale_min = size_min
	mat.scale_max = size_max
	mat.color = color
	mat.angle_min = 0.0
	mat.angle_max = TAU
	mat.angular_velocity_min = -120.0
	mat.angular_velocity_max = 120.0
	mat.color = color
	# Fade each particle out and shrink it near the end of its life instead of
	# popping it out at full size; this is what separates fire from balloons.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.45, 0.85))
	curve.add_point(Vector2(1.0, 0.10))
	var curve_tex := CurveTexture.new()
	curve_tex.curve = curve
	mat.scale_curve = curve_tex
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(color.r, color.g, color.b, color.a),
		Color(color.r * 0.8, color.g * 0.6, color.b * 0.45, color.a * 0.55),
		Color(color.r * 0.4, color.g * 0.35, color.b * 0.3, 0.0),
	])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = tex
	m.albedo_color = Color.WHITE
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		if tex == _flame_texture():
			m.emission_enabled = true
			m.emission = Color(1.0, 0.52, 0.16)
			m.emission_energy_multiplier = 1.6
	quad.material = m
	p.draw_pass_1 = quad
	parent.add_child(p)
	return p


static func _sparks(parent: Node, pos: Vector3, amount: int) -> void:
	_burst(parent, pos, mini(amount, 6), 0.28, Color(1.0, 0.66, 0.20, 1.0),
			_texture("spark"), 3.0, 7.0, Vector3(0, -9.0, 0), 0.012, 0.032, false)


## A compact fireball built from three independent billboard bursts: hot core,
## rolling smoke and metal sparks.  This replaces the imported Binbun VFX in
## the gallery so every class shares one readable style.
static func _fireball(parent: Node, pos: Vector3, kind: String) -> void:
	var s := 0.55 if kind == "infantry" else 1.0
	var q := 0.55 if _low_quality() else 1.0
	_burst(parent, pos, int(58 * s * q), 0.55, Color(1.0, 0.82, 0.42, 1.0),
			_texture("flame"), 2.6, 8.2, Vector3(0, 3.6, 0), 0.16, 0.52, false)
	_burst(parent, pos + Vector3.UP * 0.5, int(26 * s * q), 2.4,
			Color(0.26, 0.25, 0.23, 0.55), _texture("smoke"),
			0.5, 1.9, Vector3(0, 1.5, 0), 0.80, 1.9, false)
	_burst(parent, pos + Vector3.UP * 0.3, int(16 * s * q), 1.1,
			Color(0.55, 0.46, 0.33, 0.55), _texture("dust"),
			1.2, 3.6, Vector3(0, -1.5, 0), 0.35, 0.9, false)
	_sparks(parent, pos + Vector3.UP * 0.5, int(18 * s * q))


static func _dust(parent: Node, pos: Vector3, amount: int) -> void:
	_burst(parent, pos, amount, 1.0, DUST_COLOR, _texture("dust"),
			1.0, 3.4, Vector3(0, -1.6, 0), 0.35, 0.85, false)


static func _burst(parent: Node, pos: Vector3, amount: int, lifetime: float,
		color: Color, tex: Texture2D, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float,
		additive: bool) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.global_position = pos
	var p := _emitter(holder, "Burst", amount, lifetime, color, tex,
			speed_min, speed_max, gravity, size_min, size_max, additive)
	p.one_shot = true
	p.explosiveness = 1.0
	var timer := parent.get_tree().create_timer(lifetime + 0.6)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(holder):
			holder.queue_free())


static func _flash(parent: Node, pos: Vector3, radius: float, color: Color) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = radius * 3.2
	light.shadow_enabled = false
	parent.add_child(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.28)
	tw.tween_callback(light.queue_free)


static func _shockwave(parent: Node, pos: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.88, 0.66, 0.36, 0.12)
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ring)
	ring.global_position = pos
	ring.scale = Vector3.ONE * 0.4
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.10, radius), 0.55)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.55)
	tw.chain().tween_callback(ring.queue_free)


## ------------------------------- debris ------------------------------------
static func _spawn_debris(parent: Node, pos: Vector3, kind: String) -> void:
	var mats: Array[StandardMaterial3D] = []
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.24, 0.27, 0.17)
	olive.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.09, 0.09, 0.08)
	dark.roughness = 0.9
	var rust := StandardMaterial3D.new()
	rust.albedo_color = Color(0.40, 0.24, 0.14)
	rust.roughness = 0.9
	mats = [olive, dark, rust]
	var count := 9
	if kind == "tank":
		count = 15
	elif kind == "heli":
		count = 14
	elif kind == "shahed":
		count = 8
	elif kind == "infantry":
		count = 3
	if _low_quality():
		count = maxi(3, int(float(count) * 0.5))
	for i in range(count):
		var piece := RigidBody3D.new()
		piece.mass = 3.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var s := Vector3(randf_range(0.18, 0.55), randf_range(0.10, 0.28),
				randf_range(0.25, 0.85))
		bm.size = s
		mi.mesh = bm
		mi.material_override = mats[randi() % mats.size()]
		piece.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		piece.add_child(cs)
		parent.add_child(piece)
		piece.global_position = pos + Vector3(randf_range(-0.7, 0.7),
				randf_range(0.0, 0.9), randf_range(-0.7, 0.7))
		piece.apply_central_impulse(Vector3(randf_range(-6.0, 6.0),
				randf_range(5.0, 13.0), randf_range(-6.0, 6.0)) * (2.0 + float(i % 3)))
		piece.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9),
				randf_range(-9, 9))
		var timer := parent.get_tree().create_timer(9.0)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(piece):
				piece.queue_free())
