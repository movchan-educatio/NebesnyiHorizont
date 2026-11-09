import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for obj in list(bpy.context.scene.objects):
    if obj.type != 'MESH' or obj.name != 'factory_facade_detail':
        continue
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    before = set(bpy.context.scene.objects)
    bpy.ops.mesh.separate(type='LOOSE')
    after = [o for o in bpy.context.scene.objects if o not in before]
    print("[FD] parts", len(after))
    for part in after:
        mn = [1e9, 1e9, 1e9]
        mx = [-1e9, -1e9, -1e9]
        for v in part.data.vertices:
            w = part.matrix_world @ v.co
            for i in range(3):
                mn[i] = min(mn[i], w[i])
                mx[i] = max(mx[i], w[i])
        size = [mx[i] - mn[i] for i in range(3)]
        if size[0] < 2.0 and size[1] < 2.0 and mx[2] > 10.0:
            print("[FD] ", part.name, "min", [round(v, 1) for v in mn],
                  "max", [round(v, 1) for v in mx],
                  "size", [round(v, 1) for v in size])
