# Mobile "WOW" visual pass + full English localization audit

Date: 2026-11-18. Scope: **mobile / iOS-facing presentation only**; desktop
keeps its existing renderer settings and UI.

## 1. What was wrong

1. **Flat, midday maps.** The mobile renderer always uses the baked
   `sky_static.png` / `sky_mountains.png` panoramas. Both are a clear midday
   sky with a white sun, so the warm per-map sun and golden fog configured in
   `BigLevel.gd:_tune_map_environment()` were visually overridden. Every map
   read as flat daylight with lime grass.
2. **Cinematic grade missing on mobile.** Glow/post effects are disabled on the
   Mobile renderer for performance, and there was no cheap replacement.
3. **Incomplete English localization.** The existing QA scene covered only a
   subset of screens. A full sweep found untranslated Ukrainian strings on
   seven additional screens.

## 2. Visual changes (real assets, no generated art)

- `tools/grade_mobile_sky.py` recolours the **existing** baked panoramas into a
  golden-hour sky (deeper blue zenith, warm amber horizon, soft golden sun).
  Cloud shapes and baked sun azimuth are preserved, so `align_sky_to_sun()`
  stays correct.
  - New assets: `Assets/textures/sky_static_golden.png` (2K mobile),
    `Assets/textures/sky_mountains_golden.png` (4K desktop).
  - `scripts/util/quality_manager.gd` now points both sky constants at the
    graded versions. Original textures remain in the repo as source of truth.
  - Runtime cost: **zero** extra render passes — same single cubemap sample.
- `sceneries/BigLevel.gd:_tune_map_environment()` gained a mobile-only grade:
  slightly higher contrast, warmer bounced ambient/fill light, marginally
  lower exposure. Parameter-only change; no new draw calls or passes.
- `shaders/cinematic_overlay.gdshader` + `scripts/util/cinematic_overlay.gd`
  add a subtle full-screen grade via `hint_screen_texture`: elliptical
  vignette, warm highlights / cool shadows, very faint grain and scanlines.
  - One texture fetch per pixel, no extra render target.
  - Mobile-only (`iOS`, `mobile` feature, or `MOBILE_UI` env); skipped in
    headless QA.
  - Attached behind HUD widgets in `HUD/HUD.gd` (vignette 0.26) and behind the
    menu panels in `GUI/mobile/MobileMenu.gd` (vignette 0.42).
- The four menu map cards are now **fresh real in-game FPV captures** of the
  current build with this grade, not the old flat aerial thumbnails.
  `test/qa_mobile_map_views.gd` now uses a **per-map card camera**: each card
  aims at its own hero landmark (steppe wind turbine, village church,
  industrial flare stack, wetlands lighthouse) from a different side, distance
  and altitude, so the four cards no longer share one near-identical frame.

## 3. English localization audit

### New coverage

`test/qa_english_localization_full.gd` / `.tscn` instantiates **22 GUI screens**
(headless-safe subset), runs `MenuUI.localize_tree()` on each, walks every
Label/Button/RichTextLabel/LineEdit/OptionButton/Window text surface, plus both
localization dictionaries, drone-catalog getters, special-mission names, daily
challenge and report strings. It fails on any Cyrillic glyph while `EN` is
active. This complements the older `qa_english_localization.tscn`, which is
still run and still green.

### Result

| Stage | Screens | Texts scanned | Cyrillic leaks |
|---|---:|---:|---:|
| First full sweep | 22 | 2643 | **20** |
| After fixes | 22 | 2663 | **0** |
| Original QA scene | — | — | **0** |

The 20 leaks were on: `CalibrationScreen` (3), `DroneBuilder` (12),
`GraphicsScreen` (2), `OptionsMenu` (2), `OtherSettingsScreen` (1),
`PauseMenu` (1), plus dynamic source-label handling.

### Fixes

- Added the exact UA → EN strings to `GUI/ui/MenuUI.gd:EN_TEXT` (calibration
  wizard headings, drone-builder stats/actions, FPV channel label and Digital
  HD option, help/mobile-interface buttons, settings subtitle, touch-sticks
  pause button).
- `GUI/CalibrationScreen.gd:_update_source_button()` now uses the existing
  `_ui_text("ДЖЕРЕЛО: %s", "SOURCE: %s")` helper, so every input source name
  (TOUCH / ELRS / radio) is localized, not just one hard-coded variant.

### Known QA noise (pre-existing, not introduced here)

Instantiating `HUDConfig.tscn` / `HelpPage.tscn` in isolation produces script
errors (`show_component()` signal/bool mismatch, `append_bbcode()` removed in
Godot 4). These scenes are embedded in real flows; the full sweep still
completes and reports the text audit correctly. `HelpPage.gd` is legacy and is
not used by the mobile help screen.

## 4. Verification commands

```powershell
# Import / parse check
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . --editor --quit

# Localization
$env:DRONE_NO_RECORD="1"
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . res://test/qa_english_localization.tscn
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . res://test/qa_english_localization_full.tscn
# Expect: [ENGLISH_LOCALIZATION] failures=0 / [EN_FULL] ... failures=0
```

Screenshots were captured from the current working tree with the project's own
QA harnesses (`test/qa_ui_shot.tscn`, `test/qa_mobile_map_views.tscn`) in
`MOBILE_UI=1`, `DRONE_LANG=en` mode at 2340x1080 (menu) and 1280x720 (maps).

## 5. Screenshots

_See the image files next to this report in `docs/wow_v2/`._

- `01_main_menu_en.jpg` — fresh English main menu with cinematic overlay.
- `02_play_maps_en.jpg` — fresh English sortie select with real FPV map cards.
- `03_map_steppe_fpv.jpg`, `04_map_village_fpv.jpg`, `05_map_industrial_fpv.jpg`,
  `06_map_wetlands_fpv.jpg` — real current-build FPV views, golden-hour grade.
- `07_localization_builder_en.jpg`, `08_localization_graphics_en.jpg`,
  `09_localization_calibration_en.jpg`, `10_localization_options_en.jpg`,
  `11_localization_pause_en.jpg`, `12_localization_settings_en.jpg` — screens
  that previously leaked Ukrainian, now fully English.

## 6. Build / CI note

`.github/workflows/ios.yml` builds the unsigned/signed IPA on push to `main`
using Godot **4.7.2-stable** and publishes it as a GitHub Release
(`ios-build-<run>`). Local verification used the bundled Godot **4.6.1-stable**
(project feature target is 4.6). No workflow file was changed. Pushing the
approved commit is what triggers the final build.
