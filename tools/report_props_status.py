import bpy
import os
import glob
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
# We want the 10 flight drones:
drone_files = [
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

print("======================================================================")
print("COMPREHENSIVE PROPELLER AND MOTOR SHAFT AUDIT")
print("======================================================================")

for fname in drone_files:
    fpath = os.path.join(GLB_DIR, fname)
    if not os.path.exists(fpath):
        print(f"FILE MISSING: {fname}")
        continue
        
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    all_objs = list(bpy.context.scene.objects)
    
    # Identify prop objects
    prop_names = ["propeller_FL", "propeller_FR", "propeller_BR", "propeller_BL"]
    props = {name: bpy.data.objects.get(name) for name in prop_names}
    
    # Also find any other objects with prop or vint in name
    other_props = [o.name for o in all_objs if ("prop" in o.name.lower() or "vint" in o.name.lower()) and o.name not in prop_names]
    
    print(f"\n>>> DRONE: {fname} (total objects: {len(all_objs)})")
    if other_props:
        print(f"    [NOTE] other prop-like objects: {other_props}")
        
    missing = [name for name, obj in props.items() if obj is None]
    if missing:
        print(f"    [ERROR] Missing standard prop objects: {missing}")
        
    for name in prop_names:
        p = props.get(name)
        if p is None:
            continue
            
        loc = p.location
        rot = [round(r, 4) for r in p.rotation_euler]
        scale = [round(s, 4) for s in p.scale]
        
        if p.type != 'MESH' or not p.data:
            print(f"    {name}: NOT A MESH!")
            continue
            
        verts = [v.co for v in p.data.vertices]
        if not verts:
            print(f"    {name}: EMPTY MESH (0 vertices)!")
            continue
            
        min_c = [min(v[i] for v in verts) for i in range(3)]
        max_c = [max(v[i] for v in verts) for i in range(3)]
        c_local = mathutils.Vector([(min_c[i] + max_c[i]) / 2.0 for i in range(3)])
        span = [max_c[i] - min_c[i] for i in range(3)]
        
        mw = p.matrix_world
        c_world = mw @ c_local
        
        offset_from_origin = c_local.length * 1000.0 # mm
        
        status = "OK"
        if offset_from_origin > 3.0:
            status = f"WOBBLE! Mesh offset from pivot by {offset_from_origin:.1f} mm"
        
        # Check span: Z span should be small (thickness of prop), X & Y should be prop diameter
        print(f"    {name}:")
        print(f"       Pivot Location : ({loc.x:.4f}, {loc.y:.4f}, {loc.z:.4f})  Rot: {rot}  Scale: {scale}")
        print(f"       Mesh Local Ctr : ({c_local.x:.4f}, {c_local.y:.4f}, {c_local.z:.4f}) -> {status}")
        print(f"       World Center   : ({c_world.x:.4f}, {c_world.y:.4f}, {c_world.z:.4f})")
        print(f"       Dimensions     : {span[0]*1000:.1f} x {span[1]*1000:.1f} x {span[2]*1000:.1f} mm")
