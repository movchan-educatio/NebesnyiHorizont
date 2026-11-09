
extends SceneTree
func _init():
    var rig = DetailedSoldierRig.new()
    rig.setup_rig(0)
    print('Rig global basis:', rig.global_transform.basis)
    print('Model basis:', rig.model.transform.basis)
    print('Model rot degrees:', rig.model.rotation_degrees)
    quit(0)
