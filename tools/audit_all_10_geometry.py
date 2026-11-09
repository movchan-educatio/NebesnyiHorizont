import bpy, os, mathutils, math

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
models = [
    "pisun_vtol.glb",
    "falcon_x.glb",
    "peleng.glb",
    "avata2.glb",
    "quad5_custom.glb",
    "grim7.glb",
    "grim7m.glb",
    "strila8.glb",
    "holka.glb",
    "pinapipe.glb"
]

print("="*80)
print("COMPREHENSIVE GEOMETRIC AUDIT OF ALL 10 DRONES")
print("="*80)

for m in models:
    path = os.path.join(base_dir, m)
    if not os.path.exists(path):
        print(f"[MISSING] {m}")
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    
    props = [o for o in bpy.data.objects if o.name.startswith("propeller_")]
    body_objs = [o for o in bpy.data.objects if not o.name.startswith("propeller_") and o.type == 'MESH']
    empties = [o for o in bpy.data.objects if o.type == 'EMPTY']
    
    print(f"\n>>> {m}:")
    print(f"    Body meshes ({len(body_objs)}): {[b.name for b in body_objs]}")
    print(f"    Empties ({len(empties)}): {[e.name for e in empties]}")
    print(f"    Propellers ({len(props)}):")
    for p in sorted(props, key=lambda x: x.name):
        verts = [v.co for v in p.data.vertices]
        min_x, max_x = min(v.x for v in verts), max(v.x for v in verts)
        min_y, max_y = min(v.y for v in verts), max(v.y for v in verts)
        min_z, max_z = min(v.z for v in verts), max(v.z for v in verts)
        loc = [round(c, 4) for c in p.location]
        rot = [round(math.degrees(c), 1) for c in p.rotation_euler]
        scl = [round(c, 4) for c in p.scale]
        print(f"      {p.name}: loc={loc} rot_deg={rot} scl={scl} local_X=[{min_x:.4f}, {max_x:.4f}] local_Y=[{min_y:.4f}, {max_y:.4f}] local_Z=[{min_z:.4f}, {max_z:.4f}]")
