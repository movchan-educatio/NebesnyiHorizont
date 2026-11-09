
extends SceneTree
func _init():
    var p = load('res://Assets/combat/soldier_detailed_merged.glb') as PackedScene
    var inst = p.instantiate()
    var sk = inst.find_child('Skeleton3D', true, false) as Skeleton3D
    var thigh = sk.find_bone('Bip01 L Thigh_031')
    var calf = sk.find_bone('Bip01 L Calf_032')
    # Default rest pose
    var pos_rest = sk.get_bone_global_pose(calf).origin
    # Test pose = Quaternion(Vector3.RIGHT, 0.5)
    sk.set_bone_pose_rotation(thigh, Quaternion(Vector3.RIGHT, 0.5))
    sk.force_update_bone_child_transform(thigh)
    var pos_x = sk.get_bone_global_pose(calf).origin
    print('Rest calf:', pos_rest)
    print('Rot X calf:', pos_x, 'diff:', pos_x - pos_rest)
    
    sk.set_bone_pose_rotation(thigh, Quaternion(Vector3.UP, 0.5))
    sk.force_update_bone_child_transform(thigh)
    var pos_y = sk.get_bone_global_pose(calf).origin
    print('Rot Y calf:', pos_y, 'diff:', pos_y - pos_rest)

    sk.set_bone_pose_rotation(thigh, Quaternion(Vector3.BACK, 0.5))
    sk.force_update_bone_child_transform(thigh)
    var pos_z = sk.get_bone_global_pose(calf).origin
    print('Rot Z calf:', pos_z, 'diff:', pos_z - pos_rest)
    quit(0)
