import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
p = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.import_scene.gltf(filepath=p)

for p_name in ['propeller_FL', 'propeller_FR', 'propeller_BL', 'propeller_BR']:
    p_obj = bpy.data.objects.get(p_name)
    verts = np.array([v.co for v in p_obj.data.vertices])
    print(f"\n{p_name}: {len(verts)} vertices")
    # In Blender local coords, the rotation axis is Z (or in Godot it is Y).
    # If rotating around (0, 0), the distance of vertices in XY plane from (0, 0):
    radii = np.hypot(verts[:, 0], verts[:, 1])
    print(f"  Radius from (0,0): min={radii.min():.4f}, max={radii.max():.4f}")
    print(f"  X bounds: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}], mean={verts[:,0].mean():.4f}")
    print(f"  Y bounds: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}], mean={verts[:,1].mean():.4f}")
    print(f"  Z bounds: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}], mean={verts[:,2].mean():.4f}")
