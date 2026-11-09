
extends SceneTree
func _init():
    var rig = DetailedSoldierRig.new()
    rig.setup_rig(0)
    var sk = rig.skeleton
    var thigh = rig._b_thigh_l
    print('Bone name:', sk.get_bone_name(thigh))
    print('Bone pose rot:', sk.get_bone_pose_rotation(thigh))
    print('Bone rest rot:', sk.get_bone_rest(thigh).basis.get_rotation_quaternion())
    quit(0)
