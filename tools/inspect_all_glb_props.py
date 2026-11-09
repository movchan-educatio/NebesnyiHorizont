import bpy
import os
import glob
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
glb_files = sorted(glob.glob(os.path.join(GLB_DIR, "*.glb")))

print(f"Found {len(glb_files)} GLB files in {GLB_DIR}")

for glb_path in glb_files:
    fname = os.path.basename(glb_path)
    print("\n" + "=" * 60)
    print(f"INSPECTING: {fname}")
    print("=" * 60)
    
    # Clear scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    # Import GLB
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    # Check objects
    all_objs = list(bpy.context.scene.objects)
    print(f"Total objects: {len(all_objs)}")
    
    prop_objs = [obj for obj in all_objs if "prop" in obj.name.lower() or "vint" in obj.name.lower()]
    print(f"Propeller candidate objects ({len(prop_objs)}):")
    for p in prop_objs:
        loc = p.location
        rot_e = [round(r, 4) for r in p.rotation_euler]
        scale = [round(s, 4) for s in p.scale]
        
        # Check mesh bounds relative to object origin
        if p.type == 'MESH' and p.data:
            verts = [v.co for v in p.data.vertices]
            if verts:
                min_c = [min(v[i] for v in verts) for i in range(3)]
                max_c = [max(v[i] for v in verts) for i in range(3)]
                center_local = [(min_c[i] + max_c[i]) / 2.0 for i in range(3)]
                span = [max_c[i] - min_c[i] for i in range(3)]
                
                # Global vertex center
                mw = p.matrix_world
                center_global = mw @ mathutils.Vector(center_local)
                
                print(f"  - '{p.name}' (parent: {p.parent.name if p.parent else 'None'})")
                print(f"      Obj Loc: ({loc.x:.4f}, {loc.y:.4f}, {loc.z:.4f})")
                print(f"      Obj RotEuler: {rot_e}, Scale: {scale}")
                print(f"      Mesh Local Center: ({center_local[0]:.4f}, {center_local[1]:.4f}, {center_local[2]:.4f})")
                print(f"      Mesh Span (X,Y,Z): ({span[0]:.4f}, {span[1]:.4f}, {span[2]:.4f})")
                print(f"      World Mesh Center: ({center_global.x:.4f}, {center_global.y:.4f}, {center_global.z:.4f})")
                
                # Crucial check: does mesh center deviate from obj location?
                dist_local = mathutils.Vector(center_local).length
                if dist_local > 0.005: # > 5mm
                    print(f"      [WARNING] MESH VERTICES ARE NOT CENTERED AT OBJECT ORIGIN! Offset: {dist_local*1000:.1f} mm")
                else:
                    print(f"      [OK] Centered at origin (offset {dist_local*1000:.2f} mm)")
            else:
                print(f"  - '{p.name}' HAS NO VERTICES!")
        else:
            print(f"  - '{p.name}' is type {p.type}")
            
    # Also list non-propeller meshes (frame, motors, etc.)
    non_props = [obj for obj in all_objs if obj not in prop_objs and obj.type == 'MESH']
    print(f"\nOther mesh objects ({len(non_props)}):")
    for obj in non_props:
        mw = obj.matrix_world
        verts = [v.co for v in obj.data.vertices]
        if verts:
            min_c = [min(v[i] for v in verts) for i in range(3)]
            max_c = [max(v[i] for v in verts) for i in range(3)]
            span = [max_c[i] - min_c[i] for i in range(3)]
            c_local = [(min_c[i] + max_c[i]) / 2.0 for i in range(3)]
            c_glob = mw @ mathutils.Vector(c_local)
            print(f"  - '{obj.name}' verts={len(verts)} center_world=({c_glob.x:.3f}, {c_glob.y:.3f}, {c_glob.z:.3f}) span=({span[0]:.3f}, {span[1]:.3f}, {span[2]:.3f})")
