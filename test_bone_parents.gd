
extends SceneTree
func _init():
    var p = load('res://Assets/combat/soldier_detailed_merged.glb') as PackedScene
    var inst = p.instantiate()
    var sk = inst.find_child('Skeleton3D', true, false) as Skeleton3D
    for i in range(sk.get_bone_count()):
        var p_idx = sk.get_bone_parent(i)
        var p_name = sk.get_bone_name(p_idx) if p_idx >= 0 else 'ROOT'
        if 'Thigh' in sk.get_bone_name(i) or 'Calf' in sk.get_bone_name(i) or 'Pelvis' in sk.get_bone_name(i):
            print(i, ':', sk.get_bone_name(i), 'parent:', p_idx, '(', p_name, ')')
    quit(0)
