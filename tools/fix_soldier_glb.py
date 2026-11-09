"""Normalise a Sketchfab FBX-style GLB (x100 root scale + -90 deg rotation)
and re-export it as a clean glTF for Godot.  Run with Blender -b --python."""
import bpy
import sys
import os

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []
src = argv[0]
dst = argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# Rest pose is safer than baking a random animation frame.
for obj in bpy.data.objects:
    if obj.type == 'ARMATURE':
        if obj.animation_data:
            obj.animation_data.action = None
        obj.data.pose_position = 'REST'

bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active = next((o for o in bpy.context.selected_objects if o.type == 'ARMATURE'), None)

# Apply the x100 scale and axis rotation into the object data so the exported
# GLB has unit scales and a clean skeleton for Godot's importer.
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

# Add a normalising parent at a human scale.  The source is authored in
# centimetres (75 units tall); 0.0266 puts it at ~2 m.
for obj in bpy.data.objects:
    if obj.parent is None:
        obj.scale = (0.0266, 0.0266, 0.0266)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format='GLB',
    use_selection=False,
    export_animations=True,
    export_apply=True,
    export_yup=True,
)
print("[FIXSOLDIER] exported", dst)
