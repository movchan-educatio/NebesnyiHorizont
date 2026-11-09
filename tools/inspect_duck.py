import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
p = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\d1l-duck_-_ukrainian_tailsitter_vtol_fpv_quad.glb"
bpy.ops.import_scene.gltf(filepath=p)

for o in bpy.data.objects:
    if o.type == 'MESH':
        mw = o.matrix_world
        verts = np.array([mw @ v.co for v in o.data.vertices])
        print(f"Object {o.name}: {len(verts)} verts")
        print(f"  X: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}]")
        print(f"  Y: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}]")
        print(f"  Z: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}]")
