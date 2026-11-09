## Cut large fly-through openings in the handcrafted buildings.  Each cut goes
## through the full depth, so every building gets an entrance and an exit, not
## a decorative window.  The same Boolean result is used by the Godot trimesh
## collider, so the hole is flyable.
##
## Usage:
##   blender --background --factory-startup --python cut_openings.py -- <asset.glb>
import bpy
import math
import sys

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []
if not argv:
    print("[CUT] need a GLB path")
    sys.exit(1)
path = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)
print("[CUT] imported", path)

def cut_box(obj_name, center, size):
    obj = bpy.data.objects.get(obj_name)
    if obj is None:
        print("[CUT] missing", obj_name)
        return
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    cut = bpy.context.object
    cut.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("fly_through", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cut
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cut, do_unlink=True)
    if obj.data.materials:
        for poly in obj.data.polygons:
            poly.material_index = 0
    print("[CUT] box", obj_name, center, size)

def cut_cyl_y(obj_name, center, radius, depth):
    obj = bpy.data.objects.get(obj_name)
    if obj is None:
        print("[CUT] missing", obj_name)
        return
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=radius,
                                        depth=depth, location=center,
                                        rotation=(math.pi / 2.0, 0.0, 0.0))
    cut = bpy.context.object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    mod = obj.modifiers.new("fly_through", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cut
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cut, do_unlink=True)
    if obj.data.materials:
        for poly in obj.data.polygons:
            poly.material_index = 0
    print("[CUT] cyl", obj_name, center, radius)

name = path.lower()
if "factory_complex" in name:
    # Main brick hall: 16 m wide, 12 m high tunnel through both long walls.
    cut_box("hall_main", (16.8, -12.3, 6.0), (16.0, 52.0, 12.0))
    # Brick chimney: a 3.6 m bore at mid height.
    cut_cyl_y("chim_band0", (62.0, -34.0, 18.0), 1.8, 16.0)
elif "village_house" in name:
    # The cottage row is 49 x 12 x 5 m; cut a 6 x 4 m passage through the row.
    cut_box("house1", (0.5, -0.5, 2.4), (6.0, 14.0, 4.0))
elif "farm_complex" in name:
    # Barn passage and a smaller opening in the farmhouse.
    cut_box("barn", (5.0, 18.0, 8.5), (10.0, 14.0, 8.0))
    cut_box("head", (-3.0, 6.0, 5.5), (8.0, 24.0, 6.0))

bpy.ops.export_scene.gltf(
    filepath=path,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[CUT] exported", path)
