import bpy
import bmesh
import mathutils
import os

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
print("=" * 80)
print("FIXING PISUN VTOL PROPELLERS")
print("=" * 80)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# True motor bell face centers in Object_3:
motors = {
    "propeller_FR": mathutils.Vector((0.1206, 0.0004, -0.0508)),
    "propeller_FL": mathutils.Vector((-0.1201, -0.0001, -0.0519)),
    "propeller_BL": mathutils.Vector((-0.0011, 0.1219, -0.0517)),
    "propeller_BR": mathutils.Vector((-0.0003, -0.1186, -0.0517)),
}

for pname, target_loc in motors.items():
    p_obj = bpy.data.objects.get(pname)
    if not p_obj:
        print(f"Missing {pname}!")
        continue
    
    verts = [v.co for v in p_obj.data.vertices]
    # In pisun props, the 3 blades are at 120 degrees
    # The inner hub cylinder has vertices with radius < 15mm
    inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.015]
    if inner:
        # Refine hub center
        cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner)
        close = [v for v in inner if ((v.x - cen.x)**2 + (v.y - cen.y)**2)**0.5 < 0.008]
        if close:
            hub_cen = sum(close, mathutils.Vector((0,0,0))) / len(close)
        else:
            hub_cen = cen
    else:
        hub_cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
        
    min_z = min(v.z for v in verts)
    print(f"Adjusting {pname}: hub_cen=({hub_cen.x:.5f}, {hub_cen.y:.5f}, {hub_cen.z:.5f}), min_z={min_z:.4f}")
    
    # Shift vertices so hub center is at (0, 0) and bottom sits on motor face
    for v in p_obj.data.vertices:
        v.co.x -= hub_cen.x
        v.co.y -= hub_cen.y
        v.co.z -= min_z
        
    p_obj.data.update()
    p_obj.location = target_loc
    p_obj.rotation_euler = (0, 0, 0)
    print(f"   -> Placed {pname} at {list(round(c, 4) for c in target_loc)}")

bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Successfully fixed & exported pisun_vtol.glb!")
