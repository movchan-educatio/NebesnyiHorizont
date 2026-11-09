
extends Node
func _ready():
    var rig = DetailedSoldierRig.new()
    add_child(rig)
    rig.setup_rig(0)
    for c in rig.find_children('*', '', true, false):
        print(c.get_class(), ':', c.name)
    get_tree().quit(0)
