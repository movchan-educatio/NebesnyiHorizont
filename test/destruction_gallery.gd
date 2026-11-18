extends Node3D

## Standalone preview of the new hit / explosion / burning presentation.
## Run from the editor or:
##   godot --path . res://test/destruction_gallery.tscn
##   DESTR_CLASS=tank godot --path . res://test/destruction_gallery.tscn
##
## Captures staged screenshots into qa_shots/audit/.  Nothing here is part of
## the game; it only loads the real GLB models and the new DestructionFx.

const KINDS := ["tank", "bmp", "apc", "truck", "sam", "heli", "shahed", "infantry"]
const DFx := preload("res://combat/destruction_fx.gd")
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
var _blob_tex: Texture2D = null
var _phase_label: Label = null


func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("res://qa_shots/audit")
	_setup_environment()
	_setup_overlay()
	_setup_phase_hud()
	_solo = OS.get_environment("DESTR_CLASS")
	if _solo.is_empty():
		_build_grid()
		_setup_title("DESTRUCTION FX · ALL TARGET CLASSES",
				"HIT → EXPLOSION → BURNING WRECK")
	else:
		_build_solo(_solo)
		_setup_title("DESTRUCTION FX · " + _solo.to_upper(),
				"HIT → EXPLOSION → BURNING WRECK")
	await get_tree().process_frame
	await _sequence()


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.16, 0.32, 0.56)
	sky_mat.sky_horizon_color = Color(0.62, 0.70, 0.78)
	sky_mat.ground_bottom_color = Color(0.16, 0.14, 0.11)
	sky_mat.ground_horizon_color = Color(0.44, 0.40, 0.32)
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.12
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.82
	e.glow_bloom = 0.28
	e.fog_enabled = true
	e.fog_light_color = Color(0.46, 0.50, 0.54)
	e.fog_density = 0.0014
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.90, 0.76)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 135.0, 0.0)
	fill.light_color = Color(0.50, 0.66, 0.90)
	fill.light_energy = 0.24
	fill.shadow_enabled = false
	add_child(fill)

	# Warm back-rim separates the silhouettes from the sky at any zoom level.
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(16.0, 205.0, 0.0)
	rim.light_color = Color(1.0, 0.72, 0.44)
	rim.light_energy = 0.55
	rim.shadow_enabled = false
	add_child(rim)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 90.0)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.255, 0.235, 0.190)
	gm.roughness = 0.96
	ground.material_override = gm
	add_child(ground)

	# Concrete pads under each target and a painted centre line.
	for x in [-21.0, -7.0, 7.0, 21.0]:
		for z in [-8.0, 8.0]:
			var pad := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(11.0, 0.10, 11.0)
			pad.mesh = pm
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.34, 0.335, 0.31)
			pmat.roughness = 0.88
			pad.material_override = pmat
			pad.position = Vector3(x, 0.05, z)
			pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(pad)


## One full-screen quad: cinematic letterbox + vignette + fine film grain.
## No SCREEN_TEXTURE copy, so it is effectively free on the mobile renderer.
func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
render_mode unshaded;
uniform float bars : hint_range(0.0, 0.2) = 0.045;
uniform float vignette : hint_range(0.0, 1.0) = 0.62;
uniform float grain : hint_range(0.0, 0.3) = 0.07;
void fragment() {
	vec2 uv = UV;
	float n = fract(sin(dot(uv * vec2(1234.5, 5678.9) + vec2(TIME * 13.0, TIME * 7.0),
			vec2(12.9898, 78.233))) * 43758.5453);
	float edge = smoothstep(0.28, 0.82, length(uv - 0.5));
	float bar = 1.0 - step(bars, uv.y) * step(uv.y, 1.0 - bars);
	float a = clamp(edge * vignette + bar + (n - 0.5) * grain, 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = ShaderMaterial.new()
	(rect.material as ShaderMaterial).shader = s
	layer.add_child(rect)


func _setup_phase_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 21
	add_child(layer)
	_phase_label = Label.new()
	_phase_label.text = "STANDBY"
	_phase_label.position = Vector2(36, 920)
	_phase_label.add_theme_font_size_override("font_size", 22)
	_phase_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.30))
	_phase_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_phase_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_phase_label)


func _blob_texture() -> Texture2D:
	if _blob_tex != null:
		return _blob_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.55),
		Color(0.0, 0.0, 0.0, 0.34),
		Color(0.0, 0.0, 0.0, 0.10),
		Color(0.0, 0.0, 0.0, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_blob_tex = tex
	return tex


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
	_shake = maxf(0.0, _shake - delta * 1.7)
	var amount := _shake * _shake
	_cam.position = _cam_base + Vector3(
			randf_range(-0.30, 0.30), randf_range(-0.22, 0.22), randf_range(-0.18, 0.18)) * amount


func _set_phase(text: String) -> void:
	if _phase_label != null and is_instance_valid(_phase_label):
		_phase_label.text = text


func _wait_real(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _setup_title(title: String, subtitle: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	lbl.text = title + "\n" + subtitle
	lbl.position = Vector2(36, 78)
	lbl.add_theme_font_size_override("font_size", 30)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 8)
	layer.add_child(lbl)


func _build_grid() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 16.0, 40.0)
	cam.fov = 52.0
	cam.current = true
	add_child(cam)
	cam.look_at(Vector3(0.0, 3.4, 0.0), Vector3.UP)
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
		lbl.font_size = 56
		lbl.modulate = Color(1.0, 0.86, 0.42)
		lbl.outline_size = 14
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
	var dist := 13.0
	var cam_y := 5.0
	var look_y := 1.6
	if kind == "shahed":
		dist = 11.0
		cam_y = 6.0
		look_y = 2.0
	elif kind == "infantry":
		dist = 7.0
		cam_y = 3.0
		look_y = 1.1
	elif aerial:
		dist = 28.0
		cam_y = 14.0
		look_y = 9.0
	cam.position = Vector3(0.0, cam_y, dist)
	cam.fov = 48.0
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
	lbl.font_size = 72
	lbl.modulate = Color(1.0, 0.86, 0.42)
	lbl.outline_size = 16
	lbl.position = Vector3(0.0, 23.0 if aerial else 4.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(lbl)
	_labels[kind] = lbl


func _spawn_unit(kind: String, pos: Vector3) -> Node3D:
	# The game already owns a proper rigged infantry model; use it instead of
	# the low-poly rifleman placeholder.
	if kind == "infantry":
		var rig_script = load("res://combat/detailed_soldier_rig.gd")
		if rig_script != null:
			var rig: Node3D = rig_script.new()
			rig.name = "infantry"
			add_child(rig)
			rig.position = pos
			rig.setup_rig(0)
			var rbox := DroneCatalog.model_bounds(rig)
			if rbox.size.y > 0.01:
				rig.scale = Vector3.ONE * (1.85 / rbox.size.y)
			rbox = DroneCatalog.model_bounds(rig)
			rig.position.y += pos.y - rbox.position.y
			return rig
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


func _sequence() -> void:
	await _wait_real(0.35)
	_set_phase("01 · TARGET SET")
	await _shot("01_idle")

	# Hit stage - sparks, flash, jolt.
	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		DFx.hit(self, unit, unit.global_position + Vector3.UP * 1.2,
				str(kind), 1.0)
	_set_phase("02 · IMPACT")
	await _wait_real(0.05)
	await _shot("02_hit")
	await _wait_real(0.75)

	# Destruction stage. Slow the clock for the detonation beat only; the real
	# game never slows down, this is purely for the preview's cinematic read.
	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		DFx.destroy(self, unit, str(kind), 0.0)
	Engine.time_scale = 0.34
	_shake = 1.0
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
