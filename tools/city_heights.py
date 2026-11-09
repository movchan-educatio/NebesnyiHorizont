import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\sceneries\city\fpv_city.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

rows = []
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH' or not obj.name.startswith("Bld"):
        continue
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    rows.append((round(mx[2] - mn[2], 1), round(mx[0] - mn[0], 1),
                 round(mx[1] - mn[1], 1), round(mn[2], 1), obj.name))
rows.sort(reverse=True)
print("[CITYHEIGHT] count", len(rows))
for r in rows:
    print("[CITYHEIGHT]", r)
