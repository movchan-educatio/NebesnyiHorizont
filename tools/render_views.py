## render_views.py — aerial + street views framed from real scene bounds.
import bpy
from mathutils import Vector

scene = bpy.context.scene
scene.render.engine = "BLENDER_WORKBENCH"
scene.render.resolution_x = 1280
scene.render.resolution_y = 720
scene.render.film_transparent = False
scene.display.shading.light = "STUDIO"

bpy.context.view_layer.update()
mn = Vector((1e18, 1e18, 1e18))
mx = Vector((-1e18, -1e18, -1e18))
n = 0
for o in scene.objects:
    if o.type != "MESH" or not o.data.vertices:
        continue
    for v in o.data.vertices:
        w = o.matrix_world @ v.co
        mn = Vector((min(mn[i], w[i]) for i in range(3)))
        mx = Vector((max(mx[i], w[i]) for i in range(3)))
        n += 1
center = (mn + mx) / 2
size = mx - mn
print("VERTS", n, "BOUNDS min", tuple(round(float(v), 1) for v in mn),
      "max", tuple(round(float(v), 1) for v in mx))

sun_data = bpy.data.lights.new("Sun2", type="SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("Sun2", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (0.9, 0.0, 0.5)


def shoot(name, loc, target, ortho_scale=0.0):
    for o in list(scene.objects):
        if o.name.startswith("Shot"):
            bpy.data.objects.remove(o, do_unlink=True)
    cd = bpy.data.cameras.new("ShotCam")
    cam = bpy.data.objects.new("ShotCam", cd)
    scene.collection.objects.link(cam)
    cam.location = Vector(loc)
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho_scale > 0.0:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho_scale
    else:
        cd.type = "PERSP"
        cd.clip_start = 0.5
        cd.clip_end = 30000.0
    scene.camera = cam
    scene.render.filepath = (
        r"C:\Users\USER_UA\Desktop\Новий симулятор\merged_" + name + ".png")
    bpy.ops.render.render(write_still=True)
    print("WROTE", name)


diag = max(size.x, size.y)
shoot("aerial", (center.x, center.y, center.z + diag * 1.1),
      center, ortho_scale=diag * 1.15)
shoot("street", (center.x, center.y - diag * 0.35, 40.0),
      (center.x, center.y + diag * 0.3, 60.0))
