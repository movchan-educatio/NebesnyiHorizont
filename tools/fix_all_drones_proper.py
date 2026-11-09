import bpy
import bmesh
import mathutils
import os

norm_dir = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\Drones\ua_norm"

# Create/get sleek PBR propeller material
def get_prop_material(name="PropellerCarbon"):
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs['Base Color'].default_value = (0.10, 0.11, 0.12, 1.0)
            bsdf.inputs['Roughness'].default_value = 0.28
            bsdf.inputs['Metallic'].default_value = 0.15
    return mat

def get_motor_bell_material(name="MotorBellMat"):
    mat = bpy.data.materials.get(name)
    if not mat:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs['Base Color'].default_value = (0.18, 0.19, 0.21, 1.0)
            bsdf.inputs['Roughness'].default_value = 0.18
            bsdf.inputs['Metallic'].default_value = 0.90
    return mat

def apply_user_3step(prop_obj, motor_obj, target_center, prop_z_offset=0.005):
    """
    User's exact 3-step workflow:
    1. Object Mode -> Ctrl + A -> All Transforms
    2. Set Origin -> To 3D Cursor (motor center)
    3. Parenting (Ctrl + P) -> Object (Keep Transform)
    """
    # 1. Unparent first if needed
    bpy.ops.object.select_all(action='DESELECT')
    prop_obj.select_set(True)
    bpy.context.view_layer.objects.active = prop_obj
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    
    # Center motor mesh at (0, 0, 0) locally
    m_vs = [v.co for v in motor_obj.data.vertices]
    m_cen = sum(m_vs, mathutils.Vector((0,0,0))) / len(m_vs)
    for v in motor_obj.data.vertices:
        v.co -= m_cen
    motor_obj.data.update()
    
    # Place motor at target_center
    motor_obj.location = target_center
    motor_obj.rotation_euler = (0, 0, 0)
    motor_obj.scale = (1, 1, 1)
    
    # Center propeller mesh at (0, 0, 0) locally around hub
    p_vs = [v.co for v in prop_obj.data.vertices]
    p_cen = sum(p_vs, mathutils.Vector((0,0,0))) / len(p_vs)
    for v in prop_obj.data.vertices:
        v.co.x -= p_cen.x
        v.co.y -= p_cen.y
        v.co.z -= p_cen.z
    prop_obj.data.update()
    
    # Place propeller right on the motor shaft
    prop_pos = mathutils.Vector((target_center.x, target_center.y, target_center.z + prop_z_offset))
    prop_obj.location = prop_pos
    prop_obj.rotation_euler = (0, 0, 0)
    prop_obj.scale = (1, 1, 1)
    
    # STEP 1: Apply All Transforms
    bpy.ops.object.select_all(action='DESELECT')
    prop_obj.select_set(True)
    bpy.context.view_layer.objects.active = prop_obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    bpy.ops.object.select_all(action='DESELECT')
    motor_obj.select_set(True)
    bpy.context.view_layer.objects.active = motor_obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # STEP 2: Set Origin -> To 3D Cursor (motor center)
    bpy.context.scene.cursor.location = prop_pos
    
    bpy.ops.object.select_all(action='DESELECT')
    motor_obj.select_set(True)
    bpy.context.view_layer.objects.active = motor_obj
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    
    bpy.ops.object.select_all(action='DESELECT')
    prop_obj.select_set(True)
    bpy.context.view_layer.objects.active = prop_obj
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    
    # STEP 3: Parenting (Ctrl + P) -> Object (Keep Transform)
    bpy.ops.object.select_all(action='DESELECT')
    prop_obj.select_set(True)
    motor_obj.select_set(True)
    bpy.context.view_layer.objects.active = motor_obj
    bpy.ops.object.parent_set(type='OBJECT', keep_transform=True)
    
    # Assign materials
    prop_mat = get_prop_material()
    if not prop_obj.data.materials:
        prop_obj.data.materials.append(prop_mat)
    else:
        prop_obj.data.materials[0] = prop_mat
        
    motor_mat = get_motor_bell_material()
    if not motor_obj.data.materials:
        motor_obj.data.materials.append(motor_mat)
    else:
        motor_obj.data.materials[0] = motor_mat

print("Defined apply_user_3step successfully!")

# ==============================================================================
# 1. FIX FALCON-X
# ==============================================================================
def fix_falcon():
    glb = os.path.join(norm_dir, "falcon_x.glb")
    print("=== FIXING FALCON-X ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    
    # Motor cup centers
    centers = {
        'FL': mathutils.Vector((-0.09437, -0.05461, 0.02450)),
        'FR': mathutils.Vector(( 0.09437, -0.05461, 0.02450)),
        'BL': mathutils.Vector((-0.09627,  0.06628, 0.11200)),
        'BR': mathutils.Vector(( 0.09627,  0.06628, 0.11200)),
    }
    prop_offsets = {'FL': 0.0047, 'FR': 0.0047, 'BL': 0.0050, 'BR': 0.0050}
    
    for corner in ['FL', 'FR', 'BL', 'BR']:
        m = bpy.data.objects.get("motor_" + corner)
        p = bpy.data.objects.get("propeller_" + corner)
        if m and p:
            apply_user_3step(p, m, centers[corner], prop_offsets[corner])
            print(f"  Falcon {corner} fixed at {centers[corner]}")
            
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=False, export_apply=False)
    print("Exported falcon_x.glb")

# ==============================================================================
# 2. FIX PELENG
# ==============================================================================
def fix_peleng():
    glb = os.path.join(norm_dir, "peleng.glb")
    print("=== FIXING PELENG ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    
    # Exact top pad centers
    centers = {
        'FL': mathutils.Vector((-0.08663,  0.08072, 0.00200)),
        'FR': mathutils.Vector(( 0.08667,  0.08078, 0.00200)),
        'BL': mathutils.Vector((-0.09184, -0.08455, 0.00971)),
        'BR': mathutils.Vector(( 0.09048, -0.08611, 0.01282)),
    }
    
    for corner in ['FL', 'FR', 'BL', 'BR']:
        m = bpy.data.objects.get("motor_" + corner)
        p = bpy.data.objects.get("propeller_" + corner)
        if m and p:
            apply_user_3step(p, m, centers[corner], 0.0045)
            print(f"  Peleng {corner} fixed at {centers[corner]}")
            
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=False, export_apply=False)
    print("Exported peleng.glb")

# ==============================================================================
# 3. FIX HOLKA
# ==============================================================================
def fix_holka():
    glb = os.path.join(norm_dir, "holka.glb")
    print("=== FIXING HOLKA ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    
    # Exact top pad centers
    centers = {
        'FL': mathutils.Vector((-0.07557,  0.07444, -0.03832)),
        'FR': mathutils.Vector(( 0.07557,  0.07444, -0.03832)),
        'BL': mathutils.Vector((-0.07533, -0.07866, -0.03986)),
        'BR': mathutils.Vector(( 0.07395, -0.07873, -0.04016)),
    }
    
    for corner in ['FL', 'FR', 'BL', 'BR']:
        m = bpy.data.objects.get("motor_" + corner)
        p = bpy.data.objects.get("propeller_" + corner)
        if m and p:
            apply_user_3step(p, m, centers[corner], 0.0045)
            print(f"  Holka {corner} fixed at {centers[corner]}")
            
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=False, export_apply=False)
    print("Exported holka.glb")

# ==============================================================================
# 4. FIX AVATA 2
# ==============================================================================
def fix_avata2():
    glb = os.path.join(norm_dir, "avata2.glb")
    print("=== FIXING AVATA 2 ===")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    
    # Exact shaft centers
    centers = {
        'FL': mathutils.Vector((-0.05896,  0.03586, -0.00846)),
        'FR': mathutils.Vector(( 0.05800,  0.03586, -0.00846)),
        'BL': mathutils.Vector((-0.05928, -0.05393, -0.00846)),
        'BR': mathutils.Vector(( 0.05818, -0.05391, -0.00846)),
    }
    
    for corner in ['FL', 'FR', 'BL', 'BR']:
        m = bpy.data.objects.get("motor_" + corner)
        p = bpy.data.objects.get("propeller_" + corner)
        if m and p:
            apply_user_3step(p, m, centers[corner], 0.0045)
            print(f"  Avata 2 {corner} fixed at {centers[corner]}")
            
    bpy.ops.export_scene.gltf(filepath=glb, export_format='GLB', use_selection=False, export_apply=False)
    print("Exported avata2.glb")

# Run all 4 fixes:
fix_falcon()
fix_peleng()
fix_holka()
fix_avata2()
print("ALL 4 DRONES FIXED!")
