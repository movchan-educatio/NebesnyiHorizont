import bpy
import bmesh
import mathutils
import os

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for m in ["grim7.glb", "grim7m.glb", "strila8.glb"]:
    glb_path = os.path.join(base_dir, m)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    print(f"\n>>> MODEL: {m}")
    props = [o for o in bpy.data.objects if "propeller" in o.name]
    for p in props:
        verts = [v.co for v in p.data.vertices]
        dx = max(v.x for v in verts) - min(v.x for v in verts)
        dy = max(v.y for v in verts) - min(v.y for v in verts)
        dz = max(v.z for v in verts) - min(v.z for v in verts)
        inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.015]
        inner_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner) if inner else mathutils.Vector((0,0,0))
        print(f"   {p.name}: loc={list(round(c, 4) for c in p.location)}, dim=[{dx:.4f}, {dy:.4f}, {dz:.4f}], local_inner_cen=({inner_cen.x:.5f}, {inner_cen.y:.5f}, {inner_cen.z:.5f})")
