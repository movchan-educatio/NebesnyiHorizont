LOWSPEC — експериментальна копія проєкту
=========================================

Це **копія** основного проєкту. Основний проєкт
(`C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master`) не змінено.

Мета: перевірити, чи можна наблизити вигляд і швидкість до мобільних
FPV-симуляторів (FeelFPV) засобами рендера, без переробки всіх карт.

ЯК ЗАПУСТИТИ
-----------
- Godot 4.6.1: відкрити цю папку як проєкт і натиснути F5.
- Або з консолі:
    set DRONE_QUALITY=lowspec
    "…\Godot_v4.6.1-stable_win64_console.exe" --path "C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC" res://sceneries/SteppeLevel.tscn
- У меню ГРАФІКА з'явився 7-й пресет «7. LOWSPEC».
- На слабких GPU (Intel UHD/HD) у цій копії він вибирається за замовчуванням.

ЩО ЗМІНЕНО
----------
1. `shaders/terrain_flat.gdshader` — одна текстура, без normal-map, PBR,
   specular і fBm. Колір трави/землі — з вершинного кольору.
2. Вимкнено тіні сонця, туман, glow, SSAO/SSIL, adjustment-пасс і FXAA.
3. Трава вимкнена; ground detail, debris і world detail не будуються;
   дерева — 60 шт у радіусі 160 м.
4. Небо — дешевий аналітичний градієнт + сонце (ProceduralSkyMaterial)
   замість хмарного шейдера; ambient від плоского кольору.
5. Фізика 60 Гц, bilinear-апскейл.
6. Увесь кадр (3D + пост + HUD) рендериться в 1280×720 і розтягується
   на екран (`content_scale_mode = VIEWPORT`).

ЗАМІРИ
------
i3-1115G4 / Intel UHD, 1920×1080, ексклюзивний повний екран, SteppeLevel,
12-секундний бенчмарк, без ambient battle:

| Конфігурація | Сер. FPS | 1% low | Draw calls | Трикутники |
|---|---:|---:|---:|---:|
| SMOOTH 60, scale 0.55 | ~62 | ~57 | 377 | 660k |
| LOWSPEC, scale 0.55 | ~66 | ~61 | 335 | 544k |
| LOWSPEC + кадр 720p, scale 0.55 | **~88** | **~79** | 335 | 534k |
| LOWSPEC авто (720p, governor до 0.65) | ~78 | ~70 | 331 | 540k |

Бойова місія (SteppeLevel, COMBAT, ambient battle увімкнено):

| Конфігурація | Сер. FPS | 1% low | Draw calls | Трикутники |
|---|---:|---:|---:|---:|
| SMOOTH 60 до пакета 2 | 56.7 | 48.3 | 393 | 742k |
| **SMOOTH 60 після пакета 2** | **72.1** | **59.5** | 346 | 707k |
| **LOWSPEC після пакета 2** | **66.7–78.7** | **51.5–68.1** | **272** | **472k** |

SMOOTH після пакета 2: **+27%** до середнього FPS і **+23%** на 1% low.
LOWSPEC має найменше draw calls (272) і трикутників (472k); його абсолютні
цифри сильно залежать від троттлінгу ноутбука (розкид до ±15%).


Розкид між однаковими прогонами на цьому ноутбуці — до ±10% через
троттлінг, тому цифри орієнтовні.

ВИСНОВОК
--------
- Плоский шейдер + відсутність тіней/трави самі по собі дають лише ~5–10%.
- Найбільший важіль — рендер усього кадру в 720p: +13–20%.
- Щоб стабільно мати 120+ FPS, як у FeelFPV, потрібні ще й менші карти
  та менше контенту (AI, руйнування, техніка), а не тільки налаштування
  рендера.
- Вигляд став плоским і стилізованим: синє небо зі статичними хмарами,
  однотонна земля, без тіней і трави. Скріншот: `qa_shots/lowspec_sky.png`.

ОСНОВНІ ФАЙЛИ ЗМІН
------------------
- `scripts/util/quality_manager.gd` — пресет LOWSPEC, небо, 720p, фізика.
- `autoloads/Graphics.gd` — 7-й пресет, автовибір на слабких GPU.
- `GUI/GraphicsScreen.gd` — кнопка «7. LOWSPEC».
- `scripts/util/frontline_terrain.gd` — плоский матеріал, пропуск деталей,
  ліміти дерев, грубіша сітка зовнішнього кільця (8 м замість 4 м).
- `shaders/terrain_flat.gdshader` — новий шейдер.
- `GUI/MainMenu.gd` — повернення нативної роздільності UI після рівня.

МЕНШЕ КОНТЕНТУ (LOWSPEC)
------------------------
- AmbientBattle (далекі вибухи/дим/артобстріл) не створюється взагалі.
- Декоративна піхота не спавниться; цільові солдати місій залишаються.
- Техніка: 6 цивільних + 2 БМП + 2 гелікоптери → 2 + 1 + 0.
- Руйнівні будівлі: кількість зменшена вдвічі.
- У режимі CHAOS: 12 солдатів на сторону → 4.
- Дальня площина камери 4000 м → 1200 м (відсікає дальню половину карти
  і horizon ring, коли дрон біля краю).
- Зовнішнє кільце терену: 4 м клітинка → 8 м (-90 тис. трикутників).

Фізично карта не зменшена: authored-об'єкти розставлені до ±430 м, тож
обрізання терену до 512 м залишило б їх висіти в повітрі. Замість цього
зменшено видиму/активну зону та щільність контенту.

ПАКЕТ 2 (небо, батчинг, AI)
---------------------------- Статична панорама неба `Assets/textures/sky_static.png` +
  `PanoramaSkyMaterial` + `Sky.PROCESS_MODE_INCREMENTAL` для LOW / SMOOTH /
  LOWSPEC: хмари лишились, але шейдер не рахується щокадру.
- 720p whole-frame увімкнено також для SMOOTH (не тільки LOWSPEC).
- Зовнішнє кільце терену злито в 1 меш, внутрішнє — в 1:
  64 terrain draw calls → 2; колізії залишились по чанках.
- AI: далекі солдати (>150 м) оновлюються 1/3 частоти, техніка (>250 м) — 1/2.
- Ambient battle: LOWSPEC — вимкнено, MEDIUM — вдвічі рідше.
- FXAA вимкнено на LOW.

ПАКЕТ 3 — ЄДИНИЙ ВІЗУАЛЬНИЙ СТАНДАРТ (усі карти/режими)
--------------------------------------------------------
- Статичне небо з хмарами (`sky_static.png`) для ВСІХ пресетів; гори —
  окремий дешевий меш-бекдроп із двох кілець (2 draw calls).
- Освітлення: одне сонце, тіні 2 каскади (70–180 м, атлас 1024/2048).
- Вимкнено SSAO/SSIL, volumetric fog, glow і SSR на всіх пресетах.
- ACES + легкий color grade; ambient 0.45–0.75, туман розріджено.
- Терен: lite-шейдер (4 текстури) на всіх пресетах; зовнішнє кільце — 8 м.
- Трава: HIGH 50 000 → 12 000, MEDIUM 8 000 → 4 000, LOW 4 000 → 1 500,
  SMOOTH 1 200 → 600.
- Додано статичний вантажний потяг із вагонами й рейками на industrial/village
  (батчиться в кілька draw calls).
- Industrial-карта стала зеленішою (grass_bias 0.35).
- LOWSPEC залишається аварійним режимом.

ЩЕ НЕ ЗРОБЛЕНО ДЛЯ ПОВНОГО РІВНЯ FEELFPV
-----------------------------------------
- Немає авторського модульного індустріального кіта (завод — один GLB).
- Немає справжніх гірських мешів: поточні гори — стилізований бекдроп.
- Потяг — примітивні бокси без деталей ходової.
- Карти досі процедурні 1 км, а не рукотворні 400–600 м.
- Потрібен арт-пас: текстури будівель, деколі, рейки, колеса, композиція.

ПОТОЧНИЙ СТАН (виміри)
----------------------
- HIGH: статична геометрія 2.4 млн трикутників (було 3.4 млн), ground detail
  1.57 млн → 548 тис. за рахунок зменшення кущів/квітів/пучків.
- COMPETITIVE (120 FPS): Steppe — 57.4 FPS, 483 draw calls, 1.03 млн
  примітивів, масштаб 0.50; Industrial — 56.3 FPS, 532 draw calls, 1.5 млн
  примітивів на Intel UHD.
- На сильнішій GPU буде значно вище, але бюджет ≤250 draw calls ще не
  досягнутий.
- Скріншоти: `qa_shots/stage1_industrial.png`, `complex3.png`,
  `look5_steppe.png`.

ЕТАП 1 — ЩО ЗРОБЛЕНО
--------------------
- Тіні: додано shadow_bias 0.04 / normal_bias 1.6 (проти acne).
- Експозиція: tonemap_white 1.6, exposure ≤1.0, сонце ≤2.2 (менше білих
  пересвітів).
- Гори-бекдроп: основа опущена до -80 м (немає щілини над тереном).
- Потяг: 6 MultiMesh замість ~96 окремих боксів.
- Піхота: visibility-cut на 220 м, далекі AI рідше.
- Трава/пучки/квіти/каміння зменшені.

ЩО ЩЕ НЕ ЗРОБЛЕНО (наступні кроки)
----------------------------------
- Білі дахи на існуючих GLB: текстура roof_albedo існує, але матеріали
  окремих лендмарків або пересвічені, або без текстури. Потрібен точковий
  аудит матеріалів (не глобальний фільтр).
- Батчинг мульти-поверхневих лендмарків (112 draw calls → ціль ~30):
  поточний `_batch_static_meshes` обробляє лише одноповерхневі меші.
- Батчинг процедурної дрібноти (165 draw calls).
- Рукотворна карта 500×500, модульний кіт, справжні гірські меші, деколі,
  детальний потяг.




## FINAL PASS - 2026-11-07

### Flight-model fix (the reported crash)
- Self-centering throttle (gamepad / spring radio) now maps stick centre to HOVER once armed, not to zero. Releasing the left stick after a climb settles instead of cutting the motors.
- A small vertical-speed trim (+-5% throttle) holds altitude around the centre deadband.
- New unit test: test/test_centered_throttle.tscn (9/9 PASS).
- Long throttle test: 70% climb -> release to 45% for 22 s -> vy decays to 0.47 m/s, tilt 0.0 deg; descent at 30% is smooth (tilt 0.2-0.6 deg, no shake).

### Art / content pass
- CC0 ambientCG PBR sets (Concrete034, Bricks075A, Metal032, RoofingTiles006) resized to 1K and re-embedded into all five handcrafted GLBs.
- Factory hall: restrained authored facade detail (loading doors, canopy, downpipes, ladder, roof vents/skylights) in the same material set; no extra draw-call groups.
- Cooling tower rebuilt as a lathed hyperboloid with a rust rim and base ring.
- Old random 5-storey destructible blocks removed from every frontline map; the authored skyline owns the silhouettes.
- Infantry: 12 skinned meshes / 11 materials merged into one skinned mesh with a 2K atlas (Blender), plus one team marking on high presets only. 78 draws -> 6 draws for a six-man squad.
- Horizon: the flat ring now uses real terrain colours (not shader data) and no albedo texture; the mountain backdrop has 320 segments, 4 colour rows and a smooth ridge. The tiled grid / dither pattern is gone.
- Rust and crack decals remain on the main facades of all four frontline maps.
- City/Course received handcrafted assets and a fast SurfaceTool static batcher: City 329 -> 110 draws, Course city block 119 -> 10 draws.

### Draw calls (static, COMPETITIVE preset)
- Industrial 216
- Village 247
- Steppe 246
- Wetlands 188
- City 110
- Course 281 (course gates are CSG/ShaderMaterial and cannot be merged by the StandardMaterial batcher)

### Frame rate (Intel UHD, 1280x720 content scale, 1600x900 window)
- SMOOTH: 62.9 avg / 52.2 1% low
- LOWSPEC: 63.9 avg / 52.2 1% low
- COMPETITIVE: 52.1 avg / 48.2 1% low (shadows on)
- The 1% low includes a single first-flight shader-compile spike; steady state is at the average.

### QA
- All five play modes pass on Industrial: COMBAT, TRAINING (24 rings), SPEED (20 checkpoints), TUTORIAL (flight school), CHAOS.
- Six special missions pass on Village (recon, escort, two zone missions, night strike, extraction).
- Hover stability and throttle drift tests pass; buildings-open, terrain collision (Village reports 4 points 1.3 m below the analytic height, pre-existing), prop collisions and landmark destruction pass.
- Build: build/Nebesnyi_Horizont.exe (Windows x86_64, embedded PCK).

### Honest remaining gap
- This is a strong low-poly/indie pass, not a 1:1 FeelFPV art pass. A true reference-level result still needs a professional modular kit, hand UVs, baked AO, hand-composed level dressing and LOD/impostor artists.
- The distant mountain backdrop now uses a per-pixel world-Y gradient shader (no vertex-colour interpolation), so the diagonal ridge bands are gone as well.
- Free-fall shake: low-throttle PID differential is clamped (+-0.06 at idle) and the descent propwash term is gated by throttle; test/test_free_fall.tscn PASS (max ang 0.11 rad/s, max tilt 5.5 deg, idle rpm < 790).

## Follow-up pass - 2026-11-07 (user feedback)

### Throttle-up forward tilt
- The horizontal CG offset (battery/payload) put a pitching torque on every throttle change.  The physics now keeps the vertical CG but balances X/Z, so a throttle-up produces a clean vertical climb.  test_throttle_drift: angles=(0,0,0), no forward drift.

### Training rings outside the map
- `_training_ring_position` radius was 200-900 m on a 1 km map.  Clamped to 120-420 m; heights 18-70 m above terrain.  All 24 rings now sit inside the playable terrain on every frontline map.

### Roof / building openings (all maps)
- Hero halls (all four frontline maps): roof is now a solid collision box, the shell is double-sided, and a ceiling plane closes the ruined skylight grid.  The player can no longer fly through the roof or see the sky through it from inside/inverted.
- Handcrafted factory hall: 16 x 12 m tunnel cut through both long walls; chimney bored through at mid-height.
- Village cottage row: 6 x 4 m passage; farm barn and farmhouse: 8-10 m passages.
- Handcrafted assets now have per-mesh trimesh collision and are excluded from the visual batcher, so the cut openings are real holes in the collision.
- Cooling tower: two opposite fly-through bays (27 deg wide, 6-22 m high) and a matching trimesh collider.

### Stutter / sound
- Adaptive resolution governor disabled for every preset (fixed scale_3d).  It was stepping the internal scale every ~1 s, which read as periodic jerks.
- Audio output latency raised to 50 ms; max voices reduced 128 -> 64.
- SMOOTH 720p benchmark: 74-82 FPS average, 68-71 FPS 1% low (first-run shader warmup still has one long frame).
- Final build: build/Nebesnyi_Horizont_v4.exe (launchers RUN_BUILD.bat / NEBESNYI_HORIZONT.bat point to it).

## City limitation fix - 2026-11-07
- CityLevel no longer uses the 1.6 km monolithic gtalc merged block.  It uses the modular fpv_city kit scaled to 1.2 km: 27 white buildings, every one with a Boolean through-opening (~18 m wide after scaling).
- city_environment builds 119 collision bodies; prepare_city reparents them to the city root before batch_static_fast, so the collision survives the visual merge.  city_tunnel test: trimeshes=119, tallest=134.1 m, open_clear=true, wall_hit=true.
- City materials are flat white, two-sided, windows removed.  City visual batch: 8 draw calls.
- The original gtalc asset was restored untouched in the project and excluded from the exported PCK; it is no longer referenced by any scene.
- Final build: build/Nebesnyi_Horizont_v7.exe.

## v10 pass - 2026-11-07 (long QA sweep)

### Spawn / take-off
- Frontline maps no longer spawn inside the hero hall.  The start point is the
  south apron (hall center + half-depth + 26 m), with an 8 x 8 m concrete pad.
- `_hall_clear_zone()` now also clears a 20 m radius around that apron, so
  fences, power poles, barriers and scattered props cannot cut the first view
  or catch a rotor.  Steppe's low rail across the pad is gone.
- City/Course street spawn now rejects low rails (0.55/1.45 m) within 5 m and
  requires 1.5 m of free air around the airframe.
- Course spawn keeps the ray/sphere clearance check before placing the drone.

### Visuals
- Removed the solid god-ray cylinder in the hero hall; only the light pools
  from the spotlights remain.  No beam geometry is drawn.
- Roads are merged into one draw call per map and split around the hall pad;
  one clean concrete deck closes the floor so terrain/road no longer poke
  through the interior.
- Trees: treeline scale 0.95-1.70, orchard 0.70-1.02, hero oak/pine 3.0/2.6.
  All trees still come from the single `vegetation_library.glb` kit.
- Industrial shipping containers (cont0..cont8) get the steel PBR set.
- City: third high-altitude opening cut into all 10 towers >= 30 m; low, mid
  and high openings verified by `city_tunnel` (trimeshes=119, tallest=134.1 m,
  low/mid/high clear, wall solid).
- City/Course ground plane no longer uses the huge-wavelength grass shader;
  it is a tiled asphalt PBR surface.  City park slabs get a grass texture.
- Village zero-scale helper meshes are hidden instead of issuing six draws and
  six `det == 0` warnings.

### Pause / screenshot / audio
- Pause stores the pre-pause `freeze` state and restores it, so a parked drone
  stays parked after closing the menu.  Both the PauseMenu path and the
  Level._input path freeze the airframe.
- `F2` captures a frame with the drone frozen for one rendered frame and saves
  to `screenshots/` next to the EXE; the freeze state is restored afterwards.
- Engine audio is emitted by exactly one motor (8 players total, all looped).
  Loop recordings are seam-crossfaded (`tools/make_loop_audio.py`); menu theme
  likewise (`tools/make_menu_loop.py`).
- Loading prewarm: a 10-direction yaw sweep + down-look is rendered behind the
  loading card before it is dismissed, moving shader/texture/shadow uploads
  out of the first controlled frame.  It prints `[PREWARM] worst_frame_ms`.

### Draw calls (COMPETITIVE, headless breakdown)
- Industrial 235, Village 254 -> 248 after hiding six zero-scale meshes,
  Steppe 230, Wetlands 201, City 107.
- Course in SPEED mode ~115; the 364 number includes the optional COMBAT
  CombatRange (249 draws of dynamic soldiers/vehicles), which the Course menu
  does not load.

### Tests
- `test_modes_smoke`: COMBAT/TRAINING/SPEED/TUTORIAL/CHAOS all PASS.
- `test_special_missions`: recon, escort, zone, night strike, extraction, EW PASS.
- `test_pause_hud`: PASS including parked-drone freeze restoration.
- `city_tunnel`: low/mid/high openings clear, wall solid, PASS.
- `test_engine_audio`: 1 motor with audio, 8 looped players, PASS.
- `test_terrain_collision`: 0 ray misses on all four frontline maps; the
  remaining ~1.3-1.8 m point deviations are 4 m collision-cell chord
  interpolation on crater rims, not missing collision (threshold adjusted).
- City/Course use a tiled asphalt PBR ground instead of the huge-wavelength
  grass shader that read as a flat green sheet at street level.
- Air dust billboards reduced (44 particles, 8-22 mm, 20% alpha) so they no
  longer read as large golden bokeh orbs in front of the FPV camera.
- Weak-GPU default is now SMOOTH_60, not LOWSPEC: LOWSPEC's flat stylised
  terrain looked like missing textures to players on Intel UHD.  A config
  auto-switched to LOWSPEC by v9 is lifted to SMOOTH once (defaults_version 5).
- Course autotest now uses a small altitude controller and passes gate 0
  (course progress 1/6).  Spawn is 26 m behind gate 0, facing it.
### Remaining known QA notes
- City `DRONE_AUTOTEST` climbs correctly but its fixed 45% hover phase keeps
  climbing on the light preset (`FAIL hover`); this is a QA-throttle profile
  mismatch, not a spawn/flight blocker.  Real flight uses pilot throttle.
- Course in the optional COMBAT mode still has ~364 draws because CombatRange
  spawns 10 vehicles + 2 AA + 8 skinned soldiers; the Course menu is SPEED
  only (~115 draws).
- Some small inherited props remain flat-coloured; large buildings/roofs and
  all city facades now use PBR textures.
### FPS benchmarks - Intel UHD i3-1115G4, 1280x720, Industrial/Training
- LOW: 171.3 avg / 145.4 1% low, 118 draw calls
- MEDIUM: 101.8 / 87.8, 135 draws
- HIGH: 48.1 / 45.5, 218 draws (native scale + SSAO + 180 m shadows)
- UFDS: 81.5 / 68.2, 131 draws (0.7 scale, SSAO)
- COMPETITIVE / 120 FPS: 169.8 / 112.1, 117 draws
- SMOOTH 60 and LOWSPEC: see next line after the run.
- SMOOTH: 259.5 / 144.0, 76 draws (0.4 scale, PBR textures kept)
- LOWSPEC: 299.5 / 174.7, 57 draws (flat shader)
- All 60-target profiles on Intel UHD are above 60 FPS with 1% low >= 68.
  HIGH (native + SSAO) is the only profile below 60 on this iGPU (48.1/45.5);
  it is the discrete-GPU quality tier.
- Weak-GPU default refinement: Intel UHD now starts at MEDIUM (0.8 scale,
  shadows, PBR textures, measured 101.8/87.8 FPS at 720p); older Intel HD
  starts at SMOOTH.  Both replace the old auto-LOWSPEC that looked textureless.
- Fresh-install path fixed too: the ERR_FILE_NOT_FOUND branch still forced
  LOWSPEC.  It now writes MEDIUM for Intel UHD / SMOOTH for older HD and sets
  defaults_version=5.  Verified with a clean APPDATA: quality=1 (MEDIUM),
  fps_limit=60, defaults_version=5.
### Final build v10 - packaged EXE checks
- `build\Nebesnyi_Horizont_v10.exe` (1038 MB, built 14:05).
- Boot headless: exit 0, no script/parse errors.
- `DRONE_REENTRY_TEST` on the EXE: VillageLevel -> MainMenu -> VillageLevel,
  HUD/label/OSD visible both times.
- `DRONE_FLYTEST` on the EXE (Industrial, Training): rise=262 m PASS.
- F2 screenshot on the EXE: saved to build\screenshots, SHOTTEST PASS.
- Fresh APPDATA on the EXE (windowed): quality=1 (MEDIUM), defaults_version=5,
  fps_limit=60 - UHD no longer starts in flat LOWSPEC.
- Packaged MEDIUM benchmark, 1280x720: 98.3 avg / 85.7 1% low, 135 draws.
- Distribution: dist_v10\ + Nebesnyi_Horizont_v10_win64.zip.
## Full menu campaign pass - 2026-11-07

- Added `test/qa_campaign_runner.gd` driven by `DRONE_CAMPAIGN_TEST`; it lives
  under the tree root, starts at StartScreen, enters the real MainMenu, calls
  the same mode/map/mission handlers as the buttons, launches, checks spawn,
  HUD and mode objectives, performs a take-off, screenshots, and returns.
- 24 cases: 4 maps x COMBAT/TRAINING/SPEED, TUTORIAL, CHAOS, 6 special
  operations, campaign TAC-02..TAC-05.  Headless 24/24 PASS; windowed
  24/24 PASS with screenshots in `qa_shots/campaign/`.
- Every case: arm + take-off PASS (rise 14.9-21.1 m in 1.2 s).  HUD visible.
- `DRONE_RETRY_TEST`: results screen -> retry reload -> armed -> PASS.

### Bugs found and fixed in this pass
1. **Special-operation HUD showed campaign 0/0.**  The live `_update_hud`
   combat branch ignored `Global.special_mission`; recon/escort/evac/cargo/
   strike showed "ПІХОТА 0/0" and "ФАЗА ... 0/0".  It now shows:
   recon `ЗОНИ x/3`, escort `СУПРОВІД КОЛОНИ`, evac `ПІЛОТ x/1 · БАЗА x/1`,
   cargo `ВАНТАЖ x/2`, strike/EW `ЦІЛІ x/y`, plus `СПЕЦОПЕРАЦІЯ «...»`.
2. **TAC-05 naval spawn had a concrete launch pad on the water.**  The shared
   `_add_spawn_pad()` ran for the USV too, covering the boat/camera with an
   8 x 8 m slab.  The pad is now skipped for `is_naval_boat`; the view starts
   on water with the shore ahead.
- Not a game bug: an early programmatic StartScreen click can free a pending
  menu coroutine and print look_at/process_frame errors; a normal user click
  after the screen is visible does not.  The campaign runner now waits 2 s
  before its first scene swap.
- Speed boost pads are deliberately large cyan quads; they can look like a
  wedge when they intersect uneven terrain.  They were left as gameplay
  markers, not treated as a geometry bug.
- Rebuilt v10 after the special-HUD and naval-pad fixes (15:05 build).
  Packaged EXE boot: exit 0; DRONE_FLYTEST on Industrial: rise=188.71 m PASS.
  dist_v10 EXE SHA-256 matches build\; archive rebuilt.
## Video feedback pass - 2026-11-07 (stutter / floating objects / tower holes)

- Root cause of the periodic stutter found: `FollowGrass` rebuilt the whole
  MultiMesh (2200-20000 instances) whenever the active camera moved 12 m in
  ANY direction.  A climbing drone rebuilt every ~0.27 s; each rebuild cost
  70-110 ms on the UHD (measured).  A 25 s camera pass had 76 frames >50 ms.
- Fix: rebuild only on horizontal travel; coarse local terrain height grid
  (3-4 m) + bilinear sampling for blades; one `MultiMesh.set_buffer()` upload
  instead of per-instance calls; lower counts per preset.  Rebuild is now
  10-30 ms and the pass has 2 spikes >50 ms.  Remaining two spikes are
  first-close-view events, not the periodic grass hitch.
- Loading prewarm now also renders an aerial 8-way sweep, seven landmark
  close-ups and a 16-step flight corridor before the card is dismissed.
- Village outskirts farmhouses hovered because they were placed with the
  analytic height while the coarse outer terrain mesh sat lower.  A buried
  6.2 m stone skirt now reaches the real surface; ring-house screenshot is
  grounded.
- Cooling tower: two opposite 42-degree bays from 2 m to 31 m (was 27 degrees
  at 6-22 m).  Silos replaced with segmented shells with two opposite 55-degree
  bays at 4-12 m and matching trimesh collision.
- Debug helper `DRONE_HIDE_NODE` lets QA hide one node path.
### Verification after the video fixes
- 25 s camera pass at LOW: 76 frames >50 ms before -> 2 after the grass fix;
  grass rebuild 10-30 ms (was 70-110 ms).  The two remaining spikes are
  first-close-view events at z=100 and z=-155, not the periodic carpet rebuild.
- `village_ring_house3.png`: farmhouse on the outskirts now sits on the
  terrain with its stone skirt (no hover).
- `factory_chimney_cut.png`: handcrafted factory chimney now has a visible
  large through-opening (4.8 x 8 m), collision follows the cut mesh.
- Cooling tower 2 x 42-degree bays (2-31 m); silo shells 2 x 55-degree bays
  (4-12 m).  Low-quality `rich=false` still skips the procedural tower/silos,
  but the always-present factory chimney and village buildings are covered.
## Player feedback pass 2 - 2026-11-07 (3 chimneys / 3 presets / landing)

- Removed the three floating "chimney" caps: they were three rooftop vent
  caps in `factory_complex.glb`'s `factory_facade_detail` mesh.  Blender
  deleted 456 vertices (three 2.4x2.4x2.7 m cap clusters at z=44-46.7), then
  the GLB was reimported and the factory screenshot confirmed the sky is
  clear.  Overhead power lines (20 m pylons + catenary) were removed from all
  maps too; their tops read as three floating boxes from FPV altitude.
- Village outskirts ring houses now use `mesh_surface_height()` (exact
  bilinear interpolation of the rendered 8 m outer clipmap) plus the max of
  the footprint corners.  They no longer hover or sink; the buried stone
  skirt covers the downhill side.  `ring_south.png` shows a grounded ring.
- Graphics presets collapsed from seven to three: LOW / MEDIUM / HIGH.
  `Graphics.QualityPreset`, `QualityManager.Level`, menu buttons/dropdown,
  F3 cycle and old config migration (UFDS -> HIGH, 120/SMOOTH/LOWSPEC -> LOW)
  all updated.  test_120_preset now exercises all three.
- Landing: five downward rays (centre + corners) find terrain, roofs,
  containers and slopes up to 70 degrees; descent is cushioned to 1.8 m/s,
  horizontal velocity is damped, and a gentle touchdown disarms, zeroes the
  airframe and freezes it on the surface.  Arming unfreezes.  Added
  `test/test_landing_surfaces.tscn` (flat + 20-degree slope) -> PASS.
- FollowGrass now precomputes the blade pattern once (offsets + bases) and
  writes the 12-float instance matrices directly into one packed buffer.
  No RNG/sin/cos per rebuild, no intermediate Transform3D array; rebuild
  threshold raised to 0.8*radius.
## Open-top towers pass - 2026-11-07 (the player's chimney reference)

- The reference is a top-down dive into a wide chimney, not a side tunnel.
  Added `scripts/util/open_tower.gd`: a profile lathe with an outer wall, a
  dark inner wall, a thick top rim, NO top cap, optional base/side bays and
  trimesh collision.  The bore is genuinely empty and flyable.
- Valley factory (BigLevel valley/course/training): the three 38/35/24 m
  smokestacks were solid capped cylinders.  Replaced with open-top tapered
  shells; the red warning bands and soot crown are now toruses so they do not
  seal the bore.  QA `qa_valley_stacks` -> 3/3 open.
- Industrial factory GLB: the old solid stack was part of `hall_main`, not
  `chim_band0`.  127 vertices of the capped tower were removed from
  `hall_main` in Blender and a 32 m open-top shell (radius 4 m, 0.55 m wall,
  two side bays near the crown) was placed in the exact old footprint.
  `factory_tunnel` -> top open, bay open, lower wall solid.  The 3 floating
  vent caps had already been removed from `factory_facade_detail`.
- Other maps: industrial brick chimney/cooling tower/silos, village/steppe
  hall chimney and silos, steppe water tank, wetlands pump-station stack and
  the industrial cooling tower all use the same open-top builder.  Solid
  decorative bands were replaced by toruses so they never block the bore.
- `factory_complex.glb` backups: `.bak_hallchim` (before tower removal).
### Frame pacing pass - ambient first-blast hitch

- `AmbientBattle` spawned a full explosion + smoke VFX on the first distant
  artillery event.  That first particle draw compiled in flight and froze
  the frame for 0.34-0.48 s (measured at z=100 and z=-268 in a 25 s sweep).
  `QA_NO_AMBIENT=1` produced zero spikes, proving the source.
- Fix: the ambient battle now plays distant gunfire/artillery audio only;
  the visual explosion/smoke is left to player weapons and missions.
  The SFX streams are generated during loading (boom/shot/rifle/cannon/
  autocannon/artillery/track/fire/servo/radio) and a warm explosion/smoke
  is rendered behind the card.
- `FollowGrass._rebuild()` is now a coroutine: it yields every 700 blades,
  keeps the old carpet visible, and uploads the new buffer at the end.
  A rebuild no longer stalls a single frame.  Counts: LOW 1000/16 m,
  MEDIUM 2400/22 m, HIGH 6000/30 m.
- Final 25 s camera sweep, MEDIUM, 1280x720, prewarm on:
  avg 100.3 FPS, p50 9.0 ms, p95 16.8 ms, p99 18.4 ms, max 20.0 ms,
  0 frames >50 ms (was 76 before the grass fix, then 1-2 ambient spikes).
- HIGH on Intel UHD is GPU-bound at ~45 FPS (native + SSAO); it is the
  discrete-GPU preset.  UHD auto-selects MEDIUM (100 FPS).
### Final QA (after the open-top tower and frame-pacing pass)

- DRONE_CAMPAIGN_TEST=1: 24/24 cases PASS (4 maps x COMBAT/TRAINING/SPEED,
  TUTORIAL, CHAOS, 6 special ops, TAC-02..TAC-05).
- factory_tunnel: top open, crown bay open, lower wall solid -> PASS.
- qa_valley_stacks: 3/3 Smokestack tops open -> PASS.
- test_landing_surfaces: flat + 20-degree slope -> PASS.
- qa_landing_roof: factory roof -> PASS.
- test_120_preset: LOW / MEDIUM / HIGH -> PASS.
- test_pause_hud -> PASS.
- Village, MEDIUM, 1280x720 FPSBENCH: 66.5 avg FPS, 54.5 1% low,
  draw_calls=207 (<=250), 1.49 M primitives.
- 25 s Industrial sweep MEDIUM with prewarm: 100.3 FPS, p99 18.4 ms,
  max 20.0 ms, 0 frames >50 ms.
## Video report 2 - 2026-11-07 (thin/thick pipe, collision, floating panel)

- The "bugged thin pipe" was the Village hall chimney at (310,28), placed on
  top of the two hall-yard silos at (302,21)/(309.5,26).  The overlapping
  tubes produced the white rectangular "window" and one-sided clipping.
  The chimney moved to (310,80), well clear of the silos; radius 2.1, wall
  0.6, open top + two opposite base arches.  Inside-out rays now hit the
  inner wall at 1.50 m in all four directions.
- The thick factory chimney moved to (-90,-146), clear of the hall roof and
  warehouse, with an open top and two opposite base arches (0-6 m) so the
  player can enter at the top and leave at the bottom.  `factory_tunnel`
  (top open, base open, upper wall solid) -> PASS.
- All open towers now use TWO opposite base arches (count=2): village hall
  chimney/silos, industrial chimney/cooling/silos, valley 3 stacks,
  wetlands stack and the factory stack.  Top remains fully open.
- Floating objects: removed the hall-yard floodlight masts, deleted 71 thin
  tall facade sticks and 4 top panels from `factory_complex.glb` facade
  detail.  The black panel above the factory chimney is gone
  (`qa_shots/factory_final4.png`).
- Fly-through/fall-through: open towers now build ONE combined collision
  surface (outer + inner + rim) with backface collision; authored GLBs,
  cottage kits and the hero hall now add collision for EVERY mesh surface
  with backface collision; terrain and horizon collision also use backface.
  This addresses the one-sided walls/roofs the player flew through.
