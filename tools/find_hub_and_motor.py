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

for fname in drones:
    fpath = os.path.join(GLB_DIR, fname)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    p = bpy.data.objects.get("propeller_FL")
    if not p:
        print(f"{fname}: propeller_FL NOT FOUND!")
        continue
        
    mw = p.matrix_world
    verts_world = [mw @ v.co for v in p.data.vertices]
    
    # Let's find vertices close to the hub (e.g. within 10mm of the object location in XY)
    loc = p.location
    near_hub = [v for v in verts_world if (mathutils.Vector((v.x - loc.x, v.y - loc.y))).length < 0.008] # within 8mm
    
    print(f"\n--- {fname} propeller_FL ---")
    print(f"  Object location (Blender): ({loc.x:.4f}, {loc.y:.4f}, {loc.z:.4f})")
    print(f"  Near hub vertices: {len(near_hub)} / {len(verts_world)}")
    if near_hub:
        # Find the center of these hub vertices
        hub_x = sum(v.x for v in near_hub) / len(near_hub)
        hub_y = sum(v.y for v in near_hub) / len(near_hub)
        hub_z = sum(v.z for v in near_hub) / len(near_hub)
        print(f"  Hub center (mean of near-hub verts): ({hub_x:.4f}, {hub_y:.4f}, {hub_z:.4f})")
        print(f"  Difference from obj loc: dX={(hub_x-loc.x)*1000:.2f}mm, dY={(hub_y-loc.y)*1000:.2f}mm, dZ={(hub_z-loc.z)*1000:.2f}mm")
    
    # Also find motor position from the frame/motor objects
    # Let's check objects near this location
    all_other_mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH' and not o.name.startswith("propeller_")]
    nearby_motor_verts = []
    for o in all_other_mesh:
        omw = o.matrix_world
        for v in o.data.vertices:
            wv = omw @ v.co
            if (mathutils.Vector((wv.x - loc.x, wv.y - loc.y))).length < 0.018 and abs(wv.z - loc.z) < 0.030:
                nearby_motor_verts.append(wv)
                
    if nearby_motor_verts:
        # Motor top vertices
        max_mz = max(v.z for v in nearby_motor_verts)
        top_verts = [v for v in nearby_motor_verts if v.z > max_mz - 0.004]
        motor_x = sum(v.x for v in top_verts) / len(top_verts)
        motor_y = sum(v.y for v in top_verts) / len(top_verts)
        print(f"  Motor shaft/top center: ({motor_x:.4f}, {motor_y:.4f}, {max_mz:.4f})")
        print(f"  Difference motor to prop loc: dX={(motor_x-loc.x)*1000:.2f}mm, dY={(motor_y-loc.y)*1000:.2f}mm, dZ={(max_mz-loc.z)*1000:.2f}mm")
    else:
        print(f"  No frame/motor vertices found within 18mm XY of prop location!")
