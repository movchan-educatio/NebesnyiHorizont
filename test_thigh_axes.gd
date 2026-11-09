
extends SceneTree
func _init():
    var rig = DetailedSoldierRig.new()
    rig.setup_rig(0)
    var sk = rig.skeleton
    var thigh = rig._b_thigh_l
    var calf = rig._b_calf_l
    # Test rotating around X, Y, Z by 45 degrees
    for axis_name in ['X', 'Y', 'Z']:
        var axis = Vector3.RIGHT if axis_name == 'X' else (Vector3.UP if axis_name == 'Y' else Vector3.BACK)
        var q = Quaternion(axis, deg_to_rad(45.0)) * rig._rest[thigh]
        sk.set_bone_pose_rotation(thigh, q)
        # get world position of calf relative to thigh
        var thigh_global = rig.model.global_transform * sk.get_bone_global_pose(thigh)
        var calf_global = rig.model.global_transform * sk.get_bone_global_pose(calf)
        var diff = calf_global.origin - thigh_global.origin
        print('Axis', axis_name, 'calf delta in Rig space:', diff)
    quit(0)
