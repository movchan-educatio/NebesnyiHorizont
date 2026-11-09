import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\peleng.glb")

body = bpy.data.objects['peleng_body']
verts = np.array([body.matrix_world @ v.co for v in body.data.vertices])

# In the render, the empty motor bell at the rear right (X < -0.05, Y < -0.05 in Blender):
# Let's inspect all vertices in X < -0.06 and Y < -0.06
sub_verts = verts[(verts[:, 0] < -0.06) & (verts[:, 1] < -0.06)]
print(f"Sub-verts: {len(sub_verts)}")

# Let's find circular ring in sub_verts:
# A motor bell has a circle of vertices with radius ~10-15mm
# Test centers in grid:
best_var = 1e9
best_c = None
best_r = 0
for x in np.linspace(-0.10, -0.06, 41):
    for y in np.linspace(-0.11, -0.07, 41):
        for z in np.linspace(-0.01, 0.02, 31):
            d = np.linalg.norm(sub_verts - [x, y, z], axis=1)
            # Find points roughly at motor bell radius R ~ 0.010..0.015
            ring = d[(d > 0.010) & (d < 0.015)]
            if len(ring) > 80:
                var = np.var(ring)
                if var < best_var:
                    best_var = var
                    best_c = (x, y, z)
                    best_r = np.mean(ring)

print(f"Rear-left motor ring center: {best_c}, radius: {best_r*1000:.1f}mm")

# And for front-left (X < -0.05, Y > 0.05):
sub_fl = verts[(verts[:, 0] < -0.05) & (verts[:, 1] > 0.05)]
best_var = 1e9
best_c_fl = None
best_r_fl = 0
for x in np.linspace(-0.10, -0.06, 41):
    for y in np.linspace(0.05, 0.09, 41):
        for z in np.linspace(-0.02, 0.01, 31):
            d = np.linalg.norm(sub_fl - [x, y, z], axis=1)
            ring = d[(d > 0.010) & (d < 0.015)]
            if len(ring) > 80:
                var = np.var(ring)
                if var < best_var:
                    best_var = var
                    best_c_fl = (x, y, z)
                    best_r_fl = np.mean(ring)

print(f"Front-left motor ring center: {best_c_fl}, radius: {best_r_fl*1000:.1f}mm")
