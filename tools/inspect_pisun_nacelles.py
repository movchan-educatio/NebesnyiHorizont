import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect Object_3 and Object_2
for obj in bpy.data.objects:
    print(f"OBJ: {obj.name}, type={obj.type}, verts={len(obj.data.vertices) if obj.type=='MESH' else 0}")

# Let's find cylindrical motor faces or motor bell geometry in Object_3 or wherever the motors are
# Also look at the original source file for pisun_vtol if available!
