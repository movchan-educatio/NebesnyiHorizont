import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\holka.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

body = bpy.data.objects.get("Object_2")
bm = bmesh.new()
bm.from_mesh(body.data)

# Let's inspect the materials of Object_2
# Find the motor bell material!
for slot_idx, slot in enumerate(body.material_slots):
    mat_name = slot.material.name if slot.material else "None"
    faces = [f for f in bm.faces if f.material_index == slot_idx]
    print(f"Slot {slot_idx} ({mat_name}): {len(faces)} faces")
    
# Let's find the 4 circular cylinders with silver/metal material or circular rings
# The 4 motor bells are 4 identical cylinders of diameter ~ 28mm (radius ~ 14mm)
# Let's search all faces in bm.faces for small circles
for qname, (cx, cy) in [
    ("Front-Right", (0.08, 0.08)),
    ("Front-Left", (-0.08, 0.08)),
    ("Rear-Right", (0.08, -0.08)),
    ("Rear-Left", (-0.08, -0.08)),
]:
    near_verts = [v for v in bm.verts if ((v.co.x - cx)**2 + (v.co.y - cy)**2)**0.5 < 0.04]
    if near_verts:
        xs = [v.co.x for v in near_verts]
        ys = [v.co.y for v in near_verts]
        zs = [v.co.z for v in near_verts]
        print(f"\n{qname}: {len(near_verts)} verts")
        print(f"  X: [{min(xs):.4f}, {max(xs):.4f}]")
        print(f"  Y: [{min(ys):.4f}, {max(ys):.4f}]")
        print(f"  Z: [{min(zs):.4f}, {max(zs):.4f}]")
        # Find highest Z in this cluster
        max_z = max(zs)
        top = [v for v in near_verts if v.co.z > max_z - 0.003]
        top_cen = sum([v.co for v in top], mathutils.Vector((0,0,0))) / len(top)
        print(f"  Top center: ({top_cen.x:.4f}, {top_cen.y:.4f}, {max_z:.4f})")
bm.free()
