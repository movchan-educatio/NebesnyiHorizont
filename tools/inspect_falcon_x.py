import bpy
import os
import mathutils

GLB = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        mw = o.matrix_world
        verts = [mw @ v.co for v in o.data.vertices]
        min_c = [min(v[i] for v in verts) for i in range(3)]
        max_c = [max(v[i] for v in verts) for i in range(3)]
        c = [(min_c[i] + max_c[i]) / 2.0 for i in range(3)]
        span = [max_c[i] - min_c[i] for i in range(3)]
        print(f"Object: '{o.name}' center=({c[0]:.4f}, {c[1]:.4f}, {c[2]:.4f}) span=({span[0]:.4f}, {span[1]:.4f}, {span[2]:.4f})")
