
extends SceneTree
func _init():
    var p = load('res://Assets/vehicles_anim/hecu_clean.glb') as PackedScene
    var inst = p.instantiate() as Node3D
    var aabb = AABB()
    var first = true
    for c in inst.find_children('*', 'MeshInstance3D', true, false):
        var mi = c as MeshInstance3D
        if mi.name != 'Icosphere':
            var b = mi.get_aabb()
            aabb = b if first else aabb.merge(b)
            first = false
    print('HECU AABB:', aabb)
    var anim: AnimationPlayer = inst.find_child('AnimationPlayer', true, false)
    if anim:
        print('Anims:', anim.get_animation_list())
    quit(0)
