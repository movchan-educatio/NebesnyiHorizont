import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

obj28 = bpy.data.objects.get("Object_28")
print(f"Object_28 parent: {obj28.parent.name if obj28.parent else 'None'}")
print(f"Object_28 matrix_world:\n{obj28.matrix_world}")

# Circular cups in world space:
# Front-Left cup:
local_pts = {
    "FL": mathutils.Vector((-0.0996, -0.0428, -0.0370)),
    "FR": mathutils.Vector((0.0996, -0.0428, -0.0371)),
    "BL": mathutils.Vector((-0.0952, 0.0704, 0.0568)),
    "BR": mathutils.Vector((0.0954, 0.0704, 0.0569)),
}

for name, pt in local_pts.items():
    world_pt = obj28.matrix_world @ pt
    print(f"Motor {name}: local={pt} -> WORLD={world_pt}")
