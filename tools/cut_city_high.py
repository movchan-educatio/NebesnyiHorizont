## Add a third, high-altitude fly-through opening to the tall city towers.
## The first pass cut a ground door and a mid-height opening; the 30-45 m
## towers still had no way in/out at rooftop altitude, which is where an FPV
## pilot naturally approaches.  Cut one more window through the short axis at
## roughly two thirds of the building height.
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\sceneries\city\fpv_city.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
print("[CITYHIGH] imported")

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
    if sx < 3.0 or sy < 3.0 or sz < 30.0:
        continue
    h = min(9.0, max(6.0, sz * 0.22))
    z = mn[2] + sz * 0.68
    z = min(z, mx[2] - h * 0.5 - 0.8)
    center = ((mn[0] + mx[0]) * 0.5, (mn[1] + mx[1]) * 0.5, z)
    if sx <= sy:
        size = (sx + 2.0, 8.0, h)
    else:
        size = (8.0, sy + 2.0, h)
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    cut = bpy.context.object
    cut.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = obj.modifiers.new("high_fly_through", 'BOOLEAN')
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
    print("[CITYHIGH]", obj.name, "h", round(sz, 1), "z", round(z, 1),
          "opening", round(h, 1))

bpy.ops.export_scene.gltf(
    filepath=SRC,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[CITYHIGH] cut", count, "high openings")
