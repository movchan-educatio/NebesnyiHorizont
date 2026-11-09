## QA: render every authored hit scene in a labelled gallery.
extends Node3D

const KINDS := ["infantry", "tank", "bmp", "apc", "truck", "sam", "heli", "shahed"]
const POS := [
	Vector3(-4.8, 1.2, 0.0), Vector3(-1.6, 1.2, 0.0),
	Vector3(1.6, 1.2, 0.0), Vector3(4.8, 1.2, 0.0),
	Vector3(-4.8, 1.2, 4.0), Vector3(-1.6, 1.2, 4.0),
	Vector3(1.6, 1.2, 4.0), Vector3(4.8, 1.2, 4.0),
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.10, 0.12)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.80, 0.88)
	e.ambient_light_energy = 0.9
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 30)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.19, 0.18, 0.15)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 55.0
	cam.position = Vector3(0.0, 6.0, 14.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.3, 2.0), Vector3.UP)

	for i in range(KINDS.size()):
		var kind: String = KINDS[i]
		var packed := load("res://Assets/combat/hit_%s.glb" % kind) as PackedScene
		if packed == null:
			continue
		var fx := packed.instantiate() as Node3D
		add_child(fx)
		fx.position = POS[i]
		fx.scale = Vector3.ONE * (1.0 if kind == "infantry" else 1.0)
		for apn in fx.find_children("*", "AnimationPlayer", true, false):
			var ap := apn as AnimationPlayer
			if ap.get_animation_list().has("Hit"):
				ap.play("Hit")
		var lbl := Label3D.new()
		lbl.text = kind.to_upper()
		lbl.font_size = 48
		lbl.modulate = Color(1.0, 0.85, 0.4)
		lbl.position = POS[i] + Vector3(0.0, 2.6, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)
	await get_tree().create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := "C:/Users/USER_UA/AppData/Local/Temp/opencode/hitfx_gallery.png"
	print("[HITFXGALLERY] ", out, " err=", img.save_png(out))
	get_tree().quit(0)
