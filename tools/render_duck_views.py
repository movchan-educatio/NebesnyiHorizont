import bpy, math

bpy.ops.wm.read_factory_settings(use_empty=True)
p = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\d1l-duck_-_ukrainian_tailsitter_vtol_fpv_quad.glb"
bpy.ops.import_scene.gltf(filepath=p)

# Create camera and lights
cam_data = bpy.data.cameras.new("Cam")
cam_obj = bpy.data.objects.new("Cam", cam_data)
bpy.context.scene.collection.objects.link(cam_obj)
bpy.context.scene.camera = cam_obj

light_data = bpy.data.lights.new("Light", type='SUN')
light_obj = bpy.data.objects.new("Light", light_data)
bpy.context.scene.collection.objects.link(light_obj)
light_obj.rotation_euler = (math.radians(45), math.radians(30), math.radians(45))
light_data.energy = 3.0

bpy.context.scene.render.resolution_x = 800
bpy.context.scene.render.resolution_y = 600

# View 1: Isometric
cam_obj.location = (2.5, -2.5, 2.0)
cam_obj.rotation_euler = (math.radians(60), 0, math.radians(45))
bpy.context.scene.render.filepath = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\duck_iso.png"
bpy.ops.render.render(write_still=True)

# View 2: Side view (looking at X from side)
cam_obj.location = (3.5, 0, 0)
cam_obj.rotation_euler = (math.radians(90), 0, math.radians(90))
bpy.context.scene.render.filepath = r"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\duck_side.png"
bpy.ops.render.render(write_still=True)

print("Rendered duck_iso.png and duck_side.png")
