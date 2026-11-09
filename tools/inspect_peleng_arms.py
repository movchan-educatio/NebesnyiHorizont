import bpy
import os
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
fpath = os.path.join(GLB_DIR, "peleng.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=fpath)

body = bpy.data.objects.get("peleng_body")
# Look at outermost vertices in peleng_body
verts = [v.co for v in body.data.vertices]
# FL arm
fl_verts = [v for v in verts if v.x < -0.05 and v.y > 0.04]
fr_verts = [v for v in verts if v.x > 0.05 and v.y > 0.04]
br_verts = [v for v in verts if v.x > 0.05 and v.y < -0.04]
bl_verts = [v for v in verts if v.x < -0.05 and v.y < -0.04]

def find_tip(qverts):
    # outermost tip
    sorted_by_dist = sorted(qverts, key=lambda v: (v.x**2 + v.y**2), reverse=True)
    outer = sorted_by_dist[:100]
    cx = sum(v.x for v in outer) / len(outer)
    cy = sum(v.y for v in outer) / len(outer)
    cz = sum(v.z for v in outer) / len(outer)
    return cx, cy, cz, max(v.z for v in outer)

print("PELENG ARM TIPS:")
print("FL:", find_tip(fl_verts))
print("FR:", find_tip(fr_verts))
print("BR:", find_tip(br_verts))
print("BL:", find_tip(bl_verts))
