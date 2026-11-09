import bpy
import os
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

drones = [
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

def analyze_drone(fname):
    print("=" * 70)
    print(f"ANALYSIS OF DRONE: {fname}")
    print("=" * 70)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fpath = os.path.join(GLB_DIR, fname)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    # 1. Print all mesh objects
    mesh_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    print(f"Total mesh objects: {len(mesh_objs)}")
    
    # Check if motor objects exist
    motor_objs = [o for o in mesh_objs if any(k in o.name.lower() for k in ["motor", "rotor", "engine"])]
    print(f"Motor/Rotor objects found ({len(motor_objs)}): {[o.name for o in motor_objs]}")
    for mo in motor_objs:
        verts = [mo.matrix_world @ v.co for v in mo.data.vertices]
        min_c = [min(v[i] for v in verts) for i in range(3)]
        max_c = [max(v[i] for v in verts) for i in range(3)]
        span = [max_c[i] - min_c[i] for i in range(3)]
        c = [(min_c[i] + max_c[i]) / 2.0 for i in range(3)]
        print(f"  Motor Obj '{mo.name}': center=({c[0]:.4f}, {c[1]:.4f}, {c[2]:.4f}) span=({span[0]:.4f}, {span[1]:.4f}, {span[2]:.4f})")
        
    # Check propellers
    prop_objs = [o for o in mesh_objs if "propeller_" in o.name]
    print(f"Propeller objects ({len(prop_objs)}): {[o.name for o in prop_objs]}")
    for po in prop_objs:
        mw = po.matrix_world
        verts = [v.co for v in po.data.vertices]
        if not verts:
            print(f"  Prop '{po.name}': EMPTY!")
            continue
        min_c = [min(v[i] for v in verts) for i in range(3)]
        max_c = [max(v[i] for v in verts) for i in range(3)]
        c_local = mathutils.Vector([(min_c[i] + max_c[i]) / 2.0 for i in range(3)])
        c_world = mw @ c_local
        span = [max_c[i] - min_c[i] for i in range(3)]
        print(f"  Prop '{po.name}':")
        print(f"    Object location: ({po.location.x:.4f}, {po.location.y:.4f}, {po.location.z:.4f})")
        print(f"    Mesh local center: ({c_local.x:.4f}, {c_local.y:.4f}, {c_local.z:.4f}) -> offset: {c_local.length*1000:.2f} mm")
        print(f"    Mesh world center: ({c_world.x:.4f}, {c_world.y:.4f}, {c_world.z:.4f})")
        print(f"    Mesh dimensions: X={span[0]*1000:.1f}mm, Y={span[1]*1000:.1f}mm, Z={span[2]*1000:.1f}mm")

for d in drones:
    analyze_drone(d)
