# Final mobile implementation report

**Scope:** iOS/mobile only. No desktop feature work is included.

## Delivered and verified

| Requirement | Result | Evidence |
|---|---|---|
| Touch/ELRS deadzone and smoothing | Implemented through the shared `Controls.apply_stick_filter` path; touch and ELRS yaw/roll/pitch use it. Native CRSF packets are normalized from the complete channel frame to a single 15-bit scale, removing the 2048/2049 throttle jump and aligning AUX switches. | `qa_video_fixes` 48 PASS checks; `qa_mobile_elrs_protocol` 13 PASS checks. Physical transmitter validation still required. |
| iOS audio resume | App pause/resume notifications restore bus mute state and reapply volume settings; intentional mute is preserved, including repeated focus-out/pause notifications in one interruption. | `qa_video_fixes`: resume and intentional-mute checks PASS (notification simulation, not a physical call/Siri test). |
| Touch/mobile UI | Launch prompts refer to ARM instead of SPACE; the bomb sight uses mobile DROP/VIDEO hints and the selected airframe name; saved HUD preferences are no longer overwritten on level start. | `qa_mobile_hud_preferences`: 7 PASS checks; `qa_mobile_map_cards`: headless card-resource PASS and non-headless menu screenshot captured. |
| Existing map presentation | Steppe, Village, Industrial and Wetlands now have distinct mobile ground grading, contextual hall signs, a corrected panorama seam, and real FPV screenshots on the map cards instead of empty top-down previews. | `qa_mobile_map_identity`: 20 PASS checks; four map views generated with zero script/parse errors; before/after images in `docs/ios/mobile_audit_2026/`. Deeper route/density art pass remains open. |
| Mobile navigation beacons | Each frontline map gained three colour-coded collidable masts on clear ground between landmarks, so pilots can read direction at range. | `qa_mobile_map_views` now fails when fewer than two beacons are built; all four maps log `placed=3`. |
| Mobile hero landmarks | Three unique collidable silhouettes per map: wind turbine + fuel depot + silo bank (Steppe), grain elevator + church + market stalls (Village), flare stack + pipe rack + water cistern (Industrial), lighthouse + boathouse + pier house (Wetlands). Registered so scatter passes keep their berth. | `qa_mobile_map_views` requires at least three `MobileHero*` nodes per map plus a float scan (no POI hovers or sinks more than 0.45 m). |
| Terrain tiling | Deterministic low-alpha ground tint patches (up to 6 per map) break the repeating grass pattern without adding texture samples to the terrain shader. They spiral to nearby dry ground when a planned spot is reserved. | `qa_mobile_map_views` requires at least four `MobileGroundPatch*` per map; steppe=6, village=6, industrial=6, wetlands=6. |
| Map collision sweep | Existing scene probes pass on mobile-mode maps: solid objects, roof landings and open tops verified. | `qa_object_solid` PASS (9 checks), `qa_landing_roof` PASS, `qa_open_tops` PASS; `qa_floating_probe` and `qa_near_factory` exit 0. `qa_chimney_holes` (Village 310,80) is an open reconciliation item. |
| Mobile squad reaction | A hit or destroyed comrade within 42 m makes neighbours duck, and about a third briefly scatter away from the impact. Gait phases are deterministically desynced so squads never march in lockstep. | `qa_mobile_infantry_lod`: squad gait and nearby-duck checks PASS (26 PASS total). |
| Animation policy | Eight separate AnimationPlayer clips (Idle, Walk, Run, Aim, Fire, Reload, Hit, Death) are baked from the procedural poses into `Assets/combat/animations/` and hosted by a `ClipPreview` player on the mobile rig. Gameplay stays procedural; the clips are ready for a future AnimationTree. | `qa_mobile_animation_clips`: 11 PASS — all clips load and play on the skeleton. |
| Mission completion regression | TAC-05 (naval) extraction marker moved from land near the hydro plant to open water at (320, 80) so the Magura-X can finish. Missions 1–4 now complete end-to-end on the real BigLevel: recon hold → strike → all targets → extraction hold → results. | `qa_mobile_naval_mission`: 6 PASS; `qa_mobile_mission_completion`: 24 PASS across missions 1–4. |
| Mobile accessibility | Interface font scale 85–145% in the System settings tab; applies immediately by rebuilding the menu screens and persists with an out-of-range clamp on load. | `qa_mobile_font_scale`: 5 PASS. |
| Owner-video fixes | Fixed-wing mobile presets keep a clean nose FPV lens (the old airframe framing put the wing across the centre); touch hint reads ARM instead of SPACE; drone-card previews clamp to ±18% of the target size; the mission marker shows distance and a bearing arrow; the next training gate pulses; the in-flight top bar collapses to MENU + "⋯" on the left edge; slalom banners use hazard stripes; HUD link/jamming text is Ukrainian; mobile front props are no longer clipped at the frame edges. | `qa_mobile_fixed_wing_fpv`: 12 PASS with control frames; `qa_mobile_infantry_lod`, `qa_video_fixes`, `qa_mobile_mission_completion`, `qa_mobile_naval_mission` re-run green. |
| Mobile map objects | 20 Blender props + 10 hand-sculpted forge assets + 5 large landmarks per map (warehouse, grain elevator, cargo ship, factory, farm, fuel depot pool) with one material each, box colliders on compact props, a low base plinth on open/tall forge shells, and hollow `-colonly` collision plus fly-through openings (door bays, ridge skylights, open chimney, open cargo holds) on landmarks. Placement spirals to a dry, clear site with real spacing from other objects and existing POIs. | `qa_mobile_map_views` on all four maps: `props=35 forge=10 large=5 spacing_overlaps=0 float_bad=0 collider_bad=0`, corridors ≤13% blocked; `qa_mobile_landmark_stunts` probes the openings. |
| Forge asset layer | 40 war-wear GLBs rebuilt in Blender (10 per map: LEP pylon, breached khata, cooling tower, half-sunk barge, bridges, hangars, towers) with baked albedo embedded as Basis Universal, one mesh/material each and a 650–1200 m distance LOD. The half-sunk barge uses the water-site search; destroyed shells keep their openings passable via a 2.8 m base plinth. | Forge re-import: 40/40 scenes load with one textured material; `qa_mobile_map_views` reports `forge=10` and zero spacing/float/collider faults on all maps. Details: `docs/ios/FORGE_PROP_LAYER.md`. |
| Map colour pass | Crop fields use the rendered terrain-triangle height (no floating edges), muted per-field vertex tints instead of lime quads; the burnt-armour scorch decal and explosion craters are softer and lighter so they no longer read as black holes. | Visual pass; map QA stays green. |
| War-damaged landmarks | Gable-end triangles fill the roof ends, a missing roof bay, soot patches, rust streaks and rubble piles give the large structures a ruined military look; the warehouse and factory have door bays on both ends (fly-through) plus through-window rows. | `qa_mobile_landmark_stunts` 9/9 PASS; Steppe map QA `props=25 large=5 spacing_overlaps=0 float_bad=0 collider_bad=0`. |
| Mobile vehicle profiles | SAM/BMP back away when an armed drone closes under 35% of fire range (APC at 45%); the helicopter orbits with lateral strafes; the truck flees faster (×1.5); the tank holds position while firing; the Shahed steers at the armed drone and accelerates. Damage states: smoke/−28% speed below 60% HP, fire/−55% speed below 30% HP. | `qa_mobile_vehicle_profiles`: 9 PASS on a synthetic scene. |
| Mobile infantry AI | Squad alert ripples one hop through neighbours (duck + 35% scatter), deterministic gait desync, and mobile flank sidesteps while firing so squads spread instead of bunching. | `qa_mobile_infantry_lod` stays green (26 PASS) plus the new squad/flank checks. |
| Route QA | Each frontline map probes a 250–300 m corridor at 3/8/15 m and requires <50% blocked segments, with FPV screenshots of start/mid/finish. | `qa_mobile_map_views` corridor probe, all four maps exit 0. |
| Map variety | Mobile dressing budget +30% and two extra themed anchors per map in MapEnricher, still MultiMesh-batched. | `qa_mobile_map_views` + float scan stay green. |
| Mobile AI collision and escape | Infantry steps use a three-ray fan (chest + shoulders) so soldiers no longer clip thin posts/fences; ground vehicles briefly reverse when a wall bounce fails. | Mobile-gated in `enemy_infantry.gd` / `vehicle.gd`; regression QA stays green. |
| Flight school mobile help | The tutorial help sheet lists touch/ELRS controls (АРМ, РЕСЕТ, ВІДЕО, START, B) instead of keyboard keys on mobile. | Mobile-gated text in `flight_school.gd`. |
| Release version alignment | iOS preset is 1.18.0/18 and CI pins Godot 4.7.2 to match local QA; signing is documented without secrets. | `export_presets.cfg`, `.github/workflows/ios.yml`, `docs/ios/APPSTORE_SIGNING.md`. Real Team ID/certificates remain an owner-provided blocker. |
| Fixed-wing FPV and integrated payload | Mobile presets 13/14/15 show airframe and route the BЧ button to `activate_payload`; Leleka/Furia pusher props animate. | `qa_video_fixes`: all mobile payload, airframe, prop-animation checks PASS. |
| Mobile GLB optimization | Leleka 118→25 mesh objects / 119→26 primitives; Furia 68→24 / 69→25; Chaklun 49→13 / 49→13; Apache 46→26. | `tools/audit_mobile_assets.py`: all four pairs PASS; bounds delta ≤0.000778 m. |
| Vehicle LOD | Full model under 180 m, simple proxy 180–480 m, hidden beyond 480 m. | `qa_mobile_apache`: PASS for mobile mesh selection, proxy, and far hide. |
| Infantry mesh | The actual runtime asset is `soldier_detailed_merged.glb`: one skinned body mesh/primitive. The separate `rifleman_merged.glb` is not used by combat runtime; the old 58× draw-call claim was incorrect. | `qa_mobile_soldier_asset`: PASS, runtime detailed rig, merged body mesh, skeleton. |
| Infantry animations and LOD | Eight procedural actions are present (idle, walk, run, aim, fire/recoil, reload, hit, death; crouch is an extra pose). The walk cycle now rolls the stance foot heel-to-toe, the rifle drifts with an idle sway that dies down while walking/aiming/crouching, and the merged soldier is visibly armed with a 6-part procedural carbine (the merged GLB has no authored rifle mesh). Mobile pose update rate is 30 Hz near, 15 Hz mid, 0 Hz while far/hidden. | `qa_mobile_infantry_lod`: 32 PASS checks, covering all actions, heel/toe roll, weapon sway, the procedural carbine, pose-rate gating, camera-based far cull and near restore. |
| Far infantry impostor | Four transparent views of the runtime soldier are baked into a 2×2 atlas. Mobile LOD uses a camera-facing Sprite3D and selects front/right/back/left frame. | Runtime QA PASS; preview: `docs/ios/v26_mobile_infantry_lod.png`; atlas: `Assets/combat/soldier_impostor_atlas.png`. |
| iOS quit button | Hidden in the mobile menu; swipe-to-close hint shown. | `qa_video_fixes`: PASS. |
| Persistence | Mobile/control settings survive the two-process save/load test. | `qa_persist2_write` exit 0; `qa_persist2_read` PASS. |

## Runtime and source checks

- Godot 4.7.2 editor import completed with exit 0 and no script parse/import errors.
- `git diff --check` reported no whitespace errors at the time of the audit.
- The mobile validation uses `MOBILE_UI=1` to exercise the mobile path.
- Headless `qa_video_fixes` exits 0 and reports PASS. Godot also prints dummy-renderer RID allocation warnings during process teardown; these are headless-test shutdown warnings, not a gameplay assertion failure.

## Corrected claims

- Do **not** claim a measured 58× runtime draw-call reduction from `rifleman_merged.glb`: that asset is not used by the active infantry runtime.
- Do **not** claim measured GPU/CPU percentages or physical-iPhone FPS/thermal performance. Those were not benchmarked.
- The currently active detailed GLB is already a one-primitive skinned mesh; the mobile impostor and procedural animation LOD are now connected to that real runtime rig.

## Remaining device-level validation

Automated mobile-path QA passes, but the owner's physical-iPhone test via AltStore is still the active device validation. Native iOS interruption behavior and on-device frame time/thermal limits must be recorded from that test before making release-performance claims.

## Screenshots

![Mobile detailed soldier and four-view impostor comparison](ios/v26_mobile_infantry_lod.png)

![Four-view impostor source atlas](../Assets/combat/soldier_impostor_atlas.png)

![Mobile map selection with real FPV map cards](ios/v26_mobile_map_cards.png)

### Existing-map iteration

- `Assets/Branding/mobile_map_steppe.png`
- `Assets/Branding/mobile_map_village.png`
- `Assets/Branding/mobile_map_industrial.png`
- `Assets/Branding/mobile_map_wetlands.png`
- `docs/ios/mobile_audit_2026/before/` and `after/` — four before/after map views.
- Detailed map audit and remaining art work: `docs/ios/MOBILE_MAP_AUDIT_WIP.md`.

## Rebuild the impostor atlas

1. Run `tools/create_infantry_billboard.py` with Blender 5.x to render the four transparent views.
2. Run `python tools/assemble_infantry_impostor.py` (Pillow required) to build the atlas.
3. Run a Godot editor import, then `qa_mobile_infantry_lod` with `MOBILE_UI=1`.
