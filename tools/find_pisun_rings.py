import bpy, numpy as np

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb")

o3 = bpy.data.objects['Object_3']
verts = np.array([o3.matrix_world @ v.co for v in o3.data.vertices])

# On Object_3, find the 4 motor mounts at the 4 wing/fin tips:
# Left: X < -0.10, Y near 0
# Right: X > 0.10, Y near 0
# Front: Y > 0.10, X near 0
# Back: Y < -0.10, X near 0

motors = {
    'Left (-X)': verts[(verts[:, 0] < -0.10) & (np.abs(verts[:, 1]) < 0.03)],
    'Right (+X)': verts[(verts[:, 0] > 0.10) & (np.abs(verts[:, 1]) < 0.03)],
    'Front (+Y)': verts[(verts[:, 1] > 0.10) & (np.abs(verts[:, 0]) < 0.03)],
    'Back (-Y)': verts[(verts[:, 1] < -0.10) & (np.abs(verts[:, 0]) < 0.03)],
}

for mname, mverts in motors.items():
    print(f"\n=== {mname} ({len(mverts)} verts) ===")
    print(f"  X: [{mverts[:,0].min():.4f}, {mverts[:,0].max():.4f}]")
    print(f"  Y: [{mverts[:,1].min():.4f}, {mverts[:,1].max():.4f}]")
    print(f"  Z: [{mverts[:,2].min():.4f}, {mverts[:,2].max():.4f}]")
    # The motor mount face / cap is at the highest Z or lowest Z?
    # In Object_3, Z is [-0.2135, -0.0476].
    # -0.0476 is the FRONT/TOP of Object_3 (towards nose, Z > 0)!
    # -0.2135 is the rear tips of the fins!
    # Where are the motors?
    # Let's find circular ring of the motor mount
    z_top = mverts[:, 2].max()
    top_faces = mverts[mverts[:, 2] > z_top - 0.015]
    print(f"  Top face (Z > {z_top-0.015:.4f}): {len(top_faces)} verts, centroid=({top_faces[:,0].mean():.4f}, {top_faces[:,1].mean():.4f}, {top_faces[:,2].mean():.4f})")
