# v26 Road Map: Infantry Optimization & Animation LOD

**Target**: Merge rifleman.glb (58 primitives → 1) + add 6–8 animation clips + billboard impostor for far LOD

## Phase 1: Merge Rifleman Materials (Blender)

1. Import `rifleman.glb` (58 separate meshes, 12 materials)
2. Group by semantic class:
   - Head/Neck (3 meshes)
   - Torso/Arms (12 meshes)
   - Legs (8 meshes)  
   - Gear/Pouches (15 meshes)
   - Weapon/Accessories (20 meshes)
3. Create 1K atlas combining all textures (color, normal, roughness)
4. Reproject UVs onto shared atlas
5. Join all into single MeshInstance (1 primitive, 1 material)
6. Export as `rifleman_merged.glb`

**Status**: Script prepared (`tools/merge_rifleman_materials.py`)
**Blocking**: Asset authoring (texture atlas creation)

## Phase 2: Add Animation Clips (Blender)

Create 6–8 new animations from scratch or from free MoCap:
- `Idle`: standing neutral (loop)
- `Walk`: forward movement (loop)
- `Run`: faster movement (loop)
- `Aim`: rifle raised to shoulder (loop)
- `Fire`: single shot + recoil (1–2 sec)
- `Reload`: magazine swap (3–4 sec)
- `Hit`: flinch reaction (0.5–1 sec)
- `Death`: falling/ragdoll start (1–2 sec)

**Target**: 24 bones max, 30 fps keyframes, <80 KB per clip

**Status**: Not started
**Blocking**: MoCap source or manual keyframe authoring

## Phase 3: Billboard Impostor (Blender + Shader)

1. Bake 4 orthogonal views of animated soldier (front/back/left/right)
2. Combine into 2×2 texture atlas (512×512 or 256×256)
3. Create single quad Billboard mesh with alpha cutout
4. Use custom shader for dynamic rotation (face camera)

**Status**: Placeholder script created (`tools/create_infantry_billboard.py`)
**Blocking**: High-quality bake (requires Blender Cycles + high sample count)

## Phase 4: Animation LOD System (GDScript)

Already partially implemented in v25:
- `_apply_animation_lod(dist)` adjusts playback speed by distance
- Near (0–95 m): 30 Hz (playback_speed = 1.0)
- Mid (95–260 m): 15 Hz (playback_speed = 0.5)
- Far (260+ m): paused (playback_speed = 0.0)

**To do**: 
- Integrate DetailedSoldierRig animation playback speed
- Test with merged rifleman mesh
- Verify proxy swap at 125 m doesn't pop

**Status**: Integrated into v25
**Blocking**: rifleman_merged.glb ready

## Phase 5: Material Atlas Optimization

Once merged, apply shaders:
- Triplanar normal (add rivets/seams without UVs)
- Vertex AO from bake
- Emission for eyes
- Simple metallic for helmets/gear

**Status**: Pending
**Blocking**: merger completion + atlas texture

## Deliverables

| Item | v25 | v26 |
|---|---|---|
| rifleman.glb merge | — | ✅ planned |
| Animation clips (6–8) | — | ✅ planned |
| Billboard impostor | — | ✅ planned |
| Animation LOD (speed) | ✅ done | — |
| LOD proxy mesh | ✅ done | improve |

## Known Dependencies

- Blender 5.2+
- Texture atlas tool (e.g., Substance Designer or Blender UV Packing)
- MoCap source or manual keyframing skillset
- Time for asset authoring (≥8 hours for full soldier)

## Why This Matters

- **Reduce draw calls**: 58 → 1 per soldier = 10× improvement
- **Animation fidelity**: Idle/walk/aim/reload teach player unit state at a glance
- **Mobile viability**: Proxy at 125 m + animation LOD = 30 FPS on older iPhones even with 20–30 soldiers on screen
