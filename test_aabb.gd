
extends SceneTree
func _init():
    var p = load('res://Assets/vehicles_anim/alpha4_soldier_2_with_val.paranoia_mod_half_life_anim.glb') as PackedScene
    var inst = p.instantiate() as Node3D
    for c in inst.find_children('*', 'MeshInstance3D', true, false):
        var mi = c as MeshInstance3D
        print(mi.name, 'aabb:', mi.get_aabb())
    quit(0)
