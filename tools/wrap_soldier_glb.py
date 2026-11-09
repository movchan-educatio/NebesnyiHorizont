"""Wrap a Sketchfab GLB in a scale-only parent and re-export, preserving the
original skeleton and animation tracks.  Run with Blender -b --python."""
import bpy
import sys
import math

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []
src = argv[0]
dst = argv[1]
scale = float(argv[2]) if len(argv) > 2 else 0.0266

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# Create a wrapper and parent every root object to it, preserving transforms.
bpy.ops.object.empty_add(type='PLAIN_AXES', location=(0, 0, 0))
wrapper = bpy.context.object
wrapper.name = "SoldierRoot"
for obj in list(bpy.data.objects):
    if obj == wrapper:
        continue
    if obj.parent is None:
        obj.parent = wrapper
        obj.matrix_parent_inverse = wrapper.matrix_world.inverted()
wrapper.scale = (scale, scale, scale)

bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format='GLB',
    use_selection=False,
    export_animations=True,
    export_apply=False,
    export_yup=True,
)
print("[WRAPSOLDIER] exported", dst, "scale", scale)
