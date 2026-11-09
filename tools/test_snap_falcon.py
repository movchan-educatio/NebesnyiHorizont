import bpy, math
import numpy as np

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

def render_views(drone_name, cam_obj, center, radius):
    bpy.context.scene.render.resolution_x = 800
    bpy.context.scene.render.resolution_y = 600
    
    # 1. Top view
    cam_obj.location = (center[0], center[1], center[2] + radius * 2.5)
    cam_obj.rotation_euler = (0, 0, 0)
    bpy.context.scene.render.filepath = rf"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\test_snap_{drone_name}_top.png"
    bpy.ops.render.render(write_still=True)
    
    # 2. Perspective ISO view
    cam_obj.location = (center[0] + radius * 1.8, center[1] - radius * 1.8, center[2] + radius * 1.5)
    # Point towards center
    dx = center[0] - cam_obj.location[0]
    dy = center[1] - cam_obj.location[1]
    dz = center[2] - cam_obj.location[2]
    dist = math.sqrt(dx*dx + dy*dy + dz*dz)
    pitch = math.asin(dz / dist)
    yaw = math.atan2(dx, -dy)
    cam_obj.rotation_euler = (math.radians(55), 0, math.radians(45))
    bpy.context.scene.render.filepath = rf"C:\Users\USER_UA\.gemini\antigravity\brain\978b47c4-dcc4-4721-b5bc-159b55cf7522\test_snap_{drone_name}_iso.png"
    bpy.ops.render.render(write_still=True)

# Test Falcon-X snap
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb")

# Detected centers for falcon_x:
# FL: (-0.0994, -0.0517, 0.0360), norm=(0.02, 0.17, 0.98)
# FR: ( 0.0994, -0.0517, 0.0360), norm=(-0.02, 0.17, 0.98)
# BL: (-0.0965,  0.0615, 0.1186), norm=(0.06, 0.09, 0.99)
# BR: ( 0.0965,  0.0615, 0.1186), norm=(-0.06, 0.09, 0.99)
falcon_snaps = {
    'propeller_FL': ((-0.0994, -0.0517, 0.0360), (0.02, 0.17, 0.98)),
    'propeller_FR': (( 0.0994, -0.0517, 0.0360), (-0.02, 0.17, 0.98)),
    'propeller_BL': ((-0.0965,  0.0615, 0.1186), (0.06, 0.09, 0.99)),
    'propeller_BR': (( 0.0965,  0.0615, 0.1186), (-0.06, 0.09, 0.99)),
}

for pname, (pos, norm) in falcon_snaps.items():
    p = bpy.data.objects.get(pname)
    if p:
        p.location = pos
        # Align Z axis with normal
        nz = math.atan2(math.hypot(norm[0], norm[1]), norm[2])
        # Simple pitch/roll:
        p.rotation_euler = (math.atan2(norm[1], norm[2]), -math.atan2(norm[0], norm[2]), 0)

cam = setup_camera_and_lights()
render_views("falcon_x", cam, (0, 0, 0.07), 0.18)
print("Rendered falcon_x test snaps!")
