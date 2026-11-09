import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect the materials and image colors of Object_3
# To find the silver cylinder with blue ring, let's find the UVs in Object_3 that sample cyan/blue pixels!
img = bpy.data.images.get("Image_0") # Usually base color
# Let's inspect all faces in Object_3 and their UV coordinates
obj3 = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(obj3.data)
uv_layer = bm.loops.layers.uv.verify()

# Let's sample image pixels or check vertex colors
# Also let's inspect the shape:
# A motor bell is a CYLINDER with open or flat end
# Let's find vertices forming a cylinder of radius ~ 12-16mm (diameter ~ 28mm for 2806 motor!)
print("Searching for 2806 motor bell cylinders in Object_3...")
# Check all vertices near the right pod: X > 0.08
right_verts = [v for v in bm.verts if v.co.x > 0.08]
# Cluster by Z coordinate in 5mm slices
slices = {}
for v in right_verts:
    z_key = round(v.co.z, 2)
    slices.setdefault(z_key, []).append(v)

for zk in sorted(slices.keys(), reverse=True):
    vs = slices[zk]
    cen = sum([v.co for v in vs], mathutils.Vector((0,0,0))) / len(vs)
    radii = [((v.co.x - cen.x)**2 + (v.co.y - cen.y)**2)**0.5 for v in vs]
    max_r = max(radii)
    min_r = min(radii)
    avg_r = sum(radii) / len(radii)
    print(f"Z ~ {zk:.2f}: {len(vs)} verts, center=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f}), radius=[{min_r:.4f}, {max_r:.4f}], avg_r={avg_r:.4f}")
bm.free()
