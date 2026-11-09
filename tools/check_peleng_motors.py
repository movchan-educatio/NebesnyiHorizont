import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\peleng.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

m = bpy.data.objects['peleng_body']
verts = m.data.vertices
for quad, (sx, sy) in [('FL', (-1, 1)), ('FR', (1, 1)), ('BL', (-1, -1)), ('BR', (1, -1))]:
    q_verts = [v.co for v in verts if (v.co.x * sx > 0.05) and (v.co.y * sy > 0.05)]
    if q_verts:
        # Sort by Z
        top_z = max(v.z for v in q_verts)
        top_pts = [v for v in q_verts if abs(v.z - top_z) < 0.005]
        cen = sum(top_pts, mathutils.Vector()) / len(top_pts)
        print(f"Peleng {quad}: motor top=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
