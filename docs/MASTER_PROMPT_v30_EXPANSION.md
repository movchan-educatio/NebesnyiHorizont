# MASTER PROMPT v30 — «Розширення симулятора: Ліс, Нафтова платформа, ворожі камікадзе, нові дрони, економіка»

> Наступна редакція після `docs/MASTER_PROMPT_IDEAL_SIM_v29.md`.
> Скопіюй блок ` ```text ` нижче як єдиний промт для виконавця (агент або `opencode run -m opencode/hy4-flash-free#high`).
> База: `fb5b9d0` (поточний чистий стан репозиторію), `config/version="1.19.0-v19"`, Godot 4.6.1.
> Довідкові факти: `README.md`, `docs/AIRPORT_MISSIONS_FIX_REPORT.md`,
> `docs/MASTER_PROMPT_v28_GROWTH.md` (там уже реалізована прогресія — НЕ переписувати).

---

```text
ТИ — senior Godot 4 / GDScript інженер, технічний художник і QA lead.
Репозиторій: C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC
Працюй ТІЛЬКИ тут. Не переписуй проєкт з нуля — розширюй існуючі системи.
Перед великими змінами — git-бекап/окремий коміт. Некомітові файли користувача не чіпай.

ЖОРСТКІ ОБМЕЖЕННЯ
1. Mobile-first / low-spec: iPhone 11/SE+, 30–60 FPS, LOW preset за замовчуванням.
   Кожна нова функція має бюджет CPU/GPU; статику — у MultiMesh/geometry instances.
2. НЕ ламати: 3 графічні пресети, посадку, паузу, ELRS Wi-Fi, сенсор/геймпад,
   DVR/replay/Ghost, UA/EN локалізацію, наявні 5 карт і 14 місій, шкоду/БЧ/РЕБ.
3. Усі наявні QA лишаються зеленими. Обов'язковий фінальний прогон (кожен 2–3 рази):
     Godot_v4.6.1-stable_win64_console.exe --headless --path . --editor --quit
     powershell -File tools/qa_all_maps_deep.ps1        -> ALL MAPS / ALL MISSIONS PASSED
     powershell -File tools/qa_airport_all.ps1          -> ALL QA PASSED
   `--quit-after 420000` — обов'язковий запобіжник для нових QA-сцен.
4. offline-first. Без реклами, IAP, акаунтів, серверів, аналітики. Монети — локальні,
   зароблені в грі; жодного купівлі за реальні гроші.
5. Жодних зависань: нові пошуки/генерації мають wall-clock бюджет і fallback.
   Максимум 50 мс/кадр, 1.5 с на одноразову генерацію рівня.
6. Логи чисті: 0 SCRIPT ERROR / USER ERROR / Parse Error / leaked nodes.
7. Усе нове — UA + EN (`scripts/util/localization_manager.gd`, `Loc.DICT`),
   і мобільне меню `GUI/mobile/MobileMenu.gd`, і ПК-меню `GUI/MainMenu.gd`.

АРХІТЕКТУРА (не перевинаходь)
- autoloads/Global.gd — `enum Difficulty {RECRUIT=0, OPERATOR=1, ACE=2}`,
  `menu_settings` (збереження в ConfigFile), `career_xp`, `PILOT_RANKS`,
  `get_pilot_rank_info()`, `get_difficulty_*()` (час, вітер, точність, швидкість ракет,
  бонус рахунку, цілі). Уже є daily challenge/streak/stars — зберігаємо.
- autoloads/DroneCatalog.gd — каталог дронів (`apply()`, `animate_propellers()`,
  `is_uman()`, `allowed_for_map()`, `allowed_for_mode()`); 13 дронів, 3 з них —
  фрістайльні `Assets/UmanFPV/`.
- sceneries/BigLevel.gd — база 5 фронтових карт: 10 спецоперацій + 4 кампанії,
  хвилі, фази, БЧ, РЕБ, погода, DVR, `_spawn_combat_mission()`.
  `extends res://sceneries/Level.gd`; `@export var frontline_map` (рядок 151);
  `_map_path()` 1639, `_load_map()` 1649, `_place_drone_over_ground()` 2134,
 Spawn: `_player_spawn_xz()` 346, `_resolve_spawn_position()` 2097,
   вороги: `_spawn_combat_mission()` 6222, `_spawn_reinforcement_wave()` 6426.
- **Немає центрального реєстру карт!** `Global.menu_settings["selected_map"]` —
  рядок; кожне меню хардкодить свій список:
  `GUI/MainMenu.gd`: `FRONTLINE_LEVELS` 9–15, `SELECTABLE_MAPS` 18,
  `map_defs` 635–657, `_select_map()` 1182, `_launch_current_selection()` 1693;
  `GUI/mobile/MobileMenu.gd`: `MAP_META` 37–42, map cards 2425–2511
  (прев'ю `res://Assets/Branding/mobile_map_<id>.png`, рядок 2455),
  `scenes` 3098–3105. Спавн-захист: `scripts/util/frontline_terrain.gd`
  `HALL_SITES` 47–77, `STRUCT_AO_CIRCLES` 119–123.
- sceneries/UmanLevel.gd/.tscn — еталон фрістайл-карти (суцільний ґрунт, вода з
  авторестартом, 46 неонових воріт, ~240 трюкових об'єктів із колізіями,
  "спідниця" краю карти). Підключена ТІЛЬКИ до фрістайлю.
- sceneries/AirportLevel.gd — еталон інтеграції готового GLB + 12 колайдерів +
  `scripts/util/ground_route_planner.gd` для проїжджальних маршрутів техніки.
- combat/{combat_system,enemy_infantry,vehicle,aa_gun,explosion,destruction_fx,hit_fx,sfx}.gd
- autoloads/Audio.gd + Assets/Audio/SFX/Propellers/looped/motor{1..7}_loop.wav —
  двигуни з прив'язкою до RPM/газу; combat/sfx.gd — бойові звуки.
- scripts/util/DronePropellerSystem.gd + drone/parts/propellers/PropBlurShader.tres —
  видимі гвинти, мета `prop_pivots`, напрямок `spin_dir`, clamp швидкості обертання.
- scripts/util/localization_manager.gd (`Loc.DICT`), scripts/util/quality_manager.gd.
- test/qa_airport_missions.gd, test/qa_mobile_missions_audit.gd — параметризуються
  через `QA_MAP=steppe|village|industrial|wetlands|airport`;
  test/qa_uman_freestyle.gd, test/qa_prop_animation.gd — еталони нових QA.

============================================================
ЦІЛЬ 1. ДВІ НОВІ КАРТИ (P0)
============================================================
1.0. КРИТИЧНО: обидва джерела — окремі міні-проєкти, НЕ `BigLevel`-похідні.
     Просто `add_child(map_scene)` НЕ дасть дрона, FPV-камеру, HUD, паузу, місії,
     керування, DVR і зникнення loading-overlay. Обов'язково зробити обгортку:
     `sceneries/<Id>Level.tscn` інстансує `res://sceneries/BigLevel.tscn`,
     перевизначає `script` на `sceneries/<Id>Level.gd extends BigLevel.gd`,
     ставить `frontline_map = "<id>"`, задає `Respawn` і `Drone` (ідентичні
     трансформи). У скрипті: `_map_path()` (точка 1639) має повертати шлях до
     GLB/TSCN карти, `_load_map()` (1649) — `super._load_map()` + audit колізій;
     перевизначити `_find_ground_y()`, `_is_ground_spot_clear()`,
     `_special_ground_point()`, `_map_water_level()`, `_place_drone_over_ground()`.
     НЕ робити `-override` без `super._ready()` (див. UmanLevel.gd:72-86).
1.1. ЛІС — технічний id `lis_forest_freestyle`, назва «Ліс».
     ФРІСТАЙЛЬ + УСІ МІСІЇ (4 кампанії + 13 спецоперацій; QA-харнеси історично
     рахують 10+4=14 — покрити реальний перелік, а не лише старий лічильник).
     - Джерело (точна папка): `C:\Users\USER_UA\Desktop\FPV_Map_Lis`.
       Прочитати `README.md`, `05_docs/INTEGRATION_GUIDE.md`,
       `05_docs/INTEGRATION_READINESS.md`,
       `05_docs/FREESTYLE_ELEMENTS_MANIFEST.json`.
     - Скопіювати ТІЛЬКИ `03_godot_export/maps/lis_forest_freestyle/` →
       `res://maps/lis_forest_freestyle/`: `lis_freestyle_map.tscn`,
       `meshes/*.glb`, `scripts/scatter_multimesh.gd`, `scripts/setup_collisions.gd`,
       `scatter_transforms.json` (6750 трансформів). НЕ копіювати
       `01_assets_raw/`, `02_blender_source/`, `04_previews/`,
       `free_fpv_preview_cam.gd` (QA-only). Шляхи — латиницею.
     - У вже існуючій сцені: `Terrain`/`Structures`/`FreestyleGeometry` GLB,
       `ScatterMultiMesh` (31 chunk, visible range 90–520 м), `SpawnPoints`,
       `setup_collisions.gd` (334 StaticBody3D; `-colonly` → ConcavePolygonShape3D,
       collision_layer=1/mask=0), WorldEnvironment + Sun.
     - ПАСТКА: група `lis_spawnpoints` висіть на БАТЬКІВСЬКОМУ вузлі
       `SpawnPoints` (рядок 56 .tscn), а не на маркерах. Бридж має брати
       `SpawnPoints.get_children()` (`Spawn_Z01 … Spawn_Z08`), а не
       `get_nodes_in_group("lis_spawnpoints")` напряму. Дрон += `UP*2.0`.
     - 315 фрістайл-елементів/100 модулів, координати й `entry_direction`,
       `gap_width_m` у `FREESTYLE_ELEMENTS_MANIFEST.json` — змапити на
       `BigLevel` ring/gate-систему (`_build_freestyle_ring_positions()` 3779,
       `_spawn_training_rings()` 3952) або на окремі чекпоінти. Додати ворота,
       яких у вихідній сцені немає (група `fpv_gates` відсутня).
     - Конфлікт рендерера: гайд радить `gl_compatibility`, а проєкт використовує
       `forward_plus`/`mobile` (`project.godot` 227–229). НЕ перемикай глобально —
       адаптуй карту під наявний рендерер і 3 пресети, перевір iOS-пресет.
     - Бюджет: ≤350k трикутників і ≤220 draw calls у найгіршій точці
       (верхня межа джерела ~1.8M — обов'язково LOD/дальні зони).
     - Для бою: НЕ ставити заглушки на `_spawn_vehicles`, `_spawn_combat_mission`,
       `_spawn_special_or_campaign`, `_start_reinforcements` (як це робить
       UmanLevel.gd:225-241); додати `HALL_SITES`/`STRUCT_AO_CIRCLES` або власні
       безпечні зони в `scripts/util/frontline_terrain.gd`, маршрути техніки —
       через `scripts/util/ground_route_planner.gd`, перевірити 6 с руху.
     - Реєстрація: `GUI/MainMenu.gd` `FRONTLINE_LEVELS`+`SELECTABLE_MAPS`+`map_defs`,
       `GUI/mobile/MobileMenu.gd` `MAP_META`+`scenes`,
       `Assets/Branding/mobile_map_lis_forest_freestyle.png`,
       `DroneCatalog.allowed_for_map()/allowed_for_mode()` (зараз 530–545 —
       ігнорує map id!), `GUI/HelpScreen.gd`, `README.md`; зробити спільний
       предикат замість хардкоду `"uman"` у ~8 місцях меню.
     - QA: додати `lis_forest_freestyle` у `QA_MAP` `tools/qa_all_maps_deep.ps1`,
       нові `test/qa_lis_missions.gd/.tscn` + `test/qa_lis_freestyle.gd/.tscn`
       (за зразком qa_airport_missions + qa_uman_freestyle), `qa_floating_scanner`.
1.2. НАФТОВА ПЛАТФОРМА — ТІЛЬКИ ФРІСТАЙЛЬ, заміняє Умань у меню.
     Умань і її асети НЕ видаляти (лише прибрати зі списків); старі збереження з
     `selected_map == "uman"` мігрувати на новий id.
     - Джерело: `C:\Users\USER_UA\Desktop\OilRigMap_Prototype\godot_package\maps\oil_rig`.
       Прочитати `INTEGRATION_README.md`, `BUILD_REPORT.md`, `collision_report.json`.
     - Скопіювати ВСЮ папку → `res://maps/oil_rig/` (усі `.glb`, `.png`,
       `.gdshader`, `.tres`, `.gd`, `.json`, `.tscn` — GLB без вбудованих
       текстур навмисно; atlas-матеріали накладає `scripts/oil_rig_materials.gd`).
     - Готова сцена `oil_rig_map.tscn` (root `OilRigMap` + `map_runtime.gd`):
       `Sun`, `Ocean` (6000×6000 + ocean_water.gdshader), 4 platform_core,
       4 derrick, 8 crane, 4 helipad, 2 flare, 4 skybridge, 1 tanker,
       `InstancedDetails` MultiMesh + `scripts/instancing_data.json`,
       `MapColliders` (група `map_colliders`, 937 Box/Cylinder shape, БЕЗ
       concave-hull на порожнистих конструкціях), `FPVGates` — 49 Marker3D
       (`Gate_00…Gate_48`, група `fpv_gates`), `SpawnPoints` — 5 Marker3D
       (`Spawn_Helipad_P1`, `Spawn_Deck_P2`, `Spawn_Tanker`, `Spawn_Hangar_P3`,
       `Spawn_Bridge_Mid`, група `map_spawn_points` — тут група вже на маркерах),
       `WaterKillZone` (Area3D, група `water_kill_zone`). Локальний −Z = вперед.
     - Підключити: `map_spawn_points[0].global_transform` → `Respawn`/`Drone`;
       `fpv_gates` → ring/checkpoint-логіці BigLevel; `WaterKillZone.body_entered`
       → `request_respawn()` (група `"drone"`); `map_colliders` — не дублювати.
     - Статистика для бюджету: 34 900 унікальних трикутників модулів, 55–75 draw
       calls, 2×2048² PBR-атласи. На LOW — спрощені хвилі/полум'я (без SSR/SDFGI/
       volumetric/screen-space), зберегти 3 графічні пресети і mobile-рендерер.
     - Фрістайльна логіка як в UmanLevel: маршрут/ворота, трюкові об'єкти з
       колізіями, 3 фрістайльні дрони, видимі обертові гвинти; заборонити
       техніку/піхоту/ destructible/місії ( stub'и `_spawn_*`, як UmanLevel.gd:225-241).
     - Новий id у меню/довідці/брендингу `mobile_map_oil_rig.png`, QA- Env-override
       `DRONE_MAP` (BigLevel.gd:470) — зручно для тестів.
1.3. ПІСЛЯ інтеграції — прогнати всі місії на Лісі, фрістайль на обох картах,
     спавни/рух техніки й піхоти, 2–3 повтори. Заборонено "просто додати в меню".

============================================================
ЦІЛЬ 2. ВОРОЖІ ВЕЛИКІ ДРОНИ-КАМІКАДЗЕ (P0)
============================================================
2.0. Важливо: у проєкті НЕМАЄ окремого класу ворожого дрона; усі "камікадзе"
     зараз — це гравець, що таранить (`CombatSystem.kamikaze_damage`),
     і Shahed-136 (`Vehicle.Kind.SHAHED`). Папка `missions/` і `data/*` ПОРОЖНІ —
     місії хардкодяться у GDScript. Нові дрони мають стати повноцінними
     `combat_target`-юнітами, а не декорацією.
2.1. Джерело: `C:\Users\USER_UA\Desktop\Enemy_FPV_Kamikaze_Drones` (`README.md`,
     L87–88 — реальні розміри). ДВА ВЕЛИКІ = **KT-12 «Basilisk» (0.54 м,
     hexacopter, tandem warhead)** і **KT-8 «Grif» (0.49 м, 4 лопаті, тепловізор,
     важка БЧ, шасі)**; KT-0 Wraith (0.47×0.51 м) — запасний третій великий.
     KT-3 Komar (0.22 м) і KT-5 Shmel (0.31 м) — маленькі, НЕ для цієї цілі.
     Брати звичайні `glb/KT12_Basilisk.glb`, `glb/KT8_Grif.glb` (не `merged/`!),
     копіювати в `res://assets/enemy_drones/`. Ніс = −Z,верх = +Y, корінь
     `KT*_ROOT`, ~525–819 вузлів, 0 зовнішніх текстур, 0 анімацій/скінів —
     усе анімується скриптом. Для Glow_Violet/Glow_Gold додати Bloom у WorldEnvironment.
2.2. Новий юніт: `combat/enemy_kamikaze_drone.gd` + `.tscn`. Не винаходити з нуля:
     поєднати (а) `godot_example/EnemyKamikazeDrone.gd` (Area3D, `take_damage`,
     `destroyed`, політ по −Z, обертання пропелерів) з (б) патернами
     `combat/vehicle.gd` SHAHED: `enum` фази PATROL/APPROACH/DIVE/OVERSHOOT
     (L1860), передбачуване наведення `_shahed_aim_position()` (L1909),
    детонація в безпосередній близькості (L1925), `_destroy()` (L2905) з
     `_start_crash_fall()`,
     `DestructionFxScript.destroy(...)`, `CombatSfxScript.play_boom`;
     і (в) контрактом `_add_vehicle()` `BigLevel.gd:4419-4425`:
     `set_meta("is_primary_target", ...)`, групи `combat_target`, `air_target`,
     `primary_combat_target`, `signal destroyed(points)`, watchdog.
     ВАЖЛИВО: `collision_layer` прикладу (1<<3) і `collision_mask = 0` треба
     адаптувати під проєкт (шари 1/корбоді дрона), інакше пошкодження не працюватиме.
     Пропелери: у KT-8/KT-12 вузли `Prop_00_Blade_*`; у Wraith — `Fan_Prop_*`
     (строковий приклад шукає лише `Prop_` — розширити фільтр).
2.3. FSM (з часовими бюджетами): SPAWN -> APPROACH (передбачуване
     переслідування гравця, висота ≥ `_structure_ceiling()` з
     vehicle.gd, не важкі raycast-и щокадру) -> LOCK (попередження в HUD/радіо
     через `CombatSfxScript.alert_stream("...")` / `play_alert_3d()`, ~3–5 с) ->
     DIVE -> HIT/IMPACT (`CombatSystem.damage_drone(dmg, pos, source)`,
     dmg масштабується `Global.get_difficulty_*()`) -> FALLING (реальний
     tumbling-політ з димним слідом `DestructionFxScript.trail()`, іскри,
     Tween/фізика з жорстким timeout) -> EXPLODE (`ExplosionScript.spawn`,
     `DestructionFxScript.spawn_multiphase_explosion`) -> DEBRIS -> DESPAWN.
     Видалення — queue_free тільки після закінчення FX.
2.4. Вразливість: дрон має `take_damage(amount, hit_position)`, зони (БЧ/мотори),
     дим/вогонь при низькому HP, hit_fx, kill-подію в DVR/kill-cam/статистику;
     його можна збити звичайною зброєю і тараном. LOW: ≤40 одночасних
     частинкових систем, не більше 16 голосів CombatSfx одночасно.
2.5. Звук (стиль проєкту — процедурний): додати в `combat/sfx.gd` статичні
     `kamikaze_engine_stream()`, `kamikaze_warning_stream()`,
     `kamikaze_fall_stream()`, `play_*()` за зразком `shahed_engine_stream()` L928,
     `_finalise_loop()` L976, `make_looping_player()` L1268; викликати з нового
     скрипта як у `vehicle.gd:1295-1296` і `:2935`. Зареєструвати в `prewarm()`
     L1586 / `clear_caches()` L1597. Для імпортованих WAV — `Assets/Audio/SFX/Enemies/`
     + `AudioStreamPlayer3D` на шинах `"Engine"`/`"Combat"`. UA/EN рядки —
     `Loc.DICT` + `MainMenu.BRIEFINGS(_EN)`/`SPECIAL_MISSIONS`.
2.6. ПІДКЛЮЧЕННЯ ДО ВСІХ МІСІЙ: єдиний choke point —
     `sceneries/BigLevel.gd:5140 _spawn_special_or_campaign()` (викликає
     `_spawn_special_mission()` 5543 для 13 спецоперацій і `_spawn_combat_mission()`
     6222 для 4 кампаній; QA історично рахує 10+4=14 — покрити ВСІ наявні).
     Додати `_spawn_kamikaze_drones()` після гілки, один раз для будь-якої місії;
     preload нового скрипта біля L13–35. Кількість за `Global.Difficulty`:
     RECRUIT 0, **ОПЕРАТОР 1, АС 2** (рівні в `Global.gd:12`, перевіряти в QA).
     Спавн — через `_clamp_air_vec3()`, `_ensure_enemy_xz_clearance(...,
     MIN_ENEMY_SPAWN_DIST_AIR=95, MAP_AIR_SAFE, true)`, повітряні висоти L53–57;
     на LOW — кап/спрощення.
     "Заважають" = переслідують гравця, змушують маневрувати, влучання шкодить
     (може призвести до втрати планера/таймауту), **і є обов'язковими цілями**:
     `_mission_targets_total += N` при спавні, `is_primary_target=true`,
     у `_on_kamikaze_destroyed()` — `_mission_targets_destroyed += 1` +
     `_advance_phase_after_kill(true, ...)` (див. `_on_vehicle_destroyed()` L4518,
     `_check_combat_mission_complete()` L4685). НЕ зламати `_pending_combat_complete`
     і kill-cam. Оновити `CombatSystem.kamikaze_hit_radius()` L643 і
     `scripts/util/mission_drone_switcher.gd:_scan_threats()` L194–242,
     інакше логіка тарану не бачить нових дронів.
2.7. QA: новий `test/qa_kamikaze_missions.gd/.tscn` — параметризувати ВСІ місії,
     OPERATOR/ACE, усі бойові карти + Ліс; перевірити spawn count (1/2),
     FSM-переходи, падіння/вибух, звук, шкоду гравцю, знищення → completion,
     kill-cam pending, NaN/вильоти, 0 SCRIPT ERROR; 2–3 повтори; скріншоти
     `docs/kamikaze_qa/`. Окремо — LOW-профіль і мобільний HUD-попередження.

============================================================
ЦІЛЬ 3. ТРИ НОВІ КЕРОВАНІ ДРОНИ ГРАВЦЯ (P0)
============================================================
3.0. Уточнення: у проєкті НЕМАЄ дрона "антігравіті" — "Antigravity" це IDE,
     а `anti_gravity_gain` у `FlightController.gd:74` — коефіцієнт ФК.
     Еталон додавання льотних дронів — коміт `af2a7c8` (3 дрони Умані) і
     `Промт для покращення\2.txt:184-311` — читати обов'язково.
3.1. Фіксований список "перші 3" (нумерний порядок KT-0/3/5, без перетину з
     ворожими KT-8/12): **KT-0 «Wraith», KT-3 «Komar», KT-5 «Shmel»**.
     Копіювати `glb/KT0_Wraith.glb`, `glb/KT3_Komar.glb`, `glb/KT5_Shmel.glb`
     у `Assets/Drones/enemy_pack_player/` (source/*.blend з `.gdignore`);
     GLB метричні, ніс −Z, upper +Y, `model_fit:false`. 525–564 вузлів на дрон —
     забагато для LOW: зробити LOD, злити корпус у меші за матеріалами + лишити
     окремі лопаті.
3.2. Додати 3 записи в `autoloads/DroneCatalog.gd` ТІЛЬКИ В КІНЕЦЬ `PRESETS`
     (індекси **13, 14, 15**; у жодному разі не вставляти в середину — у проєкті
     є хардкодовані індекси 0..12!). Повний набір ключів як у прикладі
     `PRESETS[0]` (`:30-58`): `id/name/name_en/tag(_en)/desc(_en)/info(_en)`,
     `model/model_size/model_fit/model_yaw`, `dry/batt/kv/torque/rpm/prop_d/
     prop_p/blades/rate/motor_size/twr`, `battery_*`, `dimensions/drag_area/
     cog_offset`, `payload/payload_mass/combat/has_drop/kamikaze`,
     `parts_profile` (0..15), унікальний `audio_kind` (напр. 14/15/16),
     UA/EN опис і характеристики, ціна_unlock (ЦІЛЬ 5). Реально впливає на
     `Drone.gd:1109 apply_preset_physics()`, `FlightController.gd`,
     `Motor.gd`, `Battery.gd`; не ламати `DroneCatalog.count()`/`apply()`.
3.3. ВИДИМІ ГВИНТИ — головний ризик. Ці GLB не мають вузлів `motor_FL`/
     `propeller_FL`, а лише лопаті `Prop_00_Blade_*` (Komar/Shmel) і
     `Fan_Prop_*`/`FrontProp_*`/`RearProp_*` (Wraith) без півотів. Тому
     `DronePropellerSystem.setup_propellers()` знайде 0 півотів. Зробити одне:
     (а) переекспортувати зі включених у пакет .blend за конвенцією Умані
         (`motor_FL/FR/BR/BL` + `propeller_FL/FR/BR/BL` як порожні півоти), або
     (б) рантайм-адаптер, що згрупує лопаті під 4 згенерованими `Node3D`
         з мета `spin_dir`/`spin_axis`/`prop_pivots`. Потім
     `DroneCatalog.animate_propellers()` (`:1594`) + `drone/Drone.gd:_process()`
     (`:248-257`) крутять їх від реальних RPM/газу; на LOW — `PropBlurShader.tres`
     та `drone/Propeller.gd` (приховання лопатей >500 RPM), НЕ підвищувати
     глобально `DronePropellerSystem.MAX_VISUAL_RPM = 780`.
     БЧ — окремий видимий вузол, який не ховається разом із шасі.
     FPV: `fpv_show_airframe:true`, `fpv_hide_model:false`, підібрати
     `fpv_cam_pos/fpv_cam_pitch` (див. `_setup_fpv_camera_for_preset()` 7499),
     щоб були видно й БЧ, і пропелери; після респавна/зміни налаштувань гвинти
     відновлюються (не зламати `af18ad0`, `_refresh_model_visibility()` 10436).
3.4. Окремий звук кожного дрона (два шари вже є):
     (1) синтетичний — нові `case` в `combat/sfx.gd:drone_motor_stream()` (1299)
         з унікальними параметрами `_synth_quad_motor()` (1361) + `prewarm()`
         (1586); `Drone.refresh_motor_audio()` (371) підхопить автоматично;
     (2) записані loop-и — нові `Assets/Audio/SFX/Propellers/looped/motor8..10_loop.wav`
         і `case` в `DroneCatalog.get_recorded_motor_profile()` (436–463) +
         нові `audio_kind` у пресетів; `Motor.update_sound()` (228) робить
         кросфейд і pitch/gain по RPM. Пауза/disarm — як у наявних дронів.
     Оновити QA-очікування "13 пресетів / 13 унікальних audio_kind / 14 stream":
     `test/qa_polish_audio.gd:84-86`, `test/qa_mobile_polish_verification.gd:616-629`,
     `test/test_release_readiness.gd:67`, `test/test_new_features.gd:53`,
     `tools/render_drone_spinning_test.gd:33`.
3.5. QA: розширити `test/qa_prop_animation.gd`, `qa_all_drones_flight.gd`,
     `test_engine_audio.gd`, `test_drone_builder.gd`, `qa_respawn_fpv_view.gd`,
     `qa_all_drones_showcase.gd`, `test_release_readiness.gd` — перевірити
     16 дронів, ≥4 півотів на кожному новому, старт/стоп обертання, різні RPM,
     наявність БЧ, унікальність звуку, FPV-кадрування, вибір у ПК/мобільному
     ангарі, політ у TRAINING/COMBAT/спецопераціях. Скріншоти `docs/v30_drones/`.

============================================================
ЦІЛЬ 4. НАДІЙНІСТЬ ТА ТЕСТИ (P0)
============================================================
4.1. Кожен етап — окремий коміт, після кожного: `--headless --path . --editor --quit`.
4.2. Прогнати 2–3 рази (і записати результати в новий `docs/v30_QA_REPORT.md`):
     tools/qa_all_maps_deep.ps1 (5 бойових карт + Ліс; окремо фрістайль Нафтової),
     tools/qa_airport_all.ps1, qa_uman_freestyle/нові картові QA,
     qa_combat_all_difficulties, qa_mobile_missions_audit,
     qa_mobile_mission_completion, qa_prop_animation, qa_engine_audio,
     qa_all_drones_flight, qa_release_readiness, test_new_features.
4.3. Критерій: `failures=0`, EXITCODE=0, 0 SCRIPT ERROR, скріншоти в
     `qa_shots/v30*/`, параметри MOBILE_UI=1 + TOUCH_CONTROLS=1 — окремо.
4.4. Perf на LOW: кадр <16.6 мс (ціль), solve/AI/планування в бюджетах v28;
     нові юніти не перевищують бюджет голосів/частинок.
4.5. Не змінюй пороги тестів, поки не зрозумієш причину падіння.

============================================================
ЦІЛЬ 5. СИСТЕМА РОЗВИТКУ ПІЛОТА ТА МОНЕТИ (P1)
============================================================
5.0. ФАКТ: валюти/магазину/price/unlocked у коді НЕМАЄ. Але вже є прогресія —
     НЕ переписуй: `Global.menu_settings["career_xp"]`, `PILOT_RANKS` (810),
     `get_pilot_rank_info()` (819), `record_sortie_career()` (843),
     campaign records (336–450), `get_daily_challenge()` (578), streak,
     stars/records, `is_mission_unlocked()` (431). Монети — новий шар, не XP.
5.1. Новий autoload `Progress` у `autoloads/` + реєстрація в `project.godot`.
     Єдиний власник економіки. Файл — у вже прийнятій папці збережень:
     `user://config_G3/Progress.cfg` (ConfigFile; сусіди: Menu.cfg, Campaign.cfg,
     GameSettings.cfg, Quad.cfg, Graphics.cfg, Audio.cfg, InputMap.cfg).
     `schema_version`, atomic write + `.bak`, міграція з відсутнього/старого
     файлу, fallback при пошкодженні. Жодних серверів/акаунтів/реклами/IAP.
5.2. Заробіток (детерміновано, idempotent): база за складністю
     RECRUIT/OPERATOR/ACE (наприклад 40/70/120 через
     `Global.get_difficulty_score_multiplier()`), бонус за перше проходження
     місії (одного разу), за 3 зірки (`Global.compute_rating()` 493),
     за відсутність втрати планера, за точність/швидкість, за daily challenge
     + streak, за рекорд фрістайл-траси (`record_training_result()` 522).
     Кожна нагорода — унікальний `award_id` у збереженні; повтор не подвоює.
     Аборт/рестарт/DEMO — 0. Добовий кап на місію/режим. Виклик нарахування
     вшити в існуючі шляхи завершення: `BigLevel._show_results()` (2913+),
     `Global.record_mission_result()` (392), `record_special_mission_result()` (396),
     `record_training_result()` (522), `mark_daily_challenge_completed()` (632).
5.3. Витрати: нові дрони (13–15), карти (Ліс, Нафтова платформа), режими/спецоперації.
     Таблиця цін — `data/economy.json` (папка вже існує порожньою) або
     константи в `Progress.gd`, поля `id`, `kind` (drone|map|mode),
     `cost`, `requires_rank_xp`, `unlock_id`. Початковий стан: усі наявні
     13 дронів/5 карт/режими доступні зі старту (не зламати регресії), нові —
     платні. Для QA — `QA_UNLOCK_ALL=1` (env), у релізі ігнорується.
5.4. Гейтинг має працювати everywhere: `DroneCatalog.allowed_for_map()` (529)
     і `allowed_for_mode()` (537) мають фільтрувати через `Progress.is_unlocked()`;
     `DroneSelectScreen.gd:97-98`, `MobileMenu.gd` (44 виклики DroneCatalog),
     `MainMenu.gd` `SELECTABLE_MAPS`/`map_defs`, `MobileMenu.MAP_META`/`scenes`,
     `_select_map/_select_mode/_select_mission` — усі мають показувати замок
     і не давати запуск. Після unlock — одразу без перезапуску й після рестарту.
5.5. UI (ПК + мобільний, UA/EN): лічильник монет у головному меню/ангарі,
     картки з ціною/кнопкою «ВІДКРИТИ»/станом «ВІДКРИТО», тост нагороди після
     дебрифінгу, екран «ПРОФІЛЬ ПІЛОТА» (ранг, XP, монети, статистика)
     у `GUI/ui/MenuUI.gd` + `GUI/mobile/MobileMenu.gd`; нові ключі в
     `scripts/util/localization_manager.gd` `Loc.DICT` та `GUI/ui/MenuUI.gd EN_TEXT`.
5.6. QA: новий `test/qa_economy.gd/.tscn` — нарахування/списання/негативний
     баланс/повторна нагорода (той самий `award_id`)/перше проходження/
     добовий кап/міграція/пошкоджений Progress.cfg/перезапуск/гейтинг в обох
     меню/ unlock → політ. Прогнати 3 рази; 0 SCRIPT ERROR; разом із
     `qa_mobile_persist.gd`, `qa_persist2_read/write.gd`, `test_release_readiness.gd`.

ВИКОРИСТАННЯ HY4 FLASH FREE ЧЕРЕЗ OPENCODE (опційно)
Дозволено делегувати self-contained задачі (з абсолютними шляхами, конкретними
файлами, критерієм готовності й заборонами):
  opencode run -m opencode/hy4-flash-free#high --auto "<завдання>"  (або < NUL у cmd)
Правила: не втрачати контроль — після КОЖНОГО делегування сам перевірити
`git diff`, запустити headless-check і релевантний QA; неперевірені твердження
виконавця не додавати у звіт без доказів; передавати sessionID для продовження тієї самої
сесії; не передавати зовнішній моделі secrets/ключі/дані користувача.

ПРОЦЕС РОБОТИ
1. Проаналізуй код і QA. Не припускай — перевіряй.
2. Один коміт = одна логічна зміна + її тест.
3. Після кожної зміни: headless editor check + релевантний QA.
4. Фінал: усі прогони з ЦІЛІ 4, 2–3 повтори, чистий git diff, звіт.
5. Якщо тест падає — не змінюй поріг, поки не знайдеш корінь.

ФОРМАТ ВІДПОВІДІ
1. Що зроблено (файл:рядок, коротко).
2. Список змінених/нових файлів.
3. Результати QA (імена, PASS/FAIL, цифри FPS/мс, 3 повтори).
4. Скріншоти/артефакти (шляхи).
5. Топ-3 ризики й один конкретний наступний крок.
```

---

## Як користуватися

1. Скопіюй увесь блок `text` у нову сесію виконавця.
2. Для економії часу роби коміти за цілями: 1 → 2 → 3 → 5 → 4 (QA-прогони).
3. Після кожного коміту оновлюй `docs/v30_QA_REPORT.md` і `qa_shots/v30*/` —
   це стає новою базою для v31.
4. Якщо потрібно звузити скоуп: `Сьогодні тільки ЦІЛЬ 1, не чіпай місії й економіку.`
