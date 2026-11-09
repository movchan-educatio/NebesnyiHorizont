import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)

for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH':
        continue
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    before = set(bpy.context.scene.objects)
    try:
        bpy.ops.mesh.separate(type='LOOSE')
    except Exception as exc:
        print("[LOOSE] fail", obj.name, exc)
        continue
    after = [o for o in bpy.context.scene.objects if o not in before]
    for part in after:
        mn = [1e9, 1e9, 1e9]
        mx = [-1e9, -1e9, -1e9]
        for v in part.data.vertices:
            w = part.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
        size = [mx[i] - mn[i] for i in range(3)]
        if size[0] < 3.0 and size[2] < 3.0 and mn[2] > 8.0:
            print("[LOOSE]", obj.name, "->", part.name, "min",
                  [round(v, 1) for v in mn], "max", [round(v, 1) for v in mx],
                  "size", [round(v, 1) for v in size])
