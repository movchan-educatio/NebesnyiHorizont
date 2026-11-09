import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

p_obj = bpy.data.objects.get("propeller_FR")
verts = [v.co for v in p_obj.data.vertices]

# Find outer tips of the blades: vertices with radius > 50mm
tips = [v for v in verts if (v.x**2 + v.y**2)**0.5 > 0.050]
print(f"Outer vertices (>50mm): {len(tips)}")
# Group tips by angle theta
import math
angles = [math.atan2(v.y, v.x) for v in tips]
# Find distinct angle clusters
clusters = []
for a in angles:
    # check if close to existing cluster
    found = False
    for cl in clusters:
        # angular difference
        diff = abs((a - cl[0] + math.pi) % (2*math.pi) - math.pi)
        if diff < 0.3:
            cl.append(a)
            found = True
            break
    if not found:
        clusters.append([a])

print(f"Found {len(clusters)} blade clusters:")
for idx, cl in enumerate(clusters):
    avg_a = sum(cl) / len(cl)
    # find max radius in this cluster
    cluster_verts = [v for v in tips if abs((math.atan2(v.y, v.x) - avg_a + math.pi) % (2*math.pi) - math.pi) < 0.3]
    max_r = max((v.x**2 + v.y**2)**0.5 for v in cluster_verts)
    print(f"   Blade {idx}: angle={math.degrees(avg_a):.1f} deg, max_radius={max_r*1000:.1f} mm, count={len(cl)}")
