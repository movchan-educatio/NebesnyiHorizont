import bpy
import bmesh
import mathutils
import os

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
print("=" * 80)
print("INSPECTING & FIXING FALCON-X PROPELLERS")
print("=" * 80)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect the 4 motor mounts in Object_28 / Object_31
# Find the circular top face of each of the 4 motor bells
# 1. Front Left (X < -0.06, Y < -0.04)
# 2. Front Right (X > 0.06, Y < -0.04)
# 3. Rear Left (X < -0.06, Y > 0.02)
# 4. Rear Right (X > 0.06, Y > 0.02)

motors = {
    "propeller_FL": (-0.1005, -0.0762),
    "propeller_FR": (0.1005, -0.0762),
    "propeller_BL": (-0.0974, 0.0407),
    "propeller_BR": (0.0974, 0.0407),
}

# Find highest Z on motor bells near these coordinates
all_body_verts = []
for obj in bpy.data.objects:
    if obj.type == 'MESH' and not "prop" in obj.name.lower():
        all_body_verts.extend([obj.matrix_world @ v.co for v in obj.data.vertices])

motor_centers_exact = {}
for mname, (mx, my) in motors.items():
    near = [v for v in all_body_verts if ((v.x - mx)**2 + (v.y - my)**2)**0.5 < 0.025]
    if near:
        max_z = max(v.z for v in near)
        # Vertices near top of the motor bell
        top_verts = [v for v in near if v.z > max_z - 0.003]
        cen = sum(top_verts, mathutils.Vector((0,0,0))) / len(top_verts)
        # Shaft sits right at the top
        motor_centers_exact[mname] = mathutils.Vector((cen.x, cen.y, max_z))
        print(f"{mname}: detected motor shaft top at ({cen.x:.4f}, {cen.y:.4f}, {max_z:.4f})")
    else:
        motor_centers_exact[mname] = mathutils.Vector((mx, my, 0.041 if "F" in mname else 0.124))
        print(f"{mname}: fallback locator ({mx:.4f}, {my:.4f})")

# Now align each propeller:
# Find inner hub vertices, center them to (0, 0, 0) locally, and place object at motor shaft top
for mname in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
    p_obj = bpy.data.objects.get(mname)
    if not p_obj:
        print(f"Missing {mname}!")
        continue
    
    verts = [v.co for v in p_obj.data.vertices]
    # Inner hub: vertices with radius < 12mm
    inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.012]
    if inner:
        hub_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner)
    else:
        hub_cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
        
    min_z = min(v.z for v in verts)
    print(f"Adjusting {mname}: hub_cen=({hub_cen.x:.4f}, {hub_cen.y:.4f}, {hub_cen.z:.4f}), min_z={min_z:.4f}")
    
    # Center inner hub at (0, 0) and bottom of hub at z=0
    for v in p_obj.data.vertices:
        v.co.x -= hub_cen.x
        v.co.y -= hub_cen.y
        v.co.z -= min_z
        
    p_obj.data.update()
    
    target_pos = motor_centers_exact[mname]
    p_obj.location = target_pos
    p_obj.rotation_euler = (0, 0, 0)
    print(f"   -> Placed {mname} at {list(round(c, 4) for c in target_pos)}")

# Export
bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Successfully fixed & exported falcon_x.glb!")
