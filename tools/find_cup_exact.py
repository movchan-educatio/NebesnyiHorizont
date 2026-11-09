import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb")

# On Falcon-X, what object contains the cups?
# Object_28 or Object_31?
for oname in ['Object_28', 'Object_31']:
    o = bpy.data.objects.get(oname)
    verts = np.array([o.matrix_world @ v.co for v in o.data.vertices])
    print(f"\n=== {oname} ===")
    
    # Let's find vertices in the 4 extreme corners of the arms:
    # FL: X < -0.07, Y < -0.03
    # FR: X >  0.07, Y < -0.03
    # BL: X < -0.07, Y >  0.03
    # BR: X >  0.07, Y >  0.03
    for qname, qcond in [
        ('FL', (verts[:,0] < -0.07) & (verts[:,1] < -0.02)),
        ('FR', (verts[:,0] >  0.07) & (verts[:,1] < -0.02)),
        ('BL', (verts[:,0] < -0.07) & (verts[:,1] >  0.02)),
        ('BR', (verts[:,0] >  0.07) & (verts[:,1] >  0.02)),
    ]:
        qverts = verts[qcond]
        print(f"  {qname}: {len(qverts)} verts, X=[{qverts[:,0].min():.4f}, {qverts[:,0].max():.4f}], Y=[{qverts[:,1].min():.4f}, {qverts[:,1].max():.4f}], Z=[{qverts[:,2].min():.4f}, {qverts[:,2].max():.4f}]")
        print(f"     Centroid: ({qverts[:,0].mean():.4f}, {qverts[:,1].mean():.4f}, {qverts[:,2].mean():.4f})")
