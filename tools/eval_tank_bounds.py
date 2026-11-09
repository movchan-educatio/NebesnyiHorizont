import bpy

SRC = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\assets\vehicles\low_poly_t-72_tank_-_game_ready.glb"

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=SRC)

deps = bpy.context.evaluated_depsgraph_get()
mins = [1e9, 1e9, 1e9]
maxs = [-1e9, -1e9, -1e9]
count = 0
for ob in bpy.context.scene.objects:
    if ob.type != 'MESH':
        continue
    eo = ob.evaluated_get(deps)
    me = eo.to_mesh()
    mw = eo.matrix_world
    for v in me.vertices:
        p = mw @ v.co
        for i in range(3):
            mins[i] = min(mins[i], p[i])
            maxs[i] = max(maxs[i], p[i])
        count += 1
    eo.to_mesh_clear()

print("[EVAL] verts", count)
print("[EVAL] blender min", mins, "max", maxs, "size", [maxs[i] - mins[i] for i in range(3)])
# Blender Z-up -> Godot Y-up: gx = bx, gy = bz, gz = -by
gmin = (mins[0], mins[2], -maxs[1])
gmax = (maxs[0], maxs[2], -mins[1])
print("[EVAL] godot min", gmin, "max", gmax,
      "size", [gmax[i] - gmin[i] for i in range(3)])
