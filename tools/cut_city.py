## Cut fly-through openings in every white city block.  Each cut goes through
## the building's shorter horizontal axis, so the player can enter one facade
## and leave the opposite one.  Also used by the City and Course maps.
##
## Usage:
##   blender --background --factory-startup --python cut_city.py
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\sceneries\city\fpv_city.glb"
OUT = SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
print("[CITYCUT] imported")

def bbox(obj):
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    return mn, mx

cut_count = 0
for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH' or not obj.name.startswith("Bld"):
        continue
    mn, mx = bbox(obj)
    sx = mx[0] - mn[0]
    sy = mx[1] - mn[1]
    sz = mx[2] - mn[2]
    if sx < 2.0 or sy < 2.0 or sz < 5.0:
        continue
    opening_h = min(9.0, max(5.5, sz * 0.35))
    z_center = mn[2] + max(opening_h * 0.55, sz * 0.42)
    z_center = min(z_center, mx[2] - opening_h * 0.5 - 0.5)
    if sx <= sy:
        center = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, z_center)
        size = (sx + 2.0, 6.0, opening_h)
    else:
        center = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, z_center)
        size = (6.0, sy + 2.0, opening_h)
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
    cut_count += 1
    print("[CITYCUT]", obj.name, "size", [round(v, 1) for v in size],
          "center", [round(v, 1) for v in center])

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[CITYCUT] cut", cut_count, "buildings, exported", OUT)
