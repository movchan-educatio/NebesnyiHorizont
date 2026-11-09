## render_topdown.py — orthographic top-down render of the open blend file.
import bpy

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 1280
scene.render.resolution_y = 1280
scene.render.film_transparent = False
scene.display.shading.light = "FLAT"

cam_data = bpy.data.cameras.new("TopCam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 900.0
cam = bpy.data.objects.new("TopCam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0, 0, 500)
cam.rotation_euler = (0, 0, 0)
scene.camera = cam

sun_data = bpy.data.lights.new("Sun", type="SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("Sun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (0.9, 0.0, 0.5)

scene.render.filepath = r"C:\Users\USER_UA\Desktop\Новий симулятор\merged_topdown.png"
bpy.ops.render.render(write_still=True)
print("WROTE TOPDOWN")
