import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect Object_2 and Object_3 for cylinders / circles
for o in [bpy.data.objects.get("Object_2"), bpy.data.objects.get("Object_3")]:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    print(f"\n--- {o.name} ---")
    # Find circular face loops or circular edge loops
    for v in bm.verts:
        # Check if vertex is near any of the 4 wingtips:
        # X ~ ±0.20 or Y ~ ±0.20 or X ~ ±0.12 or Y ~ ±0.12
        if abs(v.co.x) > 0.10 or abs(v.co.y) > 0.10:
            pass
    # Print outer bounds
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    zs = [v.co.z for v in bm.verts]
    print(f"Bounds: X[{min(xs):.4f}, {max(xs):.4f}], Y[{min(ys):.4f}, {max(ys):.4f}], Z[{min(zs):.4f}, {max(zs):.4f}]")
    bm.free()
