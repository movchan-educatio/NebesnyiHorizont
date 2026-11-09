"""Build a low-poly enemy rifleman for CityFPV.

Run with Blender 5.x:
  blender --background --factory-startup --python tools/make_rifleman.py

The soldier faces +Y in Blender.  With export_yup=True the glTF/Godot
forward becomes -Z, which matches Node3D.look_at().

Outputs:
  <project>/assets/combat/rifleman.glb
  <workspace>/rifleman.blend
  <workspace>/Rifleman-blender-preview.png
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
WORKSPACE = PROJECT.parent
ASSET_DIR = PROJECT / "assets" / "combat"
GLB_PATH = ASSET_DIR / "rifleman.glb"
BLEND_PATH = WORKSPACE / "rifleman.blend"
PREVIEW_PATH = WORKSPACE / "Rifleman-blender-preview.png"


# ------------------------------------------------------------------ scene setup
def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def make_material(name: str, color: tuple[float, float, float],
                  roughness: float = 0.82, metallic: float = 0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    material.diffuse_color = (*color, 1.0)
    return material


def finish_object(obj, material, parent, smooth: bool = False):
    if material is not None:
        obj.data.materials.append(material)
    if smooth and obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def add_empty(name: str, location=(0, 0, 0), parent=None):
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=location)
    obj = bpy.context.object
    obj.name = name
    obj.empty_display_size = 0.08
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def add_box(name: str, size, location, material, parent=None,
            rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    # primitive_cube_add(size=1) is a unit cube; dimensions equal scale.
    obj.scale = (size[0], size[1], size[2])
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish_object(obj, material, parent)


def add_sphere(name: str, radius, location, material, parent=None,
               scale=(1, 1, 1), segments=16, rings=10):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments, ring_count=rings, radius=radius, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, material, parent, smooth=True)


def add_cylinder(name: str, radius: float, depth: float, location,
                 material, parent=None, rotation=(0, 0, 0), vertices=10):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=depth, location=location
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rotation
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish_object(obj, material, parent, smooth=True)


def add_cylinder_between(name: str, start, end, radius: float, material,
                         parent=None, vertices=10):
    start_v = Vector(start)
    end_v = Vector(end)
    delta = end_v - start_v
    length = delta.length
    if length < 0.0001:
        return None
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices, radius=radius, depth=length, location=midpoint
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return finish_object(obj, material, parent, smooth=True)


# ------------------------------------------------------------------ soldier
def build_soldier():
    # Palette
    uniform = make_material("Uniform_olive", (0.19, 0.24, 0.12), 0.9)
    uniform_light = make_material("Uniform_light", (0.26, 0.30, 0.16), 0.9)
    vest = make_material("Vest_dark", (0.08, 0.10, 0.055), 0.86)
    helmet = make_material("Helmet_olive", (0.13, 0.16, 0.085), 0.72)
    skin = make_material("Skin", (0.50, 0.35, 0.24), 0.82)
    boots = make_material("Boots_black", (0.022, 0.024, 0.022), 0.7)
    gloves = make_material("Gloves_black", (0.035, 0.038, 0.032), 0.8)
    gun = make_material("Rifle_gunmetal", (0.045, 0.050, 0.052), 0.42, 0.35)
    gun_dark = make_material("Rifle_dark", (0.018, 0.020, 0.020), 0.55, 0.2)
    accent = make_material("Enemy_red", (0.55, 0.035, 0.018), 0.55)
    strap = make_material("Webbing_tan", (0.30, 0.23, 0.13), 0.92)
    lens = make_material("Goggle_lens", (0.02, 0.035, 0.035), 0.28, 0.1)

    root = add_empty("Rifleman")
    legs_root = add_empty("Legs", parent=root)
    pitch_root = add_empty("PitchPivot", (0, 0, 1.02), parent=root)
    rifle_root = add_empty("Rifle", (0.10, 0.48, 1.38), parent=pitch_root)

    # Boots and legs, grouped under simple hip/knee pivots so the soldier can be
    # animated walking or running. The pivots export as empty nodes and rotate
    # around the joint, not the mesh centre.
    for side, x in (("L", -0.145), ("R", 0.145)):
        hip = add_empty(f"HipJoint_{side}", (x, 0.0, 0.98), parent=legs_root)
        knee = add_empty(f"KneeJoint_{side}", (x, 0.02, 0.56), parent=hip)
        add_box(f"Boot_{side}", (0.17, 0.31, 0.15), (x, 0.075, 0.085),
                boots, knee)
        add_box(f"Boot_toe_{side}", (0.155, 0.12, 0.075),
                (x, 0.225, 0.055), boots, knee)
        add_box(f"Shin_{side}", (0.145, 0.16, 0.38), (x, 0.02, 0.35),
                uniform, knee)
        add_box(f"Knee_{side}", (0.165, 0.18, 0.085), (x, 0.10, 0.56),
                vest, knee)
        add_box(f"Thigh_{side}", (0.18, 0.21, 0.43), (x, 0.0, 0.78),
                uniform, hip)
        add_box(f"Thigh_pocket_{side}", (0.055, 0.12, 0.16),
                (x + (0.105 if x > 0 else -0.105), 0.045, 0.76),
                uniform_light, hip)
    add_box("Pelvis", (0.43, 0.28, 0.25), (0, 0, 0.98), uniform, legs_root)
    add_box("Belt", (0.47, 0.31, 0.09), (0, 0, 1.04), strap, legs_root)
    for x in (-0.16, 0.0, 0.16):
        add_box("Belt_pouch", (0.105, 0.10, 0.13), (x, 0.18, 1.0),
                vest, legs_root)

    # Torso / plate carrier.
    add_box("Torso", (0.47, 0.27, 0.60), (0, 0, 1.33), uniform, pitch_root)
    add_box("Vest_front", (0.42, 0.10, 0.42), (0, 0.175, 1.34), vest, pitch_root)
    add_box("Vest_back", (0.44, 0.10, 0.46), (0, -0.17, 1.34), vest, pitch_root)
    add_box("Vest_side_L", (0.08, 0.24, 0.30), (-0.225, 0, 1.34), vest,
            pitch_root)
    add_box("Vest_side_R", (0.08, 0.24, 0.30), (0.225, 0, 1.34), vest,
            pitch_root)
    for x in (-0.12, 0.12):
        add_box("Chest_pouch", (0.11, 0.07, 0.15), (x, 0.235, 1.24), vest,
                pitch_root)
    add_box("Shoulder_L", (0.16, 0.26, 0.13), (-0.27, 0, 1.55),
            uniform_light, pitch_root)
    add_box("Shoulder_R", (0.16, 0.26, 0.13), (0.27, 0, 1.55),
            uniform_light, pitch_root)
    add_box("Backpack", (0.34, 0.17, 0.34), (0, -0.255, 1.33), strap,
            pitch_root)
    add_box("Backpack_top", (0.22, 0.13, 0.08), (0, -0.275, 1.53),
            uniform_light, pitch_root)
    add_box("Red_patch", (0.018, 0.115, 0.10), (-0.345, 0.0, 1.51), accent,
            pitch_root)

    # Neck / head / helmet / goggles.
    add_cylinder("Neck", 0.075, 0.13, (0, 0, 1.61), skin, pitch_root)
    add_sphere("Head", 0.155, (0, 0.02, 1.73), skin, pitch_root,
               scale=(0.92, 0.92, 1.10), segments=16, rings=10)
    add_sphere("Helmet", 0.205, (0, 0.005, 1.80), helmet, pitch_root,
               scale=(1.02, 1.08, 0.72), segments=16, rings=8)
    add_box("Helmet_brim", (0.39, 0.16, 0.035), (0, 0.115, 1.735), helmet,
            pitch_root)
    add_box("Goggle_frame", (0.27, 0.045, 0.07), (0, 0.155, 1.71), gun_dark,
            pitch_root)
    add_box("Goggle_lens", (0.20, 0.018, 0.045), (0, 0.181, 1.712), lens,
            pitch_root)
    add_box("Mouth", (0.075, 0.018, 0.02), (0, 0.168, 1.64), gun_dark,
            pitch_root)
    add_box("Helmet_band", (0.36, 0.30, 0.025), (0, 0.0, 1.755), vest,
            pitch_root)

    # Arms holding the rifle.  Right side is +X (the soldier faces +Y).
    add_cylinder_between("Upper_arm_R", (0.29, 0.0, 1.51),
                         (0.34, 0.20, 1.27), 0.068, uniform, pitch_root)
    add_cylinder_between("Forearm_R", (0.34, 0.20, 1.27),
                         (0.17, 0.47, 1.36), 0.056, uniform, pitch_root)
    add_cylinder_between("Upper_arm_L", (-0.29, 0.0, 1.51),
                         (-0.30, 0.23, 1.27), 0.068, uniform, pitch_root)
    add_cylinder_between("Forearm_L", (-0.30, 0.23, 1.27),
                         (0.01, 0.52, 1.39), 0.056, uniform, pitch_root)
    add_sphere("Glove_R", 0.070, (0.17, 0.475, 1.36), gloves, pitch_root,
               scale=(0.9, 1.15, 0.8), segments=10, rings=6)
    add_sphere("Glove_L", 0.070, (0.01, 0.525, 1.39), gloves, pitch_root,
               scale=(0.9, 1.15, 0.8), segments=10, rings=6)
    add_box("Elbow_pad_R", (0.10, 0.09, 0.08), (0.35, 0.20, 1.26), vest,
            pitch_root)
    add_box("Elbow_pad_L", (0.10, 0.09, 0.08), (-0.31, 0.23, 1.26), vest,
            pitch_root)

    # Rifle: receiver, stock, barrel, handguard, magazine, optic.
    add_box("Rifle_receiver", (0.105, 0.48, 0.115), (0.10, 0.47, 1.38),
            gun, rifle_root)
    add_box("Rifle_stock", (0.09, 0.30, 0.13), (0.10, 0.10, 1.34), gun,
            rifle_root)
    add_box("Rifle_butt", (0.10, 0.055, 0.18), (0.10, -0.05, 1.33),
            gun_dark, rifle_root)
    add_box("Rifle_handguard", (0.085, 0.30, 0.085), (0.10, 0.78, 1.39),
            gun_dark, rifle_root)
    add_cylinder("Rifle_barrel", 0.024, 0.52, (0.10, 0.96, 1.39), gun_dark,
                 rifle_root, rotation=(math.pi * 0.5, 0, 0), vertices=10)
    add_box("Rifle_muzzle_brake", (0.055, 0.10, 0.055), (0.10, 1.205, 1.39),
            gun, rifle_root)
    add_box("Rifle_magazine", (0.075, 0.12, 0.22), (0.10, 0.40, 1.255),
            gun_dark, rifle_root, rotation=(math.radians(-10), 0, 0))
    add_box("Rifle_grip", (0.065, 0.07, 0.15), (0.10, 0.29, 1.28), gun_dark,
            rifle_root, rotation=(math.radians(18), 0, 0))
    add_box("Rifle_optic", (0.065, 0.16, 0.075), (0.10, 0.46, 1.46), gun_dark,
            rifle_root)
    add_box("Rifle_sight", (0.04, 0.04, 0.04), (0.10, 0.70, 1.45), gun_dark,
            rifle_root)
    add_box("Rifle_sling", (0.025, 0.16, 0.30), (0.015, 0.30, 1.29), strap,
            rifle_root, rotation=(math.radians(22), 0, 0))
    # Muzzle empty; Godot uses its world position for tracers and flashes.
    muzzle = add_empty("Muzzle", (0.10, 1.255, 1.39), parent=rifle_root)

    # A couple of ground-contact details make the silhouette read better
    # from a distance without adding a rig.
    add_box("Chest_radio", (0.10, 0.045, 0.13), (0.16, -0.235, 1.46),
            gun_dark, pitch_root)
    add_box("Radio_antenna", (0.012, 0.012, 0.30), (0.16, -0.235, 1.66),
            gun_dark, pitch_root)

    return root, pitch_root, muzzle


# ------------------------------------------------------------------ preview
def setup_preview():
    # Ground plane (not part of the GLB selection).
    ground_mat = make_material("Preview_ground", (0.055, 0.060, 0.065), 0.95)
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    ground = bpy.context.object
    ground.name = "Preview_ground"
    ground.data.materials.append(ground_mat)

    # Camera front-right of the soldier (soldier faces +Y).
    camera_data = bpy.data.cameras.new("Preview_camera")
    camera = bpy.data.objects.new("Preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (2.45, 3.25, 1.55)
    direction = Vector((0, 0, 1.02)) - Vector(camera.location)
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    camera_data.lens = 62
    bpy.context.scene.camera = camera

    def area(name, location, energy, size, color):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = location
        direction = Vector((0, 0, 1.0)) - Vector(location)
        light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        return light

    area("Key", (3.0, 4.0, 4.2), 520, 3.0, (1.0, 0.86, 0.68))
    area("Fill", (-3.5, 2.0, 2.5), 260, 4.0, (0.62, 0.76, 1.0))
    area("Rim", (0.0, -3.8, 3.2), 420, 2.5, (1.0, 0.55, 0.30))

    world = bpy.data.worlds.new("Preview_world")
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.012, 0.016, 0.024, 1.0)
    background.inputs["Strength"].default_value = 0.55
    bpy.context.scene.world = world


def export_and_render(root):
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    # Export only the soldier hierarchy.
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in root.children_recursive:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    print(f"[rifleman] GLB: {GLB_PATH}")

    setup_preview()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW_PATH)
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.filepath = str(PREVIEW_PATH)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)
    print(f"[rifleman] BLEND: {BLEND_PATH}")
    print(f"[rifleman] PREVIEW: {PREVIEW_PATH}")


def main():
    reset_scene()
    root, _pitch, _muzzle = build_soldier()
    export_and_render(root)


main()
