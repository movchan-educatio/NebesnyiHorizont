import bpy
import os
import mathutils

GLB = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\avata2.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)

# Let's inspect all objects in avata2
motors = [
    ("FL", -0.0601, 0.0469),
    ("FR", 0.0600, 0.0469),
    ("BR", 0.0603, -0.0468),
    ("BL", -0.0603, -0.0468),
]

for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        mw = o.matrix_world
        verts = [mw @ v.co for v in o.data.vertices]
        for tag, mx, my in motors:
            near_m = [v for v in verts if (mathutils.Vector((v.x - mx, v.y - my))).length < 0.035]
            if len(near_m) > 0:
                print(f"Object '{o.name}' has {len(near_m)} vertices near motor {tag} ({mx}, {my})")
