import bpy, mathutils, os, sys
sys.stdout.reconfigure(encoding='utf-8')

path = r'c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\pisun_vtol.glb'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        print(f"Mesh: {o.name}")
        verts = o.data.vertices
        # Find 4 motor clusters
        # In pisun_vtol, the motors are along the 4 cruciform arms: +X, -X, +Y, -Y
        for arm, cond in [
            ('+X (Right)', lambda v: v.co.x > 0.10 and abs(v.co.y) < 0.05),
            ('-X (Left)', lambda v: v.co.x < -0.10 and abs(v.co.y) < 0.05),
            ('+Y (Top/Front)', lambda v: v.co.y > 0.10 and abs(v.co.x) < 0.05),
            ('-Y (Bottom/Rear)', lambda v: v.co.y < -0.10 and abs(v.co.x) < 0.05),
        ]:
            arm_v = [v.co for v in verts if cond(v)]
            if arm_v:
                # Top Z
                max_z = max(v.z for v in arm_v)
                top_v = [v for v in arm_v if abs(v.z - max_z) < 0.005]
                cen = sum(top_v, mathutils.Vector()) / len(top_v)
                print(f"   Arm {arm}: motor top=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
