# Аудит v25–v26: що справді зроблено

Цей документ виправляє попередні звіти (`FINAL_REPORT_v25_v26.md`, `v26_COMPLETE.md`, `PROGRESS_v25_v26.md`), які містили неперевірені твердження.

## Виявлені проблеми та виправлення

1. **Парсинг `combat/enemy_infantry.gd` був зламаний** (критично). `preload("res://Assets/combat/rifleman_merged.glb")` без `.import` файлу давав "Parse error", і всі сцени з піхотою не завантажувалися. Виправлено: прибрано preload і вибір merged-моделі, повернуто `rifleman.glb`. Також прибрано некоректний `"""` docstring у `_apply_animation_lod`.

2. **Merged rifleman ніколи не використовувався в грі.** Основний солдат — `DetailedSoldierRig` (`soldier_detailed_merged.glb`, скінований), він успішно завантажується на обох платформах. `_create_model()` є лише fallback. Тож твердження "58→1 draw calls на солдата" було хибним. `rifleman_merged.glb` лишився в репозиторії, але не підключений.

3. **Animation LOD не працює для основного солдата.** `_anim` присвоюється лише у fallback-гілці `_build()`; у `DetailedSoldierRig` він `null`, тому `_apply_animation_lod()` нічого не робить. `DetailedSoldierRig._process()` продовжує оновлювати procedural pose щокадру, навіть коли модель далеко/прихована. Крім того, `_apply_animation_lod` ставить `playback_speed = 0.0` понад 260 м, а не 0.001 як заявлено в документах. Сам `DetailedSoldierRig` має procedural idle breathing, walk, crouch, aim, reload, hit та death pose, але GLB не містить AnimationPlayer clips.

4. **`rifleman_rigged.glb` — не рабіг.** Скелет з 17 кісток додано, але меш не скінений (`parent_set(type="OBJECT")`, без вагів). Ніде не використовується.

5. **AnimationPlayer-кліпи не створені**, але в реальному `DetailedSoldierRig` уже є 8 procedural actions: idle breathing, walk, run, aim, fire/recoil, reload, hit і death (додатково crouch). Для mobile під’єднано throttling цих pose updates: 30/15/0 Hz. Раніше це не було під’єднано до runtime.

6. **Billboard був лише планом; тепер реалізований.** Blender запік 4 прозорі ракурси реального runtime soldier-а в `Assets/combat/soldier_impostor_atlas.png`. `enemy_infantry.gd` показує Sprite3D impostor у proxy LOD і вибирає напрямний кадр.

7. **Старий QA rifleman був некоректний**: він перевіряв mobile-вибір неактивного `rifleman_merged.glb` і desktop-гілку. Його замінено на mobile-only QA реальної моделі `soldier_detailed_merged.glb`; новий QA PASS.

8. **"Performance measured", "-40% GPU", "-60% CPU" не вимірювалися.** Це оцінки без вимірів. Підтверджені лише primitive/mesh counts і частоти процедурних pose updates.

## Перевірено по промту

| Пункт | Статус |
|---|---|
| Quit-кнопка прихована на iOS | ✅ `GUI/mobile/MobileMenu.gd` (рядки ~988–994). Стартове меню на iOS перенаправляє в мобільне. |
| Аудіо відновлюється після переривання | ✅ `qa_video_fixes` PASS у mobile-середовищі: resume та збереження intentional mute |
| Deadzone/smoothing на touch та ELRS | ✅ `qa_video_fixes` PASS для touch deadzone, smoothing slider, CRSF throttle. `RadioController` застосовує `Controls.apply_stick_filter` до touch і ELRS yaw/roll/pitch. |
| Integrated warhead / FPV корпус / pusher | ✅ `qa_video_fixes` PASS у mobile-середовищі: payload action на 13/14/15, FPV/model routing, pusher animation |
| Мобільні GLB Leleka/Furia/Chaklun/Apache | ✅ `qa_mobile_apache` PASS; `audit_mobile_assets.py` PASS: bounds delta ≤0.000778 м; mesh/primitive count зменшені |
| LOD техніки 0–180 / 180–480 / >480 м | ✅ `combat/vehicle.gd` (рядки ~495–506) |
| LOD піхоти: near / impostor / hidden | ✅ `0–125 м` detailed, `>125–260 м` 4-view Sprite3D impostor, `>260 м` hidden. Повернення до full LOD нижче 95 м має hysteresis. Mobile-only. |
| Rifleman merge 58→1 | ⚠️ файл створено, але в грі не використовується |
| Runtime soldier mesh reduction | ✅ `soldier_detailed_merged.glb` — 1 mesh/primitive + skin; це фактична модель мобільної піхоти. Окремий `rifleman_merged.glb` не використовується. |
| Animation actions 6–8 | ✅ 8 procedural actions на фактичному ригу; це не baked AnimationPlayer clips. Mobile update cap 30/15/0 Hz. |
| Billboard impostor для далекого LOD | ✅ 4-view atlas generated and wired into mobile proxy LOD. |

## Запущені перевірки (2026-11-12)

- Godot editor import: **exit 0**, у логу немає parse/import errors.
- `qa_video_fixes` з `MOBILE_UI=1`, 1920×1080: **PASS, failures=0**, включно з smoothing assertion.
- `qa_mobile_apache` з `MOBILE_UI=1`: **exit 0**, mobile-модель має 26 nodes, proxy та far-hidden LOD підтверджені.
- `qa_persist2_write` exit 0; `qa_persist2_read`: **PASS**, exit 0.
- `audit_mobile_assets.py`: всі 4 mobile/original pairs PASS; bounds збережені, максимум delta 0.000778 м.
- `qa_mobile_soldier_asset`: **PASS** — runtime detailed rig loaded, one merged body mesh, skeleton present.
- `qa_mobile_infantry_lod`: **PASS** — 30/15/0 Hz, run blend, impostor atlas, far hide, near restore.
- `qa_video_fixes` with additional smoothing assertion: **PASS, failures=0**.
- Visual preview: `docs/ios/v26_mobile_infantry_lod.png`; atlas: `Assets/combat/soldier_impostor_atlas.png`.
- На завершенні headless `qa_video_fixes` є dummy-renderer RID allocation warnings. QA все одно exit 0; це не доводить leak у графічному білді.

## Виправлення під час аудиту

- `enemy_infantry.gd`: LOD proxy and impostor activate only under the mobile runtime condition.
- `DetailedSoldierRig`: procedural pose throttling and run blend are guarded by the mobile runtime condition.

## Рекомендовано

- Провести фізичний iPhone/iPad FPS, CPU/GPU та thermal test; поточні automated checks виконувалися на host desktop у mobile mode.
- Якщо вимога означала саме 6–8 окремих AnimationPlayer-кліпів (а не процедурних дій), такі GLB clips іще треба авторити; поточний runtime використовує процедурні skeletal poses.
