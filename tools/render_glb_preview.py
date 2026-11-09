"""Render a GLB model to a PNG for QA. Run with Blender -b --python."""
import bpy
import math
import os
import sys

argv = sys.argv
if "--" in argv:
    argv = argv[argv.index("--") + 1:]
else:
    argv = []
src = argv[0] if len(argv) > 0 else ""
out = argv[1] if len(argv) > 1 else "C:/Users/USER_UA/AppData/Local/Temp/opencode/blender_preview.png"
anim = argv[2] if len(argv) > 2 else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
if anim:
    target_action = bpy.data.actions.get(anim)
    if target_action is not None:
        for obj in bpy.data.objects:
            if obj.type == 'ARMATURE':
                if obj.animation_data is None:
                    obj.animation_data_create()
                obj.animation_data.action = target_action
                # Disable NLA so the requested action is authoritative.
                for track in obj.animation_data.nla_tracks:
                    track.mute = True
    frame = int(os.environ.get("RENDER_FRAME", "5"))
    bpy.context.scene.frame_set(frame)

# Compute combined bounds of mesh objects in world space.
mn = [1e18, 1e18, 1e18]
mx = [-1e18, -1e18, -1e18]
for obj in bpy.data.objects:
    if obj.type != 'MESH':
        continue
    for corner in obj.bound_box:
        p = obj.matrix_world @ __import__('mathutils').Vector(corner)
        for i in range(3):
            mn[i] = min(mn[i], p[i])
            mx[i] = max(mx[i], p[i])
center = [(mn[i] + mx[i]) * 0.5 for i in range(3)]
size = max(mx[i] - mn[i] for i in range(3))
if size < 0.001:
    size = 2.0
print("[RENDER] bounds", mn, mx, "size", size)

# Move model so its feet are at z=0 and center x/y at 0.
for obj in bpy.data.objects:
    if obj.parent is None:
        obj.location.x -= center[0]
        obj.location.y -= center[1]
        obj.location.z -= mn[2]

# Camera at three-quarter front.
cam_data = bpy.data.cameras.new("QACam")
cam = bpy.data.objects.new("QACam", cam_data)
bpy.context.collection.objects.link(cam)
dist = size * 1.6
cx = dist * 0.8
cy = -dist * 1.0
cz = size * 0.75
cam.location = (cx, cy, cz)
target = (0.0, 0.0, size * 0.45)
direction = (target[0] - cx, target[1] - cy, target[2] - cz)
import mathutils
cam.rotation_euler = mathutils.Vector(direction).to_track_quat('-Z', 'Y').to_euler()
bpy.context.scene.camera = cam

# Three-point lighting.
def add_area(name, loc, energy, color, size_):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = energy
    data.color = color
    data.size = size_
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    d = (0.0, 0.0, size * 0.45)
    direction = (d[0] - loc[0], d[1] - loc[1], d[2] - loc[2])
    obj.rotation_euler = mathutils.Vector(direction).to_track_quat('-Z', 'Y').to_euler()
    return obj

add_area("Key", (size * 1.6, -size * 1.8, size * 2.4), 600 * size * size, (1.0, 0.95, 0.86), size)
add_area("Fill", (-size * 2.0, -size * 1.2, size * 1.2), 220 * size * size, (0.72, 0.82, 1.0), size)
add_area("Rim", (-size * 0.4, size * 2.2, size * 2.0), 400 * size * size, (1.0, 0.86, 0.72), size)

# Ground plane.
bpy.ops.mesh.primitive_plane_add(size=size * 20, location=(0, 0, 0))
ground = bpy.context.object
mat = bpy.data.materials.new("Ground")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.22, 0.22, 0.2, 1)
bsdf.inputs["Roughness"].default_value = 0.92
ground.data.materials.append(mat)

world = bpy.data.worlds.new("QAWorld")
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs[0].default_value = (0.05, 0.06, 0.08, 1)
bg.inputs[1].default_value = 0.45
bpy.context.scene.world = world

scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_x = 900
scene.render.resolution_y = 650
scene.render.film_transparent = False
scene.render.image_settings.file_format = 'PNG'
scene.render.filepath = out
scene.render.image_settings.color_mode = 'RGBA'
bpy.ops.render.render(write_still=True)
print("[RENDER] saved", out)
