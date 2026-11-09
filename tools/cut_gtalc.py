## Open two full-length fly-through corridors through the merged City map
## (gtalc_2001_full-map_3dmodel.glb).  Blender's Z is height here: the global
## bbox is X 1683 m, Y 1615 m (depth), Z 286 m (height).  Cut both corridors
## 15 m above the lowest point, with a 10 x 8 m cross-section.
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\sceneries\city\gtalc_2001_full-map_3dmodel.glb"
OUT = SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
print("[GCUT] imported")

mn = [1e9, 1e9, 1e9]
mx = [-1e9, -1e9, -1e9]
objs = []
for o in bpy.context.scene.objects:
    if o.type != 'MESH':
        continue
    objs.append(o)
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
print("[GCUT] objects", len(objs), "bbox", [round(v, 1) for v in mn],
      [round(v, 1) for v in mx])
cx = (mn[0] + mx[0]) * 0.5
cy = (mn[1] + mx[1]) * 0.5
z_cut = 15.0
h = 8.0
print("[GCUT] corridors at z=", round(z_cut, 1), "center", round(cx, 1),
      round(cy, 1))

bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, z_cut))
a = bpy.context.object
a.scale = (mx[0] - mn[0] + 6.0, 10.0, h)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=(cx, cy, z_cut))
b = bpy.context.object
b.scale = (10.0, mx[1] - mn[1] + 6.0, h)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
bpy.ops.object.select_all(action='DESELECT')
a.select_set(True)
b.select_set(True)
bpy.context.view_layer.objects.active = a
bpy.ops.object.join()
cuts = bpy.context.active_object
cuts.name = "__corridor_cuts"

for i, o in enumerate(objs):
    mod = o.modifiers.new("fly_through", 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.solver = 'EXACT'
    mod.object = cuts
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=mod.name)
    if (i + 1) % 40 == 0:
        print("[GCUT] cut", i + 1, "/", len(objs))

bpy.data.objects.remove(cuts, do_unlink=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[GCUT] exported", OUT)

