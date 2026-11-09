import bpy, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\quad5_custom.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

print("=== QUAD5 MOTOR SHAFTS ===")
for o in bpy.context.scene.objects:
    if 'motor_shaft' in o.name.lower() or 'prop_nut' in o.name.lower():
        print(f"  {o.name:25} loc={o.matrix_world.translation}")
