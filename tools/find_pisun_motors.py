import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
p = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.import_scene.gltf(filepath=p)

for o in bpy.data.objects:
    if o.type == 'MESH' and not o.name.startswith("propeller"):
        verts = np.array([o.matrix_world @ v.co for v in o.data.vertices])
        print(f"Object {o.name}: {len(verts)} verts")
        print(f"  X: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}]")
        print(f"  Y: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}]")
        print(f"  Z: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}]")

# Let's search for cylindrical features / motor bells on Object_3
o3 = bpy.data.objects.get("Object_3")
verts = np.array([o3.matrix_world @ v.co for v in o3.data.vertices])
# Object_3 has dims (0.3020, 0.3063, 0.1658)
# Let's find vertices at extrema of X and Y
print("Extrema of Object_3:")
print("  X < -0.12:", len(verts[verts[:,0] < -0.12]))
print("  X >  0.12:", len(verts[verts[:,0] >  0.12]))
print("  Y < -0.12:", len(verts[verts[:,1] < -0.12]))
print("  Y >  0.12:", len(verts[verts[:,1] >  0.12]))
print("Centroids of extrema:")
for name, m in [
    ("Left (-X)", verts[:,0] < -0.10),
    ("Right (+X)", verts[:,0] > 0.10),
    ("Back/Bottom (-Y)", verts[:,1] < -0.10),
    ("Front/Top (+Y)", verts[:,1] > 0.10)
]:
    v_sub = verts[m]
    if len(v_sub) > 0:
        print(f"  {name}: {len(v_sub)} verts, centroid=({v_sub[:,0].mean():.4f}, {v_sub[:,1].mean():.4f}, {v_sub[:,2].mean():.4f})")
        print(f"     X range: [{v_sub[:,0].min():.4f}, {v_sub[:,0].max():.4f}]")
        print(f"     Y range: [{v_sub[:,1].min():.4f}, {v_sub[:,1].max():.4f}]")
        print(f"     Z range: [{v_sub[:,2].min():.4f}, {v_sub[:,2].max():.4f}]")
