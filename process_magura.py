import bpy
import os
from mathutils import Vector

bpy.ops.wm.read_homefile(use_empty=True)
src_glb = r'c:\Users\USER_UA\Desktop\3д моделі нових дронів\Магура-Х\ukrainian_navy_maritime_drone.glb'
dst_glb = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\magura_x.glb'

bpy.ops.import_scene.gltf(filepath=src_glb)

obj = bpy.data.objects.get('Object_2')
if not obj:
    for o in bpy.data.objects:
        if o.type == 'MESH':
            obj = o
            break

print("Processing Magura mesh:", obj.name)

# Resize images from 4096 to 2048
for img in bpy.data.images:
    if img.size[0] > 2048 or img.size[1] > 2048:
        print(f"Resizing {img.name} from {img.size[0]}x{img.size[1]} to 2048x2048")
        img.scale(2048, 2048)

# Center and scale mesh
coords = [v.co for v in obj.data.vertices]
min_x = min(c.x for c in coords); max_x = max(c.x for c in coords)
min_y = min(c.y for c in coords); max_y = max(c.y for c in coords)
min_z = min(c.z for c in coords); max_z = max(c.z for c in coords)

raw_len = max_z - min_z # 929.25 units
target_len = 5.50 # 5.5 meters
scale_factor = target_len / raw_len

mid_x = (min_x + max_x) * 0.5
mid_z = (min_z + max_z) * 0.5
waterline_y = -22.0 # Where the water plane sits against the hull chines

# In raw model, +Z is bow (narrow) and -Z is stern (wide).
# In Godot, -Z is forward. So we negate Z and negate X (180 deg yaw rotation)
for v in obj.data.vertices:
    # Rotate 180 around Y so bow points to -Z (Godot forward)
    cur_x = -(v.co.x - mid_x) * scale_factor
    cur_y = (v.co.y - waterline_y) * scale_factor
    cur_z = -(v.co.z - mid_z) * scale_factor
    v.co.x = cur_x
    v.co.y = cur_y
    v.co.z = cur_z

obj.name = "Magura_Hull"
obj.location = Vector((0, 0, 0))

# Remove unnecessary empty objects
for o in list(bpy.data.objects):
    if o != obj:
        bpy.data.objects.remove(o, do_unlink=True)

# Check bounds after transform
new_coords = [v.co for v in obj.data.vertices]
print(f"New bounds:")
print(f"  X (width): [{min(c.x for c in new_coords):.3f}, {max(c.x for c in new_coords):.3f}] = {max(c.x for c in new_coords) - min(c.x for c in new_coords):.3f} m")
print(f"  Y (height): [{min(c.y for c in new_coords):.3f}, {max(c.y for c in new_coords):.3f}] = {max(c.y for c in new_coords) - min(c.y for c in new_coords):.3f} m")
print(f"  Z (length): [{min(c.z for c in new_coords):.3f}, {max(c.z for c in new_coords):.3f}] = {max(c.z for c in new_coords) - min(c.z for c in new_coords):.3f} m")

# Export to GLB
os.makedirs(os.path.dirname(dst_glb), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=dst_glb,
    export_format='GLB',
    use_selection=False,
    export_apply=True
)
print("SUCCESSFULLY EXPORTED magura_x.glb to", dst_glb)
