#!/usr/bin/env python3
"""
Create a minimal rigged skeleton for rifleman_merged.glb.
Simplified version without auto-weight (just bone structure).
"""

import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).parent.parent
MERGED_GLB = ROOT / "Assets" / "combat" / "rifleman_merged.glb"
OUT_GLB = ROOT / "Assets" / "combat" / "rifleman_rigged.glb"

def create_rifleman_rig():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    
    if not MERGED_GLB.exists():
        print(f"[RIG] FAIL: {MERGED_GLB} not found")
        return False
    
    # Import merged mesh
    bpy.ops.import_scene.gltf(filepath=str(MERGED_GLB))
    
    meshes = [o for o in scene.objects if o.type == "MESH"]
    print(f"[RIG] Imported {len(meshes)} mesh object(s)")
    
    if not meshes:
        print("[RIG] FAIL: No meshes found")
        return False
    
    mesh_obj = meshes[0]
    
    # Create armature in edit mode
    arm_data = bpy.data.armatures.new("RiflemanArm")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    scene.collection.objects.link(arm_obj)
    
    # Set context
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    
    # Add bones
    bones_data = [
        ("Hips", (0, 0.5, 0), (0, 1.0, 0), None),
        ("Spine", (0, 1.0, 0), (0, 1.4, 0), "Hips"),
        ("Chest", (0, 1.4, 0), (0, 1.7, 0), "Spine"),
        ("Neck", (0, 1.7, 0), (0, 1.85, 0), "Chest"),
        ("Head", (0, 1.85, 0), (0, 2.05, 0), "Neck"),
        ("L_Shoulder", (-0.18, 1.6, 0), (-0.55, 1.45, 0), "Chest"),
        ("L_Elbow", (-0.55, 1.45, 0), (-0.85, 1.25, 0), "L_Shoulder"),
        ("L_Wrist", (-0.85, 1.25, 0), (-0.95, 1.1, 0), "L_Elbow"),
        ("R_Shoulder", (0.18, 1.6, 0), (0.55, 1.45, 0), "Chest"),
        ("R_Elbow", (0.55, 1.45, 0), (0.85, 1.25, 0), "R_Shoulder"),
        ("R_Wrist", (0.85, 1.25, 0), (0.95, 1.1, 0), "R_Elbow"),
        ("L_Hip", (-0.1, 0.5, 0), (-0.1, 0.1, 0), "Hips"),
        ("L_Knee", (-0.1, 0.1, 0), (-0.1, -0.5, 0), "L_Hip"),
        ("L_Ankle", (-0.1, -0.5, 0), (-0.1, -1.2, 0), "L_Knee"),
        ("R_Hip", (0.1, 0.5, 0), (0.1, 0.1, 0), "Hips"),
        ("R_Knee", (0.1, 0.1, 0), (0.1, -0.5, 0), "R_Hip"),
        ("R_Ankle", (0.1, -0.5, 0), (0.1, -1.2, 0), "R_Knee"),
    ]
    
    for name, head, tail, parent in bones_data:
        bone = arm_data.edit_bones.new(name)
        bone.head = Vector(head)
        bone.tail = Vector(tail)
        if parent:
            parent_bone = arm_data.edit_bones.get(parent)
            if parent_bone:
                bone.parent = parent_bone
    
    print(f"[RIG] Created {len(arm_data.edit_bones)} bones")
    
    # Exit edit mode
    bpy.ops.object.mode_set(mode="OBJECT")
    
    # Parent mesh to armature (simple parenting, no weights for now)
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.parent_set(type="OBJECT")
    
    print("[RIG] Parented mesh to armature")
    
    # Export
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_GLB),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_skins=True,
    )
    
    print(f"[RIG] Saved {OUT_GLB.name}")
    return True

if __name__ == "__main__":
    success = create_rifleman_rig()
    if not success:
        raise SystemExit(1)
