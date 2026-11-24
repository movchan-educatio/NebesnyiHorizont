# v30 Independent QA & Remediation Report

**Repository:** `C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC` (uncommitted working tree on base commit `fb5b9d0`)  
**Engine:** `Godot_v4.6.1-stable_win64_console.exe`

---

## 1. Oil Rig Floating-Objects Root Cause & Fixes (`maps/oil_rig/`, `sceneries/OilRigLevel.gd`)

1. **Exporter Y-scale & collider axis mismatch (`maps/oil_rig/oil_rig_map.tscn`, `scripts/instancing_data.json`):**
   - `Modules` instances used unscaled `3.2` on Y while X/Z used `sc` (`3.0` on main modules, `1.56` on `Tanker_31`), squashing decks below their derricks/props; fixed all 39 `Modules` Y-scales (`sc * 3.2`: `9.6` main modules, `4.992` `Tanker_31`).
   - Swapped Blender `(X, Y, Z)` -> Godot `(X, Z, Y)` on all 34 `BoxShape3D_b*` collision shapes and recomputed all 376 `RailPosts` heights (`y = 378.24 / 379.20`).
2. **Backface culling (`cull_mode = 2`) & ocean textures:**
   - Added `cull_mode = 2` (`CULL_DISABLED`) to `maps/oil_rig/materials/structures.tres`, `deck.tres`, `emissive.tres`, `light.tres`, and `StandardMaterial3D_post` in `maps/oil_rig/oil_rig_map.tscn` so inward/flipped faces of procedural `geomlib.py` cylinders and deck undersides no longer disappear and make equipment look floating.
   - Fixed `ShaderMaterial_ocean` parameter prefixes (`shader_parameter/wave_a|wave_b|foam_mask`), fixed `water_normal_a/b.png.import` (`compress/normal_map=0`, `mipmaps/generate=true`), removed runtime shader parameter overrides in `sceneries/OilRigLevel.gd`, updated `DEFAULT_SPAWN = (-204, 407.04, 510)`, disabled training rings, and fixed `_on_oilrig_water_body`.
3. **Preview thumbnail & reimport:**
   - Re-rendered `Assets/Branding/mobile_map_oilrig.png` (`1920x1080`) after the material/culling fix and ran `--headless --path . --editor --quit` so `MobileMenu` renders the updated `.ctex`.

---

## 2. Lis Forest Terrain, Scatter, Water & Grounding (`maps/lis_forest_freestyle/`, `sceneries/LisLevel.gd`)

- Restored conifer `tree_trunk_*` MultiMesh chunks (`16` chunks) in `maps/lis_forest_freestyle/scripts/scatter_multimesh.gd` and removed invalid `alpha_hash_enabled` in `setup_collisions.gd`.
- Added `_built` guard to `setup_collisions.gd` and invoked `_map_instance.call("_build")` synchronously from `LisLevel._load_map()` so terrain/prop colliders exist before mission units spawn.
- Rewrote `LisLevel._find_ground_y()` (removing the `+0.05` self-climb offset, excluding `Drone` and unit/target groups, looping up to 16 raycasts and accepting only hits under `LisFreestyleMap/Terrain` (`terrain_playable-colonly`) so overhead `Structures`/`FreestyleGeometry` props do not cause `8.09 m` escort elevation jumps).
- Wired `FOREST_WATER_Y = -12.0`, `forest_is_water` checks, and kill-zone/void clamps in `LisLevel.gd` and `BigLevel.gd`.

---

## 3. Kamikaze, Missions, New Drones, Economy & Menus

- **Kamikaze & Missions (`combat/enemy_kamikaze_drone.gd`, `combat/enemy_infantry.gd`, `combat/ballistics.gd`, `sceneries/BigLevel.gd`):** Added standalone auto-activation, `impacted_player` tracking, rotor blade grouping around `*_HubUpper` pivots, AGL terrain clearance, non-primary tagging on non-kill special ops `[1,2,3,4,11,13]`, and dedicated Lis mission routes/altitudes.
- **Drones (`autoloads/DroneCatalog.gd`, `scripts/util/DronePropellerSystem.gd`):** Added presets `13` (`wraith`), `14` (`komar`), `15` (`shmel`) with 4 rotor pivots, preserved author textures (`keep_authored_colors`), and reverted preset `5` (`military_fpv`) to its `fb5b9d0` baseline (`twr = 3.1`, `drag_area = Vector3(0.050, 0.060, 0.035)`).
- **Economy & Menus (`autoloads/Progress.gd`, `autoloads/Global.gd`, `GUI/MainMenu.gd`, `GUI/DroneSelectScreen.gd`, `GUI/mobile/MobileMenu.gd`):** Removed legacy `mode_chaos`/`award_sortie`, fixed `first_key` cap burn bug, added atomic `.tmp` -> `.bak` save recovery, 2-tap unlock confirmation, compact `"🔒 ◈ %d"` mobile map card badge, and startup guards resetting locked `_selected_map` / `_selected_special`.
- **Clutter Cleanup:** Removed `maps/oil_rig/qa/` (405 files) and stray `qa_*` scene/script artifacts inside `maps/`.

---

## 4. Verification Results (`qa_shots/v30_fix_verify/` — run after final edit to `sceneries/LisLevel.gd`)

| Check / Suite | Exit | Observed Result |
|---|---:|---|
| `--headless --path . --editor --quit` | `0` | 0 `SCRIPT ERROR` / `SHADER ERROR` / `Parse Error` / `ERROR:` |
| `test/qa_v30_systems.tscn` | `0` | `[V30-SYS] failures=0` (ConfigFile parse error log line is from intentional `.bak` corruption test) |
| `test/qa_v30_maps.tscn` | `0` | `[V30-MAP] failures=0` |
| `test/qa_v30_water.tscn` | `0` | `[WATER-QA] failures=0` |
| `test/qa_v30_drone_colors.tscn` | `0` | `[COLOR] failures=0`, 0 ObjectDB leaks |
| `test/qa_v30_oilrig_materials.tscn` | `0` | `[MAT-TEST] failures=0` (`--verbose`: 0 leaked `Node`/`Mesh`, 3 active `SceneTreeTimer`s at exit) |
| `test/qa_airport_missions.tscn` (`QA_MAP=lis_forest_freestyle`, `QA_UNLOCK_ALL=1`) | `0` | `[MAP-QA:lis_forest_freestyle] screenshots=0 failures=0` (`escort max_step=0.59 m`, `0` stalls/recoveries) |
| `test/qa_mobile_missions_audit.tscn` (`QA_MAP=lis_forest_freestyle`, `QA_UNLOCK_ALL=1`) | `0` | `PASS_COUNT=122`, `[MOB-QA:lis_forest_freestyle] screenshots=0 failures=0` |
| `test/qa_prop_animation.tscn` | `0` | `[PROP_QA] failures=0` |
| `test/qa_respawn_fpv_view.tscn` | `0` | `[RESPAWN_FPV] failures=0` |
| `test/qa_uman_freestyle.tscn` | `0` | `[UMAN-QA] fails=0` |
| `test/test_special_missions.tscn` | `0` | `[SPECIAL] RESULT PASS` |
| `test/qa_all20_fixes.tscn` | `0` | `[QA20] SUMMARY failures=0` |
| `test/qa_mobile_mission_completion.tscn` | `0` | `[MOBILE_MISSION_COMPLETION] failures=0` |
| `test/test_release_readiness.tscn` | `0` | `[RELEASE-QA] mobile_ui=false fails=0` |
| `test/qa_all_drones_flight.tscn` (`--quit-after 20000`) | `1` | Presets `0..4`, `6..12`, and `13..15` pass; preset `5 military_fpv` fails `bad forward 50%SoC (v=3.6 tilt=38.2 dy=-12.2)` (pre-existing on unmodified `fb5b9d0` baseline; headless dummy renderer also logs `Parameter "material" is null` on presets 10–12). |

---

## 5. Visually Inspected Screenshots

All 10 images were opened and inspected directly:
- `Assets/Branding/mobile_map_oilrig.png`
- `Assets/Branding/mobile_map_lis_forest_freestyle.png`
- `qa_shots/v30_fix_verify/oilrig_overview.png`
- `qa_shots/v30_fix_verify/oilrig_deck_closeup.png`
- `qa_shots/v30_fix_verify/lis_trunks_infantry.png`
- `qa_shots/v30_fix_verify/drone_13_wraith.png`
- `qa_shots/v30_fix_verify/drone_14_komar.png`
- `qa_shots/v30_fix_verify/drone_15_shmel.png`
- `qa_shots/v30_fix_verify/mobile_menu_play.png`
- `qa_shots/v30_fix_verify/mobile_menu_hangar.png`

---

## 6. Remaining Real-Device / Manual Notes

- **Real iOS Device:** Headless Windows runs and desktop Vulkan/dummy captures do not validate iOS Metal shader compilation, frame-rate budgets on thermal throttling, real touch multi-finger ergonomics, or `user://` container migration across app updates.
- **Interactive Flight:** Test-driven forward/hover checks passed for new drones `13..15`, while human FPV stick feel (camera angle, audio mix, kamikaze terminal approach) still benefits from a live playtest; preset `5` (`military_fpv`) forward-flight test failure (`v=3.6`, `dy=-12.2`) remains as inherited from commit `fb5b9d0`.
- **Untouched Artifacts:** `qa_shots/v30_triple/` was preserved untouched.
