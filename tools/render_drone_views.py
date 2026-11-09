import bpy
import mathutils
import math
import os

def render_model_views(glb_path, out_prefix):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Setup camera
    cam_data = bpy.data.cameras.new("Cam")
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Setup lights
    light_data = bpy.data.lights.new("Sun", type='SUN')
    light_data.energy = 3.0
    light_obj = bpy.data.objects.new("Sun", light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(30), math.radians(45))

    light_data2 = bpy.data.lights.new("SunFill", type='SUN')
    light_data2.energy = 1.5
    light_obj2 = bpy.data.objects.new("SunFill", light_data2)
    bpy.context.scene.collection.objects.link(light_obj2)
    light_obj2.rotation_euler = (math.radians(-45), math.radians(-30), math.radians(-45))
    
    bpy.context.scene.render.resolution_x = 800
    bpy.context.scene.render.resolution_y = 600
    bpy.context.scene.render.engine = 'BLENDER_WORKBENCH'
    bpy.context.scene.display.shading.color_type = 'MATERIAL'
    bpy.context.scene.display.shading.light = 'STUDIO'
    
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    if not meshes:
        return
        
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
    
    views = [
        ("top", center + mathutils.Vector((0, 0, size * 2.2)), (0, 0, 0)),
        ("side", center + mathutils.Vector((size * 2.2, 0, 0)), (math.radians(90), 0, math.radians(90))),
        ("front", center + mathutils.Vector((0, -size * 2.2, 0)), (math.radians(90), 0, 0)),
        ("iso", center + mathutils.Vector((size * 1.5, -size * 1.5, size * 1.2)), (math.radians(55), 0, math.radians(45))),
    ]
    
    out_dir = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522"
    for vname, pos, rot in views:
        cam_obj.location = pos
        direction = center - pos
        rot_quat = direction.to_track_quat('-Z', 'Y')
        cam_obj.rotation_euler = rot_quat.to_euler()
        bpy.context.scene.render.filepath = os.path.join(out_dir, f"{out_prefix}_{vname}.png")
        bpy.ops.render.render(write_still=True)
        print(f"Rendered {out_prefix}_{vname}.png")

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
for m in ["pisun_vtol.glb", "falcon_x.glb", "peleng.glb", "holka.glb"]:
    prefix = "inspect_" + m.replace(".glb", "")
    render_model_views(os.path.join(base_dir, m), prefix)
