import bpy, mathutils
import numpy as np

def fit_circle_3d(points):
    pts = np.array(points)
    cen = pts.mean(axis=0)
    return cen

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

o3 = bpy.data.objects['Object_3']
verts = np.array([v.co for v in o3.data.vertices])

# Pisun has 4 motor nacelles at tips of wings
# Wings extend along +X, -X, +Y, -Y
for tag, cond in [
    ("Right Wing (+X)", verts[:, 0] > 0.11),
    ("Left Wing (-X)", verts[:, 0] < -0.11),
    ("Top Wing (+Y)", verts[:, 1] > 0.11),
    ("Bottom Wing (-Y)", verts[:, 1] < -0.11),
]:
    w_verts = verts[cond]
    # Motor mount is at the tip where Z is near the top of the nacelle
    # Z range of nacelle tip
    max_z = w_verts[:, 2].max()
    tip_verts = w_verts[w_verts[:, 2] > max_z - 0.01]
    cen = tip_verts.mean(axis=0)
    print(f"{tag}: tip_verts={len(tip_verts)}, motor_center=({cen[0]:.4f}, {cen[1]:.4f}, {cen[2]:.4f})")
