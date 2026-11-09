import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb")

o = bpy.data.objects['Object_28']
verts = np.array([o.matrix_world @ v.co for v in o.data.vertices])

# In the front-right arm: X > 0.08, Y < -0.02
fr_verts = verts[(verts[:, 0] > 0.08) & (verts[:, 1] < -0.02)]
# The cup rim is a circular ring of vertices
# Let's find vertices with Z between -0.01 and 0.02
# and find circular rings
print(f"FR verts count: {len(fr_verts)}")

# Let's test candidate centers in steps of 1mm
best_var = 1e9
best_c = None
best_r = 0
for x in np.linspace(0.08, 0.11, 31):
    for y in np.linspace(-0.07, -0.03, 41):
        for z in np.linspace(-0.01, 0.03, 41):
            d = np.linalg.norm(fr_verts - [x, y, z], axis=1)
            # Find points roughly at distance R ~ 0.010..0.016
            near_shell = d[(d > 0.010) & (d < 0.016)]
            if len(near_shell) > 100:
                var = np.var(near_shell)
                if var < best_var:
                    best_var = var
                    best_c = (x, y, z)
                    best_r = np.mean(near_shell)

print(f"Best FR cup center: {best_c}, radius: {best_r*1000:.1f}mm")

# Same for BL: X < -0.07, Y > 0.03
bl_verts = verts[(verts[:, 0] < -0.07) & (verts[:, 1] > 0.03)]
best_var = 1e9
best_c_bl = None
best_r_bl = 0
for x in np.linspace(-0.11, -0.08, 31):
    for y in np.linspace(0.04, 0.08, 41):
        for z in np.linspace(0.08, 0.12, 41):
            d = np.linalg.norm(bl_verts - [x, y, z], axis=1)
            near_shell = d[(d > 0.010) & (d < 0.016)]
            if len(near_shell) > 100:
                var = np.var(near_shell)
                if var < best_var:
                    best_var = var
                    best_c_bl = (x, y, z)
                    best_r_bl = np.mean(near_shell)

print(f"Best BL cup center: {best_c_bl}, radius: {best_r_bl*1000:.1f}mm")
