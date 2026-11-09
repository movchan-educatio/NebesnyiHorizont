import bpy, os, math

def render_drone_preview(filename, out_name):
    base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
    filepath = os.path.join(base_dir, filename)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    # Camera
    cam_data = bpy.data.cameras.new("Cam")
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj
    
    # Tactical terminal turntable camera angle:
    # Cam pitch ~ 25 deg, Yaw ~ 45 deg
    cam_obj.location = (0.28, -0.28, 0.22)
    cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
    cam_data.lens = 50.0

    # Lighting
    sun_data = bpy.data.lights.new("Sun", type='SUN')
    sun_obj = bpy.data.objects.new("Sun", sun_data)
    bpy.context.scene.collection.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(45), math.radians(30), math.radians(45))
    sun_data.energy = 4.0

    fill_data = bpy.data.lights.new("Fill", type='SUN')
    fill_obj = bpy.data.objects.new("Fill", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(-45), math.radians(-30), math.radians(-45))
    fill_data.energy = 2.0
    
    bpy.context.scene.render.resolution_x = 800
    bpy.context.scene.render.resolution_y = 600
    
    out_path = rf"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\{out_name}.png"
    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f"Rendered {out_name} to {out_path}")

render_drone_preview("falcon_x.glb", "final_preview_falcon_x")
render_drone_preview("peleng.glb", "final_preview_peleng")
render_drone_preview("pisun_vtol.glb", "final_preview_pisun")
render_drone_preview("avata2.glb", "final_preview_avata2")
