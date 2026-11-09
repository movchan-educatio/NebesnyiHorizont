
extends SceneTree
func _init():
    var packed = load('res://Assets/combat/soldier_detailed_merged.glb') as PackedScene
    var inst = packed.instantiate()
    for c in inst.find_children('*', '', true, false):
        print(c.get_class(), ':', c.name)
        if c is AnimationPlayer:
            print('ANIMATIONS:', c.get_animation_list())
        if c is MeshInstance3D:
            print('MESH:', c.name, 'skin:', c.skin != null, 'skeleton path:', c.skeleton)
    quit(0)
