import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's check the empty locators in falcon_x!
# Remember in the hierarchy we saw:
# [EMPTY] _1_14 | loc=[-0.0974, 0.0407, 0.1236]
# [EMPTY] _2_2_11 | loc=[-0.1005, -0.0762, 0.0387]
# [EMPTY] _2_8 | loc=[0.1005, -0.0762, 0.0387]
# [EMPTY] _5 | loc=[0.0974, 0.0407, 0.1236]
# Look at these 4 empties!
print("=== FALCON-X EMPTIES / MOTOR LOCATORS ===")
for obj in bpy.data.objects:
    if "jiangye" in obj.name or "polySurface" in obj.name or obj.parent and "jiangye" in obj.parent.name:
        w_loc = obj.matrix_world.translation
        print(f"Empty/Obj: {obj.name}, parent={obj.parent.name if obj.parent else 'None'}, loc={list(round(c, 4) for c in obj.location)}, world_loc={list(round(c, 4) for c in w_loc)}")

# Also search all meshes in falcon_x to see which vertices are at the motor tips
print("\n=== FALCON-X MESHES MOTOR TIPS ===")
for obj in bpy.data.objects:
    if obj.type == 'MESH' and not "prop" in obj.name.lower():
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        # Check quadrants
        for qname, cond in [
            ("FL (X>0, Y<0)", lambda v: v.co.x > 0.05 and v.co.y < -0.02),
            ("FR (X<0, Y<0)", lambda v: v.co.x < -0.05 and v.co.y < -0.02),
            ("BL (X>0, Y>0)", lambda v: v.co.x > 0.05 and v.co.y > 0.02),
            ("BR (X<0, Y>0)", lambda v: v.co.x < -0.05 and v.co.y > 0.02),
        ]:
            matching = [obj.matrix_world @ v.co for v in bm.verts if cond(v)]
            if matching:
                min_x = min(c.x for c in matching)
                max_x = max(c.x for c in matching)
                min_y = min(c.y for c in matching)
                max_y = max(c.y for c in matching)
                min_z = min(c.z for c in matching)
                max_z = max(c.z for c in matching)
                print(f"[{obj.name}] {qname}: {len(matching)} verts, bounds: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}]")
        bm.free()
