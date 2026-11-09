import bpy
import os

GLB = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\avata2.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        print(f"\n--- OBJECT: {o.name} (verts: {len(o.data.vertices)}) ---")
        mw = o.matrix_world
        verts = [mw @ v.co for v in o.data.vertices]
        min_c = [min(v[i] for v in verts) for i in range(3)]
        max_c = [max(v[i] for v in verts) for i in range(3)]
        print(f"  World bounds X: [{min_c[0]:.4f}, {max_c[0]:.4f}]")
        print(f"  World bounds Y: [{min_c[1]:.4f}, {max_c[1]:.4f}]")
        print(f"  World bounds Z: [{min_c[2]:.4f}, {max_c[2]:.4f}]")
        # Check if it has geometry in the propeller area (e.g. near (-0.06, 0.047))
        near_prop = [v for v in verts if (v.x + 0.06)**2 + (v.y - 0.047)**2 < 0.035**2]
        print(f"  Verts near FL prop: {len(near_prop)}")
