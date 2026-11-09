import bpy
import mathutils

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

obj = bpy.data.objects.get("factory_facade_detail")
if obj is None:
    raise SystemExit("[POLECUT] factory_facade_detail missing")

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
before = set(bpy.context.scene.objects)
bpy.ops.mesh.separate(type='LOOSE')
parts = [o for o in bpy.context.scene.objects if o not in before and o.type == 'MESH']
removed = 0
keep = [obj]
for part in parts:
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in part.data.vertices:
        w = part.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    sx = mx[0] - mn[0]
    sy = mx[1] - mn[1]
    sz = mx[2] - mn[2]
    # Thin, tall, free-standing facade sticks/antennas: these are the objects
    # the player sees "hanging in the air" around the factory roof.
    if (sx < 0.8 and sy < 0.8 and sz > 7.0) or mn[2] > 20.0:
        bpy.data.objects.remove(part, do_unlink=True)
        removed += 1
    else:
        keep.append(part)
print("[POLECUT] removed parts", removed, "kept", len(keep))

bpy.ops.object.select_all(action='DESELECT')
for k in keep:
    if k.name in bpy.context.scene.objects:
        k.select_set(True)
bpy.context.view_layer.objects.active = obj
if len(keep) > 1:
    bpy.ops.object.join()
obj.name = "factory_facade_detail"

bpy.ops.export_scene.gltf(
    filepath=SRC,
    export_format='GLB',
    export_animations=False,
    export_apply=False,
)
print("[POLECUT] saved")
