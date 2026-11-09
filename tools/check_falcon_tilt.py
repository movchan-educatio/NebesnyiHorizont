import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

print("=== FALCON_X ORIENTATION ===")
for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        print(f"Mesh {o.name}: rotation_euler={o.rotation_euler} rot_deg={[round(r*180/3.14159, 1) for r in o.rotation_euler]}")
        p = o.parent
        while p:
            print(f"   parent {p.name}: rot_deg={[round(r*180/3.14159, 1) for r in p.rotation_euler]}")
            p = p.parent
