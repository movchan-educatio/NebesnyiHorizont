import bpy, os, math
import numpy as np

def find_circle_center_and_normal(pts):
    pts = np.array(pts)
    # Fit plane
    centroid = pts.mean(axis=0)
    shifted = pts - centroid
    _, _, vh = np.linalg.svd(shifted)
    normal = vh[2] # normal to best fit plane
    if normal[2] < 0: # make normal point generally upward (+Z)
        normal = -normal
    normal = normal / np.linalg.norm(normal)
    
    # Project to 2D plane
    u = vh[0] / np.linalg.norm(vh[0])
    v = np.cross(normal, u)
    p2d = np.column_stack([np.dot(shifted, u), np.dot(shifted, v)])
    
    # 2D circle fit
    x = p2d[:, 0]
    y = p2d[:, 1]
    A = np.column_stack([2*x, 2*y, np.ones(len(x))])
    b = x**2 + y**2
    sol, _, _, _ = np.linalg.lstsq(A, b, rcond=None)
    c2d = sol[:2]
    r = math.sqrt(max(0.0, sol[2] + c2d[0]**2 + c2d[1]**2))
    center3d = centroid + c2d[0]*u + c2d[1]*v
    return center3d, normal, r

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for fn in sorted(os.listdir(base_dir)):
    if not fn.endswith(".glb") or fn.startswith("radiomaster") or fn.startswith("magura"):
        continue
    p = os.path.join(base_dir, fn)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=p)
    
    print("\n" + "="*50)
    print("EXACT MOTOR DETECTION:", fn)
    print("="*50)
    
    body_objs = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith("propeller")]
    all_verts = []
    for bo in body_objs:
        mw = bo.matrix_world
        all_verts.extend([mw @ v.co for v in bo.data.vertices])
    all_verts = np.array(all_verts)
    
    # For each existing propeller, look at the body vertices within 25mm of its current location
    for p_name in ['propeller_FL', 'propeller_FR', 'propeller_BL', 'propeller_BR']:
        p_obj = bpy.data.objects.get(p_name)
        if not p_obj:
            print(f"  {p_name}: NOT FOUND")
            continue
        ploc = np.array(p_obj.location)
        dists = np.linalg.norm(all_verts - ploc, axis=1)
        nearby = all_verts[dists < 0.035] # within 35mm
        if len(nearby) < 10:
            print(f"  {p_name}: Only {len(nearby)} body verts nearby!")
            continue
            
        # The motor top stator face is typically the highest Z among the nearby motor vertices
        # (or for VTOL, furthest along motor normal)
        z_max = nearby[:, 2].max()
        # Ring of vertices within top 4mm of motor
        top_ring = nearby[nearby[:, 2] > (z_max - 0.005)]
        if len(top_ring) >= 6:
            c3d, n3d, r = find_circle_center_and_normal(top_ring)
            print(f"  {p_name:12}: Stator Top Center=({c3d[0]:.4f}, {c3d[1]:.4f}, {c3d[2]:.4f}), r={r*1000:.1f}mm, norm=({n3d[0]:.2f}, {n3d[1]:.2f}, {n3d[2]:.2f}) [offset from curr: {np.linalg.norm(c3d - ploc)*1000:.1f}mm]")
        else:
            print(f"  {p_name:12}: top_ring has only {len(top_ring)} verts")
