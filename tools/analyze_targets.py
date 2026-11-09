import bpy, numpy as np

def analyze_drone(filename):
    print("=" * 60)
    print("ANALYZING:", filename)
    print("=" * 60)
    p = rf"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\{filename}"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=p)
    
    body_objs = [o for o in bpy.data.objects if o.type == 'MESH' and not o.name.startswith("propeller")]
    for bo in body_objs:
        verts = np.array([bo.matrix_world @ v.co for v in bo.data.vertices])
        print(f"Body Mesh '{bo.name}': {len(verts)} verts")
        print(f"  X: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}]")
        print(f"  Y: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}]")
        print(f"  Z: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}]")
        
    props = [o for o in bpy.data.objects if o.name.startswith("propeller")]
    for po in props:
        verts = np.array([v.co for v in po.data.vertices])
        print(f"Propeller '{po.name}': loc={po.location}, rot={po.rotation_euler}, verts={len(verts)}")
        print(f"  Local X: [{verts[:,0].min():.4f}, {verts[:,0].max():.4f}] mean={verts[:,0].mean():.4f}")
        print(f"  Local Y: [{verts[:,1].min():.4f}, {verts[:,1].max():.4f}] mean={verts[:,1].mean():.4f}")
        print(f"  Local Z: [{verts[:,2].min():.4f}, {verts[:,2].max():.4f}]")

analyze_drone("peleng.glb")
analyze_drone("falcon_x.glb")
analyze_drone("pisun_vtol.glb")
