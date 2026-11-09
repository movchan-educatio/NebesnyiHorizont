import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\holka.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

body = bpy.data.objects['Object_2']
# Find vertices in each quadrant with high Z (top of motor)
corners = {
    'FL': ([-0.12, -0.04], [0.04, 0.12]),
    'FR': ([0.04, 0.12], [0.04, 0.12]),
    'BL': ([-0.12, -0.04], [-0.12, -0.04]),
    'BR': ([0.04, 0.12], [-0.12, -0.04]),
}

for name, (xr, yr) in corners.items():
    v_near = [v.co for v in body.data.vertices if xr[0] <= v.co.x <= xr[1] and yr[0] <= v.co.y <= yr[1]]
    if v_near:
        # find max z
        max_z = max(v.z for v in v_near)
        top_v = [v for v in v_near if v.z > max_z - 0.005]
        cen = sum(top_v, mathutils.Vector()) / len(top_v)
        p = bpy.data.objects.get(f'propeller_{name}')
        ploc = p.location if p else None
        print(f"Corner {name}: motor top center=({cen.x:+.4f}, {cen.y:+.4f}, {cen.z:+.4f}) prop_loc=({ploc.x:+.4f}, {ploc.y:+.4f}, {ploc.z:+.4f})")
