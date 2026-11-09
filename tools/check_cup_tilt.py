import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

obj28 = bpy.data.objects.get("Object_28")
bm = bmesh.new()
bm.from_mesh(obj28.data)

# Let's inspect the faces of the circular bottom or rim of the cup
# For Front-Left:
fl_faces = [f for f in bm.faces if ((f.calc_center_median().x - (-0.0996))**2 + (f.calc_center_median().y - (-0.0428))**2)**0.5 < 0.015]
print(f"FL faces: {len(fl_faces)}")
normals = [f.normal for f in fl_faces]
avg_n = sum(normals, mathutils.Vector((0,0,0))) / len(normals)
print(f"Average normal in FL cup: {avg_n}")

# Check flat faces inside the cup
flat_faces = [f for f in fl_faces if f.normal.z > 0.8]
print(f"Flat upward faces in FL cup: {len(flat_faces)}")
if flat_faces:
    avg_up = sum([f.normal for f in flat_faces], mathutils.Vector((0,0,0))) / len(flat_faces)
    print(f"Cup floor normal: {avg_up}")
bm.free()
