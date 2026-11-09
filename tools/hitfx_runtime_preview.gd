## QA: render the runtime hit FX (GLB + engine particles).
extends Node3D

const KINDS := ["infantry", "tank", "bmp", "apc", "truck", "sam", "heli", "shahed"]
const POS := [
	Vector3(-4.6, 1.0, 0.0), Vector3(-1.5, 1.0, 0.0),
	Vector3(1.5, 1.0, 0.0), Vector3(4.6, 1.0, 0.0),
	Vector3(-4.6, 1.0, 4.0), Vector3(-1.5, 1.0, 4.0),
	Vector3(1.5, 1.0, 4.0), Vector3(4.6, 1.0, 4.0),
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.78, 0.86)
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_bloom = 0.4
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.18, 0.17, 0.14)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 55.0
	cam.position = Vector3(0.0, 5.5, 13.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.2, 2.0), Vector3.UP)
	await get_tree().process_frame
	var kinds: Array = KINDS
	var positions: Array = POS
	if OS.get_environment("HIT_KIND") != "":
		kinds = [OS.get_environment("HIT_KIND")]
		positions = [Vector3(0.0, 1.0, 0.0)]
		cam.position = Vector3(0.0, 2.8, 7.0)
		cam.look_at(Vector3(0.0, 1.2, 0.0), Vector3.UP)
	var power := 1.0
	if OS.get_environment("HIT_POWER") != "":
		power = float(OS.get_environment("HIT_POWER"))
	for i in range(kinds.size()):
		HitFx.spawn(self, positions[i], kinds[i], 1.0, power)
		var lbl := Label3D.new()
		lbl.text = String(kinds[i]).to_upper()
		lbl.font_size = 48
		lbl.modulate = Color(1.0, 0.85, 0.4)
		lbl.position = positions[i] + Vector3(0.0, 3.0, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
	await get_tree().create_timer(0.22).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/hitfx_runtime.png"
	print("[HITFXRUNTIME] ", out, " err=", img.save_png(out))
	get_tree().quit(0)
