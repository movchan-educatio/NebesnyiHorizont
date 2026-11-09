"""
==============================================================================
FPV DRONE MODULAR PARTS GENERATOR FOR BLENDER (Python API)
==============================================================================
Generates modular FPV drone components (Frames, Motors, Props, Batteries,
Cameras, Payloads) for both civilian/racing and military/combat tiers.
Sets logical Origin points, applies transforms, assigns PBR materials,
organizes into collections, and exports each part as an optimized .glb mesh
along with a comprehensive drone_parts_data.json specification for Godot 4.

Compatible with Blender 4.x and 5.x.
Run from Blender's 'Scripting' workspace or via CLI:
  blender --background --python generate_drone_parts.py
==============================================================================
"""

import bpy
import bmesh
import math
import mathutils
import os
import json

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__)) if "__file__" in locals() else os.path.expanduser("~")
EXPORT_DIR = os.path.join(SCRIPT_DIR, "assets", "drone_parts")
JSON_OUTPUT_PATH = os.path.join(EXPORT_DIR, "drone_parts_data.json")

os.makedirs(EXPORT_DIR, exist_ok=True)

# -----------------------------------------------------------------------------
# MATRIX & BMESH PRIMITIVE HELPERS
# -----------------------------------------------------------------------------
def mat_trans(tx, ty, tz):
    return mathutils.Matrix.Translation((tx, ty, tz))

def mat_scale(sx, sy, sz):
    return mathutils.Matrix.Diagonal((sx, sy, sz, 1.0))

def mat_rot_z(angle_rad):
    return mathutils.Matrix.Rotation(angle_rad, 4, 'Z')

def mat_rot_x(angle_rad):
    return mathutils.Matrix.Rotation(angle_rad, 4, 'X')

def mat_rot_y(angle_rad):
    return mathutils.Matrix.Rotation(angle_rad, 4, 'Y')

def bmesh_cylinder(bm, radius, depth, matrix=None, cap_ends=True, segments=16):
    if matrix is None:
        matrix = mathutils.Matrix.Identity(4)
    return bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius,
        depth=depth,
        matrix=matrix
    )

def bmesh_cone(bm, radius1, radius2, depth, matrix=None, cap_ends=True, segments=16):
    if matrix is None:
        matrix = mathutils.Matrix.Identity(4)
    return bmesh.ops.create_cone(
        bm,
        cap_ends=cap_ends,
        cap_tris=False,
        segments=segments,
        radius1=radius1,
        radius2=radius2,
        depth=depth,
        matrix=matrix
    )

# -----------------------------------------------------------------------------
# SCENE & UTILITY HELPERS
# -----------------------------------------------------------------------------
def reset_scene():
    """Clear all objects, meshes, and materials in the current scene."""
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for block in bpy.data.meshes:
        if block.users == 0:
            bpy.data.meshes.remove(block)
    for block in bpy.data.materials:
        if block.users == 0:
            bpy.data.materials.remove(block)
    for coll in bpy.data.collections:
        if coll.name != "Master Collection":
            bpy.data.collections.remove(coll)

def get_or_create_collection(name):
    """Ensure a named collection exists in the scene hierarchy."""
    if name in bpy.data.collections:
        return bpy.data.collections[name]
    coll = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(coll)
    return coll

def get_or_create_material(name, color_rgba, metallic=0.0, roughness=0.5):
    """Create or return a Principled BSDF material with PBR properties."""
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name=name)
    # Avoid deprecated use_nodes warning in Blender 5/6 if possible
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
    if bsdf:
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = color_rgba
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness
    return mat

def apply_material(obj, mat):
    """Assign material to object."""
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)

def finalize_object(obj, collection, origin=(0, 0, 0)):
    """Apply transforms, set origin, and link to collection."""
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # Set cursor to desired origin and set origin to cursor
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.context.scene.cursor.location = (0, 0, 0)
    
    # Link to collection and unlink from other
    for coll in list(obj.users_collection):
        if coll != collection:
            coll.objects.unlink(obj)
    if obj.name not in collection.objects:
        collection.objects.link(obj)
    obj.select_set(False)

# -----------------------------------------------------------------------------
# 1. FRAME GENERATORS
# -----------------------------------------------------------------------------
def create_frame_race_5(coll, mat_carbon, mat_standoff):
    """Lightweight 5-inch True-X Racing Frame."""
    diag = 0.220 # 220mm motor-to-motor
    arm_len = diag / 2.0
    arm_w = 0.012
    thick = 0.004
    
    bm = bmesh.new()
    
    # Center deck
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_scale(0.045, 0.075, thick))
    
    # 4 True-X arms at 45, 135, 225, 315 deg
    angles = [math.radians(45), math.radians(135), math.radians(225), math.radians(315)]
    for a in angles:
        cx = math.cos(a) * (arm_len / 2.0)
        cy = math.sin(a) * (arm_len / 2.0)
        m_arm = mat_trans(cx, cy, 0) @ mat_rot_z(a) @ mat_scale(arm_len, arm_w, thick)
        bmesh.ops.create_cube(bm, size=1.0, matrix=m_arm)
        
        # Motor pad at the end of each arm
        pad_x = math.cos(a) * arm_len
        pad_y = math.sin(a) * arm_len
        bmesh_cylinder(bm, radius=0.015, depth=thick, matrix=mat_trans(pad_x, pad_y, 0))
        
    # Top plate
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, 0.022) @ mat_scale(0.035, 0.065, 0.002))
    
    # 4 Standoff posts
    for sx, sy in [(-0.015, -0.025), (0.015, -0.025), (-0.015, 0.025), (0.015, 0.025)]:
        bmesh_cylinder(bm, radius=0.0025, depth=0.022, matrix=mat_trans(sx, sy, 0.011), segments=12)
        
    mesh = bpy.data.meshes.new("Frame_Race_5")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Frame_Race_5", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_carbon)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

def create_frame_freestyle_7(coll, mat_carbon, mat_standoff):
    """Stretched-X 7-inch Freestyle / Long-Range Frame with Camera Cage."""
    thick = 0.0055
    bm = bmesh.new()
    
    # Long central bus deck
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_scale(0.055, 0.190, thick))
    
    # Stretched Deadcat arm positions
    motor_positions = [
        (-0.125, 0.085),  # Front Left
        (0.125, 0.085),   # Front Right
        (-0.105, -0.115), # Rear Left
        (0.105, -0.115)   # Rear Right
    ]
    for mx, my in motor_positions:
        cx, cy = mx / 2.0, my / 2.0
        arm_len = math.sqrt(mx*mx + my*my)
        angle = math.atan2(my, mx)
        m_arm = mat_trans(cx, cy, 0) @ mat_rot_z(angle) @ mat_scale(arm_len, 0.015, thick)
        bmesh.ops.create_cube(bm, size=1.0, matrix=m_arm)
        # Motor pad
        bmesh_cylinder(bm, radius=0.018, depth=thick, matrix=mat_trans(mx, my, 0))
        
    # Upper deck plate
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, -0.015, 0.026) @ mat_scale(0.045, 0.160, 0.0025))
    
    # Front camera cage / TPU protection wedge
    m_cage = mat_trans(0, 0.090, 0.016) @ mat_rot_x(math.radians(-25)) @ mat_scale(0.038, 0.040, 0.028)
    bmesh.ops.create_cube(bm, size=1.0, matrix=m_cage)
    
    # 6 standoffs
    for sx, sy in [(-0.02, -0.08), (0.02, -0.08), (-0.02, 0.0), (0.02, 0.0), (-0.02, 0.06), (0.02, 0.06)]:
        bmesh_cylinder(bm, radius=0.0025, depth=0.026, matrix=mat_trans(sx, sy, 0.013), segments=12)
        
    mesh = bpy.data.meshes.new("Frame_Freestyle_7")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Frame_Freestyle_7", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_carbon)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

def create_frame_heavy_10(coll, mat_carbon, mat_metal):
    """10-inch Reinforced Military Kamikaze Frame with Double Truss Arms."""
    thick = 0.008 # 8mm carbon
    bm = bmesh.new()
    
    # Armor Center Plates (Bottom & Top)
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_scale(0.085, 0.240, thick))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, 0.034) @ mat_scale(0.075, 0.210, 0.004))
    
    # 4 Heavy 10-inch Truss Arms
    motor_coords = [(-0.160, 0.160), (0.160, 0.160), (-0.160, -0.160), (0.160, -0.160)]
    for mx, my in motor_coords:
        cx, cy = mx / 2.0, my / 2.0
        arm_len = math.sqrt(mx*mx + my*my)
        angle = math.atan2(my, mx)
        m_arm = mat_trans(cx, cy, 0) @ mat_rot_z(angle) @ mat_scale(arm_len, 0.024, thick)
        bmesh.ops.create_cube(bm, size=1.0, matrix=m_arm)
        # Heavy motor pad
        bmesh_cylinder(bm, radius=0.022, depth=thick, matrix=mat_trans(mx, my, 0))
        
    # Cross reinforcement braces (truss struts)
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0.11, 0.005) @ mat_scale(0.180, 0.012, 0.004))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, -0.11, 0.005) @ mat_scale(0.180, 0.012, 0.004))
    
    # Underbelly heavy payload mounting rails
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(-0.025, 0, -0.015) @ mat_scale(0.010, 0.200, 0.020))
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0.025, 0, -0.015) @ mat_scale(0.010, 0.200, 0.020))
    
    mesh = bpy.data.meshes.new("Frame_Heavy_10")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Frame_Heavy_10", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_carbon)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

def create_frame_cinewhoop_3(coll, mat_carbon, mat_duct):
    """3-inch Cinewhoop Frame with Aerodynamic Propeller Ducts."""
    thick = 0.003
    bm = bmesh.new()
    
    # Central fuselage
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_scale(0.042, 0.095, thick))
    
    # 4 Duct Rings around each motor
    duct_radius = 0.045 # 90mm diameter for 3" prop
    motor_coords = [(-0.052, 0.052), (0.052, 0.052), (-0.052, -0.052), (0.052, -0.052)]
    
    for mx, my in motor_coords:
        # Duct cylinder ring
        bmesh_cylinder(bm, radius=duct_radius, depth=0.024, matrix=mat_trans(mx, my, 0.010), cap_ends=False, segments=24)
        # Inner motor hub
        bmesh_cylinder(bm, radius=0.012, depth=thick, matrix=mat_trans(mx, my, 0), segments=16)
        
        # 3 spoke struts connecting hub to duct
        for a in [0, math.radians(120), math.radians(240)]:
            spoke_m = mat_trans(mx + math.cos(a)*duct_radius*0.5, my + math.sin(a)*duct_radius*0.5, 0) @ \
                      mat_rot_z(a) @ mat_scale(duct_radius, 0.004, thick)
            bmesh.ops.create_cube(bm, size=1.0, matrix=spoke_m)
            
    # Top plate
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, 0.020) @ mat_scale(0.038, 0.080, 0.002))
    
    mesh = bpy.data.meshes.new("Frame_Cinewhoop_3")
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new("Frame_Cinewhoop_3", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_duct)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# 2. MOTOR GENERATORS
# -----------------------------------------------------------------------------
def create_motor(name, coll, bell_radius, bell_height, shaft_len, mat_bell, mat_base):
    """Procedural BLDC Drone Motor (Origin at bottom base)."""
    bm = bmesh.new()
    base_h = 0.003
    
    # 1. Base mount plate (Origin is at z=0)
    bmesh_cylinder(bm, radius=bell_radius * 0.95, depth=base_h, matrix=mat_trans(0, 0, base_h / 2.0))
    
    # 2. Stator core / copper coils ring
    stator_h = bell_height * 0.85
    bmesh_cylinder(bm, radius=bell_radius * 0.80, depth=stator_h, matrix=mat_trans(0, 0, base_h + stator_h / 2.0))
    
    # 3. Outer Rotor Bell (anodized shell)
    bmesh_cylinder(bm, radius=bell_radius, depth=bell_height, matrix=mat_trans(0, 0, base_h + bell_height / 2.0))
    
    # 4. Top Bell Grip / Flange
    flange_h = 0.002
    bmesh_cylinder(bm, radius=bell_radius * 0.65, depth=flange_h, matrix=mat_trans(0, 0, base_h + bell_height + flange_h / 2.0))
    
    # 5. M5 Titanium/Steel Prop Shaft
    shaft_rad = 0.0025 # 5mm diameter
    shaft_z = base_h + bell_height + flange_h + shaft_len / 2.0
    bmesh_cylinder(bm, radius=shaft_rad, depth=shaft_len, matrix=mat_trans(0, 0, shaft_z))
    
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_bell)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# 3. PROPELLER GENERATORS
# -----------------------------------------------------------------------------
def create_propeller(name, coll, radius_m, pitch_deg, chord_m, mat_prop):
    """Procedural 3-Blade Drone Propeller (Origin at hub shaft center)."""
    bm = bmesh.new()
    
    # 1. Central mounting hub
    hub_rad = 0.007
    hub_h = 0.007
    bmesh_cylinder(bm, radius=hub_rad, depth=hub_h, matrix=mat_trans(0, 0, 0))
    
    # 2. 3 Aerodynamic Twisted Blades
    blade_len = radius_m - hub_rad
    for blade_idx in range(3):
        angle = blade_idx * (2.0 * math.pi / 3.0)
        segs = 5
        for s in range(segs):
            t = (s + 0.5) / float(segs)
            r_pos = hub_rad + t * blade_len
            local_pitch = math.radians(pitch_deg * (1.0 - t * 0.45))
            local_chord = chord_m * (1.0 - t * 0.40)
            local_thick = 0.0025 * (1.0 - t * 0.55)
            
            bx = math.cos(angle) * r_pos
            by = math.sin(angle) * r_pos
            
            m_seg = mat_trans(bx, by, 0) @ mat_rot_z(angle) @ mat_rot_x(local_pitch) @ \
                    mat_scale(blade_len / segs * 1.05, local_chord, local_thick)
            bmesh.ops.create_cube(bm, size=1.0, matrix=m_seg)
            
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_prop)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# 4. BATTERY GENERATORS
# -----------------------------------------------------------------------------
def create_battery(name, coll, dims, is_cylindrical, mat_body, mat_wire, mat_plug):
    """Drone Battery Pack (Origin at bottom contact plane)."""
    bm = bmesh.new()
    dx, dy, dz = dims
    
    if not is_cylindrical:
        # Standard rectangular LiPo brick
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, dz / 2.0) @ mat_scale(dx, dy, dz))
    else:
        # 6S2P Pack composed of 12 cylindrical 21700 Li-Ion cells
        cell_r = dx / 4.0
        cell_h = dy
        for row in range(2):
            for col in range(3):
                cx = (col - 1) * (cell_r * 2.05)
                cz = (row + 0.5) * (cell_r * 2.05)
                m_c = mat_trans(cx, 0, cz) @ mat_rot_x(math.radians(90))
                bmesh_cylinder(bm, radius=cell_r, depth=cell_h, matrix=m_c)
                
    # Silicone Leads (Red/Black wires exiting front)
    wire_scale = mat_scale(0.004, 0.030, 0.004)
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(-0.008, dy / 2.0 + 0.015, dz * 0.75) @ wire_scale)
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0.008, dy / 2.0 + 0.015, dz * 0.75) @ wire_scale)
    
    # XT60 / XT90 connector block
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, dy / 2.0 + 0.032, dz * 0.75) @ mat_scale(0.016, 0.018, 0.009))
    
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_body)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# 5. CAMERA GENERATORS
# -----------------------------------------------------------------------------
def create_camera(name, coll, is_thermal, mat_case, mat_lens):
    """FPV Camera module (Origin at rear tilt pivot)."""
    bm = bmesh.new()
    
    if not is_thermal:
        # 19x19 Micro FPV Analog Camera
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0.010, 0) @ mat_scale(0.019, 0.019, 0.019))
        bmesh_cylinder(bm, radius=0.007, depth=0.012, matrix=mat_trans(0, 0.024, 0) @ mat_rot_x(math.radians(90)))
    else:
        # Tactical Military Thermal / FLIR sensor pod
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0.018, 0) @ mat_scale(0.034, 0.036, 0.034))
        # Germanium lens barrel
        bmesh_cylinder(bm, radius=0.014, depth=0.018, matrix=mat_trans(0, 0.042, 0) @ mat_rot_x(math.radians(90)))
        # Rear cooling fins
        for f in range(3):
            bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, -0.002 - f*0.003, 0) @ mat_scale(0.030, 0.0015, 0.028))
            
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_case)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# 6. PAYLOAD GENERATORS
# -----------------------------------------------------------------------------
def create_payload_empty(coll, mat_metal):
    """Empty payload clamp bracket."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, -0.004) @ mat_scale(0.030, 0.040, 0.006))
    mesh = bpy.data.meshes.new("Payload_Empty")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Payload_Empty", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_metal)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

def create_payload_drop_vog(coll, mat_metal, mat_fuse):
    """VOG-17 Fragmentation Grenade Dropper System with aerodynamic fins."""
    bm = bmesh.new()
    # Servo dropper clamp
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, -0.008) @ mat_scale(0.025, 0.050, 0.014))
    # VOG-17 30mm Grenade Body
    bmesh_cylinder(bm, radius=0.015, depth=0.075, matrix=mat_trans(0, 0, -0.055))
    
    # 3D printed stabilizer fins
    bmesh_cylinder(bm, radius=0.019, depth=0.020, matrix=mat_trans(0, 0, -0.022), cap_ends=False)
    for a in [0, math.radians(90), math.radians(180), math.radians(270)]:
        f_m = mat_trans(math.cos(a)*0.018, math.sin(a)*0.018, -0.022) @ mat_rot_z(a) @ mat_scale(0.015, 0.002, 0.020)
        bmesh.ops.create_cube(bm, size=1.0, matrix=f_m)
        
    # Nose fuse
    bmesh_cylinder(bm, radius=0.007, depth=0.012, matrix=mat_trans(0, 0, -0.096))
    
    mesh = bpy.data.meshes.new("Payload_Drop_VOG")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Payload_Drop_VOG", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_metal)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

def create_payload_kamikaze_pg7(coll, mat_warhead, mat_cone):
    """Heavy PG-7 Shaped-Charge Anti-Armor Warhead for Kamikaze Drones."""
    bm = bmesh.new()
    
    # Heavy mounting clamps
    bmesh.ops.create_cube(bm, size=1.0, matrix=mat_trans(0, 0, -0.012) @ mat_scale(0.045, 0.120, 0.020))
    
    # PG-7 Main shaped-charge body (85mm diameter)
    bmesh_cylinder(bm, radius=0.0425, depth=0.180, matrix=mat_trans(0, 0.040, -0.045) @ mat_rot_x(math.radians(90)))
    
    # Forward standoff cone
    bmesh_cone(bm, radius1=0.0425, radius2=0.012, depth=0.120, matrix=mat_trans(0, 0.180, -0.045) @ mat_rot_x(math.radians(-90)))
    
    # Nose piezo fuse
    bmesh_cylinder(bm, radius=0.008, depth=0.040, matrix=mat_trans(0, 0.255, -0.045) @ mat_rot_x(math.radians(90)))
    
    # Rear tail shank
    bmesh_cylinder(bm, radius=0.020, depth=0.090, matrix=mat_trans(0, -0.090, -0.045) @ mat_rot_x(math.radians(90)))
    
    mesh = bpy.data.meshes.new("Payload_Kamikaze_PG7")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Payload_Kamikaze_PG7", mesh)
    bpy.context.scene.collection.objects.link(obj)
    apply_material(obj, mat_warhead)
    finalize_object(obj, coll, origin=(0, 0, 0))
    return obj

# -----------------------------------------------------------------------------
# SPECIFICATION DATABASE GENERATION (JSON)
# -----------------------------------------------------------------------------
def build_parts_specification():
    """Build the JSON data dictionary with realistic aerodynamic & electrical specs."""
    return {
        "metadata": {
            "version": "1.0",
            "author": "Antigravity FPV Technical Artist",
            "units": {"weight": "grams", "thrust": "grams", "voltage": "volts", "dimensions": "meters"}
        },
        "parts": [
            # --- FRAMES ---
            {
                "id": "frame_race_5",
                "name": "Race X-5 Carbon",
                "category": "frame",
                "type": "civilian",
                "weight_g": 68,
                "mesh_path": "res://assets/drone_parts/Frame_Race_5.glb",
                "size_inch": 5.0,
                "max_battery_weight": 220,
                "description": "Ультралегка симетрична True-X рама для FPV-перегонів.",
                "mounts": {
                    "motor_fl": [-0.078, 0.078, 0.0],
                    "motor_fr": [0.078, 0.078, 0.0],
                    "motor_bl": [-0.078, -0.078, 0.0],
                    "motor_br": [0.078, -0.078, 0.0],
                    "camera": [0.0, 0.065, 0.015],
                    "battery": [0.0, -0.020, -0.015],
                    "payload": [0.0, 0.0, -0.025]
                }
            },
            {
                "id": "frame_freestyle_7",
                "name": "Apex LongRange 7",
                "category": "frame",
                "type": "civilian",
                "weight_g": 142,
                "mesh_path": "res://assets/drone_parts/Frame_Freestyle_7.glb",
                "size_inch": 7.0,
                "max_battery_weight": 650,
                "description": "Подовжена рама Stretched-X для далеких польотів та носіння важких акумуляторів.",
                "mounts": {
                    "motor_fl": [-0.125, 0.085, 0.0],
                    "motor_fr": [0.125, 0.085, 0.0],
                    "motor_bl": [-0.105, -0.115, 0.0],
                    "motor_br": [0.105, -0.115, 0.0],
                    "camera": [0.0, 0.110, 0.020],
                    "battery": [0.0, -0.030, 0.025],
                    "payload": [0.0, -0.010, -0.025]
                }
            },
            {
                "id": "frame_heavy_10",
                "name": "Грім-10 Тактична Рама",
                "category": "frame",
                "type": "military",
                "weight_g": 265,
                "mesh_path": "res://assets/drone_parts/Frame_Heavy_10.glb",
                "size_inch": 10.0,
                "max_battery_weight": 1400,
                "description": "Посилена військова рама з 8-мм фермовими променями для важких дронів-камікадзе.",
                "mounts": {
                    "motor_fl": [-0.160, 0.160, 0.0],
                    "motor_fr": [0.160, 0.160, 0.0],
                    "motor_bl": [-0.160, -0.160, 0.0],
                    "motor_br": [0.160, -0.160, 0.0],
                    "camera": [0.0, 0.140, 0.025],
                    "battery": [0.0, 0.020, 0.030],
                    "payload": [0.0, -0.020, -0.045]
                }
            },
            {
                "id": "frame_cinewhoop_3",
                "name": "BumbleBee 3 Whoop",
                "category": "frame",
                "type": "civilian",
                "weight_g": 95,
                "mesh_path": "res://assets/drone_parts/Frame_Cinewhoop_3.glb",
                "size_inch": 3.0,
                "max_battery_weight": 280,
                "description": "Рама з захисними кільцевими дактами для безпечних зйомок та польотів у приміщенні.",
                "mounts": {
                    "motor_fl": [-0.052, 0.052, 0.0],
                    "motor_fr": [0.052, 0.052, 0.0],
                    "motor_bl": [-0.052, -0.052, 0.0],
                    "motor_br": [0.052, -0.052, 0.0],
                    "camera": [0.0, 0.050, 0.015],
                    "battery": [0.0, -0.010, 0.025],
                    "payload": [0.0, 0.0, -0.020]
                }
            },

            # --- MOTORS ---
            {
                "id": "motor_2207_highkv",
                "name": "Xing2 2207 (2450KV)",
                "category": "motor",
                "type": "civilian",
                "weight_g": 32,
                "mesh_path": "res://assets/drone_parts/Motor_2207_HighKV.glb",
                "thrust_g": 1620,
                "kv_rating": 2450,
                "max_prop_inch": 5.1,
                "description": "Високооборотний гоночний двигун для 5-дюймових гвинтів."
            },
            {
                "id": "motor_2807_lowkv",
                "name": "FlashHobby 2807 (1300KV)",
                "category": "motor",
                "type": "military",
                "weight_g": 54,
                "mesh_path": "res://assets/drone_parts/Motor_2807_LowKV.glb",
                "thrust_g": 2450,
                "kv_rating": 1300,
                "max_prop_inch": 10.0,
                "description": "Тяговитий мотор зі сталевим валом для 7-10 дюймових ударних FPV."
            },

            # --- PROPELLERS ---
            {
                "id": "prop_5x4x3",
                "name": "Gemfan 51466 V2 (3-Blade)",
                "category": "prop",
                "type": "civilian",
                "weight_g": 4.2,
                "mesh_path": "res://assets/drone_parts/Prop_5x4x3.glb",
                "diameter_inch": 5.1,
                "pitch_inch": 4.6,
                "blades": 3,
                "description": "Швидкісний полікарбонатний гвинт для агресивного фрістайлу."
            },
            {
                "id": "prop_7x4x3",
                "name": "HQProp 7040 (3-Blade)",
                "category": "prop",
                "type": "civilian",
                "weight_g": 9.1,
                "mesh_path": "res://assets/drone_parts/Prop_7x4x3.glb",
                "diameter_inch": 7.0,
                "pitch_inch": 4.0,
                "blades": 3,
                "description": "Ефективний гвинт великого радіусу дії з низьким рівнем шуму."
            },
            {
                "id": "prop_10x5x3",
                "name": "Master Airscrew 1050 (3-Blade)",
                "category": "prop",
                "type": "military",
                "weight_g": 18.5,
                "mesh_path": "res://assets/drone_parts/Prop_10x5x3.glb",
                "diameter_inch": 10.0,
                "pitch_inch": 5.0,
                "blades": 3,
                "description": "Вантажний армований гвинт для підйому бойової частини."
            },

            # --- BATTERIES ---
            {
                "id": "battery_4s_1500",
                "name": "Tattu R-Line 4S 1500mAh 120C",
                "category": "battery",
                "type": "civilian",
                "weight_g": 178,
                "mesh_path": "res://assets/drone_parts/Battery_4S_1500.glb",
                "capacity_mah": 1500,
                "voltage_v": 14.8,
                "max_discharge_c": 120,
                "description": "Легкий гоночний LiPo акумулятор із миттєвою струмовіддачею."
            },
            {
                "id": "battery_6s_4500",
                "name": "Molicel P42A 6S2P 8400mAh Li-Ion",
                "category": "battery",
                "type": "military",
                "weight_g": 860,
                "mesh_path": "res://assets/drone_parts/Battery_6S_4500.glb",
                "capacity_mah": 8400,
                "voltage_v": 22.2,
                "max_discharge_c": 45,
                "description": "Важка збірка з елементів 21700 для бойових операцій на великих дистанціях."
            },

            # --- CAMERAS ---
            {
                "id": "camera_analog",
                "name": "Foxeer Predator 5 Micro",
                "category": "camera",
                "type": "civilian",
                "weight_g": 8.5,
                "mesh_path": "res://assets/drone_parts/Camera_Analog.glb",
                "latency_ms": 4.0,
                "sensor_type": "daylight_rgb",
                "fov_deg": 125,
                "description": "Ультранизька затримка сигналу для швидкісного пілотування."
            },
            {
                "id": "camera_thermal",
                "name": "FLIR Boson 640 Thermal Core",
                "category": "camera",
                "type": "military",
                "weight_g": 38.0,
                "mesh_path": "res://assets/drone_parts/Camera_Thermal.glb",
                "latency_ms": 18.0,
                "sensor_type": "thermal_flir",
                "fov_deg": 95,
                "description": "Тепловізійний бойовий модуль для виявлення замаскованої техніки вночі."
            },

            # --- PAYLOADS ---
            {
                "id": "payload_empty",
                "name": "Без навантаження (Чистий політ)",
                "category": "payload",
                "type": "civilian",
                "weight_g": 5,
                "mesh_path": "res://assets/drone_parts/Payload_Empty.glb",
                "damage_radius": 0.0,
                "armor_penetration": 0.0,
                "is_explosive": False,
                "description": "Стандартний монтажний замок без боєприпасу."
            },
            {
                "id": "payload_drop_vog",
                "name": "Система скиду (ВОГ-17 ОФ)",
                "category": "payload",
                "type": "military",
                "weight_g": 340,
                "mesh_path": "res://assets/drone_parts/Payload_Drop_VOG.glb",
                "damage_radius": 7.5,
                "armor_penetration": 12.0,
                "is_explosive": True,
                "description": "30-мм осколкова граната з хвостовиком та сервоприводом дистанційного скиду."
            },
            {
                "id": "payload_kamikaze_pg7",
                "name": "Кумулятивна БЧ ПГ-7ВР (Камікадзе)",
                "category": "payload",
                "type": "military",
                "weight_g": 1450,
                "mesh_path": "res://assets/drone_parts/Payload_Kamikaze_PG7.glb",
                "damage_radius": 4.0,
                "armor_penetration": 650.0,
                "is_explosive": True,
                "description": "Важка бронебійна кумулятивна бойова частина для знищення танків прямим ударом."
            }
        ]
    }

# -----------------------------------------------------------------------------
# MAIN GENERATION & EXPORT WORKFLOW
# -----------------------------------------------------------------------------
def run():
    print(">>> Starting FPV Drone Modular Components Generator...")
    reset_scene()
    
    # 1. Setup Collections
    col_frames = get_or_create_collection("Frames")
    col_motors = get_or_create_collection("Motors")
    col_props = get_or_create_collection("Props")
    col_batteries = get_or_create_collection("Batteries")
    col_cameras = get_or_create_collection("Cameras")
    col_payloads = get_or_create_collection("Payloads")
    
    # 2. Setup Shared PBR Materials
    mat_carbon = get_or_create_material("Mat_Carbon", (0.08, 0.08, 0.09, 1.0), metallic=0.1, roughness=0.45)
    mat_metal = get_or_create_material("Mat_Metal", (0.45, 0.48, 0.50, 1.0), metallic=0.9, roughness=0.3)
    mat_standoff_red = get_or_create_material("Mat_AnodizedRed", (0.85, 0.08, 0.10, 1.0), metallic=0.95, roughness=0.25)
    mat_duct_neon = get_or_create_material("Mat_DuctNeon", (0.15, 0.85, 0.95, 1.0), metallic=0.0, roughness=0.3)
    mat_bell_race = get_or_create_material("Mat_BellRace", (0.05, 0.45, 0.95, 1.0), metallic=0.95, roughness=0.2)
    mat_bell_mil = get_or_create_material("Mat_BellMilitary", (0.15, 0.16, 0.15, 1.0), metallic=0.85, roughness=0.4)
    mat_prop_poly = get_or_create_material("Mat_PropPoly", (0.15, 0.95, 0.25, 1.0), metallic=0.0, roughness=0.25)
    mat_prop_smoke = get_or_create_material("Mat_PropSmoke", (0.06, 0.06, 0.06, 1.0), metallic=0.05, roughness=0.3)
    mat_lipo = get_or_create_material("Mat_BatteryLiPo", (0.95, 0.78, 0.08, 1.0), metallic=0.0, roughness=0.5)
    mat_wire = get_or_create_material("Mat_WireRed", (0.9, 0.05, 0.05, 1.0), metallic=0.0, roughness=0.6)
    mat_plug = get_or_create_material("Mat_XT60", (0.95, 0.85, 0.10, 1.0), metallic=0.0, roughness=0.3)
    mat_liion_mil = get_or_create_material("Mat_BatteryMilitary", (0.18, 0.22, 0.14, 1.0), metallic=0.0, roughness=0.7)
    mat_cam_analog = get_or_create_material("Mat_CameraAnalog", (0.85, 0.35, 0.05, 1.0), metallic=0.85, roughness=0.3)
    mat_lens = get_or_create_material("Mat_LensGlass", (0.05, 0.05, 0.08, 1.0), metallic=0.2, roughness=0.05)
    mat_cam_thermal = get_or_create_material("Mat_CameraThermal", (0.24, 0.26, 0.18, 1.0), metallic=0.2, roughness=0.7)
    mat_warhead_od = get_or_create_material("Mat_WarheadOD", (0.22, 0.26, 0.16, 1.0), metallic=0.3, roughness=0.6)
    mat_warhead_cone = get_or_create_material("Mat_WarheadAlu", (0.65, 0.68, 0.65, 1.0), metallic=0.85, roughness=0.35)
    
    # 3. Generate Objects
    print("  -> Generating Frames...")
    obj_frame_race = create_frame_race_5(col_frames, mat_carbon, mat_standoff_red)
    obj_frame_free = create_frame_freestyle_7(col_frames, mat_carbon, mat_metal)
    obj_frame_heavy = create_frame_heavy_10(col_frames, mat_carbon, mat_metal)
    obj_frame_whoop = create_frame_cinewhoop_3(col_frames, mat_carbon, mat_duct_neon)
    
    print("  -> Generating Motors...")
    obj_motor_2207 = create_motor("Motor_2207_HighKV", col_motors, 0.0135, 0.014, 0.014, mat_bell_race, mat_metal)
    obj_motor_2807 = create_motor("Motor_2807_LowKV", col_motors, 0.0170, 0.018, 0.016, mat_bell_mil, mat_metal)
    
    print("  -> Generating Propellers...")
    obj_prop_5 = create_propeller("Prop_5x4x3", col_props, 0.0635, 32.0, 0.014, mat_prop_poly)
    obj_prop_7 = create_propeller("Prop_7x4x3", col_props, 0.0889, 28.0, 0.017, mat_prop_smoke)
    obj_prop_10 = create_propeller("Prop_10x5x3", col_props, 0.1270, 24.0, 0.024, mat_carbon)
    
    print("  -> Generating Batteries...")
    obj_batt_4s = create_battery("Battery_4S_1500", col_batteries, (0.035, 0.075, 0.032), False, mat_lipo, mat_wire, mat_plug)
    obj_batt_6s = create_battery("Battery_6S_4500", col_batteries, (0.048, 0.145, 0.048), True, mat_liion_mil, mat_wire, mat_metal)
    
    print("  -> Generating Cameras...")
    obj_cam_analog = create_camera("Camera_Analog", col_cameras, False, mat_cam_analog, mat_lens)
    obj_cam_thermal = create_camera("Camera_Thermal", col_cameras, True, mat_cam_thermal, mat_lens)
    
    print("  -> Generating Payloads...")
    obj_payload_empty = create_payload_empty(col_payloads, mat_metal)
    obj_payload_vog = create_payload_drop_vog(col_payloads, mat_metal, mat_warhead_cone)
    obj_payload_pg7 = create_payload_kamikaze_pg7(col_payloads, mat_warhead_od, mat_warhead_cone)
    
    all_objects = [
        obj_frame_race, obj_frame_free, obj_frame_heavy, obj_frame_whoop,
        obj_motor_2207, obj_motor_2807,
        obj_prop_5, obj_prop_7, obj_prop_10,
        obj_batt_4s, obj_batt_6s,
        obj_cam_analog, obj_cam_thermal,
        obj_payload_empty, obj_payload_vog, obj_payload_pg7
    ]
    
    # 4. Export each mesh object as GLB
    print("\n>>> Exporting GLB meshes to: %s" % EXPORT_DIR)
    for obj in all_objects:
        bpy.ops.object.select_all(action='SELECT')
        for o in bpy.context.selected_objects:
            o.select_set(False)
            
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        
        target_path = os.path.join(EXPORT_DIR, f"{obj.name}.glb")
        
        bpy.ops.export_scene.gltf(
            filepath=target_path,
            export_format='GLB',
            use_selection=True,
            export_apply=True,
            export_yup=True
        )
        print("  ✓ Exported: %s.glb" % obj.name)
        obj.select_set(False)
        
    # 5. Generate and save JSON
    print("\n>>> Generating drone parts specification JSON...")
    data = build_parts_specification()
    with open(JSON_OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print("  ✓ Saved JSON specification to: %s" % JSON_OUTPUT_PATH)
    print("\n>>> ALL 16 MODULAR COMPONENTS GENERATED & EXPORTED SUCCESSFULLY! <<<")

if __name__ == "__main__":
    run()
