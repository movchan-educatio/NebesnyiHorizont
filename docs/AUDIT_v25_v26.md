# Аудит v25–v26: що справді зроблено

Цей документ виправляє попередні звіти (`FINAL_REPORT_v25_v26.md`, `v26_COMPLETE.md`, `PROGRESS_v25_v26.md`), які містили неперевірені твердження.

## Виявлені проблеми та виправлення

1. **Парсинг `combat/enemy_infantry.gd` був зламаний** (критично). `preload("res://Assets/combat/rifleman_merged.glb")` без `.import` файлу давав "Parse error", і всі сцени з піхотою не завантажувалися. Виправлено: прибрано preload і вибір merged-моделі, повернуто `rifleman.glb`. Також прибрано некоректний `"""` docstring у `_apply_animation_lod`.

2. **Merged rifleman ніколи не використовувався в грі.** Основний солдат — `DetailedSoldierRig` (`soldier_detailed_merged.glb`, скінований), він успішно завантажується на обох платформах. `_create_model()` є лише fallback. Тож твердження "58→1 draw calls на солдата" було хибним. `rifleman_merged.glb` лишився в репозиторії, але не підключений.

3. **Animation LOD не працює для основного солдата.** `_anim` присвоюється лише у fallback-гілці `_build()`; у `DetailedSoldierRig` він `null`, тому `_apply_animation_lod()` нічого не робить. Крім того, `_apply_animation_lod` ставить `playback_speed = 0.0` понад 260 м, а не 0.001 як заявлено в документах.

4. **`rifleman_rigged.glb` — не рабіг.** Скелет з 17 кісток додано, але меш не скінений (`parent_set(type="OBJECT")`, без вагів). Ніде не використовується.

5. **Анімації (6–8 кліпів) і billboard impostor не створено.** `create_rifleman_idle.py` ніколи не запускався, вихідного `rifleman_idle.glb` немає. Impostor — лише планування.

6. **QA `qa_v26_rifleman_merged` не пройшов.** Godot зависав без виводу, результату немає. Твердження "PASS" в попередніх звітах не підтверджено.

7. **"Performance measured", "-40% GPU", "-60% CPU" не вимірювалися.** Це оцінки без вимірів.

## Перевірено по промту

| Пункт | Статус |
|---|---|
| Quit-кнопка прихована на iOS | ✅ `GUI/mobile/MobileMenu.gd` (рядки ~988–994). Стартове меню на iOS перенаправляє в мобільне. |
| Аудіо відновлюється після переривання | ✅ код є в `autoloads/Audio.gd` (`_notification`); не перепроходжено в цій сесії |
| Deadzone/smoothing на сенсорних стіках | ✅ код у `TouchControls.gd`; повторний QA не запускався в цій сесії |
| Integrated warhead / FPV корпус (v25) | ✅ код і QA з попередньої сесії; не перезапускались |
| Мобільні GLB Leleka/Furia/Chaklun/Apache | ✅ файли є (LFS), QA bounds попередньо PASS |
| LOD техніки 0–180 / 180–480 / >480 м | ✅ `combat/vehicle.gd` (рядки ~495–506) |
| LOD піхоти 0–125 / >125 proxy / >260 hidden | ✅ `combat/enemy_infantry.gd` `_update_lod()` (порог proxy 125 м, не 95 м як у документах) |
| Rifleman merge 58→1 | ⚠️ файл створено, але в грі не використовується |
| Анімаційні кліпи (6–8) | ❌ не зроблено |
| Billboard impostor для далекого LOD | ❌ не зроблено (лишилась капсула/box proxy) |

## Обмеження перевірки

- Повторно перевірено лише парсинг `enemy_infantry.gd`. Режим `--check-only` не завантажує автолоади (однакова помилка `Global` і в незміненому `vehicle.gd`), тож повноцінна компіляція не підтверджена.
- Повний QA-прогін у цій сесії не робився.

## Рекомендовано

- Запустити повний імпорт Godot і `qa_video_fixes`, `qa_persist2_*`, `qa_mobile_apache` для підтвердження v25.
- Вирішити, чи потрібен merged rifleman взагалі: основний солдат уже скінений і підключений. Якщо так, треба переробити merge для `soldier_detailed_merged.glb`, а не `rifleman.glb`.
- Підключити animation LOD до `DetailedSoldierRig` (передавати `playback_speed` в його `AnimationPlayer`).
- Створювати animation-кліпи і impostor як окремі задачі з власним QA.
