import bpy
import bmesh
import mathutils
import os

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

models = [
    "holka.glb",
    "pinapipe.glb",
    "avata2.glb",
    "pisun_vtol.glb",
    "peleng.glb",
    "grim7.glb",
    "grim7m.glb",
    "strila8.glb",
    "falcon_x.glb",
    "quad5_custom.glb"
]

print("=" * 80)
print("AUDIT OF ALL 10 DRONE PROPELLERS & HUBS")
print("=" * 80)

for m in models:
    glb_path = os.path.join(base_dir, m)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    print(f"\n>>> MODEL: {m}")
    props = [o for o in bpy.data.objects if "propeller" in o.name]
    if not props:
        print("   NO PROPELLERS FOUND!")
        continue
    for p in props:
        vcount = len(p.data.vertices) if p.type == 'MESH' else 0
        loc = list(round(c, 4) for c in p.location)
        rot = list(round(c, 4) for c in p.rotation_euler)
        if p.type == 'MESH' and vcount > 0:
            verts = [v.co for v in p.data.vertices]
            dx = max(v.x for v in verts) - min(v.x for v in verts)
            dy = max(v.y for v in verts) - min(v.y for v in verts)
            dz = max(v.z for v in verts) - min(v.z for v in verts)
            cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
            # Find center of inner hub (vertices within 10mm of center)
            inner = [v for v in verts if (v.x**2 + v.y**2)**0.5 < 0.012]
            inner_cen = sum(inner, mathutils.Vector((0,0,0))) / len(inner) if inner else cen
            print(f"   {p.name}: loc={loc}, rot={rot}, verts={vcount}, dim=[{dx:.4f}, {dy:.4f}, {dz:.4f}], local_inner_cen=({inner_cen.x:.5f}, {inner_cen.y:.5f}, {inner_cen.z:.5f})")
