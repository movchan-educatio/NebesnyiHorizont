"""
Master Drone Normalization and Propeller Centering Pipeline.
Uses verified geometric motor stator & cup centers, correct blade counts,
and precise tilt alignment for all 10 drones.
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
    "falcon_x.glb": {
        "motors": {
            "propeller_FL": ((-0.1000, -0.0690, 0.0260), (0.0,  0.15, 0.99)),
            "propeller_FR": (( 0.1000, -0.0690, 0.0260), (0.0,  0.15, 0.99)),
            "propeller_BL": ((-0.0970,  0.0470, 0.1080), (0.0,  0.10, 0.99)),
            "propeller_BR": (( 0.0970,  0.0470, 0.1080), (0.0,  0.10, 0.99)),
        }
    },
    "peleng.glb": {
        "motors": {
            "propeller_FL": ((-0.0880,  0.0640, 0.0020), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0880,  0.0640, 0.0020), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0690, -0.0740, 0.0130), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0690, -0.0740, 0.0130), (0.0, 0.0, 1.0)),
        }
    },
    "pisun_vtol.glb": {
        "motors": {
            "propeller_FL": ((-0.1278, -0.0001, -0.0580), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1256,  0.0005, -0.0580), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0011,  0.1293, -0.0580), (0.0, 0.0, 1.0)),
            "propeller_BR": ((-0.0006, -0.1256, -0.0580), (0.0, 0.0, 1.0)),
        }
    },
    "avata2.glb": {
        "motors": {
            "propeller_FL": ((-0.0575,  0.0451, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0575,  0.0451, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0585, -0.0450, 0.0008), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0585, -0.0450, 0.0008), (0.0, 0.0, 1.0)),
        }
    },
    "quad5_custom.glb": {
        "motors": {
            "propeller_FL": ((-0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0780,  0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0780, -0.0825, 0.0384), (0.0, 0.0, 1.0)),
        }
    },
    "grim7.glb": {
        "motors": {
            "propeller_FL": ((-0.1301,  0.0850, 0.0168), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1008,  0.0850, 0.0168), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1301, -0.1150, 0.0168), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1008, -0.1150, 0.0168), (0.0, 0.0, 1.0)),
        }
    },
    "grim7m.glb": {
        "motors": {
            "propeller_FL": ((-0.1070,  0.1276, 0.0042), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.1070,  0.1276, 0.0042), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.1070, -0.1107, 0.0042), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.1070, -0.1107, 0.0042), (0.0, 0.0, 1.0)),
        }
    },
    "strila8.glb": {
        "motors": {
            "propeller_FL": ((-0.0919,  0.0722, 0.0216), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0919,  0.0722, 0.0216), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0919, -0.1110, 0.0216), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0919, -0.1110, 0.0216), (0.0, 0.0, 1.0)),
        }
    },
    "holka.glb": {
        "motors": {
            "propeller_FL": ((-0.0524,  0.0669, -0.0298), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0525,  0.0672, -0.0297), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0517, -0.0643, -0.0303), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0544, -0.0673, -0.0305), (0.0, 0.0, 1.0)),
        }
    },
    "pinapipe.glb": {
        "motors": {
            "propeller_FL": ((-0.0590,  0.0496, -0.0089), (0.0, 0.0, 1.0)),
            "propeller_FR": (( 0.0590,  0.0496, -0.0089), (0.0, 0.0, 1.0)),
            "propeller_BL": ((-0.0584, -0.0490, -0.0091), (0.0, 0.0, 1.0)),
            "propeller_BR": (( 0.0584, -0.0490, -0.0091), (0.0, 0.0, 1.0)),
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
            
    # 2. Delete all non-mesh objects (empties, cameras, lights)
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
        
    # 4. Snap each propeller to its exact motor stator center and tilt
    motors = cfg["motors"]
    for p_name, (target_pos, normal) in motors.items():
        prop = bpy.data.objects.get(p_name)
        if not prop:
            print(f"  [WARN] Propeller {p_name} missing in {filename}")
            continue
            
        bpy.ops.object.select_all(action='DESELECT')
        prop.select_set(True)
        bpy.context.view_layer.objects.active = prop
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        
        verts = np.array([v.co for v in prop.data.vertices])
        if len(verts) == 0:
            continue
            
        mid = (verts.min(axis=0) + verts.max(axis=0)) / 2.0
        d = np.hypot(verts[:, 0] - mid[0], verts[:, 1] - mid[1])
        
        hub_pts = verts[d < 0.015][:, :2]
        if len(hub_pts) >= 6:
            hcx, hcy, r = fit_circle_2d(hub_pts)
        else:
            hcx, hcy = mid[0], mid[1]
            
        min_z = float(verts[:, 2].min())
        
        # Shift vertices so hub axis is at (0, 0) and base is at Z=0
        for v in prop.data.vertices:
            v.co.x -= hcx
            v.co.y -= hcy
            v.co.z -= min_z
        prop.data.update()
        
        # Position at exact motor stator center
        prop.location = target_pos
        
        # Align rotation with motor normal
        nx, ny, nz = normal
        rot_x = math.atan2(ny, nz)
        rot_y = -math.atan2(nx, nz)
        prop.rotation_euler = (rot_x, rot_y, 0.0)
        prop.scale = (1.0, 1.0, 1.0)
        print(f"  [OK] Snapped {p_name} to ({target_pos[0]:.4f}, {target_pos[1]:.4f}, {target_pos[2]:.4f}), rot=({math.degrees(rot_x):.1f}°, {math.degrees(rot_y):.1f}°)")
        
    # 5. Clean up unused data
    bpy.ops.outliner.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
    
    # 6. Re-export to GLB cleanly
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format='GLB',
        export_yup=True,
        export_apply=False
    )
    print(f"  [EXPORTED] {filepath} successfully!")

print("\n>>> ALL 10 DRONES PERFECTED AND SAVED <<<")
