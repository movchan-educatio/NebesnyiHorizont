extends Node3D

## Standalone cinematic preview of the hit / explosion / burning presentation.
## Run from the editor or:
##   godot --path . res://test/destruction_gallery.tscn
##   DESTR_CLASS=tank godot --path . res://test/destruction_gallery.tscn
##
## Captures staged screenshots into qa_shots/audit/. Nothing here is part of
## the game; it only loads the real GLB models and the live DestructionFx.
##
## Visual direction: baked golden-hour sky, warm key / cool fill / hot rim,
## textured mud, floating dust and a single full-screen finishing grade. Every
## expensive look is baked or cached once - the runtime cost stays at a handful
## of draw calls plus one screen-texture fetch for the grade.

const KINDS := ["tank", "bmp", "apc", "truck", "sam", "heli", "shahed", "infantry"]
const DFx := preload("res://combat/destruction_fx.gd")
const CinematicOverlay := preload("res://scripts/util/cinematic_overlay.gd")
const MODELS := {
	"tank": "res://Assets/vehicles/low_poly_t-72_tank_-_game_ready.glb",
	"bmp": "res://Assets/vehicles/low-poly_bmp-2m.glb",
	"apc": "res://Assets/vehicles/btr-90_ussr.glb",
	"truck": "res://Assets/vehicles/gaz_tigr_low_poly.glb",
	"sam": "res://Assets/vehicles/btr-90_ussr.glb",
	"heli": "res://Assets/vehicles/apache_hecu_half-life.glb",
	"shahed": "res://Assets/Drones/shahed-136.glb",
	"infantry": "res://Assets/combat/rifleman.glb",
}
const SIZES := {
	"tank": 9.2, "bmp": 7.2, "apc": 8.2, "truck": 5.6, "sam": 8.2,
	"heli": 16.5, "shahed": 3.8, "infantry": 1.85,
}
const YAWS := {
	"tank": 0.0, "bmp": PI, "apc": PI * 0.5, "truck": PI, "sam": PI * 0.5,
	"heli": PI, "shahed": PI, "infantry": 0.0,
}
const AERIAL := ["heli", "shahed"]

var _units := {}
var _labels := {}
var _solo := ""
var _out_dir := ""
var _t := 0.0
var _cam: Camera3D = null
var _cam_base := Vector3.ZERO
var _shake := 0.0
var _push := 0.0
var _roll := 0.0
var _blob_tex: Texture2D = null
var _dot_tex: Texture2D = null
var _phase_label: Label = null
var _phase_index: Label = null

static var _ground_tex: ImageTexture = null


func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("res://qa_shots/audit")
	_setup_environment()
	_setup_overlay()
	_setup_phase_hud()
	_solo = OS.get_environment("DESTR_CLASS")
	if _solo.is_empty():
		_build_grid()
		_setup_title("DESTRUCTION FX", "ALL TARGET CLASSES  /  HIT · DETONATION · WRECK")
	else:
		_build_solo(_solo)
		_setup_title("DESTRUCTION FX", _solo.to_upper() + "  /  HIT · DETONATION · WRECK")
	await get_tree().process_frame
	await _sequence()


# ---------------------------------------------------------------------------
# World: baked sky + cinematic light rig + textured ground + atmosphere
# ---------------------------------------------------------------------------
func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()

	# The same baked golden-hour panorama the game uses. One cubemap sample,
	# zero per-frame cost, and instantly ten times richer than a flat gradient.
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	var tex := load("res://Assets/textures/sky_mountains_golden.png") as Texture2D
	if tex != null:
		mat.panorama = tex
		mat.filter = true
		sky.sky_material = mat
	else:
		var fallback := ProceduralSkyMaterial.new()
		fallback.sky_top_color = Color(0.10, 0.24, 0.48)
		fallback.sky_horizon_color = Color(0.92, 0.72, 0.48)
		fallback.ground_bottom_color = Color(0.09, 0.08, 0.07)
		sky.sky_material = fallback
	# Incremental radiance baking avoids a multi-second stall on the first
	# frame when the 4K panorama is used with sky ambient / reflections.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.sky = sky
	# Put the baked sun glow behind the targets for a natural back-rim.
	e.sky_rotation.y = deg_to_rad(-62.0)
	e.background_energy_multiplier = 0.55

	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.75
	e.ambient_light_energy = 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.06
	e.tonemap_white = 1.0
	e.glow_enabled = true
	e.glow_normalized = true
	e.glow_intensity = 0.72
	e.glow_bloom = 0.20
	e.glow_hdr_threshold = 1.02
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.10
	e.adjustment_brightness = 1.01

	e.fog_enabled = true
	e.fog_light_color = Color(0.52, 0.48, 0.40)
	e.fog_light_energy = 0.55
	e.fog_density = 0.0018
	e.fog_aerial_perspective = 0.60
	e.fog_height = 26.0
	e.fog_height_density = 0.0042
	e.fog_sky_affect = 0.42
	e.sdfgi_enabled = false
	e.ssr_enabled = false
	env.environment = e
	add_child(env)

	# Warm late-afternoon key: the single most important cinematic cue.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-36.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.82, 0.62)
	sun.light_energy = 1.82
	sun.light_indirect_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.24
	sun.shadow_blur = 1.1
	add_child(sun)

	# Cool sky fill keeps the shadow side readable without flattening it.
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	fill.rotation_degrees = Vector3(-18.0, 138.0, 0.0)
	fill.light_color = Color(0.46, 0.64, 0.92)
	fill.light_energy = 0.38
	fill.shadow_enabled = false
	add_child(fill)

	# Hot back-rim separates every silhouette from the bright sky.
	var rim := DirectionalLight3D.new()
	rim.name = "BackRim"
	rim.rotation_degrees = Vector3(14.0, 208.0, 0.0)
	rim.light_color = Color(1.0, 0.66, 0.34)
	rim.light_energy = 0.70
	rim.shadow_enabled = false
	add_child(rim)

	# A warm ground-bounce card lifts the undersides of the hulls.
	var bounce := DirectionalLight3D.new()
	bounce.name = "GroundBounce"
	bounce.rotation_degrees = Vector3(72.0, 20.0, 0.0)
	bounce.light_color = Color(0.86, 0.58, 0.34)
	bounce.light_energy = 0.18
	bounce.shadow_enabled = false
	add_child(bounce)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(1600.0, 1600.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.225, 0.222, 0.215)
	gm.albedo_texture = _ground_texture()
	gm.set("uv1_scale", Vector3(64.0, 64.0, 1.0))
	gm.roughness = 0.94
	gm.metallic = 0.0
	ground.material_override = gm
	add_child(ground)

	# Concrete pads, a painted centre line and subtle panel seams.
	for x in [-21.0, -7.0, 7.0, 21.0]:
		for z in [-8.0, 8.0]:
			var pad := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(11.0, 0.10, 11.0)
			pad.mesh = pm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.235, 0.225, 0.205)
			pmat.roughness = 0.90
			pad.material_override = pmat
			pad.position = Vector3(x, 0.05, z)
			pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(pad)

	_spawn_dust()


func _ground_texture() -> ImageTexture:
	if _ground_tex != null:
		return _ground_tex
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 918273
	# Multi-octave value noise, smoothly interpolated by the GPU bilinear filter.
	var base: Array = []
	for oct in range(3):
		var grid: Array = []
		var n := 8 << oct
		for gy in range(n):
			var row: Array = []
			for gx in range(n):
				row.append(rng.randf())
			grid.append(row)
		base.append({"n": n, "grid": grid})
	for y in range(size):
		for x in range(size):
			var value := 0.0
			var amp := 0.58
			var total := 0.0
			for oct in range(3):
				var layer: Dictionary = base[oct]
				var n: int = layer["n"]
				var g: Array = layer["grid"]
				var fx := float(x) / float(size) * float(n)
				var fy := float(y) / float(size) * float(n)
				var ix := int(fx) % n
				var iy := int(fy) % n
				var jx := (ix + 1) % n
				var jy := (iy + 1) % n
				var sx: float = fx - floorf(fx)
				var sy: float = fy - floorf(fy)
				sx = sx * sx * (3.0 - 2.0 * sx)
				sy = sy * sy * (3.0 - 2.0 * sy)
				var a: float = g[iy][ix]
				var b: float = g[iy][jx]
				var c: float = g[jy][ix]
				var d: float = g[jy][jx]
				var v := lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sy)
				value += v * amp
				total += amp
				amp *= 0.5
			value /= maxf(total, 0.001)
			var shade := 0.68 + value * 0.52
			var grit := rng.randf_range(-0.035, 0.035)
			img.set_pixel(x, y, Color(
					clampf(shade + grit, 0.0, 1.0),
					clampf(shade * 0.94 + grit, 0.0, 1.0),
					clampf(shade * 0.82 + grit, 0.0, 1.0), 1.0))
	_ground_tex = ImageTexture.create_from_image(img)
	return _ground_tex


func _soft_dot() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	grad.add_point(0.35, Color(1, 1, 1, 0.65))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	_dot_tex = tex
	return tex


## Floating dust caught in the key light: the cheapest way to make air feel
## volumetric. One GPUParticles emitter, one cached 32px texture.
func _spawn_dust() -> void:
	var p := GPUParticles3D.new()
	p.name = "AirDust"
	p.amount = 90
	p.lifetime = 9.0
	p.preprocess = 4.0
	p.visibility_aabb = AABB(Vector3(-60, -2, -45), Vector3(120, 34, 90))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38.0, 11.0, 26.0)
	pm.direction = Vector3(0.25, 0.06, 0.0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.04
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0.0, -0.008, 0.0)
	pm.scale_min = 0.010
	pm.scale_max = 0.040
	pm.color = Color(1.0, 0.86, 0.70, 0.32)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_dot()
	qm.albedo_color = Color(1.0, 0.88, 0.72, 0.28)
	qm.disable_receive_shadows = true
	quad.material = qm
	p.draw_pass_1 = quad
	add_child(p)
	p.emitting = true


# ---------------------------------------------------------------------------
# Full-screen finishing grade + title cards
# ---------------------------------------------------------------------------
func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "CinematicGrade"
	layer.layer = 20
	add_child(layer)
	CinematicOverlay.attach_canvas(layer,
			0.42,   # vignette
			0.016,  # grain
			0.0,    # scanline
			0.052,  # letterbox
			0.16,   # warm light leak
			1.08,   # contrast
			1.05,   # saturation
			0.032)  # halation


func _setup_phase_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_phase_label = Label.new()
	_phase_label.text = "STANDBY"
	_phase_label.position = Vector2(54, 906)
	_phase_label.add_theme_font_size_override("font_size", 23)
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.42))
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	_phase_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_phase_label)

	_phase_index = Label.new()
	_phase_index.text = "REC ●"
	_phase_index.position = Vector2(54, 62)
	_phase_index.add_theme_font_size_override("font_size", 18)
	_phase_index.add_theme_color_override("font_color", Color(1.0, 0.42, 0.30, 0.9))
	_phase_index.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_phase_index.add_theme_constant_override("outline_size", 5)
	layer.add_child(_phase_index)

	# Thin warm accent rules framing the frame like a viewfinder.
	for y in [56.0, 946.0]:
		var rule := ColorRect.new()
		rule.position = Vector2(54, y)
		rule.size = Vector2(1812, 2)
		rule.color = Color(1.0, 0.72, 0.36, 0.20)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rule)


func _setup_title(title: String, subtitle: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	var accent := ColorRect.new()
	accent.position = Vector2(54, 108)
	accent.size = Vector2(4, 62)
	accent.color = Color(1.0, 0.70, 0.30, 0.95)
	layer.add_child(accent)

	var lbl := Label.new()
	lbl.text = title
	lbl.position = Vector2(74, 104)
	lbl.add_theme_font_size_override("font_size", 38)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.84))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	lbl.add_theme_constant_override("outline_size", 9)
	layer.add_child(lbl)

	var sub := Label.new()
	sub.text = subtitle
	sub.position = Vector2(76, 150)
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.86, 0.78, 0.66, 0.92))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	sub.add_theme_constant_override("outline_size", 6)
	layer.add_child(sub)


func _blob_texture() -> Texture2D:
	if _blob_tex != null:
		return _blob_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.62),
		Color(0.0, 0.0, 0.0, 0.38),
		Color(0.0, 0.0, 0.0, 0.12),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_blob_tex = tex
	return _blob_tex


## Cheap contact shadow / scorch disc. One quad per target, no shadow map work.
func _ground_disc(pos: Vector3, radius: float, strength: float) -> void:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_texture = _blob_texture()
	mat.albedo_color = Color(1.0, 1.0, 1.0, strength)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	mesh.position = Vector3(pos.x, 0.115, pos.z)
	mesh.rotation.x = -PI * 0.5


func _process(delta: float) -> void:
	if _cam == null:
		return
	_t += delta
	_shake = maxf(0.0, _shake - delta * 1.7)
	_push = lerpf(_push, 0.0, 1.0 - exp(-2.2 * delta))
	_roll = lerpf(_roll, 0.0, 1.0 - exp(-3.0 * delta))
	var amount := _shake * _shake
	var base := _cam_base + Vector3(0.0, 0.0, -_push)
	_cam.position = base + Vector3(
			randf_range(-0.34, 0.34), randf_range(-0.24, 0.24), randf_range(-0.20, 0.20)) * amount
	_cam.rotation.z = _roll + randf_range(-0.012, 0.012) * amount


func _set_phase(text: String) -> void:
	if _phase_label != null and is_instance_valid(_phase_label):
		_phase_label.text = text


func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _build_grid() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 18.0, 46.0)
	cam.fov = 52.0
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(0.0, 4.0, 0.0), Vector3.UP)
	_cam = cam
	_cam_base = cam.position
	for i in range(KINDS.size()):
		var kind: String = KINDS[i]
		var x := -24.0 + float(i % 4) * 16.0
		var z := -9.0 if i < 4 else 9.0
		var y := 14.0 if kind in AERIAL else 0.0
		_units[kind] = _spawn_unit(kind, Vector3(x, y, z))
		if not (kind in AERIAL):
			_ground_disc(Vector3(x, 0.0, z), float(SIZES.get(kind, 6.0)) * 0.62, 0.85)
		var lbl := Label3D.new()
		lbl.text = kind.to_upper()
		lbl.font_size = 52
		lbl.modulate = Color(1.0, 0.84, 0.46)
		lbl.outline_size = 12
		lbl.position = Vector3(x, (21.0 if kind in AERIAL else 4.4), z)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
		_labels[kind] = lbl


func _build_solo(kind: String) -> void:
	if not MODELS.has(kind):
		kind = "tank"
	_solo = kind
	var cam := Camera3D.new()
	var aerial := kind in AERIAL
	var dist := 12.4
	var cam_y := 4.8
	var look_y := 1.7
	if kind == "shahed":
		dist = 10.5
		cam_y = 5.6
		look_y = 2.0
	elif kind == "infantry":
		dist = 6.8
		cam_y = 2.8
		look_y = 1.1
	elif aerial:
		dist = 26.0
		cam_y = 13.0
		look_y = 9.0
	cam.position = Vector3(0.0, cam_y, dist)
	cam.fov = 46.0
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(0.0, look_y, 0.0), Vector3.UP)
	_cam = cam
	_cam_base = cam.position
	if not aerial:
		_ground_disc(Vector3.ZERO, float(SIZES.get(kind, 6.0)) * 0.62, 0.85)
	_units[kind] = _spawn_unit(kind, Vector3(0.0, 14.0 if aerial else 0.0, 0.0))
	var lbl := Label3D.new()
	lbl.text = kind.to_upper()
	lbl.font_size = 70
	lbl.modulate = Color(1.0, 0.84, 0.46)
	lbl.outline_size = 14
	lbl.position = Vector3(0.0, 23.0 if aerial else 4.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)
	_labels[kind] = lbl


func _spawn_unit(kind: String, pos: Vector3) -> Node3D:
	# Infantry: a purpose-built low-poly figure that is ALREADY lying flat.
	# Both the detailed rig and the rifleman GLB have origins that send the body
	# underground when a generic wrapper is rotated; this proxy has no such
	# ambiguity and reads clearly as a fallen, burning soldier in the preview.
	if kind == "infantry":
		return _spawn_fallen_soldier(pos)

	var wrapper := Node3D.new()
	wrapper.name = kind
	add_child(wrapper)
	wrapper.position = pos
	var path: String = MODELS.get(kind, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return wrapper
	var packed := load(path) as PackedScene
	if packed == null:
		return wrapper
	var model := packed.instantiate() as Node3D
	if model == null:
		return wrapper
	wrapper.add_child(model)
	model.rotation = Vector3(0.0, float(YAWS.get(kind, 0.0)), 0.0)
	var box := DroneCatalog.model_bounds(model)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	if longest > 0.001:
		model.scale = Vector3.ONE * (float(SIZES.get(kind, 6.0)) / longest)
	box = DroneCatalog.model_bounds(model)
	var center := box.get_center()
	model.global_position += Vector3(pos.x - center.x, pos.y - box.position.y,
			pos.z - center.z)
	return wrapper


## Procedural fallen soldier for the preview. Everything is authored in world
## space at ground level, so neither the collapse tween nor the burn anchor can
## push any part of the body under the terrain.
func _spawn_fallen_soldier(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "infantry"
	add_child(root)
	root.position = pos
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.24, 0.27, 0.17)
	olive.roughness = 0.95
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.11, 0.09)
	dark.roughness = 0.9

	# Torso lying along Z, slightly rolled onto one side.
	var torso := MeshInstance3D.new()
	var torso_box := BoxMesh.new()
	torso_box.size = Vector3(0.62, 0.26, 1.05)
	torso.mesh = torso_box
	torso.material_override = olive
	torso.position = Vector3(0.0, 0.20, 0.0)
	torso.rotation.z = deg_to_rad(-12.0)
	root.add_child(torso)

	var helmet := MeshInstance3D.new()
	var helm_mesh := SphereMesh.new()
	helm_mesh.radius = 0.19
	helm_mesh.height = 0.26
	helm_mesh.radial_segments = 12
	helm_mesh.rings = 8
	helmet.mesh = helm_mesh
	helmet.material_override = dark
	helmet.position = Vector3(0.06, 0.24, 0.66)
	root.add_child(helmet)

	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.20, 0.18, 0.78)
		leg.mesh = leg_box
		leg.material_override = olive
		leg.position = Vector3(side * 0.18, 0.14, -0.78)
		leg.rotation.y = deg_to_rad(side * 8.0)
		root.add_child(leg)
		var arm := MeshInstance3D.new()
		var arm_box := BoxMesh.new()
		arm_box.size = Vector3(0.16, 0.14, 0.62)
		arm.mesh = arm_box
		arm.material_override = olive
		arm.position = Vector3(side * 0.42, 0.13, 0.12)
		arm.rotation.y = deg_to_rad(side * 22.0)
		root.add_child(arm)

	var rifle := MeshInstance3D.new()
	var rifle_box := BoxMesh.new()
	rifle_box.size = Vector3(0.06, 0.06, 0.86)
	rifle.mesh = rifle_box
	rifle.material_override = dark
	rifle.position = Vector3(0.48, 0.12, -0.30)
	rifle.rotation.y = deg_to_rad(14.0)
	root.add_child(rifle)
	return root


func _sequence() -> void:
	await _wait_real(0.35)
	_set_phase("01 · TARGET SET")
	await _shot("01_idle")

	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		DFx.hit(self, unit, unit.global_position + Vector3.UP * 1.2, str(kind), 1.0)
	_set_phase("02 · IMPACT")
	await _wait_real(0.05)
	await _shot("02_hit")
	await _wait_real(0.75)

	# The detonation beat: slow motion, camera push-in and a subtle roll.
	# Engine.time_scale is restored before the next frame; the real game never
	# slows down.
	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		if kind == "infantry":
			# Already authored flat: skip the generic collapse tween so the
			# preview figure cannot rotate through the ground.
			DFx.destroy(self, unit, str(kind), 0.0, {"move_unit": false})
		else:
			DFx.destroy(self, unit, str(kind), 0.0)
	Engine.time_scale = 0.34
	_shake = 1.0
	_push = 0.9
	_roll = -0.012
	_set_phase("03 · DETONATION · 0.34×")
	await _wait_real(0.62)
	Engine.time_scale = 1.0
	await _shot("03_blast")

	_set_phase("04 · FIRE & SMOKE")
	await _wait_real(0.55)
	await _shot("04_burning")
	await _wait_real(0.60)
	_set_phase("05 · AIRFRAME DOWN")
	await _shot("05_falling")
	_shake = 0.55
	_roll = 0.018
	await _wait_real(0.28)
	await _shot("05b_impact")

	for kind in _units.keys():
		if kind in AERIAL:
			continue
		var p: Vector3 = (_units[kind] as Node3D).global_position
		_ground_disc(Vector3(p.x, 0.0, p.z), float(SIZES.get(kind, 6.0)) * 0.78, 0.55)

	_set_phase("06 · WRECK BURNING")
	await _wait_real(1.10)
	await _shot("06_wreck")
	_set_phase("07 · AFTERMATH")
	await _wait_real(2.20)
	await _shot("07_aftermath")
	await _wait_real(0.30)
	Engine.time_scale = 1.0
	get_tree().quit(0)


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := _solo if not _solo.is_empty() else "grid"
	var path := "%s/destruction_%s_%s.png" % [_out_dir, base, stage]
	var err := img.save_png(path)
	print("[DESTR] ", path, " err=", err)
