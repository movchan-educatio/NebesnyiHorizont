# Final mobile implementation report

**Scope:** iOS/mobile only. No desktop feature work is included.

## Delivered and verified

| Requirement | Result | Evidence |
|---|---|---|
| Touch/ELRS deadzone and smoothing | Implemented through the shared `Controls.apply_stick_filter` path; touch and ELRS yaw/roll/pitch use it. CRSF native throttle 172–1811 is normalized. | `qa_video_fixes` mobile run: PASS, including new smoothing-slider check. |
| iOS audio resume | App pause/resume notifications restore bus mute state and reapply volume settings; intentional mute is preserved. | `qa_video_fixes`: resume and intentional-mute checks PASS (notification simulation, not a physical call/Siri test). |
| Fixed-wing FPV and integrated payload | Mobile presets 13/14/15 show airframe and route the BЧ button to `activate_payload`; Leleka/Furia pusher props animate. | `qa_video_fixes`: all mobile payload, airframe, prop-animation checks PASS. |
| Mobile GLB optimization | Leleka 118→25 mesh objects / 119→26 primitives; Furia 68→24 / 69→25; Chaklun 49→13 / 49→13; Apache 46→26. | `tools/audit_mobile_assets.py`: all four pairs PASS; bounds delta ≤0.000778 m. |
| Vehicle LOD | Full model under 180 m, simple proxy 180–480 m, hidden beyond 480 m. | `qa_mobile_apache`: PASS for mobile mesh selection, proxy, and far hide. |
| Infantry mesh | The actual runtime asset is `soldier_detailed_merged.glb`: one skinned body mesh/primitive. The separate `rifleman_merged.glb` is not used by combat runtime; the old 58× draw-call claim was incorrect. | `qa_mobile_soldier_asset`: PASS, runtime detailed rig, merged body mesh, skeleton. |
| Infantry animations and LOD | Eight procedural actions are present (idle, walk, run, aim, fire/recoil, reload, hit, death; crouch is an extra pose). Mobile pose update rate is 30 Hz near, 15 Hz mid, 0 Hz while far/hidden. These are procedural skeletal actions, not separate AnimationPlayer clips. | `qa_mobile_infantry_lod`: 19 PASS checks, covering all actions, 30/15/0 Hz, far cull and near restore. |
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

Automated mobile-path QA passes, but this session did not run on a physical iPhone/iPad. Native iOS interruption behavior and on-device frame time/thermal limits still need device confirmation before making release-performance claims.

## Screenshots

![Mobile detailed soldier and four-view impostor comparison](ios/v26_mobile_infantry_lod.png)

![Four-view impostor source atlas](../Assets/combat/soldier_impostor_atlas.png)
