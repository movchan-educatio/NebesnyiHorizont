import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\holka.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

body = bpy.data.objects.get("Object_2")
bm = bmesh.new()
bm.from_mesh(body.data)

# Let's inspect the 4 motor cylinders at the tips of the arms in holka:
# Front-Left: X < -0.05, Y > 0.04
# Front-Right: X > 0.05, Y > 0.04
# Rear-Left: X < -0.04, Y < -0.04
# Rear-Right: X > 0.04, Y < -0.04

for qname, cond in [
    ("FL", lambda v: v.co.x < -0.04 and v.co.y > 0.04),
    ("FR", lambda v: v.co.x > 0.04 and v.co.y > 0.04),
    ("BL", lambda v: v.co.x < -0.04 and v.co.y < -0.04),
    ("BR", lambda v: v.co.x > 0.04 and v.co.y < -0.04),
]:
    verts = [v.co for v in bm.verts if cond(v)]
    print(f"\n=== HOLKA {qname} (verts: {len(verts)}) ===")
    # Find the motor cylinder:
    # Look at the outer tip of the arm:
    # In the rendered image, the motor bells are clearly visible vertical cylinders with open top!
    # Let's find vertices with highest Z (top of cylinder)
    max_z = max(v.z for v in verts)
    min_z = min(v.z for v in verts)
    print(f"Z range: [{min_z:.4f}, {max_z:.4f}]")
    
    # Motor cylinder vertices: find circle of radius ~ 10-15mm
    # Let's find the top rim of the motor cup (highest 5mm of the cylinder)
    top_rim = [v for v in verts if v.z > max_z - 0.005]
    cen_rim = sum(top_rim, mathutils.Vector((0,0,0))) / len(top_rim)
    # Refine center of circle in XY plane
    best_cen = cen_rim
    for _ in range(5):
        radii = [((v.x - best_cen.x)**2 + (v.y - best_cen.y)**2)**0.5 for v in top_rim]
        ring = [v for v, r in zip(top_rim, radii) if 0.005 < r < 0.016]
        if ring:
            best_cen = sum(ring, mathutils.Vector((0,0,0))) / len(ring)
    
    print(f"REFINED MOTOR CUP TOP CENTER: ({best_cen.x:.4f}, {best_cen.y:.4f}, {max_z:.4f})")
bm.free()
