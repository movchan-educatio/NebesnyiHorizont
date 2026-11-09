
extends SceneTree
func _init():
    var packed = load('res://Assets/combat/soldier_detailed_merged.glb') as PackedScene
    var inst = packed.instantiate()
    var mi = inst.find_child('SoldierMerged', true, false) as MeshInstance3D
    var sk = inst.find_child('Skeleton3D', true, false) as Skeleton3D
    var skin = mi.skin
    print('Skin binds count:', skin.get_bind_count())
    for i in range(mini(15, skin.get_bind_count())):
        var bname = skin.get_bind_name(i)
        var sk_idx = sk.find_bone(bname)
        print('Bind', i, ':', bname, '-> sk_idx:', sk_idx)
    quit(0)
