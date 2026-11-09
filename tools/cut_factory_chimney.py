## Cut one large through-tunnel (two opposite openings) in the handcrafted
## factory chimney.  The 7.4 x 7.4 x 21 m concrete stack had no openings at all.
import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

target = None
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH' and obj.name.lower().startswith("chim"):
        target = obj
        break
if target is None:
    raise SystemExit("[FACTORYCUT] chimney not found")

mn = [1e9, 1e9, 1e9]
mx = [-1e9, -1e9, -1e9]
for v in target.data.vertices:
    w = target.matrix_world @ v.co
    for i in range(3):
        mn[i] = min(mn[i], w[i])
        mx[i] = max(mx[i], w[i])
center = [(mn[i] + mx[i]) * 0.5 for i in range(3)]
size = [mx[i] - mn[i] for i in range(3)]
print("[FACTORYCUT]", target.name, "center", center, "size", size)

# Through the X axis: 4.8 m wide (Y), 8 m high (Z), centered mid-height.
cut_center = (center[0], center[1], mn[2] + size[2] * 0.58)
cut_size = (size[0] + 4.0, 4.8, 8.0)
bpy.ops.mesh.primitive_cube_add(size=1.0, location=cut_center)
cut = bpy.context.object
cut.scale = cut_size
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
mod = target.modifiers.new("chimney_tunnel", 'BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.solver = 'EXACT'
mod.object = cut
bpy.context.view_layer.objects.active = target
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cut, do_unlink=True)
if target.data.materials:
    for poly in target.data.polygons:
        poly.material_index = 0

bpy.ops.export_scene.gltf(
    filepath=SRC,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[FACTORYCUT] cut", cut_size, "at", cut_center)
