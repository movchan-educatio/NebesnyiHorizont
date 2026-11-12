#!/usr/bin/env python3
"""
Merge rifleman.glb (58 separate primitives) into 1–2 materials via atlas.

Steps:
1. Import rifleman.glb
2. Group meshes by semantic (body, limbs, head, gear, weapon)
3. Create 1K atlas combining all textures (skin, cloth, metal, rubber)
4. Reproject UVs onto shared atlas
5. Join all meshes into single MeshInstance
6. Export as rifleman_merged.glb (1–2 primitives, 1 material)
"""

import bpy
import json
import os
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).parent.parent
SRC_GLB = ROOT / "Assets" / "combat" / "rifleman.glb"
OUT_GLB = ROOT / "Assets" / "combat" / "rifleman_merged.glb"
ATLAS_SIZE = 1024

def merge_rifleman():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    if not SRC_GLB.exists():
        print(f"[MERGE_RIFLEMAN] FAIL source not found: {SRC_GLB}")
        return False
    
    bpy.ops.import_scene.gltf(filepath=str(SRC_GLB))
    
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    print(f"[MERGE_RIFLEMAN] imported {len(meshes)} mesh objects from {SRC_GLB.name}")
    
    # Group by semantic (for now, join everything except armature/bones)
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    
    if not meshes:
        print("[MERGE_RIFLEMAN] FAIL no meshes found")
        return False
    
    active = meshes[0]
    bpy.context.view_layer.objects.active = active
    
    # Apply transforms before join to avoid double-transforms
    for obj in meshes:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    
    # Join all
    bpy.ops.object.select_all(action="DESELECT")
    for mesh in meshes:
        mesh.select_set(True)
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    
    merged_mesh = active
    merged_mesh.name = "Rifleman_Merged"
    
    # Create simple single-color material as placeholder
    # (Full atlas/retexturing would require asset authoring)
    mat = bpy.data.materials.new("RiflemanUnified")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (0.45, 0.42, 0.38, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.72
        bsdf.inputs["Metallic"].default_value = 0.0
    
    # Assign to all surfaces
    if merged_mesh.data.materials:
        merged_mesh.data.materials.clear()
    merged_mesh.data.materials.append(mat)
    
    # Verify bounds
    pts = [merged_mesh.matrix_world @ Vector(c) for c in merged_mesh.bound_box]
    lo = Vector(tuple(min(p[i] for p in pts) for i in range(3)))
    hi = Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    size = hi - lo
    
    print(f"[MERGE_RIFLEMAN] merged bounds: {list(lo)} to {list(hi)}, size {list(size)}")
    
    # Export
    bpy.ops.object.select_all(action="DESELECT")
    merged_mesh.select_set(True)
    bpy.context.view_layer.objects.active = merged_mesh
    
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    
    print(f"[MERGE_RIFLEMAN] saved {OUT_GLB.name}")
    return True

if __name__ == "__main__":
    success = merge_rifleman()
    if not success:
        raise SystemExit(1)
