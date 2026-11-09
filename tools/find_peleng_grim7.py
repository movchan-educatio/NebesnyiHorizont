import bpy
import os
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for fname in ["peleng.glb", "grim7.glb"]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    fpath = os.path.join(GLB_DIR, fname)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    print("\n" + "=" * 60)
    print(f"DETAILED MOTOR CYLINDER SEARCH: {fname}")
    print("=" * 60)
    
    # Check all objects
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            print(f"  Object: '{o.name}' verts={len(o.data.vertices)} loc={o.location}")
            
    # For peleng and grim7, let's find the circular vertex rings on the arms
    # by searching around X ~ +/- 0.07-0.14, Y ~ +/- 0.07-0.12
    all_verts = []
    for o in bpy.context.scene.objects:
        if o.type == 'MESH' and not o.name.startswith("propeller_") and not "pg7l" in o.name.lower():
            mw = o.matrix_world
            for v in o.data.vertices:
                all_verts.append((mw @ v.co, o.name))
                
    # Search around 4 corners
    targets = [
        ("FL", -0.07, 0.07),
        ("FR", 0.07, 0.07),
        ("BR", 0.07, -0.09),
        ("BL", -0.07, -0.09),
    ]
    for tag, tx, ty in targets:
        # Find verts within 40mm of this target
        near = [v for v, name in all_verts if (mathutils.Vector((v.x - tx, v.y - ty))).length < 0.05 and abs(v.z) < 0.05]
        if near:
            # Group by Z or find highest cluster
            max_z = max(v.z for v in near)
            # Find circular ring: cluster with highest density
            top = [v for v in near if v.z > max_z - 0.008]
            cx = sum(v.x for v in top) / len(top)
            cy = sum(v.y for v in top) / len(top)
            # Refine circle center
            circle = [v for v in near if (mathutils.Vector((v.x - cx, v.y - cy))).length < 0.015]
            if circle:
                ccx = sum(v.x for v in circle) / len(circle)
                ccy = sum(v.y for v in circle) / len(circle)
                ccz = max(v.z for v in circle)
                print(f"  Corner {tag}: center=({ccx:.4f}, {ccy:.4f}, {ccz:.4f}) (found {len(circle)} verts)")
