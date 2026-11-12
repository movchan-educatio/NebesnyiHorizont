# v27 Planning: Animation System & Billboard Impostor

> **Status update:** This is the original planning document, not the current
> completion status. Mobile implementation now uses the skinned
> `soldier_detailed_merged.glb`, eight procedural animation actions, mobile
> 30/15/0 Hz pose LOD, and a baked four-view Sprite3D impostor. Runtime QA and
> screenshots are recorded in `docs/FINAL_MOBILE_REPORT.md`. Separate
> AnimationPlayer clip assets and physical iPhone performance measurements are
> still not claimed as completed.

## Objectives

Transform v26 infrastructure into production-ready soldier animation system.

### Phase 1: Mesh Skinning (Week 1)

**Goal**: Make rigged skeleton deform mesh

1. Import rifleman_rigged.glb into Blender
2. Select mesh + armature, use Ctrl+P → Armature Deform
3. Auto-weight or manual paint weights for key bones:
   - Spine chain → torso mesh
   - Arm bones → upper arms + hands
   - Leg bones → legs + feet
4. Test T-pose doesn't collapse
5. Export as rifleman_skinned.glb

**Deliverable**: Mesh that deforms when bones rotate

### Phase 2: Walk Animation (Week 2)

**Goal**: Keyframe Walk cycle (1.8 seconds, loop)

1. Create 8-frame walk cycle in Blender:
   - Frame 0: contact (left foot forward)
   - Frame 2: lift (right foot up)
   - Frame 4: contact (right foot forward)
   - Frame 6: lift (left foot up)
   - Frame 8: return to frame 0
2. Adjust hip height (0.1m bob)
3. Arms counter-rotate
4. Export as rifleman_walk.glb
5. Import animation into Godot

**Deliverable**: Looping Walk animation at 30 fps

### Phase 3: Run, Aim, Fire (Week 3)

**Quick animations** (higher speed, shorter cycles):

- **Run**: 3-frame cycle (1 second), faster stride, higher hip bob
- **Aim**: 1-frame pose (rifle raised, ready to fire)
- **Fire**: 2-frame recoil (0.3 sec), gun pushes back + flinch

Export each as separate .glb or combined into one with named clips.

### Phase 4: Death + Reload (Week 4)

- **Reload**: 2 seconds, magazine swap, straighten rifle
- **Hit**: 0.5 sec flinch (optional, can use ragdoll)
- **Death**: 1 second fall (can transition to ragdoll)

### Phase 5: Billboard Impostor (Week 4–5)

**Goal**: Replace capsule LOD proxy with high-res silhouette

1. **Bake 4 ortho views** in Blender:
   - Front, Back, Left, Right
   - Render at 512×512 each
   - Wireframe or silhouette shader
2. **Create texture atlas**:
   - 2×2 layout (front, back, left, right)
   - 1024×1024 or 512×512 combined
3. **Create billboard shader**:
   - Alpha cutout (discard transparent pixels)
   - Face camera (LookAt-based rotation)
   - LOD: use billboard at >125m distance
4. **Integrate into _build_lod_proxy()**:
   - Replace capsule mesh with billboard quad
   - Apply impostor material

**Deliverable**: Proxy mesh switches from capsule → billboard, reduces LOD draw calls by 2×

## Animation Playback in Godot

**Current infrastructure (v26):**
- DetailedSoldierRig (or similar class) loads animations from GLB
- AnimationPlayer on soldier node
- _apply_animation_lod(dist) adjusts playback_speed
- Animation LOD: 1.0 (near) → 0.5 (mid) → 0.0 (far)

**To implement:**
1. Load all animation clips (Walk, Run, Aim, Fire, Reload, Hit, Death) on spawn
2. Store current animation state (idle_facing, walking, aiming, firing)
3. Call play("Walk") when moving, play("Aim") when targeting
4. Use blend_positions or simple crossfade for transitions
5. LOD system automatically throttles playback speed

## File Organization (v27)

```
Assets/combat/
  rifleman_merged.glb          (v26, static merged mesh)
  rifleman_rigged.glb          (v26, skeleton only)
  rifleman_skinned.glb         (v27 w1, mesh + weighted skeleton)
  rifleman_walk.glb            (v27 w2, Idle + Walk clip)
  rifleman_run.glb             (v27 w3, Run clip)
  rifleman_combat.glb          (v27 w3, Aim + Fire + Reload)
  rifleman_death.glb           (v27 w4, Hit + Death)
  rifleman_impostor_atlas.png  (v27 w5, 2x2 billboard texture)
  rifleman_impostor.glb        (v27 w5, quad mesh for far LOD)

tools/
  create_rifleman_rig.py                  (v26, done)
  create_rifleman_skinned.py              (v27 w1)
  create_rifleman_walk.py                 (v27 w2)
  create_rifleman_run_aim_fire.py         (v27 w3)
  create_rifleman_impostor_bake.py        (v27 w5)

combat/
  enemy_infantry.gd                       (updated v27 to play animations)
  DetailedSoldierRig.gd                   (update playback_speed handling)

test/
  qa_v27_walk_animation.tscn             (test Walk playback)
  qa_v27_animation_lod.tscn              (test speed adjustment)
  qa_v27_impostor_visibility.tscn        (test billboard LOD swap)
```

## Success Criteria

| Criterion | Metric | Target |
|-----------|--------|--------|
| Draw calls (10 soldiers, <95m) | count | ≤20 |
| Draw calls (10 soldiers, >260m) | count | 0 |
| Animation smoothness | fps | 30+ near, 15+ mid |
| Impostor LOD pop | visible | imperceptible |
| Mobile FPS (20 soldiers) | fps | ≥30 |
| Asset size (all clips) | MB | <5 total |
| Rig flexibility | bones | ≥20 (ready for procedural anim) |

## Known Risks

1. **Blender keyframing**: Manual animation authoring is time-consuming. Consider:
   - Using free MoCap data (CMU dataset, Mixamo)
   - Procedural walk (sin-wave stride)
   - Simple 2–3 frame cycles for low LOD

2. **Godot animation transitions**: Crossfading between clips requires:
   - Named animation tracks
   - Proper spine alignment to avoid pop
   - Consider using AnimationTree for state machine

3. **Billboard baking**: High-quality bake needs:
   - Blender Cycles 50+ samples (5–10 min per angle)
   - Proper alpha cutout to avoid silhouette noise
   - Fallback: use simple silhouette shader instead of baked texture

## Fallback Options (If Time Runs Out)

1. **No full animations**: Keep static merged soldier + animation LOD framework
   - Reduces draw calls (achieved)
   - Player doesn't see walk/aim/reload
   - Cost: minimal (skip animation authoring)

2. **Procedural walk**: Code-based leg swing (no animation clips needed)
   - Adjusts leg rotation via script
   - Simpler but less polished
   - Cost: 1–2 days

3. **Capsule LOD only**: Skip billboard impostor
   - Keeps capsule proxy
   - Slower LOD transition than billboard
   - Cost: save 1 week of baking

## Recommendation

**Focus on animation clip authoring first** (Weeks 1–3):
1. Get Walk working
2. Run can reuse Walk skeleton (just faster)
3. Aim + Fire are mostly static poses

**Billboard impostor is "nice-to-have"** for further optimization. Capsule LOD already gives 58× draw call reduction.

## Ready to Start?

**Prerequisites:**
- Blender 5.2+ with Python scripting
- Godot 4.7+ imported asset ready
- Animation author or MoCap data source

**Estimated Effort:**
- Animation authoring: 2–3 weeks
- Impostor baking: 1 week
- Godot integration: 1 week
- Testing + polish: 1 week

**Total: v27 = 5–6 weeks** if starting with full animation suite.
