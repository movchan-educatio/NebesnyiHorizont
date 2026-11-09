
extends Node
func _ready():
    var rig = DetailedSoldierRig.new()
    add_child(rig)
    rig.setup_rig(0)
    # Check head bone global forward vector
    var sk = rig.skeleton
    var head = rig._b_head
    var head_trans = rig.model.global_transform * sk.get_bone_global_pose(head)
    print('Head basis:', head_trans.basis)
    print('Muzzle pos relative to rig:', rig.muzzle.position if rig.muzzle else 'NO MUZZLE')
    print('Rifle pivot basis:', rig.rifle_pivot.basis if rig.rifle_pivot else 'NO RIFLE')
    get_tree().quit(0)
