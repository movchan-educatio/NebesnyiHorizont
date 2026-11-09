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

def find_quadrant_motors(fname):
    print("=" * 60)
    print(f"FINDING MOTORS FOR: {fname}")
    print("=" * 60)
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fpath = os.path.join(GLB_DIR, fname)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    # Check all non-propeller meshes
    all_objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    
    # First, let's look at existing propeller positions to know roughly where the 4 corners are
    props = {name: bpy.data.objects.get(name) for name in ["propeller_FL", "propeller_FR", "propeller_BR", "propeller_BL"]}
    
    # For each quadrant (FL: X<0, Y>0; FR: X>0, Y>0; BR: X>0, Y<0; BL: X<0, Y<0):
    # Wait, pisun_vtol is a cross (+ configuration):
    # FL: X < -0.05
    # FR: X > 0.05
    # BR: Y < -0.05
    # BL: Y > 0.05
    
    # Collect all vertices from all non-propeller objects
    non_prop_objs = [o for o in all_objs if not o.name.startswith("propeller_") and not "vint_" in o.name]
    
    # Look for motor / rotor objects specifically if they exist
    motor_objs = [o for o in non_prop_objs if any(k in o.name.lower() for k in ["rotor", "motor", "engine"])]
    print(f"Motor objects: {[o.name for o in motor_objs]}")
    
    quadrants = {}
    if fname == "pisun_vtol.glb":
        quadrants = {
            "FL": lambda x, y: x < -0.08 and abs(y) < 0.06,
            "FR": lambda x, y: x > 0.08 and abs(y) < 0.06,
            "BR": lambda x, y: y < -0.08 and abs(x) < 0.06,
            "BL": lambda x, y: y > 0.08 and abs(x) < 0.06,
        }
    elif fname == "falcon_x.glb":
        # Check scale first!
        # If falcon_x is in mm or meters:
        max_dim = max(max(abs(v.co.x), abs(v.co.y), abs(v.co.z)) for o in non_prop_objs for v in o.data.vertices)
        print(f"falcon_x max dimension: {max_dim}")
        # Note in falcon_x: forward/back signs
        quadrants = {
            "FL": lambda x, y: x > 0.04 and y < -0.01,
            "FR": lambda x, y: x < -0.04 and y < -0.01,
            "BR": lambda x, y: x > 0.04 and y > 0.01,
            "BL": lambda x, y: x < -0.04 and y > 0.01,
        }
    else:
        quadrants = {
            "FL": lambda x, y: x < -0.03 and y > 0.03,
            "FR": lambda x, y: x > 0.03 and y > 0.03,
            "BR": lambda x, y: x > 0.03 and y < -0.03,
            "BL": lambda x, y: x < -0.03 and y < -0.03,
        }
        
    for qname, qcond in quadrants.items():
        # Find all vertices belonging to motor / frame in this region
        qverts = []
        for o in non_prop_objs:
            mw = o.matrix_world
            for v in o.data.vertices:
                wv = mw @ v.co
                if qcond(wv.x, wv.y):
                    qverts.append(wv)
        if not qverts:
            print(f"  {qname}: NO VERTICES FOUND!")
            continue
            
        # Top of the motor (highest Z in this quadrant)
        max_z = max(v.z for v in qverts)
        # Vertices within 8mm of max_z
        top_verts = [v for v in qverts if v.z > max_z - 0.008]
        
        # Center of these top vertices
        cx = sum(v.x for v in top_verts) / len(top_verts)
        cy = sum(v.y for v in top_verts) / len(top_verts)
        cz = max_z
        
        # Let's refine by finding the cylinder center: vertices within 15mm radius of (cx, cy)
        cyl_verts = [v for v in qverts if (mathutils.Vector((v.x - cx, v.y - cy))).length < 0.015 and v.z > max_z - 0.015]
        if cyl_verts:
            cyl_cx = sum(v.x for v in cyl_verts) / len(cyl_verts)
            cyl_cy = sum(v.y for v in cyl_verts) / len(cyl_verts)
        else:
            cyl_cx, cyl_cy = cx, cy
            
        print(f"  {qname}: motor top center = ({cyl_cx:.4f}, {cyl_cy:.4f}, {cz:.4f})  (max_z={max_z:.4f}, {len(cyl_verts)} motor verts)")

for d in drones:
    find_quadrant_motors(d)
