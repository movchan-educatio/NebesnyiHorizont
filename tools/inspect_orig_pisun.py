import bpy
import mathutils
import os

path = r"C:\Users\USER_UA\Desktop\Новий симулятор\Моделі дронів\d1l-duck_-_ukrainian_tailsitter_vtol_fpv_quad.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

print("=" * 80)
print("ORIGINAL PISUN VTOL SOURCE:")
for obj in bpy.data.objects:
    dim = [round(d, 4) for d in obj.dimensions] if obj.type == 'MESH' else []
    loc = [round(l, 4) for l in obj.location]
    rot = [round(r, 4) for r in obj.rotation_euler]
    scl = [round(s, 4) for s in obj.scale]
    p_name = obj.parent.name if obj.parent else "None"
    print(f"[{obj.type}] {obj.name} | parent={p_name} | loc={loc} | rot={rot} | scl={scl} | dim={dim}")
    if "prop" in obj.name.lower() or "blade" in obj.name.lower() or "motor" in obj.name.lower():
        verts = [v.co for v in obj.data.vertices]
        if verts:
            print(f"   verts count: {len(verts)}")
            cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
            print(f"   local center: {cen}")
            w_cen = obj.matrix_world @ cen
            print(f"   world center: {w_cen}")
