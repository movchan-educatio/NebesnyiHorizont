import bpy
import os

GLB = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

p = bpy.data.objects.get("propeller_FL")
print("PISUN_VTOL propeller_FL:")
print("  location:", p.location)
print("  rotation:", p.rotation_euler)
verts = [v.co for v in p.data.vertices]
min_c = [min(v[i] for v in verts) for i in range(3)]
max_c = [max(v[i] for v in verts) for i in range(3)]
print("  span X, Y, Z:", [max_c[i] - min_c[i] for i in range(3)])
