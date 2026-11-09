import bpy
import mathutils
import os

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

def inspect_model(name):
    print("=" * 80)
    print(f"INSPECTING: {name}")
    glb_path = os.path.join(base_dir, name)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    
    for obj in bpy.data.objects:
        p_name = obj.parent.name if obj.parent else "None"
        vcount = len(obj.data.vertices) if obj.type == 'MESH' else 0
        dim = [round(d, 4) for d in obj.dimensions] if obj.type == 'MESH' else []
        loc = [round(l, 4) for l in obj.location]
        rot = [round(r, 4) for r in obj.rotation_euler]
        print(f"[{obj.type}] {obj.name} | parent={p_name} | loc={loc} | rot={rot} | dim={dim} | verts={vcount}")
        if "prop" in obj.name.lower():
            verts = [v.co for v in obj.data.vertices]
            if verts:
                min_x = min(v.x for v in verts)
                max_x = max(v.x for v in verts)
                min_y = min(v.y for v in verts)
                max_y = max(v.y for v in verts)
                min_z = min(v.z for v in verts)
                max_z = max(v.z for v in verts)
                cen = sum(verts, mathutils.Vector((0,0,0))) / len(verts)
                print(f"   PROP BOUNDS: X[{min_x:.4f}, {max_x:.4f}], Y[{min_y:.4f}, {max_y:.4f}], Z[{min_z:.4f}, {max_z:.4f}] | center={cen}")

for m in ["pisun_vtol.glb", "falcon_x.glb", "peleng.glb", "holka.glb"]:
    inspect_model(m)
