import bpy, mathutils
import numpy as np

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for m in ["grim7.glb", "grim7m.glb", "strila8.glb", "pinapipe.glb", "holka.glb"]:
    path = f"{base_dir}\\{m}"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print(f"\n==================== {m} ====================")
    for p in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
        po = bpy.data.objects.get(p)
        if po:
            verts = np.array([v.co for v in po.data.vertices])
            print(f"  {p}: loc={[round(c, 4) for c in po.location]} span_x={verts[:,0].ptp():.4f} span_y={verts[:,1].ptp():.4f}")
