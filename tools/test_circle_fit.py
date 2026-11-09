import bpy, os, math
import numpy as np

def fit_circle_2d(points):
    # points: array of (x, y)
    pts = np.array(points)
    x = pts[:, 0]
    y = pts[:, 1]
    A = np.column_stack([2*x, 2*y, np.ones(len(pts))])
    b = x**2 + y**2
    sol, residuals, rank, s = np.linalg.lstsq(A, b, rcond=None)
    xc, yc = sol[0], sol[1]
    r = math.sqrt(max(0.0, sol[2] + xc**2 + yc**2))
    return xc, yc, r

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
for m in ["falcon_x.glb", "pisun_vtol.glb", "peleng.glb", "quad5_custom.glb", "avata2.glb"]:
    path = os.path.join(base_dir, m)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print(f"\n--- {m} ---")
    for p_name in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
        p = bpy.data.objects.get(p_name)
        if not p:
            continue
        verts = np.array([v.co for v in p.data.vertices])
        # Find rough center
        mid = (verts.min(axis=0) + verts.max(axis=0)) / 2.0
        # Distance in XY from mid
        d = np.hypot(verts[:, 0] - mid[0], verts[:, 1] - mid[1])
        # In hub region: radius < 12mm
        hub_pts = verts[d < 0.012][:, :2]
        if len(hub_pts) >= 5:
            xc, yc, r = fit_circle_2d(hub_pts)
            print(f"  {p_name}: hub_pts={len(hub_pts)} -> shaft_center=({xc:.5f}, {yc:.5f}), hub_r={r*1000:.1f}mm")
        else:
            print(f"  {p_name}: too few hub pts ({len(hub_pts)})")
