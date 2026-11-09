"""List armatures/actions after importing a GLB."""
import bpy
import sys

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
src = argv[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
print("[INSPECT] actions:", [(a.name, a.frame_range[:]) for a in bpy.data.actions])
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        ad = obj.animation_data
        print("[INSPECT] armature", obj.name, "action", ad.action.name if ad and ad.action else None,
              "nla", [(t.name, [s.name for s in t.strips]) for t in ad.nla_tracks] if ad else None)
