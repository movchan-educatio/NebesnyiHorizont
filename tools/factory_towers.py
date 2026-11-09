import bpy

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\handcrafted\factory_complex.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH':
        continue
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for v in obj.data.vertices:
        w = obj.matrix_world @ v.co
        for i in range(3):
            mn[i] = min(mn[i], w[i])
            mx[i] = max(mx[i], w[i])
    name = obj.name.lower()
    if any(k in name for k in ["chim", "tower", "silo", "pipe", "stack"]):
        print("[FACT]", obj.name, "size", [round(mx[i] - mn[i], 1) for i in range(3)],
              "min", [round(v, 1) for v in mn], "max", [round(v, 1) for v in mx])
