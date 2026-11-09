import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\peleng.glb")

body = bpy.data.objects['peleng_body']
verts = np.array([body.matrix_world @ v.co for v in body.data.vertices])

print("Finding exact motor stator centers for Peleng...")

# Peleng quadrants:
# FL: X < -0.05, Y > 0.03
# FR: X >  0.05, Y > 0.03
# BL: X < -0.05, Y < -0.03
# BR: X >  0.05, Y < -0.03
quads = {
    'FL': (verts[:,0] < -0.05) & (verts[:,1] > 0.03),
    'FR': (verts[:,0] >  0.05) & (verts[:,1] > 0.03),
    'BL': (verts[:,0] < -0.05) & (verts[:,1] < -0.03),
    'BR': (verts[:,0] >  0.05) & (verts[:,1] < -0.03),
}

for qname, qmask in quads.items():
    qverts = verts[qmask]
    # Motor stator is a cylinder of radius ~14mm
    # Search grid for center that minimizes variance of distances to cylindrical shell
    # Bounds:
    xmin, xmax = qverts[:,0].min(), qverts[:,0].max()
    ymin, ymax = qverts[:,1].min(), qverts[:,1].max()
    zmin, zmax = qverts[:,2].min(), qverts[:,2].max()
    
    best_var = 1e9
    best_c = None
    best_r = 0
    # The motor is at the outer corner of each arm
    for x in np.linspace(xmin, xmax, 35):
        for y in np.linspace(ymin, ymax, 35):
            for z in np.linspace(zmax - 0.01, zmax, 15):
                d = np.linalg.norm(qverts - [x, y, z], axis=1)
                shell = d[(d > 0.008) & (d < 0.016)]
                if len(shell) > 60:
                    var = np.var(shell)
                    if var < best_var:
                        best_var = var
                        best_c = (x, y, z)
                        best_r = np.mean(shell)
    print(f"  {qname}: Center=({best_c[0]:.4f}, {best_c[1]:.4f}, {best_c[2]:.4f}), radius={best_r*1000:.1f}mm, top_z={zmax:.4f}")
