
extends SceneTree
func _init():
    var p = load('res://Assets/combat/rifleman.glb') as PackedScene
    var inst = p.instantiate() as Node3D
    for c in inst.find_children('*', 'MeshInstance3D', true, false):
        var mi = c as MeshInstance3D
        print(mi.name, 'aabb:', mi.get_aabb())
    for c in inst.find_children('*', 'AnimationPlayer', true, false):
        var ap = c as AnimationPlayer
        print('Rifleman anims:', ap.get_animation_list())
    quit(0)
