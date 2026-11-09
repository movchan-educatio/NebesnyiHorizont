import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

obj3 = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(obj3.data)
uv_layer = bm.loops.layers.uv.verify()

# Let's inspect faces around the 4 motor positions:
# We know the motor bells are cylindrical shells with silver metal and cyan ring.
# Let's find cylindrical shells in Object_3:
# For each face in Object_3, calculate its distance from the pod centers
pod_centers = [
    ("Top", 0.0, 0.122, -0.05),
    ("Bottom", 0.0, -0.120, -0.05),
    ("Left", -0.121, 0.0, -0.05),
    ("Right", 0.121, 0.0, -0.05),
]

for name, px, py, pz in pod_centers:
    print(f"\n=== POD {name} ===")
    near_faces = [f for f in bm.faces if ((f.calc_center_median().x - px)**2 + (f.calc_center_median().y - py)**2)**0.5 < 0.035]
    print(f"Near faces: {len(near_faces)}")
    # Find Z distribution of near faces
    z_coords = [f.calc_center_median().z for f in near_faces]
    if z_coords:
        print(f"Z range: min={min(z_coords):.4f}, max={max(z_coords):.4f}")
        # Find faces near max Z (top cap) and faces forming the cylinder
        caps = [f for f in near_faces if f.calc_center_median().z > max(z_coords) - 0.005]
        print(f"Top cap faces: {len(caps)}")
        for f in caps[:5]:
            print(f"   cap face normal: {f.normal}, center: {f.calc_center_median()}")
bm.free()
