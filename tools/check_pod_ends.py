import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

obj3 = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(obj3.data)

# Let's inspect the right pod (X > 0.08)
pod_verts = [v for v in bm.verts if v.co.x > 0.08]
print(f"Right pod has {len(pod_verts)} verts")
min_z = min(v.co.z for v in pod_verts)
max_z = max(v.co.z for v in pod_verts)
print(f"Right pod Z range: min={min_z:.4f}, max={max_z:.4f}")

# What is at max_z (-0.0508)?
max_verts = [v for v in pod_verts if v.co.z > max_z - 0.015]
cen_max = sum([v.co for v in max_verts], mathutils.Vector((0,0,0))) / len(max_verts)
print(f"Shape at max_z ({max_z:.4f}): {len(max_verts)} verts, center=({cen_max.x:.4f}, {cen_max.y:.4f}, {cen_max.z:.4f})")

# What is at min_z (-0.1205)?
min_verts = [v for v in pod_verts if v.co.z < min_z + 0.015]
cen_min = sum([v.co for v in min_verts], mathutils.Vector((0,0,0))) / len(min_verts)
print(f"Shape at min_z ({min_z:.4f}): {len(min_verts)} verts, center=({cen_min.x:.4f}, {cen_min.y:.4f}, {cen_min.z:.4f})")

# Let's check which end has circular cylinders / motor bells!
# Measure diameter at max_z vs min_z
dx_max = max(v.co.x for v in max_verts) - min(v.co.x for v in max_verts)
dy_max = max(v.co.y for v in max_verts) - min(v.co.y for v in max_verts)
print(f"Span at max_z: dx={dx_max:.4f}, dy={dy_max:.4f}")

dx_min = max(v.co.x for v in min_verts) - min(v.co.x for v in min_verts)
dy_min = max(v.co.y for v in min_verts) - min(v.co.y for v in min_verts)
print(f"Span at min_z: dx={dx_min:.4f}, dy={dy_min:.4f}")

bm.free()
