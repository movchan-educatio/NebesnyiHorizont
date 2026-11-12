#!/usr/bin/env python3
"""Bake four transparent orthographic views of the runtime infantry rig.

Run with Blender 5.x in background mode. The atlas is assembled by a separate
Pillow command so the build script stays compatible with Blender's Python.
Frame order: front, right, back, left; atlas is a 2x2 grid.
"""

import bpy
from pathlib import Path
from mathutils import Vector
from math import radians

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Assets" / "combat" / "soldier_detailed_merged.glb"
OUT_DIR = Path.home() / "AppData" / "Local" / "Temp" / "opencode" / "infantry_impostor"
OUT_DIR.mkdir(parents=True, exist_ok=True)

VIEWS = [
    ("front", Vector((0.0, -1.0, 0.0))),
    ("right", Vector((1.0, 0.0, 0.0))),
    ("back", Vector((0.0, 1.0, 0.0))),
    ("left", Vector((-1.0, 0.0, 0.0))),
]


def world_bounds(objects):
    corners = []
    for obj in objects:
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    lo = Vector(tuple(min(point[i] for point in corners) for i in range(3)))
    hi = Vector(tuple(max(point[i] for point in corners) for i in range(3)))
    return lo, hi


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if not SOURCE.is_file():
        raise FileNotFoundError(SOURCE)

    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    imported = list(bpy.context.scene.objects)
    meshes = [obj for obj in imported if obj.type == "MESH"]
    if not meshes:
        raise RuntimeError("The runtime detailed soldier GLB has no mesh objects")
    body = max(meshes, key=lambda obj: len(obj.data.vertices))
    for obj in meshes:
        if obj != body:
            obj.hide_render = True

    # Godot's runtime rig rotates this Y-up Sketchfab export by +90° around X.
    # Apply the same transform here, then normalize to its runtime 1.88 m height.
    top_level = [obj for obj in imported if obj.parent is None and obj.type != "MESH"]
    bake_root = bpy.data.objects.new("BakeRoot", None)
    bpy.context.scene.collection.objects.link(bake_root)
    bake_root.rotation_euler.x = radians(90.0)
    for obj in top_level:
        obj.parent = bake_root
        obj.matrix_parent_inverse.identity()
    bpy.context.view_layer.update()
    lo, hi = world_bounds([body])
    size = hi - lo
    if size.z < 1.2 or size.z < max(size.x, size.y):
        raise RuntimeError(f"Runtime axis conversion failed; body bounds={tuple(size)}")
    bake_root.scale = Vector((1.88 / size.z,) * 3)
    bpy.context.view_layer.update()
    lo, hi = world_bounds([body])
    bake_root.location -= Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    bpy.context.view_layer.update()
    lo, hi = world_bounds([body])
    size = hi - lo
    center = (lo + hi) * 0.5
    print(f"[IMPOSTOR_BAKE] source={SOURCE.name} body={body.name} bounds={tuple(size)}")

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 256
    scene.render.resolution_y = 512
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = True
    scene.render.image_settings.compression = 15
    scene.render.filepath = str(OUT_DIR / "view.png")
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    scene.world = bpy.data.worlds.new("ImpostorWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.38, 0.42, 0.36, 1.0)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.35

    camera_data = bpy.data.cameras.new("ImpostorCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = size.z * 1.25
    camera = bpy.data.objects.new("ImpostorCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

    light_data = bpy.data.lights.new("ImpostorKey", "AREA")
    light_data.energy = 1150.0
    light_data.shape = "DISK"
    light_data.size = 3.0
    light = bpy.data.objects.new("ImpostorKey", light_data)
    scene.collection.objects.link(light)
    light.location = center + Vector((-3.0, -4.0, 4.0))
    light.rotation_euler = (center - light.location).to_track_quat("-Z", "Y").to_euler()

    fill_data = bpy.data.lights.new("ImpostorFill", "AREA")
    fill_data.energy = 550.0
    fill_data.size = 4.0
    fill = bpy.data.objects.new("ImpostorFill", fill_data)
    scene.collection.objects.link(fill)
    fill.location = center + Vector((3.0, 2.0, 2.0))
    fill.rotation_euler = (center - fill.location).to_track_quat("-Z", "Y").to_euler()

    for name, direction in VIEWS:
        camera.location = center + direction * 4.0
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(OUT_DIR / f"{name}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[IMPOSTOR_BAKE] rendered {name}: {scene.render.filepath}")

    print(f"[IMPOSTOR_BAKE] tiles ready in {OUT_DIR}")


if __name__ == "__main__":
    main()
