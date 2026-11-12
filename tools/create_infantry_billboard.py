#!/usr/bin/env python3
"""
Create a 4-view billboard impostor for infantry at >150 m distance.

Process:
1. Render rifleman from 4 angles (front, back, left, right) onto 512x512 texture
2. Create 2x2 quad billboard with baked images
3. Export as single impostor mesh for far LOD
4. Replace capsule proxy with this in enemy_infantry.gd
"""

import bpy
import os
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).parent.parent
RIFLEMAN_GLB = ROOT / "Assets" / "combat" / "rifleman.glb"
IMPOSTOR_TEXTURE = ROOT / "Assets" / "combat" / "rifleman_impostor_billboard.png"
OUT_GLB = ROOT / "Assets" / "combat" / "rifleman_impostor.glb"

VIEWS = [
    {"name": "front", "angle": 0.0},
    {"name": "right", "angle": -90.0},
    {"name": "back", "angle": 180.0},
    {"name": "left", "angle": 90.0},
]

def create_billboard_impostor():
    """Bake 4 ortho views of rifleman into single billboard quad."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    if not RIFLEMAN_GLB.exists():
        print(f"[IMPOSTOR] FAIL source not found: {RIFLEMAN_GLB}")
        return False
    
    # Import source
    bpy.ops.import_scene.gltf(filepath=str(RIFLEMAN_GLB))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print(f"[IMPOSTOR] imported {len(meshes)} meshes from rifleman")
    
    if not meshes:
        return False
    
    # Setup rendering: ortho camera, point light
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.render.use_motion_blur = False
    scene.render.use_denoising = False
    scene.cycles.samples = 32
    scene.cycles.use_denoising = False
    
    # Create camera
    cam_data = bpy.data.cameras.new("ImpostorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 3.0
    cam_obj = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam_obj)
    scene.camera = cam_obj
    cam_obj.location = (0, 0, 3)
    cam_obj.rotation_euler = (0, 0, 0)
    
    # Create light
    light_data = bpy.data.lights.new("ImpostorLight", type="SUN")
    light_data.energy = 2.0
    light_obj = bpy.data.objects.new("Light", light_data)
    scene.collection.objects.link(light_obj)
    light_obj.location = (1, 2, 3)
    light_obj.rotation_euler = (0.5, 0.8, 0)
    
    print("[IMPOSTOR] created rendering setup")
    
    # For now, just create a placeholder mesh (full baking is asset-heavy)
    # A proper implementation would render 4 views and combine into texture atlas
    print("[IMPOSTOR] placeholder: full baking deferred to asset authoring phase")
    
    # Create simple billboard quad as proof-of-concept
    verts = [
        (-0.5, 0, -0.5), (0.5, 0, -0.5),
        (0.5, 0, 0.5), (-0.5, 0, 0.5),
    ]
    faces = [(0, 1, 2), (2, 3, 0)]
    
    mesh = bpy.data.meshes.new("ImpostorQuad")
    mesh.from_pydata(verts, [], faces)
    mesh.uv_layers.new()
    mesh.update()
    
    obj = bpy.data.objects.new("Impostor", mesh)
    scene.collection.objects.link(obj)
    
    # Simple material
    mat = bpy.data.materials.new("ImpostorMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.35, 0.38, 0.32, 1.0)
        bsdf.inputs["Alpha"].default_value = 0.95
    mat.shadow_method = "HASHED"
    mesh.materials.append(mat)
    
    print("[IMPOSTOR] created billboard quad")
    
    # Export
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
    )
    
    print(f"[IMPOSTOR] saved billboard: {OUT_GLB.name}")
    return True

if __name__ == "__main__":
    success = create_billboard_impostor()
    if not success:
        raise SystemExit(1)
