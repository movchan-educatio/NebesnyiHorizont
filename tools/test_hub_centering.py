import bpy
import os
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
fpath = os.path.join(GLB_DIR, "pinapipe.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=fpath)

p = bpy.data.objects.get("propeller_FL")
mw = p.matrix_world
verts_world = [mw @ v.co for v in p.data.vertices]

# Find circle of inner hole (within 5mm XY of mean)
mean_w = mathutils.Vector((
    sum(v.x for v in verts_world) / len(verts_world),
    sum(v.y for v in verts_world) / len(verts_world),
    sum(v.z for v in verts_world) / len(verts_world),
))

# Filter vertices within 4mm radius of mean in XY
inner_hole = [v for v in verts_world if (mathutils.Vector((v.x - p.location.x, v.y - p.location.y))).length < 0.004]
print(f"Inner hole vertices count: {len(inner_hole)}")
if inner_hole:
    hx = sum(v.x for v in inner_hole) / len(inner_hole)
    hy = sum(v.y for v in inner_hole) / len(inner_hole)
    hz = sum(v.z for v in inner_hole) / len(inner_hole)
    print(f"Computed hub center: ({hx:.5f}, {hy:.5f}, {hz:.5f})")
    print(f"Object location was: ({p.location.x:.5f}, {p.location.y:.5f}, {p.location.z:.5f})")
    print(f"Difference: dX={(hx-p.location.x)*1000:.3f}mm, dY={(hy-p.location.y)*1000:.3f}mm, dZ={(hz-p.location.z)*1000:.3f}mm")
