import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\grim7.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

for o in bpy.context.scene.objects:
    if 'carbon' in o.name.lower():
        verts = o.data.vertices
        for quad, (sx, sy) in [('FL', (-1, 1)), ('FR', (1, 1)), ('BL', (-1, -1)), ('BR', (1, -1))]:
            q_verts = [v.co for v in verts if (v.co.x * sx > 0.05) and (v.co.y * sy > 0.05)]
            if q_verts:
                cen = sum(q_verts, mathutils.Vector()) / len(q_verts)
                print(f"Grim7 {quad}: arm tip=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
