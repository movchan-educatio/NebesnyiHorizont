import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\quad5_custom.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

for o in bpy.context.scene.objects:
    if 'camera' in o.name.lower() or 'cam' in o.name.lower():
        print(f"Cam: {o.name} loc={o.matrix_world.translation}")
