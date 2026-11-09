"""
Rebuilds all 10 drones in res://Assets/Drones/ua_norm/ with verified motor coordinates,
pristine propeller geometry, and correct shaft orientations.
"""

import bpy, os, sys, math
import numpy as np

BASE_DIR = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
REF_PROP = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\Parts\Propellers\Propeller1\Propeller1.glb"

# Exact motor mount coordinates in Blender coordinate system (Z is up, Y is forward/back)
DRONE_CONFIGS = {
    "falcon_x.glb": {
        "use_custom_props": True,
        "motors": {
            "propeller_FL": ((-0.0993, -0.0506, 0.0150), (0.02, 0.20, 0.98)),
            "propeller_FR": (( 0.0993, -0.0506, 0.0150), (-0.02, 0.20, 0.98)),
            "propeller_BL": ((-0.0957,  0.0606, 0.1043), (0.06, 0.09, 0.99)),
            "propeller_BR": (( 0.0957,  0.0606, 0.1043), (-0.06, 0.09, 0.99)),
        }
    },
    "peleng.glb": {
        "use_custom_props": False,
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0880,  0.0640, 0.0020), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0880,  0.0640, 0.0020), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0690, -0.0740, 0.0130), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0690, -0.0740, 0.0130), (0.0, 0.0, 1.0)),
        }
    },
    "pisun_vtol.glb": {
        "use_custom_props": True,
        "motors": {
            "propeller_FL": ((-0.1278, -0.0001, -0.0580), (0.0, 1.0, 0.0)),
            "propeller_FR": (( 0.1256,  0.0005, -0.0580), (0.0, 1.0, 0.0)),
            "propeller_BL": ((-0.0011,  0.1293, -0.0580), (0.0, 1.0, 0.0)),
            "propeller_BR": ((-0.0006, -0.1256, -0.0580), (0.0, 1.0, 0.0)),
        }
    },
    "avata2.glb": {
        "use_custom_props": True,
        "motors": {
            "propeller_FL": ((-0.0575,  0.0451, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0575,  0.0451, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0585, -0.0450, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0585, -0.0450, 0.0008), (0.0, 0.0, 1.0)),
        }
    },
    "grim7.glb": {
        "use_custom_props": False,
        "prop_d": 8.0,
        "motors": {
            "propeller_FL": ((-0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
        }
    },
    "grim7m.glb": {
        "use_custom_props": False,
        "prop_d": 8.0,
        "motors": {
            "propeller_FL": ((-0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
        }
    },
    "strila8.glb": {
        "use_custom_props": False,
        "prop_d": 8.5,
        "motors": {
            "propeller_FL": ((-0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
        }
    },
    "quad5_custom.glb": {
        "use_custom_props": False,
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
        }
    },
    "holka.glb": {
        "use_custom_props": False,
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0524,  0.0669, -0.0298), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0525,  0.0672, -0.0297), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0517, -0.0643, -0.0303), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0544, -0.0673, -0.0305), (0.0, 0.0, 1.0)),
        }
    },
    "pinapipe.glb": {
        "use_custom_props": False,
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0590,  0.0496, -0.0089), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0590,  0.0496, -0.0089), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0584, -0.0490, -0.0091), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0584, -0.0490, -0.0091), (0.0, 0.0, 1.0)),
        }
    }
}

# 1. Load reference propeller data (CW and CCW)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=REF_PROP)
cw_ref = bpy.data.objects.get("CW")
ccw_ref = bpy.data.objects.get("CCW")

# Extract reference vertex arrays
cw_verts_base = np.array([v.co for v in cw_ref.data.vertices])
ccw_verts_base = np.array([v.co for v in ccw_ref.data.vertices])

cw_polys = [p.vertices[:] for p in cw_ref.data.polygons]
ccw_polys = [p.vertices[:] for p in ccw_ref.data.polygons]

print("[OK] Reference propeller loaded (CW & CCW)")

# 2. Process each drone
for filename, cfg in DRONE_CONFIGS.items():
    filepath = os.path.join(BASE_DIR, filename)
    print(f"\n==========================================")
    print(f"PROCESSING: {filename}")
    print(f"==========================================")
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    # Unparent everything keeping world coordinates
    for obj in list(bpy.data.objects):
        if obj.parent is not None:
            mw = obj.matrix_world.copy()
            obj.parent = None
            obj.matrix_world = mw
            
    # Remove non-meshes
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)
            
    # Apply transforms to all body parts
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if not obj.name.startswith("propeller_"):
            obj.select_set(True)
    if bpy.context.selected_objects:
        bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        
    motors = cfg["motors"]
    use_custom = cfg.get("use_custom_props", False)
    prop_scale = cfg.get("prop_d", 5.0) / 5.1
    
    for p_name, (target_pos, normal) in motors.items():
        is_cw = (p_name in ["propeller_FL", "propeller_BR"])
        
        if not use_custom:
            # Replace with reference pristine propeller mesh
            old_prop = bpy.data.objects.get(p_name)
            if old_prop:
                bpy.data.objects.remove(old_prop, do_unlink=True)
                
            mesh_data = bpy.data.meshes.new(p_name)
            base_verts = cw_verts_base if is_cw else ccw_verts_base
            base_polys = cw_polys if is_cw else ccw_polys
            
            # Scale reference prop to target prop diameter
            scaled_verts = base_verts * prop_scale
            mesh_data.from_pydata(scaled_verts.tolist(), [], base_polys)
            mesh_data.update()
            
            prop = bpy.data.objects.new(p_name, mesh_data)
            bpy.context.scene.collection.objects.link(prop)
        else:
            # Custom propeller (e.g. Falcon-X or Avata or Pisun)
            prop = bpy.data.objects.get(p_name)
            if not prop:
                print(f"  [WARN] Missing {p_name}")
                continue
                
        # Set exact location
        prop.location = target_pos
        
        # Set orientation aligned with motor normal
        nx, ny, nz = normal
        # Calculate Euler angles for normal
        # Standard normal is (0, 0, 1)
        rot_x = math.atan2(ny, nz) if (nz != 0 or ny != 0) else 0.0
        rot_y = -math.atan2(nx, math.sqrt(ny*ny + nz*nz))
        if normal == (0.0, 1.0, 0.0):
            # Pointing along +Y (forward, e.g. Pisun VTOL nacelle)
            prop.rotation_euler = (math.radians(-90), 0.0, 0.0)
        else:
            prop.rotation_euler = (rot_x, rot_y, 0.0)
            
        prop.scale = (1.0, 1.0, 1.0)
        print(f"  [OK] Placed {p_name} at ({target_pos[0]:.4f}, {target_pos[1]:.4f}, {target_pos[2]:.4f}), rot=({math.degrees(prop.rotation_euler.x):.1f}°, {math.degrees(prop.rotation_euler.y):.1f}°)")

    # Clean orphaned data
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    
    # Export back to GLB
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        export_yup=True,
        export_apply=False
    )
    print(f"  [EXPORTED] {filename} successfully!")

print("\n>>> MASTER REBUILD OF ALL 10 DRONES COMPLETE <<<")
