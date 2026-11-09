import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

print("=== PISUN VTOL MATERIALS & MESHES ===")
for obj in bpy.data.objects:
    if obj.type == 'MESH':
        mats = [slot.material.name if slot.material else "None" for slot in obj.material_slots]
        print(f"Mesh: {obj.name}, verts: {len(obj.data.vertices)}, mats: {mats}")

# Let's find the silver cylinder / motor bell vertices in Object_3:
# The user screenshot clearly shows a silver cylinder with cyan ring on the right nacelle.
# Let's find vertices with highest/lowest coordinates or where cyan/silver material is applied!
obj3 = bpy.data.objects.get("Object_3")
for slot_idx, slot in enumerate(obj3.material_slots):
    mat_name = slot.material.name if slot.material else "None"
    faces_with_mat = [f for f in obj3.data.polygons if f.material_index == slot_idx]
    print(f"Slot {slot_idx} ({mat_name}): {len(faces_with_mat)} faces")
    if "motor" in mat_name.lower() or "metal" in mat_name.lower() or "silver" in mat_name.lower() or "cyan" in mat_name.lower() or len(faces_with_mat) < 1000:
        verts_idx = set()
        for f in faces_with_mat:
            verts_idx.update(f.vertices)
        if verts_idx:
            v_cos = [obj3.data.vertices[i].co for i in verts_idx]
            min_x = min(c.x for c in v_cos)
            max_x = max(c.x for c in v_cos)
            min_y = min(c.y for c in v_cos)
            max_y = max(c.y for c in v_cos)
            min_z = min(c.z for c in v_cos)
            max_z = max(c.z for c in v_cos)
            print(f"   -> Bounds: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}]")
