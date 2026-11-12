extends Node3D

## Visual check: smoke and fire particle billboards must render as soft puffs
## with alpha, not as opaque dark rectangles.  Saves a PNG for manual review.
## Run: SMOKE_SHOT=<path> godot --path . res://test/qa_smoke_visual.tscn
##      [--rendering-method mobile]
const ExplosionScript = preload("res://combat/explosion.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, 6.0, 18.0)
	cam.look_at(Vector3(0.0, 1.0, 0.0))
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-42.0, 28.0, 0.0)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.70, 0.90)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)
	# Ground for the decal to project onto.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.45, 0.40, 0.28)
	ground.material_override = gmat
	add_child(ground)
	# Same scorch decal the Steppe burnt-armour POI uses.
	var scorch := Decal.new()
	var tex := GradientTexture2D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.05, 0.04, 0.03, 0.9),
			Color(0.04, 0.035, 0.03, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	scorch.texture_albedo = tex
	scorch.size = Vector3(22.0, 7.0, 22.0)
	scorch.albedo_mix = 0.85
	scorch.cull_mask = 1
	scorch.position = Vector3(0.0, 3.0, 0.0)
	add_child(scorch)
	ExplosionScript.smoke_column(self, Vector3(-8.0, 4.0, -2.0), 6.0)
	ExplosionScript.fire_column(self, Vector3(8.0, 3.0, -2.0), 6.0)
	await get_tree().create_timer(1.6).timeout
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("SMOKE_SHOT")
	if path.is_empty():
		path = "user://smoke_test.png"
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("[SMOKE_VIS] saved=", path, " err=", err)
	get_tree().quit(0 if err == OK else 1)
