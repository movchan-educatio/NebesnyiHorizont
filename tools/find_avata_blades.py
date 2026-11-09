import bpy
import bmesh
import mathutils
import os

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\avata2.glb"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

rings_obj = bpy.data.objects.get("DJI_Avata2_Propeller_Rings")
hard_obj = bpy.data.objects.get("DJI_Avata2_Hardware_Small")

print("Checking DJI_Avata2_Propeller_Rings islands...")
bm = bmesh.new()
bm.from_mesh(rings_obj.data)
visited = set()
islands = []
for v in bm.verts:
    if v in visited:
        continue
    island = []
    stack = [v]
    visited.add(v)
    while stack:
        curr = stack.pop()
        island.append(curr)
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited:
                visited.add(o)
                stack.append(o)
    islands.append(island)

print(f"Total islands: {len(islands)}")
prop_islands = []
for idx, isl in enumerate(islands):
    # Check if verts are ~400-420 or bounds indicate a blade
    coords = [v.co for v in isl]
    cen = sum(coords, mathutils.Vector((0,0,0))) / len(coords)
    # Motors are roughly at |X| ~ 0.06, |Y| ~ 0.047
    if 350 <= len(isl) <= 450:
        print(f"Blade Island {idx}: verts={len(isl)}, center=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
        prop_islands.append((idx, cen, isl))

print(f"\nTotal potential blade islands found: {len(prop_islands)} (expecting 12 = 4 props * 3 blades)")
bm.free()

# Also check hardware small for the screws/caps
print("\nChecking DJI_Avata2_Hardware_Small screws/caps...")
bm = bmesh.new()
bm.from_mesh(hard_obj.data)
visited = set()
hard_islands = []
for v in bm.verts:
    if v in visited:
        continue
    island = []
    stack = [v]
    visited.add(v)
    while stack:
        curr = stack.pop()
        island.append(curr)
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited:
                visited.add(o)
                stack.append(o)
    hard_islands.append(island)

print(f"Hardware islands: {len(hard_islands)}")
# Screws on the prop hubs:
motor_centers = [
    ("FL", -0.0601, 0.0469),
    ("FR", 0.0600, 0.0469),
    ("BL", -0.0603, -0.0468),
    ("BR", 0.0603, -0.0468),
]
for mc_name, mx, my in motor_centers:
    near_screws = []
    for idx, isl in enumerate(hard_islands):
        coords = [v.co for v in isl]
        cen = sum(coords, mathutils.Vector((0,0,0))) / len(coords)
        dist = ((cen.x - mx)**2 + (cen.y - my)**2)**0.5
        if dist < 0.02 and cen.z > -0.01:
            near_screws.append((idx, len(isl), cen))
    print(f"Near {mc_name} ({mx:.4f}, {my:.4f}): {len(near_screws)} islands:")
    for idx, vcnt, cen in near_screws:
        print(f"   isl {idx}: verts={vcnt}, cen=({cen.x:.4f}, {cen.y:.4f}, {cen.z:.4f})")
bm.free()
