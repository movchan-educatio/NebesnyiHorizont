import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Let's inspect the images/textures used by the materials in pisun_vtol.glb
for img in bpy.data.images:
    print(f"Image: {img.name}, size: {img.size[0]}x{img.size[1]}, filepath: {img.filepath}")

# Let's check the materials
for mat in bpy.data.materials:
    print(f"Material: {mat.name}")
    if mat.use_nodes:
        for node in mat.node_tree.nodes:
            print(f"   Node: {node.name} ({node.type})")
