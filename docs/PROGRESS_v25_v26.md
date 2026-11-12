# Узагальнений звіт v25–v26: Шлях від критичних помилок до масштабування

## Стан реалізації вимог з промту

### ✅ ЗАВЕРШЕНО (v25)

**Критичні помилки (зафіксовані):**
1. ✅ Deadzone/Smoothing повзунки тепер впливають на сенсорні стіки
2. ✅ Аудіо відновлюється після iOS-переривань (alarm/Siri/call)
3. ✅ CRSF throttle правильно нормалізується для мобільного ELRS

**Графіка для мобіля:**
- ✅ Адаптивна 3D роздільність (0.58–0.84 scale)
- ✅ FPS cap за частотою дисплея (58/118 Hz)
- ✅ LOD для техніки (0–180 м / 180–480 м / >480 м)
- ✅ Animation LOD для піхоти (30 Hz / 15 Hz / paused)
- ✅ Мобільні GLB-варіанти (Leleka, Furia, Chaklun, Apache)

**Fixed-Wing FPV & Payload:**
- ✅ Leleka/Furia/Chaklun показують корпус у FPV
- ✅ Integrated warheads для 13/14/15 presets
- ✅ Touch button активує payload
- ✅ PC-інваріант: original payload=0, FPV unchanged

**QA Suite:**
- ✅ `qa_video_fixes`: 50+ тестів → **PASS**
- ✅ `qa_persist2_*`: persistence → **PASS**
- ✅ `qa_mobile_apache`: LOD & asset selection → **PASS**
- ✅ Audit asset bounds: all ±0.01 м

### 🟡 В ПРОЦЕСІ (v26)

**Rifleman merge (58→1 primitives):**
- ✅ Blender script написана й виконана
- ✅ `rifleman_merged.glb` створена (70 KB, 1 mesh, 1 primitive)
- 🟡 Q/A тест запущений (чекаю результат)
- 🟡 Fallback logic в infantry.gd (мобіль → merged, desktop → original)

**Animation LOD система:**
- ✅ Framework вже вбудований у v25
- ✅ `_apply_animation_lod(dist)` регулює playback_speed
- 🟡 Testing з merged rifleman_merged.glb
- 🟡 DetailedSoldierRig integration

**Billboard impostor:**
- 🟡 Placeholder script створена
- ⏳ Full baking (4 views → atlas) требує asset authoring

### ⏳ FUTURE (v27+)

**Infantry animations (6–8 clips):**
- Idle, Walk, Run, Aim, Fire, Reload, Hit, Death
- 24 bones, 30 fps keyframes, <80 KB per clip
- MoCap source або manual keyframing

**Baked lightmaps & occlusion culling:**
- AO/lightmaps для будівель (LightmapGI)
- Occluders для ПРОМЗОНИ

**Damage states & decals:**
- Підбита техніка (mesh swap)
- Вибухи, попадання, сліди

**Art direction pass:**
- Силуети, контраст, кольорове кодування
- Readability на мобілі

## Метрики оптимізації

| Ассет | Draw Calls | Primitives | Розмір | Status |
|---|---:|---:|---:|---|
| rifleman.glb | 58 | 58 | ~110 KB | Original (desktop) |
| rifleman_merged.glb | 1 | 1 | ~70 KB | ✅ v26 |
| Apache (mobile) | 26 | 26 | ~150 KB | ✅ v25 |
| Leleka (mobile) | 25 | 26 | ~4.5 MB | ✅ v25 |
| Infantry proxy (LOD1) | 1–2 | 1–2 | Capsule | ✅ v25 |

**Draw calls на сцену (10 піхотинців):**
- Desktop: 580 (58 × 10) → неприйнятне
- Mobile (original): 580 → неприйнятне
- Mobile (merged): 10 (1 × 10) → **58× improvement**

**Frame budget (мобіль, 60 FPS = 16.7 ms):**
- Graphics (70%): ~11 ms
  - 3D render: ~8 ms (includes LOD, batching)
  - HUD: ~2 ms (untouched by 3D LOD)
  - Compositing: ~1 ms
- Physics (15%): ~2.5 ms (terrain, vehicles, hitscan)
- Gameplay (15%): ~2.5 ms (AI, targeting, UI)

## Залежності & блокери

**v26 (в очікуванні):**
- Godot Rifleman merge QA result
- DetailedSoldierRig animation playback integration
- Mobile vs Desktop GLB path selection (fallback logic)

**v27 (вимагає контенту):**
- MoCap data або manual keyframe authoring for 6–8 animation clips
- High-res texture atlas creation (1K atlas combining 12 source materials)
- Billboard baking (Blender Cycles, 4× ortho renders)

## Файли що змінилися v25→v26

**Scripts:**
- `combat/enemy_infantry.gd`: Animation LOD speed adjustment
- `autoloads/DroneCatalog.gd`: Mobile FPV framing (v25)
- `autoloads/Graphics.gd`: Mobile quality detection (v25)
- `sceneries/BigLevel.gd`: Mobile front-prop visibility (v25)

**Assets (v26):**
- `Assets/combat/rifleman_merged.glb` (NEW)
- `tools/merge_rifleman_materials.py` (script)
- `tools/create_infantry_billboard.py` (script, placeholder)
- `test/qa_v26_rifleman_merged.gd` + `.tscn` (QA)

**Documentation:**
- `docs/v26_ROADMAP.md` (planning)
- `docs/ios/REPORT_v25.md` (finalized v25)

## Знані проблеми & відкриті питання

1. **Rifleman skeleton**: Original rifleman.glb немає кістяка (58 rigid parts). Merged версія також без анімацій. Потребує нового skeleton або RIG-а для Walk/Aim/Fire.

2. **DetailedSoldierRig**: V25 вже використовує ригований soldier, але його animation playback не інтегрований з `_apply_animation_lod()`. Потребує прямої передачі playback_speed до AnimationPlayer.

3. **Billboard alpha**: Impostor потребує proper alpha cutout shader для силуету. Поточний placeholder — просто quad.

4. **Bounds verification**: Всі merged GLB перевірені на bounds alignment. Rifleman merged — OK. Але animation bake може змінити bounds.

5. **PC regression**: Всі тести підтверджують що PC runtime не змінилась, але детальний проходdocumentation на фізичному PC потрібен перед production release.

## Next Steps (по пріоритетам)

1. **v26 Close-out**:
   - Дочекатись QA результату для rifleman merged
   - Додати fallback logic у Infantry._create_model()
   - Комітити v26 з prepare-for-animation меткою

2. **Animation Infrastructure (v27 Prep)**:
   - Досліджувати MoCap sources (BVH/FBX)
   - Або підготовити Blender rig з base skeleton
   - Написати batch animation importer

3. **Billboard System (v27)**:
   - Bake 4 views в Blender
   - Create texture atlas + dynamic rotation shader
   - Integrate в_build_lod_proxy() замість capsule

4. **Full v27 Release**:
   - Merge + 6–8 anims + billboard
   - ~50% draw call reduction для typical combat scene (20–30 soldiers)
   - Target: 60 FPS stable на iPhone 11/12

## Выводы

v25 **вирішила 3 критичні помилки + 3 feature requests** із промту. Мобільна інфраструктура LOD, адаптивна графіка, аудіо recovery й FPV framing готові.

v26 **розпочала наступну хвилю оптимізації**: rifleman merge дає 58× draw call reduction. Це базис для масштабування на мобілі без втрати деталей.

v27+ — це контентна робота (анімації, атласи, baking), але infrastructure готова.

---

**Report Date**: 2026-11-12  
**Last Commit**: v25 (09abd7d)  
**Next Milestone**: v26 close-out (awaiting rifleman QA)  
**iOS Build**: Ready for GitHub Actions workflow
