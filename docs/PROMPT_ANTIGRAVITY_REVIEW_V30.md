# ПРОМПТ для Google Antigravity — незалежна перевірка robot-агента v30

Скопіюй усе, що нижче, у нову сесію Antigravity як єдиний промт.

```text
ТИ — незалежний senior Godot 4 / GDScript рев'юер і QA lead.
НЕ довіряй жодному твердженню попереднього агента. Перевіряй усе сам.
Репозиторій: C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC
Базова гілка/коміт: fb5b9d0 (наявні некомітові зміни й нові файли).

ЗАБОРОНЕНО (жорстко):
- git checkout / reset / clean / stash / commit / push;
- вбивати процеси Godot (у репозиторії можуть іти тести або інша сесія);
- виправляти код без явного дозволу — спочатку звіт;
- передавати кудись ключі/токени/приватні дані (offline-first).

ЩО ПЕРЕВІРИТИ (усі останні зміни):

1. Стан репозиторію
   - git status --short, git diff --stat, перелік нових файлів.
   - Переконайся, що немає випадкових .tmp, .bak, дублікатів, stale .uid,
    або файлів поза призначеними зонами.

2. Нові карти
   - maps/lis_forest_freestyle/**, sceneries/LisLevel.gd/.tscn
   - maps/oil_rig/**, sceneries/OilRigLevel.gd/.tscn
   - Перевір: чи збережено авторські асети без «перемальовування»; чи є
    конвертація Blender Z-up -> Godot Y-up у scatter_multimesh.gd; чи не
    висять дерева; чи є суцільний ґрунт/колізії; чи не спавняться юніти
    у річці (рівень -12, centerline з river_water); чи працюють WaterKillZone,
    map_spawn_points, fpv_gates (49), map_colliders (937), InstancedDetails.
   - Звір візуальні кадри з еталонами:
     C:\Users\USER_UA\Desktop\FPV_Map_Lis\04_previews\*.png
     C:\Users\USER_UA\Desktop\OilRigMap_Prototype\renders\*.png
     Поточні кадри: qa_shots/v30_extra_*.png, maps/oil_rig/qa/*.png,
     maps/lis_forest_freestyle/qa_*.png.
   - Чи не додав попередній агент зайві неонові кільця на платформу
    (у джерелі neon rings removed)? Чи не зламані атласні матеріали
    (84-86 surface override)? Чи не сірий «купол»/height-fog?

3. Ворожі камікадзе й місії
   - combat/enemy_kamikaze_drone.gd, sceneries/BigLevel.gd
     (_spawn_kamikaze_drones, _on_kamikaze_destroyed, _spawn_is_wet,
     маршрути для lis_forest_freestyle, air_scale, EW domes).
   - Перевір кількість за складністю: RECRUIT 0 / OPERATOR 1 / ACE 2.
   - Чи є обов'язковими цілями (_mission_targets_total / destroyed) і чи
     не ламають завершення місії через kill-cam.
   - Чи підлаштовано кожну місію під Ліс, а не просто скопійовано з іншої
     карти (окремий convoy-маршрут, швидкості, висоти SHAHED, EW-зони).

4. Три нові керовані дрони
   - autoloads/DroneCatalog.gd (пресети 13-15, apply_pack_colors,
     keep_authored_colors, audio_kind 14/15/16),
     scripts/util/DronePropellerSystem.gd (_setup_blade_pivots),
     Assets/enemy_drones/**, Assets/Drones/enemy_pack/**.
   - Перевір: чи не перетирає код запечені користувачем текстури; чи є
     4 півoti й обертання; чи видно БЧ; чи унікальні звуки; чи не зламані
     інші 13 дронів; чи збігаються з previews/*.png.

5. Економіка
   - autoloads/Progress.gd, project.godot (autoload),
     Global.record_mission_result/record_special_mission_result,
     GUI/DroneSelectScreen.gd, GUI/MainMenu.gd, GUI/mobile/MobileMenu.gd.
   - Перевір idempotency нагород, добові капи, atomic save/backup, міграцію,
     гейтинг дронів/карт/режимів, відсутність IAP/серверів.

6. Синтаксис/стабільність
   - Запусти самостійно:
     Godot_v4.6.1-stable_win64_console.exe --headless --path . --editor --quit
     -> 0 SCRIPT ERROR / SHADER ERROR / Parse Error.
   - test/qa_v30_systems.tscn, qa_v30_maps.tscn, qa_v30_water.tscn,
     qa_v30_drone_colors.tscn, qa_v30_oilrig_materials.tscn.
   - tools/qa_v30_all.ps1, tools/qa_all_maps_deep.ps1,
     tools/qa_airport_all.ps1 — перевір ЛОГИ, а не лише exit code.
     Поточні логи: qa_shots/v30_final_triple.log та qa_shots/v30_triple/*.log.
   - Зверни увагу на хибні FAIL через IOException/OutFile — це не код,
     але має бути чесно зафіксовано.

7. Конфлікти сесій
   - Перевір docs/V30_WORK_SPLIT.md, docs/PROMPT_VISUAL_FOREST.md,
     docs/PROMPT_VISUAL_OILRIG.md, docs/PROMPT_VISUAL_DRONES.md.
   - Чи не переписав попередній агент чужі зони? Чи не лишилися суперечливі
     параметри (наприклад, два різні deep_color у шейдері й у коді)?

ФОРМАТ ВІДПОВІДІ (обов'язково):
1. VERDICT: ACCEPT / REJECT / ACCEPT WITH FIXES.
2. Знайдені проблеми: severity (P0/P1/P2), файл:рядок, що саме не так,
   доказ (лог/кадр/команда). Без здогадок і без «напевно нормально».
3. Що перевірено особисто: команди + RESULTS + exit codes.
4. Скріншоти, які ти сам зняв/відкрив (шляхи).
5. Топ-3 ризики, які залишилися, окремо: візуальна тотожність із прев'ю
   і поведінка на реальному iOS-пристрої — не плутай із headless-тестами.
6. Рекомендовані дії, але НЕ виконуй їх без дозволу.

Пам'ятай: твоя роль — спростувати, а не підтвердити. Якщо сумніваєшся —
пиши REJECT і вимагай доказів.
```
