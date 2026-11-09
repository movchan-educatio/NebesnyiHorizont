import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect the mesh faces and normals of Object_3 around the motor positions:
# Motor 1: [-0.0013, 0.1223, -0.05]
# Motor 2: [-0.0006, -0.1205, -0.05]
# Motor 3: [-0.121, 0.0002, -0.05]
# Motor 4: [0.12, 0.0006, -0.05]
obj = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(obj.data)

motor_locs = [
    ("Motor_Top", mathutils.Vector((-0.0013, 0.1223, -0.05))),
    ("Motor_Bottom", mathutils.Vector((-0.0006, -0.1205, -0.05))),
    ("Motor_Left", mathutils.Vector((-0.121, 0.0002, -0.05))),
    ("Motor_Right", mathutils.Vector((0.12, 0.0006, -0.05))),
]

for name, m_loc in motor_locs:
    print(f"\n--- {name} near {m_loc} ---")
    nearby_verts = [v for v in bm.verts if (v.co - m_loc).length < 0.04]
    print(f"Nearby verts in Object_3: {len(nearby_verts)}")
    if nearby_verts:
        min_x = min(v.co.x for v in nearby_verts)
        max_x = max(v.co.x for v in nearby_verts)
        min_y = min(v.co.y for v in nearby_verts)
        max_y = max(v.co.y for v in nearby_verts)
        min_z = min(v.co.z for v in nearby_verts)
        max_z = max(v.co.z for v in nearby_verts)
        print(f"Bounds: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}]")
    
    # Check circular face loops or face normals
    nearby_faces = [f for f in bm.faces if any((v.co - m_loc).length < 0.04 for v in f.verts)]
    print(f"Nearby faces: {len(nearby_faces)}")
    # Find average normal of the circular motor end cap
    normals = [f.normal for f in nearby_faces]
    if normals:
        avg_norm = sum(normals, mathutils.Vector((0,0,0))) / len(normals)
        print(f"Average face normal: {avg_norm}")
        # Look for flat end face (faces where normal is close to +Z, -Z, +Y, -Y, etc)
        for f in nearby_faces:
            if f.area > 0.00005:
                print(f"   Face area={f.area:.6f}, normal={list(round(c, 3) for c in f.normal)}, center={list(round(c, 3) for c in f.calc_center_median())}")
bm.free()
