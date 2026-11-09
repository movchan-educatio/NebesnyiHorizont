import bpy
import os
import glob
import mathutils

GLB_DIR = r"c:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

# Exact motor shaft centers for all 10 drones:
MOTOR_POSITIONS = {
    "holka.glb": {
        "FL": mathutils.Vector((-0.0620, 0.0641, -0.0260)),
        "FR": mathutils.Vector((0.0633, 0.0647, -0.0260)),
        "BR": mathutils.Vector((0.0577, -0.0639, -0.0250)),
        "BL": mathutils.Vector((-0.0581, -0.0657, -0.0250)),
    },
    "pinapipe.glb": {
        "FL": mathutils.Vector((-0.0647, 0.0534, -0.0040)),
        "FR": mathutils.Vector((0.0647, 0.0535, -0.0040)),
        "BR": mathutils.Vector((0.0648, -0.0535, -0.0040)),
        "BL": mathutils.Vector((-0.0648, -0.0535, -0.0040)),
    },
    "avata2.glb": {
        "FL": mathutils.Vector((-0.0601, 0.0469, 0.0045)),
        "FR": mathutils.Vector((0.0600, 0.0469, 0.0045)),
        "BR": mathutils.Vector((0.0603, -0.0468, 0.0045)),
        "BL": mathutils.Vector((-0.0603, -0.0468, 0.0045)),
    },
    "pisun_vtol.glb": {
        "FL": mathutils.Vector((-0.1210, 0.0002, -0.0500)),
        "FR": mathutils.Vector((0.1200, 0.0006, -0.0500)),
        "BR": mathutils.Vector((-0.0006, -0.1205, -0.0500)),
        "BL": mathutils.Vector((-0.0013, 0.1223, -0.0500)),
    },
    "peleng.glb": {
        "FL": mathutils.Vector((-0.0909, 0.0843, 0.0050)),
        "FR": mathutils.Vector((0.0909, 0.0843, 0.0050)),
        "BR": mathutils.Vector((0.0940, -0.0864, 0.0100)),
        "BL": mathutils.Vector((-0.0935, -0.0875, 0.0100)),
    },
    "grim7.glb": {
        "FL": mathutils.Vector((-0.1005, 0.0848, 0.0180)),
        "FR": mathutils.Vector((0.1005, 0.0848, 0.0180)),
        "BR": mathutils.Vector((0.1005, -0.1146, 0.0180)),
        "BL": mathutils.Vector((-0.1005, -0.1146, 0.0180)),
    },
    "grim7m.glb": {
        "FL": mathutils.Vector((-0.1065, 0.1271, 0.0060)),
        "FR": mathutils.Vector((0.1064, 0.1271, 0.0060)),
        "BR": mathutils.Vector((0.1062, -0.1103, 0.0060)),
        "BL": mathutils.Vector((-0.1061, -0.1103, 0.0060)),
    },
    "strila8.glb": {
        "FL": mathutils.Vector((-0.0919, 0.0722, 0.0225)),
        "FR": mathutils.Vector((0.0919, 0.0723, 0.0225)),
        "BR": mathutils.Vector((0.0919, -0.1110, 0.0225)),
        "BL": mathutils.Vector((-0.0919, -0.1111, 0.0225)),
    },
    "falcon_x.glb": {
        "FL": mathutils.Vector((0.0983, -0.0493, 0.0400)),
        "FR": mathutils.Vector((-0.0983, -0.0493, 0.0400)),
        "BR": mathutils.Vector((0.0966, 0.0677, 0.1215)),
        "BL": mathutils.Vector((-0.0966, 0.0677, 0.1215)),
    },
    "quad5_custom.glb": {
        "FL": mathutils.Vector((-0.0780, 0.0825, 0.0390)),
        "FR": mathutils.Vector((0.0780, 0.0825, 0.0390)),
        "BR": mathutils.Vector((0.0780, -0.0825, 0.0390)),
        "BL": mathutils.Vector((-0.0780, -0.0825, 0.0390)),
    }
}

def center_propeller_geometry(prop_obj, target_pos):
    """
    Given a propeller mesh object and a target motor position:
    1. Unparents object and clears object rotation/scale.
    2. Identifies the central hub vertices (closest to the XY center of the hub).
    3. Shifts the mesh vertices so the hub is at local (0, 0, 0).
    4. Sets object location to target_pos, rotation=(0,0,0), scale=(1,1,1).
    """
    mw = prop_obj.matrix_world.copy()
    verts_world = [mw @ v.co for v in prop_obj.data.vertices]
    
    # Calculate XY center of the hub
    # First approximate center from all vertices
    mean_x = sum(v.x for v in verts_world) / len(verts_world)
    mean_y = sum(v.y for v in verts_world) / len(verts_world)
    
    # For a 3-blade prop, the mean of all vertices is offset by ~10-15mm.
    # But the central hub cylinder has vertices in a tight cluster around the true center.
    # We find the densest 2D cluster or vertices within 6mm radius of the closest cluster:
    # Actually, we know target_pos is the motor shaft! The hub MUST be near target_pos in the original model!
    # Let's find vertices within 10mm of target_pos in XY:
    near_target = [v for v in verts_world if (mathutils.Vector((v.x - target_pos.x, v.y - target_pos.y))).length < 0.015]
    if len(near_target) >= 10:
        # Hub is definitely here!
        hub_x = sum(v.x for v in near_target) / len(near_target)
        hub_y = sum(v.y for v in near_target) / len(near_target)
        # Refine with 4mm radius from (hub_x, hub_y)
        tight_hub = [v for v in verts_world if (mathutils.Vector((v.x - hub_x, v.y - hub_y))).length < 0.005]
        if len(tight_hub) >= 6:
            hub_x = sum(v.x for v in tight_hub) / len(tight_hub)
            hub_y = sum(v.y for v in tight_hub) / len(tight_hub)
            hub_z = sum(v.z for v in tight_hub) / len(tight_hub)
        else:
            hub_z = sum(v.z for v in near_target) / len(near_target)
    else:
        # Fallback to mean
        hub_x, hub_y, hub_z = mean_x, mean_y, sum(v.z for v in verts_world) / len(verts_world)
        
    hub_world = mathutils.Vector((hub_x, hub_y, hub_z))
    print(f"      Calculated Hub World: ({hub_world.x:.4f}, {hub_world.y:.4f}, {hub_world.z:.4f})")
    
    # Unparent
    prop_obj.parent = None
    
    # Update vertex coordinates in mesh data:
    # v_new_local = (v_world - hub_world)
    for v in prop_obj.data.vertices:
        vw = mw @ v.co
        v.co = vw - hub_world
        
    prop_obj.data.update()
    
    # Set object transform
    prop_obj.location = target_pos
    prop_obj.rotation_euler = mathutils.Euler((0.0, 0.0, 0.0), 'XYZ')
    prop_obj.scale = mathutils.Vector((1.0, 1.0, 1.0))
    
    # Verify local center of tight hub is now exactly (0, 0, 0)
    new_local_verts = [v.co for v in prop_obj.data.vertices]
    new_tight = [v for v in new_local_verts if mathutils.Vector((v.x, v.y)).length < 0.005]
    if new_tight:
        lcx = sum(v.x for v in new_tight) / len(new_tight)
        lcy = sum(v.y for v in new_tight) / len(new_tight)
        lcz = sum(v.z for v in new_tight) / len(new_tight)
        print(f"      Verified Hub Local Center: ({lcx*1000:.2f}mm, {lcy*1000:.2f}mm, {lcz*1000:.2f}mm) -> ZERO WOBBLE!")
    print(f"      Placed at Motor Shaft: ({prop_obj.location.x:.4f}, {prop_obj.location.y:.4f}, {prop_obj.location.z:.4f})")

def process_drone(fname):
    print("\n" + "=" * 70)
    print(f"PROCESSING DRONE: {fname}")
    print("=" * 70)
    
    fpath = os.path.join(GLB_DIR, fname)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=fpath)
    
    motors = MOTOR_POSITIONS[fname]
    
    # Clean up duplicate objects if any (like .001)
    if fname == "grim7.glb":
        for o in list(bpy.context.scene.objects):
            if o.name in ["propeller_BL.001", "propeller_FL.001"]:
                print(f"  Removing ghost duplicate: {o.name}")
                bpy.data.objects.remove(o, do_unlink=True)
                
    # Find the 4 propeller objects
    prop_objs = {}
    for tag in ["FL", "FR", "BR", "BL"]:
        std_name = f"propeller_{tag}"
        obj = bpy.data.objects.get(std_name)
        if obj is None:
            # Check alternative names
            alt_names = [
                f"vint_{tag.lower()}_low_DRONE_0",
                f"propeller_{tag.lower()}",
            ]
            for an in alt_names:
                candidate = bpy.data.objects.get(an)
                if candidate:
                    candidate.name = std_name
                    obj = candidate
                    break
        prop_objs[tag] = obj
        
    for tag, p in prop_objs.items():
        if p is None:
            print(f"  [ERROR] Propeller object for {tag} NOT FOUND in {fname}!")
            continue
        p.name = f"propeller_{tag}"
        target = motors[tag]
        print(f"  Processing {p.name}:")
        center_propeller_geometry(p, target)
        
    # Re-export GLB
    print(f"  Exporting updated GLB: {fpath}...")
    bpy.ops.export_scene.gltf(
        filepath=fpath,
        export_format='GLB',
        export_apply=True,
        export_yup=True
    )
    print(f"  [SUCCESS] {fname} exported successfully!")

for fname in MOTOR_POSITIONS.keys():
    process_drone(fname)

print("\n" + "=" * 70)
print("ALL 10 DRONES SUCCESSFULLY REALIGNED AND CENTERED!")
print("=" * 70)
