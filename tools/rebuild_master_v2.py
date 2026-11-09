"""
Master Drone Rebuild v2:
Rebuilds all 10 flying drones in res://Assets/Drones/ua_norm/ with exact geometric
motor coordinates, pristine reference 3-blade propellers (CW/CCW), zero origin offset,
and correct shaft orientation.
"""

import bpy, os, sys, math
import numpy as np

BASE_DIR = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"
REF_PROP = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\Parts\Propellers\Propeller1\Propeller1.glb"

# Configuration for all 10 drones:
# Coordinates are in Blender space: (X, Y, Z) where Z is UP.
# For each motor: (location_xyz, normal_xyz)
DRONE_CONFIGS = {
    # 0. «ГОЛКА» (5.1")
    "holka.glb": {
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0498,  0.0551, -0.0274), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0498,  0.0551, -0.0274), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0380, -0.0643, -0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0373, -0.0634, -0.0262), (0.0, 0.0, 1.0)),
        }
    },
    # 1. PinaPipe (5.1")
    "pinapipe.glb": {
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0641,  0.0490, -0.0058), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0643,  0.0493, -0.0058), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0631, -0.0496, -0.0058), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0638, -0.0495, -0.0058), (0.0, 0.0, 1.0)),
        }
    },
    # 2. DJI Avata 2 (3.0" Cinewhoop)
    "avata2.glb": {
        "prop_d": 3.0,
        "clean_body_islands": True, # Clean static blades if any
        "motors": {
            "propeller_FL": ((-0.0586,  0.0458, -0.0060), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0586,  0.0458, -0.0060), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0586, -0.0437, -0.0060), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0586, -0.0437, -0.0060), (0.0, 0.0, 1.0)),
        }
    },
    # 3. «Пісюн» VTOL (7.0")
    # In ua_norm/pisun_vtol.glb, the fuselage is along Z (+Z is nose).
    # Motors mount at Z = -0.0526 and shafts point along +Z!
    "pisun_vtol.glb": {
        "prop_d": 7.0,
        "motors": {
            "propeller_FL": ((-0.1357,  0.0008, -0.0526), (0.0, 0.0, 1.0)), # Left wing
            "propeller_FR": (( 0.1368, -0.0001, -0.0526), (0.0, 0.0, 1.0)), # Right wing
            "propeller_BR": ((-0.0022, -0.1322, -0.0524), (0.0, 0.0, 1.0)), # Bottom fin
            "propeller_BL": ((-0.0012,  0.1374, -0.0526), (0.0, 0.0, 1.0)), # Top fin
        }
    },
    # 4. «Пеленг» (5.1")
    "peleng.glb": {
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.0870,  0.0797,  0.0012), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0870,  0.0797,  0.0012), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0896, -0.0846,  0.0113), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0828, -0.0804,  0.0102), (0.0, 0.0, 1.0)),
        }
    },
    # 5. «Грім-7» (8.0")
    "grim7.glb": {
        "prop_d": 8.0,
        "motors": {
            "propeller_FL": ((-0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
        }
    },
    # 6. «Грім-7М» (8.0")
    "grim7m.glb": {
        "prop_d": 8.0,
        "motors": {
            "propeller_FL": ((-0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1556,  0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1556, -0.1552, 0.0262), (0.0, 0.0, 1.0)),
        }
    },
    # 7. «Стріла-8» (8.5")
    "strila8.glb": {
        "prop_d": 8.5,
        "motors": {
            "propeller_FL": ((-0.0917,  0.0684, 0.0150), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0957,  0.0722, 0.0150), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0970, -0.1163, 0.0150), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0851, -0.1172, 0.0150), (0.0, 0.0, 1.0)),
        }
    },
    # 8. «Falcon-X» Digital (5.1")
    # Motor sockets in Object_28
    "falcon_x.glb": {
        "prop_d": 5.1,
        "motors": {
            "propeller_FL": ((-0.1004, -0.0546, 0.0383), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1004, -0.0546, 0.0383), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0986,  0.0615, 0.1201), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0986,  0.0615, 0.1201), (0.0, 0.0, 1.0)),
        }
    },
    # 9. «Quad-5» Custom (5.0")
    "quad5_custom.glb": {
        "prop_d": 5.0,
        "motors": {
            "propeller_FL": ((-0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
        }
    },
}

# 1. Load pristine reference propellers
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=REF_PROP)
cw_ref = bpy.data.objects.get("CW")
ccw_ref = bpy.data.objects.get("CCW")

cw_verts_base = np.array([v.co for v in cw_ref.data.vertices])
ccw_verts_base = np.array([v.co for v in ccw_ref.data.vertices])
cw_polys = [p.vertices[:] for p in cw_ref.data.polygons]
ccw_polys = [p.vertices[:] for p in ccw_ref.data.polygons]

print("[OK] Reference propeller templates loaded.")

for filename, cfg in DRONE_CONFIGS.items():
    filepath = os.path.join(BASE_DIR, filename)
    print(f"\n==========================================")
    print(f"REBUILDING MASTER: {filename}")
    print(f"==========================================")
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    # Unparent everything preserving world transforms
    for obj in list(bpy.data.objects):
        if obj.parent is not None:
            mw = obj.matrix_world.copy()
            obj.parent = None
            obj.matrix_world = mw
            
    # Remove non-meshes
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)
            
    # Remove any existing propeller objects
    for obj in list(bpy.data.objects):
        if obj.name.startswith("propeller_"):
            bpy.data.objects.remove(obj, do_unlink=True)
            
    # Apply transform to all body objects so origins are clean at (0,0,0)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        obj.select_set(True)
    if bpy.context.selected_objects:
        bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        
    motors = cfg["motors"]
    prop_scale = cfg["prop_d"] / 5.1
    
    for p_name, (target_pos, normal) in motors.items():
        is_cw = (p_name in ["propeller_FL", "propeller_BR"])
        mesh_data = bpy.data.meshes.new(p_name)
        base_verts = cw_verts_base if is_cw else ccw_verts_base
        base_polys = cw_polys if is_cw else ccw_polys
        
        # Scale reference propeller exactly
        scaled_verts = base_verts * prop_scale
        mesh_data.from_pydata(scaled_verts.tolist(), [], base_polys)
        mesh_data.update()
        
        prop = bpy.data.objects.new(p_name, mesh_data)
        bpy.context.scene.collection.objects.link(prop)
        
        # Set exact position on motor mount
        prop.location = target_pos
        prop.rotation_euler = (0.0, 0.0, 0.0) # Local Z is shaft, UP in Godot
        prop.scale = (1.0, 1.0, 1.0)
        print(f"  + Added {p_name} ({'CW' if is_cw else 'CCW'}) at ({target_pos[0]:.4f}, {target_pos[1]:.4f}, {target_pos[2]:.4f})")
        
    # Purge unused data
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    
    # Export back to GLB
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        export_yup=True,
        export_apply=False
    )
    print(f"  [SAVED] {filename}")

print("\n>>> ALL 10 MASTER DRONES REBUILT SUCCESSFULLY <<<")
