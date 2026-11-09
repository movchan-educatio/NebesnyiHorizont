import bpy, os
import numpy as np

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for fn in sorted(os.listdir(base_dir)):
    if not fn.endswith(".glb") or fn.startswith("radiomaster") or fn.startswith("magura"):
        continue
    filepath = os.path.join(base_dir, fn)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    print("\n" + "=" * 60)
    print(f"DRONE: {fn}")
    print("=" * 60)
    
    props = [o for o in bpy.data.objects if o.name.startswith("propeller_")]
    body_objs = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith("propeller_")]
    
    if not body_objs:
        print("NO BODY MESHES!")
        continue
    if not props:
        print("NO PROPELLERS!")
        continue
        
    all_body_verts = []
    for bo in body_objs:
        mw = bo.matrix_world
        all_body_verts.extend([mw @ v.co for v in bo.data.vertices])
    all_body_verts = np.array(all_body_verts)
    
    for p in props:
        p_loc = np.array(p.matrix_world.to_translation())
        # Distance to all body verts
        dists = np.linalg.norm(all_body_verts - p_loc, axis=1)
        min_dist = dists.min()
        closest_vert = all_body_verts[np.argmin(dists)]
        print(f"  {p.name:15} at ({p_loc[0]:.4f}, {p_loc[1]:.4f}, {p_loc[2]:.4f}) | closest body vertex: ({closest_vert[0]:.4f}, {closest_vert[1]:.4f}, {closest_vert[2]:.4f}) -> DIST = {min_dist*1000:.1f} mm")
