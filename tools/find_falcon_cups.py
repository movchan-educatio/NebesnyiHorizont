import bpy
import bmesh
import mathutils

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\falcon_x.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

# Look at Object_28 (the arm frame)
obj28 = bpy.data.objects.get("Object_28")
bm = bmesh.new()
bm.from_mesh(obj28.data)

# Let's inspect the 4 circular cups at the arm tips!
# In the render, we see 4 beautiful circular motor cups on the 4 arms:
# Front-left, Front-right, Rear-left, Rear-right
# A circular cup has a circle of vertices of radius ~ 12-16mm
for qname, cond in [
    ("Front-Left (X<0, Y<0)", lambda v: v.co.x < -0.06 and v.co.y < 0),
    ("Front-Right (X>0, Y<0)", lambda v: v.co.x > 0.06 and v.co.y < 0),
    ("Rear-Left (X<0, Y>0)", lambda v: v.co.x < -0.06 and v.co.y > 0),
    ("Rear-Right (X>0, Y>0)", lambda v: v.co.x > 0.06 and v.co.y > 0),
]:
    verts = [v.co for v in bm.verts if cond(v)]
    print(f"\n=== {qname} (total {len(verts)} verts) ===")
    # Find the circular cup:
    # Look at the outermost tip of the arm
    # For Front: min Y
    # For Rear: max Y
    if "Front" in qname:
        extreme_y = min(v.y for v in verts)
        print(f"Front arm extreme Y = {extreme_y:.4f}")
        # The motor cup is around the extreme tip!
        tip_verts = [v for v in verts if v.y < extreme_y + 0.04]
    else:
        extreme_y = max(v.y for v in verts)
        print(f"Rear arm extreme Y = {extreme_y:.4f}")
        tip_verts = [v for v in verts if v.y > extreme_y - 0.04]
        
    # In tip_verts, find circular edge loops or find center of circle
    # Find Z bounds
    min_z = min(v.z for v in tip_verts)
    max_z = max(v.z for v in tip_verts)
    cen = sum([v for v in tip_verts], mathutils.Vector((0,0,0))) / len(tip_verts)
    print(f"Tip verts count={len(tip_verts)}, cen=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f}), Z range=[{min_z:.4f}, {max_z:.4f}]")
    
    # Calculate radius from cen in XY plane
    # Refine center using circular regression
    # The cup vertices are in a ring of radius ~ 14mm
    best_cen = cen
    for _ in range(5):
        radii = [((v.x - best_cen.x)**2 + (v.y - best_cen.y)**2)**0.5 for v in tip_verts]
        # cup ring is around 10-18mm
        ring = [v for v, r in zip(tip_verts, radii) if 0.008 < r < 0.020]
        if ring:
            best_cen = sum(ring, mathutils.Vector((0,0,0))) / len(ring)
    
    print(f"REFINED MOTOR CUP CENTER: ({best_cen.x:.4f}, {best_cen.y:.4f}, {best_cen.z:.4f})")
bm.free()
