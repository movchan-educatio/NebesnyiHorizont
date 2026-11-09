## Add a second, ground-level fly-through door to every fpv_city building.
## The first cut was at mid-height; a player on the street needs a low opening
## too.  The existing mid opening is preserved.
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\sceneries\city\fpv_city.glb"
OUT = SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
print("[CITYLOW] imported")

def bbox(obj):
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    return mn, mx

count = 0
for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH' or not obj.name.startswith("Bld"):
        continue
    mn, mx = bbox(obj)
    sx = mx[0] - mn[0]
    sy = mx[1] - mn[1]
    sz = mx[2] - mn[2]
    if sx < 2.0 or sy < 2.0 or sz < 5.0:
        continue
    h = min(7.0, max(5.0, sz * 0.25))
    z = mn[2] + h * 0.5 + 0.2
    if sx <= sy:
        center = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, z)
        size = (sx + 2.0, 6.0, h)
    else:
        center = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, z)
        size = (6.0, sy + 2.0, h)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    cut = bpy.context.object
    cut.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("low_door", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cut
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cut, do_unlink=True)
    if obj.data.materials:
        for poly in obj.data.polygons:
            poly.material_index = 0
    count += 1
    print("[CITYLOW]", obj.name, "z", round(z, 1), "h", round(h, 1))

bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[CITYLOW] cut", count, "doors, exported", OUT)
