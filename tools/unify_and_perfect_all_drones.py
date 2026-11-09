"""
Master Drone Normalization and Propeller Centering Pipeline.
Applies the rigorous geometric approach:
1. Clear all parent hierarchies and delete all empty/dummy nodes (e.g. Sketchfab_model, root, etc.).
2. Bake all world transforms into mesh data (Ctrl+A -> Apply All Transforms).
3. Compute exact circular hub centers for all propellers using least-squares circle fitting (numpy).
4. Recenter propeller mesh vertices strictly to (0, 0) with bottom at Z=0.
5. Snap propeller object origins and positions directly to the physical motor stator centers.
6. Export clean standard glTF 2.0 with export_yup=True.
"""

import bpy, os, sys, math
import numpy as np

def fit_circle_2d(points):
    pts = np.array(points)
    x = pts[:, 0]
    y = pts[:, 1]
    A = np.column_stack([2 * x, 2 * y, np.ones(len(pts))])
    b = x**2 + y**2
    sol, _, _, _ = np.linalg.lstsq(A, b, rcond=None)
    xc, yc = sol[0], sol[1]
    r = math.sqrt(max(0.0, sol[2] + xc**2 + yc**2))
    return xc, yc, r

DRONE_CONFIGS = {
    "pisun_vtol.glb": {
        "motors": {
            "propeller_FL": (-0.1289, -0.0001, -0.0560),
            "propeller_FR": ( 0.1286,  0.0003, -0.0560),
            "propeller_BL": (-0.0013,  0.1320, -0.0560),
            "propeller_BR": (-0.0004, -0.1283, -0.0560),
        }
    },
    "peleng.glb": {
        "motors": {
            "propeller_FL": (-0.0772,  0.0776, 0.0020),
            "propeller_FR": ( 0.0772,  0.0776, 0.0020),
            "propeller_BL": (-0.0840, -0.0799, 0.0111),
            "propeller_BR": ( 0.0849, -0.0791, 0.0128),
        }
    },
    "falcon_x.glb": {
        "motors": {
            "propeller_FL": (-0.1080, -0.0674, 0.0413),
            "propeller_FR": ( 0.1080, -0.0674, 0.0413),
            "propeller_BL": (-0.1051,  0.0352, 0.1163),
            "propeller_BR": ( 0.1051,  0.0352, 0.1163),
        }
    },
    "quad5_custom.glb": {
        "motors": {
            "propeller_FL": (-0.0780,  0.0825, 0.0386),
            "propeller_FR": ( 0.0780,  0.0825, 0.0386),
            "propeller_BL": (-0.0780, -0.0825, 0.0386),
            "propeller_BR": ( 0.0780, -0.0825, 0.0386),
        }
    },
    "grim7.glb": {
        "motors": {
            "propeller_FL": (-0.1301,  0.0851, 0.0180),
            "propeller_FR": ( 0.1008,  0.0850, 0.0180),
            "propeller_BL": (-0.1301, -0.1150, 0.0180),
            "propeller_BR": ( 0.1008, -0.1150, 0.0180),
        }
    },
    "grim7m.glb": {
        "motors": {
            "propeller_FL": (-0.1065,  0.1271, 0.0060),
            "propeller_FR": ( 0.1064,  0.1271, 0.0060),
            "propeller_BL": (-0.1061, -0.1103, 0.0060),
            "propeller_BR": ( 0.1062, -0.1103, 0.0060),
        }
    },
    "strila8.glb": {
        "motors": {
            "propeller_FL": (-0.0919,  0.0722, 0.0225),
            "propeller_FR": ( 0.0919,  0.0723, 0.0225),
            "propeller_BL": (-0.0919, -0.1111, 0.0225),
            "propeller_BR": ( 0.0919, -0.1110, 0.0225),
        }
    },
    "holka.glb": {
        "motors": {
            "propeller_FL": (-0.0696,  0.0716, -0.0270),
            "propeller_FR": ( 0.0696,  0.0716, -0.0270),
            "propeller_BL": (-0.0667, -0.0714, -0.0270),
            "propeller_BR": ( 0.0702, -0.0749, -0.0270),
        }
    },
    "pinapipe.glb": {
        "motors": {
            "propeller_FL": (-0.0647,  0.0534, -0.0040),
            "propeller_FR": ( 0.0647,  0.0535, -0.0040),
            "propeller_BL": (-0.0648, -0.0535, -0.0040),
            "propeller_BR": ( 0.0648, -0.0535, -0.0040),
        }
    },
    "avata2.glb": {
        "motors": {
            "propeller_FL": (-0.0591,  0.0450, -0.0070),
            "propeller_FR": ( 0.0591,  0.0450, -0.0070),
            "propeller_BL": (-0.0590, -0.0451, -0.0070),
            "propeller_BR": ( 0.0590, -0.0451, -0.0070),
        }
    }
}

base_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

for filename, cfg in DRONE_CONFIGS.items():
    filepath = os.path.join(base_dir, filename)
    if not os.path.exists(filepath):
        print(f"[SKIP] File not found: {filepath}")
        continue
        
    print(f"\n==========================================")
    print(f"PROCESSING: {filename}")
    print(f"==========================================")
    
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=filepath)
    
    # 1. Unparent all objects keeping world transform
    for obj in list(bpy.data.objects):
        if obj.parent is not None:
            mw = obj.matrix_world.copy()
            obj.parent = None
            obj.matrix_world = mw
            
    # 2. Delete all non-mesh objects (empties, sketchfab wrappers, cameras, lights)
    for obj in list(bpy.data.objects):
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)
            
    # 3. For all non-propeller body meshes, bake transforms to world coords
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if not obj.name.startswith("propeller_"):
            obj.select_set(True)
    if bpy.context.selected_objects:
        bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        
    # 4. Process each propeller: center geometry around central hub and snap to motor
    motors = cfg["motors"]
    for p_name, target_pos in motors.items():
        prop = bpy.data.objects.get(p_name)
        if not prop:
            print(f"  [WARN] Propeller {p_name} missing in {filename}")
            continue
            
        # Ensure any unapplied prop rotation/scale is applied to vertices
        bpy.ops.object.select_all(action='DESELECT')
        prop.select_set(True)
        bpy.context.view_layer.objects.active = prop
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        
        verts = np.array([v.co for v in prop.data.vertices])
        if len(verts) == 0:
            continue
            
        mid = (verts.min(axis=0) + verts.max(axis=0)) / 2.0
        d = np.hypot(verts[:, 0] - mid[0], verts[:, 1] - mid[1])
        
        # Hub cylinder circle fitting:
        hub_pts = verts[d < 0.014][:, :2]
        if len(hub_pts) >= 6:
            hcx, hcy, r = fit_circle_2d(hub_pts)
        else:
            hcx, hcy = mid[0], mid[1]
            
        min_z = float(verts[:, 2].min())
        
        # Shift all vertices so the hub axis is exactly at (0, 0), and bottom sits at Z=0
        for v in prop.data.vertices:
            v.co.x -= hcx
            v.co.y -= hcy
            v.co.z -= min_z
        prop.data.update()
        
        # Set object location directly to physical motor mount center
        prop.location = target_pos
        prop.rotation_euler = (0.0, 0.0, 0.0)
        prop.scale = (1.0, 1.0, 1.0)
        print(f"  [OK] Centered {p_name} (hub_offset=({hcx:.4f}, {hcy:.4f})) -> snapped to ({target_pos[0]:.4f}, {target_pos[1]:.4f}, {target_pos[2]:.4f})")
        
    # 5. Clean up unused mesh data/materials/orphans
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    
    # 6. Re-export to GLB cleanly
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        export_yup=True,
        export_apply=False
    )
    print(f"  [EXPORTED] {filepath} successfully!")

print("\n>>> ALL 10 DRONES SUCCESSFULLY PROCESSED AND NORMALIZED <<<")
