
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

    var p = load('res://Assets/vehicles_anim/alpha4_soldier_2_with_val.paranoia_mod_half_life_anim.glb') as PackedScene
    var inst = p.instantiate() as Node3D
    add_child(inst)
    var s = 1.85 / 74.9
    inst.scale = Vector3.ONE * s
    # Center origin
    inst.position = Vector3(-7.6 * s, 0, 10.2 * s)

    var cam = Camera3D.new()
    add_child(cam)
    cam.position = Vector3(0.0, 1.0, 2.8)
    cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
    cam.current = true

    var anim: AnimationPlayer = inst.find_child('AnimationPlayer', true, false)
    if anim:
        var w = anim.get_animation('Walk')
        w.loop_mode = Animation.LOOP_LINEAR
        anim.play('Walk')
        anim.seek(0.5, true)

    await get_tree().create_timer(0.6).timeout
    await RenderingServer.frame_post_draw
    var img = get_viewport().get_texture().get_image()
    img.save_png('res://qa_shots/soldier_anim_walk.png')
    print('SAVED soldier_anim_walk.png')
    get_tree().quit(0)
