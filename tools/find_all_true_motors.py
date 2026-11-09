import bpy, mathutils, os

BASE_DIR = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

def get_quadrant_top(obj, qx, qy, min_r=0.03):
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    # Filter by quadrant
    quad = [v for v in verts if v.x * qx > min_r and v.y * qy > min_r]
    if not quad:
        return None
    quad.sort(key=lambda v: v.z, reverse=True)
    top20 = quad[:20]
    return sum(top20, mathutils.Vector()) / len(top20)

print("=== EXACT MOTOR MOUNT LOCATIONS FROM GEOMETRY ===")

# 1. Holka
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "holka.glb"))
o = bpy.data.objects['Object_2']
print("\nHOLKA:")
for qx, qy, name in [(-1, 1, 'FL'), (1, 1, 'FR'), (1, -1, 'BR'), (-1, -1, 'BL')]:
    cen = get_quadrant_top(o, qx, qy, 0.03)
    print(f"  {name}: {cen}")

# 2. PinaPipe
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "pinapipe.glb"))
o = bpy.data.objects.get('Motor_Rotor_Rotor_0') or bpy.data.objects.get('Frame_Top_Frame_0')
print("\nPINAPIPE:")
for qx, qy, name in [(-1, 1, 'FL'), (1, 1, 'FR'), (1, -1, 'BR'), (-1, -1, 'BL')]:
    cen = get_quadrant_top(o, qx, qy, 0.03)
    print(f"  {name}: {cen}")

# 3. Avata 2
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "avata2.glb"))
o = bpy.data.objects['DJI_Avata2_Arms_Motors']
print("\nAVATA 2 (from Arms_Motors):")
for qx, qy, name in [(-1, 1, 'FL'), (1, 1, 'FR'), (1, -1, 'BR'), (-1, -1, 'BL')]:
    cen = get_quadrant_top(o, qx, qy, 0.03)
    print(f"  {name}: {cen}")

# 4. Peleng
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "peleng.glb"))
o = bpy.data.objects['peleng_body']
print("\nPELENG:")
for qx, qy, name in [(-1, 1, 'FL'), (1, 1, 'FR'), (1, -1, 'BR'), (-1, -1, 'BL')]:
    cen = get_quadrant_top(o, qx, qy, 0.04)
    print(f"  {name}: {cen}")

# 5. Falcon-X
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "falcon_x.glb"))
o = bpy.data.objects['Object_28']
print("\nFALCON-X (from Object_28 cups):")
for qx, qy, name in [(-1, 1, 'BL'), (1, 1, 'BR'), (1, -1, 'FR'), (-1, -1, 'FL')]:
    cen = get_quadrant_top(o, qx, qy, 0.04)
    print(f"  {name}: {cen}")

# 6. Strila-8
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "strila8.glb"))
print("\nSTRILA-8 (from rotor objects):")
for r_name in ['rotor_korpus_fl_low_DRONE_0', 'rotor_korpus_fr_low_DRONE_0', 'rotor_korpus_bl_low_DRONE_0', 'rotor_korpus_low_DRONE_0']:
    r_obj = bpy.data.objects.get(r_name)
    if r_obj:
        verts = [r_obj.matrix_world @ v.co for v in r_obj.data.vertices]
        verts.sort(key=lambda v: v.z, reverse=True)
        top = sum(verts[:20], mathutils.Vector()) / 20.0
        print(f"  {r_name}: {top}")

# 7. Pisun VTOL
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.join(BASE_DIR, "pisun_vtol.glb"))
print("\nPISUN VTOL:")
for obj_name in ['Object_2', 'Object_3']:
    obj = bpy.data.objects.get(obj_name)
    if obj:
        print(f"  {obj_name} bounds: min={min(v.co for v in obj.data.vertices)} max={max(v.co for v in obj.data.vertices)}")
