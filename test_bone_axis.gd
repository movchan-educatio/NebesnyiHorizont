
extends SceneTree
func _init():
    var rig = DetailedSoldierRig.new()
    var ok = rig.setup_rig(0)
    if ok:
        var sk = rig.skeleton
        var b_thigh = rig._b_thigh_l
        var rest = sk.get_bone_rest(b_thigh)
        print('Thigh rest transform:', rest)
        print('Thigh rest basis:', rest.basis)
        var parent_idx = sk.get_bone_parent(b_thigh)
        print('Parent bone:', sk.get_bone_name(parent_idx) if parent_idx >= 0 else 'root')
    quit(0)
