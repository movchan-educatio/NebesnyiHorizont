import bpy
import bmesh
import mathutils
import os

glb_path = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm\avata2.glb"
print("=" * 80)
print("FIXING DJI AVATA 2 PROPELLERS")
print("=" * 80)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

rings_obj = bpy.data.objects.get("DJI_Avata2_Propeller_Rings")
hard_obj = bpy.data.objects.get("DJI_Avata2_Hardware_Small")

# Delete old flat dummy propeller objects
for name in ["propeller_FL", "propeller_FR", "propeller_BL", "propeller_BR"]:
    old_p = bpy.data.objects.get(name)
    if old_p:
        bpy.data.objects.remove(old_p, do_unlink=True)
        print(f"Removed dummy {name}")

# In DJI_Avata2_Propeller_Rings, separate the 12 blade islands:
# BL: islands near X=-0.060, Y=-0.047
# BR: islands near X=0.060, Y=-0.047
# FL: islands near X=-0.060, Y=0.047
# FR: islands near X=0.060, Y=0.047

bm_rings = bmesh.new()
bm_rings.from_mesh(rings_obj.data)

# Find all islands
visited = set()
islands = []
for v in bm_rings.verts:
    if v in visited:
        continue
    isl = []
    stack = [v]
    visited.add(v)
    while stack:
        curr = stack.pop()
        isl.append(curr)
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited:
                visited.add(o)
                stack.append(o)
    islands.append(isl)

print(f"Total islands in rings: {len(islands)}")

# Identify blade islands (verts ~ 400-425)
motor_defs = {
    "propeller_FL": (-0.0601, 0.0469),
    "propeller_FR": (0.0600, 0.0469),
    "propeller_BL": (-0.0603, -0.0468),
    "propeller_BR": (0.0603, -0.0468),
}

assigned_blades = {k: [] for k in motor_defs}
for isl in islands:
    if 380 <= len(isl) <= 450:
        coords = [v.co for v in isl]
        cen = sum(coords, mathutils.Vector((0,0,0))) / len(coords)
        # Find which motor it is closest to
        best_dist = 999.0
        best_motor = None
        for mname, (mx, my) in motor_defs.items():
            d = ((cen.x - mx)**2 + (cen.y - my)**2)**0.5
            if d < best_dist:
                best_dist = d
                best_motor = mname
        if best_dist < 0.045:
            assigned_blades[best_motor].append(isl)

for mname, isls in assigned_blades.items():
    print(f"{mname} has {len(isls)} blades (expected 3)")

# Also find screws in DJI_Avata2_Hardware_Small for each prop hub
bm_hard = bmesh.new()
bm_hard.from_mesh(hard_obj.data)
visited_hard = set()
hard_islands = []
for v in bm_hard.verts:
    if v in visited_hard:
        continue
    isl = []
    stack = [v]
    visited_hard.add(v)
    while stack:
        curr = stack.pop()
        isl.append(curr)
        for e in curr.link_edges:
            o = e.other_vert(curr)
            if o not in visited_hard:
                visited_hard.add(o)
                stack.append(o)
    hard_islands.append(isl)

assigned_screws = {k: [] for k in motor_defs}
for isl in hard_islands:
    coords = [v.co for v in isl]
    cen = sum(coords, mathutils.Vector((0,0,0))) / len(coords)
    # Check if on top of motor hub: Z > 0.001
    if cen.z > 0.001:
        for mname, (mx, my) in motor_defs.items():
            d = ((cen.x - mx)**2 + (cen.y - my)**2)**0.5
            if d < 0.015:
                assigned_screws[mname].append(isl)

for mname, isls in assigned_screws.items():
    print(f"{mname} has {len(isls)} screw/hardware parts")

# Create 4 new propeller mesh objects
# Material for propellers: use existing dark prop material or create one
prop_mat = None
for mat in bpy.data.materials:
    if "prop" in mat.name.lower() or "plastic" in mat.name.lower():
        prop_mat = mat
        break
if not prop_mat:
    prop_mat = bpy.data.materials.new("Avata2_Propeller_Mat")
    prop_mat.use_nodes = True

all_blade_verts = set()
for isls in assigned_blades.values():
    for isl in isls:
        all_blade_verts.update(isl)

all_screw_verts = set()
for isls in assigned_screws.values():
    for isl in isls:
        all_screw_verts.update(isl)

# For each motor, extract its blades + screws into a new Mesh
new_prop_objs = []
for mname, (mx, my) in motor_defs.items():
    prop_bm = bmesh.new()
    
    # Add blade vertices and faces
    blade_verts_motor = set()
    for isl in assigned_blades[mname]:
        blade_verts_motor.update(isl)
    
    # We find all faces where all vertices are in blade_verts_motor
    blade_faces = [f for f in bm_rings.faces if all(v in blade_verts_motor for v in f.verts)]
    
    vert_map = {}
    for f in blade_faces:
        new_verts = []
        for v in f.verts:
            if v not in vert_map:
                vert_map[v] = prop_bm.verts.new(v.co)
            new_verts.append(vert_map[v])
        prop_bm.faces.new(new_verts)
        
    # Also add screw faces
    screw_verts_motor = set()
    for isl in assigned_screws[mname]:
        screw_verts_motor.update(isl)
    screw_faces = [f for f in bm_hard.faces if all(v in screw_verts_motor for v in f.verts)]
    screw_map = {}
    for f in screw_faces:
        new_verts = []
        for v in f.verts:
            if v not in screw_map:
                screw_map[v] = prop_bm.verts.new(v.co)
            new_verts.append(screw_map[v])
        prop_bm.faces.new(new_verts)
        
    prop_bm.verts.ensure_lookup_table()
    
    # Compute true rotational center of the hub
    # Using screw centers or blade hub tips
    # Screws are at exact center of hub
    if screw_verts_motor:
        screw_cos = [v.co for v in screw_verts_motor]
        cen_hub = sum(screw_cos, mathutils.Vector((0,0,0))) / len(screw_cos)
    else:
        blade_cos = [v.co for v in blade_verts_motor]
        cen_hub = sum(blade_cos, mathutils.Vector((0,0,0))) / len(blade_cos)
        cen_hub.x = mx
        cen_hub.y = my
        
    print(f"Constructed {mname}: {len(prop_bm.verts)} verts. Hub center: ({cen_hub.x:.4f}, {cen_hub.y:.4f}, {cen_hub.z:.4f})")
    
    # Shift vertices so hub center is at (0, 0, 0)
    for v in prop_bm.verts:
        v.co.x -= cen_hub.x
        v.co.y -= cen_hub.y
        v.co.z -= cen_hub.z
        
    new_mesh = bpy.data.meshes.new(mname)
    prop_bm.to_mesh(new_mesh)
    prop_bm.free()
    
    new_obj = bpy.data.objects.new(mname, new_mesh)
    bpy.context.scene.collection.objects.link(new_obj)
    new_obj.location = cen_hub
    new_obj.data.materials.append(prop_mat)
    new_prop_objs.append(new_obj)

# Now delete the blade faces from rings_obj
bmesh.ops.delete(bm_rings, geom=list(all_blade_verts), context='VERTS')
bm_rings.to_mesh(rings_obj.data)
bm_rings.free()

# Delete screw faces from hard_obj
bmesh.ops.delete(bm_hard, geom=list(all_screw_verts), context='VERTS')
bm_hard.to_mesh(hard_obj.data)
bm_hard.free()

print("Blades and screws cleanly separated into 4 distinct rotating propeller objects!")

# Export back to avata2.glb
bpy.ops.export_scene.gltf(
    filepath=glb_path,
    export_format='GLB',
    use_selection=False,
    export_apply=False
)
print("Successfully exported updated avata2.glb!")
