
extends Node
func _ready():
    var env = WorldEnvironment.new()
    var env_res = Environment.new()
    env_res.background_mode = Environment.BG_COLOR
    env_res.background_color = Color(0.2, 0.25, 0.3)
    env.environment = env_res
    add_child(env)
    
    var light = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-45, 45, 0)
    add_child(light)

    var cam = Camera3D.new()
    cam.position = Vector3(0, 1.3, 3.2)
    cam.look_at(Vector3(0, 1.2, 0))
    cam.current = true
    add_child(cam)

    var rig = DetailedSoldierRig.new()
    add_child(rig)
    rig.setup_rig(0)
    rig.set_walk(1.5, 1.0)

    await get_tree().create_timer(0.5).timeout
    await RenderingServer.frame_post_draw
    var img = get_viewport().get_texture().get_image()
    img.save_png('res://qa_shots/soldier_walk_pose.png')
    print('SAVED soldier_walk_pose.png')
    get_tree().quit()
