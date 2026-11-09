import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\holka.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

body = bpy.data.objects.get("Object_2")
bm = bmesh.new()
bm.from_mesh(body.data)

quads = {
    "FL (X<0, Y>0)": [v for v in bm.verts if v.co.x < -0.04 and v.co.y > 0.04],
    "FR (X>0, Y>0)": [v for v in bm.verts if v.co.x > 0.04 and v.co.y > 0.04],
    "BL (X<0, Y<0)": [v for v in bm.verts if v.co.x < -0.04 and v.co.y < -0.04],
    "BR (X>0, Y<0)": [v for v in bm.verts if v.co.x > 0.04 and v.co.y < -0.04],
}

print("=== HOLKA BODY MOTOR MOUNT LOCATIONS ===")
for qname, verts in quads.items():
    if verts:
        max_z = max(v.co.z for v in verts)
        top_verts = [v for v in verts if v.co.z > max_z - 0.005]
        cen = sum([v.co for v in top_verts], mathutils.Vector((0,0,0))) / len(top_verts)
        print(f"{qname}: top_center = ({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")

bm.free()

print("\n=== CURRENT HOLKA PROPELLER OBJECT LOCATIONS ===")
for p in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
    obj = bpy.data.objects.get(p)
    if obj:
        print(f"{p}: loc={list(round(c, 4) for c in obj.location)}")
