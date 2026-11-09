import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
p = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\peleng.glb"
bpy.ops.import_scene.gltf(filepath=p)

body = bpy.data.objects.get("peleng_body")
if not body:
    print("peleng_body not found!")
    for o in bpy.data.objects:
        print(o.name)
else:
    verts = np.array([body.matrix_world @ v.co for v in body.data.vertices])
    print(f"peleng_body verts: {len(verts)}")
    print(f"X: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}]")
    print(f"Y: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}]")
    print(f"Z: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}]")
    
    # Motor detection:
    # Peleng has 4 motors at 4 corners
    # Let's find cylindrical surfaces or clusters in each quadrant
    fl_verts = verts[(verts[:, 0] < -0.04) & (verts[:, 1] > 0.03)]
    fr_verts = verts[(verts[:, 0] > 0.04) & (verts[:, 1] > 0.03)]
    bl_verts = verts[(verts[:, 0] < -0.04) & (verts[:, 1] < -0.03)]
    br_verts = verts[(verts[:, 0] > 0.04) & (verts[:, 1] < -0.03)]
    
    print("\n--- Peleng Body Motor Clusters in Blender Coords ---")
    for qname, qverts in [('FL', fl_verts), ('FR', fr_verts), ('BL', bl_verts), ('BR', br_verts)]:
        if len(qverts) == 0:
            print(f"{qname}: NO VERTS!")
            continue
        print(f"{qname}: {len(qverts)} verts")
        print(f"  X: [{qverts[:,0].min():.4f}, {qverts[:,0].max():.4f}]")
        print(f"  Y: [{qverts[:,1].min():.4f}, {qverts[:,1].max():.4f}]")
        print(f"  Z: [{qverts[:,2].min():.4f}, {qverts[:,2].max():.4f}]")
        # Find highest Z (top of motor)
        max_z = qverts[:, 2].max()
        top_verts = qverts[qverts[:, 2] > max_z - 0.008]
        print(f"  Top motor cap: X={top_verts[:,0].mean():.4f}, Y={top_verts[:,1].mean():.4f}, Z={top_verts[:,2].mean():.4f}")

for p_name in ['propeller_FL', 'propeller_FR', 'propeller_BL', 'propeller_BR']:
    p_obj = bpy.data.objects.get(p_name)
    if p_obj:
        print(f"Current {p_name} location in Blender: {p_obj.location}")
