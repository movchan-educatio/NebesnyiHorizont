import bpy, os

def render_model(glb_path, out_prefix):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Camera
    cam_data = bpy.data.cameras.new(name='Cam')
    cam_obj = bpy.data.objects.new('Cam', cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Sun 1
    l1 = bpy.data.lights.new(name='L1', type='SUN')
    l1.energy = 3.0
    lo1 = bpy.data.objects.new('LO1', l1)
    bpy.context.scene.collection.objects.link(lo1)
    lo1.location = (2, 2, 5)
    
    # Sun 2 (fill)
    l2 = bpy.data.lights.new(name='L2', type='SUN')
    l2.energy = 1.5
    lo2 = bpy.data.objects.new('LO2', l2)
    bpy.context.scene.collection.objects.link(lo2)
    lo2.location = (-2, -2, -3)
    
    bpy.context.scene.render.resolution_x = 800
    bpy.context.scene.render.resolution_y = 800
    out_dir = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522"
    
    # Top view
    cam_obj.location = (0, 0, 0.8)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.render.filepath = os.path.join(out_dir, f"{out_prefix}_top.png")
    bpy.ops.render.render(write_still=True)
    
    # Iso view
    cam_obj.location = (0.35, -0.35, 0.35)
    cam_obj.rotation_euler = (0.9553, 0.0, 0.7854)
    bpy.context.scene.render.filepath = os.path.join(out_dir, f"{out_prefix}_iso.png")
    bpy.ops.render.render(write_still=True)

base = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
for name in ["pisun_vtol", "falcon_x", "peleng", "avata2", "quad5_custom"]:
    path = os.path.join(base, f"{name}.glb")
    render_model(path, f"verify_{name}")
print("ALL VERIFICATION RENDERS COMPLETE!")
