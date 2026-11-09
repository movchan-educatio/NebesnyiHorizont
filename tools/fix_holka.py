import bpy
import bmesh
import mathutils
import os

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\holka.glb"
print("=" * 80)
print("FIXING HOLKA PROPELLERS")
print("=" * 80)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

body = bpy.data.objects.get("Object_2")
bm = bmesh.new()
bm.from_mesh(body.data)

quads = {
    "propeller_FL": [v for v in bm.verts if v.co.x < -0.04 and v.co.y > 0.04],
    "propeller_FR": [v for v in bm.verts if v.co.x > 0.04 and v.co.y > 0.04],
    "propeller_BL": [v for v in bm.verts if v.co.x < -0.04 and v.co.y < -0.04],
    "propeller_BR": [v for v in bm.verts if v.co.x > 0.04 and v.co.y < -0.04],
}

motor_mounts = {}
for qname, verts in quads.items():
    max_z = max(v.co.z for v in verts)
    top_verts = [v for v in verts if v.co.z > max_z - 0.004]
    cen = sum([v.co for v in top_verts], mathutils.Vector((0,0,0))) / len(top_verts)
    motor_mounts[qname] = mathutils.Vector((cen.x, cen.y, max_z))
    print(f"{qname}: motor top at ({cen.x:.4f}, {cen.y:.4f}, {max_z:.4f})")

bm.free()

for pname in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
    p_obj = bpy.data.objects.get(pname)
    if not p_obj:
        print(f"Missing {pname}!")
        continue
    
    verts = [v.co for v in p_obj.data.vertices]
    inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.012]
    if inner:
        hub_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner)
    else:
        hub_cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
        
    min_z = min(v.z for v in verts)
    print(f"Adjusting {pname}: hub_cen=({hub_cen.x:.4f}, {hub_cen.y:.4f}, {hub_cen.z:.4f}), min_z={min_z:.4f}")
    
    for v in p_obj.data.vertices:
        v.co.x -= hub_cen.x
        v.co.y -= hub_cen.y
        v.co.z -= min_z
        
    p_obj.data.update()
    
    target_pos = motor_mounts[pname]
    p_obj.location = target_pos
    p_obj.rotation_euler = (0, 0, 0)
    print(f"   -> Placed {pname} at {list(round(c, 4) for c in target_pos)}")

bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Successfully fixed & exported holka.glb!")
