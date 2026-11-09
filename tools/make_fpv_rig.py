"""Build the combat FPV rig the onboard camera sees - a yellow munition with
silver antenna wire loops, matching the "Combat FPV drone" reference.  A preview
is rendered from the exact in-game camera (vertical FOV 90, looking forward).

Run: blender --background --factory-startup --python tools/make_fpv_rig.py
Outputs: assets/drone/fpv_rig.glb  and  FPVRig-preview.png
"""
from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

SCRIPT = Path(__file__).resolve()
PROJECT = SCRIPT.parent.parent
WORKSPACE = PROJECT.parent
OUT_PATH = PROJECT / "assets" / "drone" / "fpv_rig.glb"
PREVIEW = WORKSPACE / "FPVRig-preview.png"


def bl(loc):
    # Godot (x, y up, z forward = -Z) -> Blender (x, -z, y up)
    return (loc[0], -loc[2], loc[1])


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images,
                  bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            try:
                block.remove(item)
            except Exception:
                pass


def material(name, color, roughness=0.6, metallic=0.0, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, alpha)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    mat.diffuse_color = (*color, alpha)
    return mat


def _finish(obj, mat, parent, rot):
    obj.name = obj.name
    if rot != (0.0, 0.0, 0.0):
        obj.rotation_euler = rot
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(mat)
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def box(name, loc, size, mat, parent, yaw=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[2], size[1])
    return _finish(obj, mat, parent, (0.0, 0.0, yaw))


def cylinder(name, loc, radius, depth, mat, parent, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=radius, depth=depth,
                                        location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, parent, rot)


def cone(name, loc, radius, depth, mat, parent, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=20, radius1=radius, radius2=0.0,
                                    depth=depth, location=bl(loc))
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, parent, rot)


def cyl_between(name, start, end, radius, mat, parent, verts=10):
    a = Vector(bl(start))
    b = Vector(bl(end))
    delta = b - a
    length = delta.length
    if length < 1e-4:
        return None
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius,
                                        depth=length, location=(a + b) * 0.5)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.data.materials.append(mat)
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    return obj


def torus(name, loc, major, minor, mat, parent, rot=(math.pi * 0.5, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(location=bl(loc), major_radius=major,
                                     minor_radius=minor, major_segments=28,
                                     minor_segments=8)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, mat, parent, rot)


def build_rig():
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0, 0, 0))
    root = bpy.context.active_object
    root.name = "FPVRig"

    silver = material("WireSilver", (0.86, 0.87, 0.89), 0.3, 0.5)
    yellow = material("PayloadYellow", (0.90, 0.73, 0.20), 0.45)
    olive = material("PayloadTip", (0.70, 0.56, 0.18), 0.5)
    carbon = material("Carbon", (0.07, 0.07, 0.08), 0.4)

    # Payload: a big yellow munition at the bottom centre, nose forward/up.
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(0.0, 0.0, 0.0))
    payload = bpy.context.active_object
    payload.name = "Payload"
    payload.parent = root
    payload.matrix_parent_inverse = root.matrix_world.inverted()
    cylinder("PayloadBody", (0.0, -0.42, -0.74), 0.16, 0.92, yellow, payload,
             rot=(math.pi * 0.5 - 0.14, 0.0, 0.0))
    cone("PayloadNose", (0.0, -0.32, -1.30), 0.16, 0.32, olive, payload,
         rot=(-math.pi * 0.5 - 0.14, 0.0, 0.0))
    cylinder("PayloadCollar", (0.0, -0.46, -0.30), 0.10, 0.10, silver, payload,
             rot=(math.pi * 0.5 - 0.14, 0.0, 0.0))

    # Silver antenna wire loops rising over the payload (reference look).
    torus("WireLoop_L", (-0.09, -0.10, -0.52), 0.17, 0.008, silver, root,
          rot=(math.pi * 0.5, 0.0, 0.35))
    torus("WireLoop_R", (0.10, -0.08, -0.48), 0.15, 0.008, silver, root,
          rot=(math.pi * 0.5, 0.0, -0.35))
    torus("WireLoop_Top", (0.0, 0.02, -0.42), 0.12, 0.007, silver, root,
          rot=(math.pi * 0.5, 0.0, 0.0))
    # Wires sweeping out to the frame sides.
    cyl_between("Wire_L", (-0.05, -0.22, -0.66), (-0.62, -0.30, -0.30), 0.007, silver, root)
    cyl_between("Wire_R", (0.05, -0.22, -0.66), (0.62, -0.30, -0.30), 0.007, silver, root)

    # A hint of the carbon frame just above the payload.
    box("FrameTop", (0.0, -0.30, -0.42), (0.34, 0.02, 0.20), carbon, root)

    return root


def setup_preview() -> None:
    ground = material("PreviewGround", (0.32, 0.34, 0.28), 1.0)
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0, 14.0, -2.5))
    plane = bpy.context.active_object
    plane.name = "PreviewGround"
    plane.data.materials.append(ground)

    world = bpy.data.worlds.new("PreviewWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.45, 0.56, 0.7, 1.0)
    bpy.context.scene.world = world

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("Sun", sun_data)
    bpy.context.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(55.0), 0.0, math.radians(30.0))

    cam_data = bpy.data.cameras.new("FPVCam")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle = math.radians(90.0)
    cam = bpy.data.objects.new("FPVCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 0.0)
    cam.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    bpy.context.scene.camera = cam


def render_preview() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(PREVIEW)
    bpy.ops.render.render(write_still=True)
    print(f"[fpv-rig] preview {PREVIEW}")


def main() -> None:
    clear_scene()
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    root = build_rig()
    setup_preview()
    render_preview()

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_PATH), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_cameras=False,
        export_lights=False)
    print(f"[fpv-rig] wrote {OUT_PATH}")


main()
