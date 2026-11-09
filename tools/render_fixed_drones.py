import bpy
import mathutils
import math
import os

out_dir = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522"
base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

def render_fixed_views(glb_name, out_name):
    glb_path = os.path.join(base_dir, glb_name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Setup camera
    cam_data = bpy.data.cameras.new("Cam")
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Setup lights
    light_data = bpy.data.lights.new("Sun1", type='SUN')
    light_data.energy = 3.5
    light_obj = bpy.data.objects.new("Sun1", light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(30), math.radians(45))

    light_data2 = bpy.data.lights.new("Sun2", type='SUN')
    light_data2.energy = 2.0
    light_obj2 = bpy.data.objects.new("Sun2", light_data2)
    bpy.context.scene.collection.objects.link(light_obj2)
    light_obj2.rotation_euler = (math.radians(-45), math.radians(-30), math.radians(-45))
    
    bpy.context.scene.render.resolution_x = 960
    bpy.context.scene.render.resolution_y = 640
    bpy.context.scene.render.engine = 'BLENDER_WORKBENCH'
    bpy.context.scene.display.shading.color_type = 'MATERIAL'
    bpy.context.scene.display.shading.light = 'STUDIO'
    
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    all_coords = []
    for m in meshes:
        for v in m.bound_box:
            all_coords.append(m.matrix_world @ mathutils.Vector(v))
            
    min_x = min(c.x for c in all_coords)
    max_x = max(c.x for c in all_coords)
    min_y = min(c.y for c in all_coords)
    max_y = max(c.y for c in all_coords)
    min_z = min(c.z for c in all_coords)
    max_z = max(c.z for c in all_coords)
    center = mathutils.Vector(((min_x + max_x)/2, (min_y + max_y)/2, (min_z + max_z)/2))
    size = max(max_x - min_x, max_y - min_y, max_z - min_z)
    
    # 1. Perspective view (similar to Godot main menu)
    pos_iso = center + mathutils.Vector((size * 1.4, -size * 1.6, size * 1.1))
    cam_obj.location = pos_iso
    cam_obj.rotation_euler = (center - pos_iso).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = os.path.join(out_dir, f"{out_name}_iso.png")
    bpy.ops.render.render(write_still=True)
    
    # 2. Top view (showing all 4 motors and props alignment)
    pos_top = center + mathutils.Vector((0, 0, size * 2.2))
    cam_obj.location = pos_top
    cam_obj.rotation_euler = (center - pos_top).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.render.filepath = os.path.join(out_dir, f"{out_name}_top.png")
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {out_name} iso and top views.")

for gname, oname in [
    ("avata2.glb", "fixed_avata2"),
    ("falcon_x.glb", "fixed_falcon_x"),
    ("peleng.glb", "fixed_peleng"),
    ("holka.glb", "fixed_holka"),
    ("pisun_vtol.glb", "fixed_pisun_vtol"),
]:
    render_fixed_views(gname, oname)
