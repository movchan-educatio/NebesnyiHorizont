import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

body = bpy.data.objects.get("Object_3")
bm = bmesh.new()
bm.from_mesh(body.data)

pods = {
    "Pod_Top (Y>0.08)": [v for v in bm.verts if v.co.y > 0.08 and abs(v.co.x) < 0.04],
    "Pod_Bottom (Y<-0.08)": [v for v in bm.verts if v.co.y < -0.08 and abs(v.co.x) < 0.04],
    "Pod_Left (X<-0.08)": [v for v in bm.verts if v.co.x < -0.08 and abs(v.co.y) < 0.04],
    "Pod_Right (X>0.08)": [v for v in bm.verts if v.co.x > 0.08 and abs(v.co.y) < 0.04],
}

print("=== PISUN VTOL MOTOR BELL POSITIONS IN OBJECT_3 ===")
for pname, verts in pods.items():
    if verts:
        # Highest Z in this pod is the motor face pointing towards the nose
        max_z = max(v.co.z for v in verts)
        top_verts = [v for v in verts if v.co.z > max_z - 0.005]
        cen = sum([v.co for v in top_verts], mathutils.Vector((0,0,0))) / len(top_verts)
        min_x = min(v.co.x for v in verts)
        max_x = max(v.co.x for v in verts)
        min_y = min(v.co.y for v in verts)
        max_y = max(v.co.y for v in verts)
        min_z = min(v.co.z for v in verts)
        print(f"{pname}:")
        print(f"   Motor Face Top Z = {max_z:.4f}")
        print(f"   Motor Face Center = ({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
        print(f"   Pod bounds: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}]")

bm.free()

print("\n=== CURRENT PROPELLER OBJECT LOCATIONS IN PISUN VTOL ===")
for p in ["propeller_BL", "propeller_BR", "propeller_FL", "propeller_FR"]:
    obj = bpy.data.objects.get(p)
    if obj:
        print(f"{p}: loc={list(round(c, 4) for c in obj.location)}")
