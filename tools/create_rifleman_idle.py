#!/usr/bin/env python3
"""
Create a minimal Idle animation for rigged rifleman.

Single-frame "T-pose" animation at 30 fps:
- All bones in default pose
- Used for testing animation playback before Walk/Run/Fire are authored
"""

import bpy
from pathlib import Path

ROOT = Path(__file__).parent.parent
RIGGED_GLB = ROOT / "Assets" / "combat" / "rifleman_rigged.glb"
OUT_ANIM = ROOT / "Assets" / "combat" / "rifleman_idle.glb"

def create_idle_animation():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    
    if not RIGGED_GLB.exists():
        print(f"[ANIM_IDLE] FAIL source not found: {RIGGED_GLB}")
        return False
    
    # Import rigged mesh
    bpy.ops.import_scene.gltf(filepath=str(RIGGED_GLB))
    
    # Find armature
    armatures = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if not armatures:
        print("[ANIM_IDLE] FAIL no armature found")
        return False
    
    armature = armatures[0]
    scene = bpy.context.scene
    
    # Create Action (animation)
    action = bpy.data.actions.new("Idle")
    
    # Pose bones are already in default position
    # Add a single keyframe at frame 1 to satisfy animation requirement
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    
    # Insert keyfames for all bones at frame 1
    scene.frame_current = 1
    for bone in armature.pose.bones:
        bone.keyframe_insert(data_path="location", frame=1)
        bone.keyframe_insert(data_path="rotation_quaternion", frame=1)
        bone.keyframe_insert(data_path="scale", frame=1)
    
    # Set action
    armature.animation_data_create()
    armature.animation_data.action = action
    
    print(f"[ANIM_IDLE] created animation '{action.name}' with {len(action.fcurves)} curves")
    
    # Export with animation
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    
    bpy.ops.export_scene.gltf(
        filepath=str(OUT_ANIM),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_skins=True,
        export_deformation_bones=True,
    )
    
    print(f"[ANIM_IDLE] saved {OUT_ANIM.name}")
    return True

if __name__ == "__main__":
    success = create_idle_animation()
    if not success:
        raise SystemExit(1)
