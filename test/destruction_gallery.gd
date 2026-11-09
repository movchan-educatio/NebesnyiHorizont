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


func _ready() -> void:
	_out_dir = ProjectSettings.globalize_path("res://qa_shots/audit")
	_setup_environment()
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
	e.ambient_light_energy = 0.65
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.12
	e.fog_enabled = true
	e.fog_light_color = Color(0.55, 0.62, 0.70)
	e.fog_density = 0.0018
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 135.0, 0.0)
	fill.light_color = Color(0.55, 0.68, 0.86)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)

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


func _setup_title(title: String, subtitle: String) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	lbl.text = title + "\n" + subtitle
	lbl.position = Vector2(36, 26)
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
	for i in range(KINDS.size()):
		var kind: String = KINDS[i]
		var x := -24.0 + float(i % 4) * 16.0
		var z := -9.0 if i < 4 else 9.0
		var y := 14.0 if kind in AERIAL else 0.0
		_units[kind] = _spawn_unit(kind, Vector3(x, y, z))
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
	await get_tree().create_timer(0.35).timeout
	await _shot("01_idle")
	# Hit stage.
	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		DFx.hit(self, unit, unit.global_position + Vector3.UP * 1.2,
				str(kind), 1.0)
	await get_tree().create_timer(0.05).timeout
	await _shot("02_hit")
	await get_tree().create_timer(0.75).timeout
	# Destruction stage.
	for kind in _units.keys():
		var unit: Node3D = _units[kind]
		DFx.destroy(self, unit, str(kind), 0.0)
	await get_tree().create_timer(0.18).timeout
	await _shot("03_blast")
	await get_tree().create_timer(0.55).timeout
	await _shot("04_burning")
	await get_tree().create_timer(0.60).timeout
	await _shot("05_falling")
	await get_tree().create_timer(0.28).timeout
	await _shot("05b_impact")
	await get_tree().create_timer(1.10).timeout
	await _shot("06_wreck")
	await get_tree().create_timer(2.20).timeout
	await _shot("07_aftermath")
	await get_tree().create_timer(0.30).timeout
	get_tree().quit(0)


func _shot(stage: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var base := _solo if not _solo.is_empty() else "grid"
	var path := "%s/destruction_%s_%s.png" % [_out_dir, base, stage]
	var err := img.save_png(path)
	print("[DESTR] ", path, " err=", err)
