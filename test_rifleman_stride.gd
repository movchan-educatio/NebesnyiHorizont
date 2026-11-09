
extends Node
func _ready():
    get_window().size = Vector2i(1280, 720)
    var env = WorldEnvironment.new()
    var env_res = Environment.new()
    env_res.background_mode = Environment.BG_COLOR
    env_res.background_color = Color(0.2, 0.25, 0.3)
    env.environment = env_res
    add_child(env)

    var light = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, 45, 0)
    add_child(light)

    var p = load('res://Assets/combat/rifleman.glb') as PackedScene
    var model = p.instantiate() as Node3D
    add_child(model)
    model.scale = Vector3.ONE * (2.2 / 1.8)

    # Setup leg pivots
    var hip_l = Node3D.new()
    hip_l.name = 'Hip_L'
    hip_l.position = Vector3(-0.14, 0.95, 0.0)
    model.add_child(hip_l)
    for part in ['Thigh_L', 'Thigh_pocket_L']:
        var n = model.find_child(part, true, false)
        if n:
            n.reparent(hip_l)
            n.position -= hip_l.position
    var knee_l = Node3D.new()
    knee_l.name = 'Knee_L'
    knee_l.position = Vector3(0.0, -0.45, 0.0)
    hip_l.add_child(knee_l)
    for part in ['Shin_L', 'Knee_L', 'Boot_L', 'Boot_toe_L']:
        var n = hip_l.find_child(part, true, false)
        if n:
            n.reparent(knee_l)
            n.position -= knee_l.position

    # Right leg
    var hip_r = Node3D.new()
    hip_r.name = 'Hip_R'
    hip_r.position = Vector3(0.14, 0.95, 0.0)
    model.add_child(hip_r)
    for part in ['Thigh_R', 'Thigh_pocket_R']:
        var n = model.find_child(part, true, false)
        if n:
            n.reparent(hip_r)
            n.position -= hip_r.position
    var knee_r = Node3D.new()
    knee_r.name = 'Knee_R'
    knee_r.position = Vector3(0.0, -0.45, 0.0)
    hip_r.add_child(knee_r)
    for part in ['Shin_R', 'Knee_R', 'Boot_R', 'Boot_toe_R']:
        var n = hip_r.find_child(part, true, false)
        if n:
            n.reparent(knee_r)
            n.position -= knee_r.position

    # Swing legs in a dramatic running stride
    hip_l.rotation.x = 0.85
    knee_l.rotation.x = -0.95
    hip_r.rotation.x = -0.75
    knee_r.rotation.x = 0.0

    var cam = Camera3D.new()
    add_child(cam)
    cam.position = Vector3(2.4, 1.2, 0.0)
    cam.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
    cam.current = true

    await get_tree().create_timer(0.5).timeout
    await RenderingServer.frame_post_draw
    var img = get_viewport().get_texture().get_image()
    img.save_png('res://qa_shots/rifleman_run_stride.png')
    print('SAVED rifleman_run_stride.png')
    get_tree().quit(0)
