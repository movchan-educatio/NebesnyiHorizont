
extends SceneTree
func _init():
    var path = 'res://Assets/vehicles_anim/alpha4_soldier_2_with_val.paranoia_mod_half_life_anim.glb'
    var p = load(path) as PackedScene
    var inst = p.instantiate()
    var anim: AnimationPlayer = null
    for c in inst.find_children('*', 'AnimationPlayer', true, false):
        anim = c as AnimationPlayer
        break
    if anim:
        print('FOUND ANIMATIONPLAYER:', anim.get_animation_list())
        for a in anim.get_animation_list():
            var anim_res = anim.get_animation(a)
            print('Anim', a, 'len:', anim_res.length, 'loop:', anim_res.loop_mode, 'tracks:', anim_res.get_track_count())
    else:
        print('NO ANIMATIONPLAYER')
    quit(0)
