import bpy, math

def setup_camera_and_lights():
    cam_data = bpy.data.cameras.new("Cam")
    cam_obj = bpy.data.objects.new("Cam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    bpy.context.scene.camera = cam_obj

    light_data = bpy.data.lights.new("Sun", type='SUN')
    light_obj = bpy.data.objects.new("Sun", light_data)
    bpy.context.scene.collection.objects.link(light_obj)
    light_obj.rotation_euler = (math.radians(45), math.radians(30), math.radians(45))
    light_data.energy = 4.0

    fill_data = bpy.data.lights.new("Fill", type='SUN')
    fill_obj = bpy.data.objects.new("Fill", fill_data)
    bpy.context.scene.collection.objects.link(fill_obj)
    fill_obj.rotation_euler = (math.radians(-45), math.radians(-30), math.radians(-45))
    fill_data.energy = 2.0
    return cam_obj

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\peleng.glb")

peleng_snaps = {
    'propeller_FL': (-0.088,  0.064, 0.002),
    'propeller_FR': ( 0.088,  0.064, 0.002),
    'propeller_BL': (-0.069, -0.074, 0.013),
    'propeller_BR': ( 0.069, -0.074, 0.013),
}

for pname, pos in peleng_snaps.items():
    p = bpy.data.objects.get(pname)
    if p:
        p.location = pos

cam = setup_camera_and_lights()
cam.location = (0.25, -0.25, 0.20)
cam.rotation_euler = (math.radians(60), 0, math.radians(45))
bpy.context.scene.render.filepath = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\test_peleng_correct.png"
bpy.ops.render.render(write_still=True)
print("Rendered test_peleng_correct.png")
