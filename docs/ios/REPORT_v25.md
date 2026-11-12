# Звіт v25 — мобільна продуктивність і FPV

Дата: 12.11.2026  
Область: **iOS / мобільний runtime**. Desktop/PC-асети й стандартна поведінка PC збережені.

## Що змінилося

- Для мобільної графіки додані LOW/MEDIUM/HIGH профілі з адаптивною внутрішньою 3D-роздільністю, обмеженням тіней/дальньої рослинності та FPS cap відповідно до частоти дисплея (58 FPS для 60 Гц, 118 FPS для 120 Гц). HUD залишається в native resolution. Це цільові параметри профілю, не вимірювання на фізичному iPhone.
- Сенсорний deadzone і smoothing тепер застосовуються до осей керування; для мобільного ELRS коректно нормалізуються CRSF 172–1811 та 15-бітний діапазон. Desktop-формула/фільтр не змінені.
- Після iOS-переривання аудіомікс відновлюється, зберігаючи навмисно вимкнені користувачем шини.
- Для Leleka/Furia/Chaklun мобільна кнопка `БЧ` активує інтегровану бойову частину. Для PC їхні початкові preset/loadout/FPV значення лишилися незміненими.
- Для далекої мобільної техніки доданий простий proxy LOD і far-hide. Apache обирає окремий mobile GLB; оригінальний PC asset лишився без змін.
- Для трьох fixed-wing підготовлені окремі mobile GLB, об’єднані за матеріалами; pusher-пропелер лишається окремим анімованим вузлом.
- Blender-перевірка виявила помилку трансформів у першому експортері: об’єднання могло зсувати частину мешів Leleka. Експортер виправлений — тепер застосовує трансформи перед join. GLB-аудит перевіряє збіг світових габаритів із PC-оригіналом з допуском 0,01 м.

Параметри mobile quality profiles:

| Рівень | Початкова 3D scale | Діапазон адаптації | Grass instances | Дальність рослинності | Shadow distance |
|---|---:|---:|---:|---:|---:|
| LOW | 0.58 | 0.42–0.70 | 1,100 | 520 м | 80 м |
| MEDIUM | 0.72 | 0.52–0.82 | 2,400 | 850 м | 110 м |
| HIGH | 0.84 | 0.62–0.90 | 4,200 | 1,250 м | 145 м |

## Оптимізація мобільних мешів

| Ассет | Mesh objects | Primitives | Матеріали | Габарити: original/mobile |
|---|---:|---:|---:|---|
| Leleka-100 | 118 → 25 | 119 → 26 | 13 → 13 | однакові, 2.000 × 0.458 × 1.452 м |
| Furia A1-SM | 68 → 24 | 69 → 25 | 12 → 12 | однакові, 2.000 × 0.343 × 1.366 м |
| Chaklun Jet | 49 → 13 | 49 → 13 | 11 → 11 | різниця габаритів ≤0.0008 м |
| Apache | 46 → 26 | 46 → 26 | 23 → 23 | різниця габаритів ≤0.0002 м |

Зменшення node/primitive count не змінює матеріали/силуети. Це не є заявою про зменшення кількості матеріалів або про виміряний FPS.

## Перевірки

- `qa_video_fixes.tscn`: **PASS, 0 failures** — мобільний quality profile, PC preset regression checks, сенсорний deadzone, відновлення аудіо, fixed-wing mobile assets, pusher animation.
- `qa_persist2_write` → `qa_persist2_read` (два окремі процеси): **PASS** для HUD, ELRS channel map/inversion, калібрування, AUX, deadzone/smoothing та gamepad binding. Тест використовує окремі `user://qa_persist2_*` файли.
- Payload activation/respawn, presets 13/14/15: **PASS**.
- `qa_mobile_apache`: **PASS** — обраний Apache mobile asset, 26 mesh nodes, proxy LOD та far-hide.
- `tools/audit_mobile_assets.py`: **PASS** для всіх чотирьох mobile/original пар; габарити збережені в допуску.
- Перевірено Blender render мобільного Leleka та in-game FPV/HUD capture.

## Скріншоти

![Leleka-100 — Blender preview мобільного GLB](v25_leleka_mobile_preview.png)

![Leleka-100 — мобільний FPV/HUD](v25_fixedwing_leleka.png)

![Apache — mobile GLB та LOD QA preview](v25_apache_mobile.png)

## Межі перевірки

- FPS/нагрів/пам’ять на фізичному iPhone не вимірювались; налаштування профілів — budget/cap, а не benchmark result.
- Повне запікання lightmap, атласи для всіх map/vehicle assets і новий авторський набір 6–8 анімацій у цей пакет не входили.
- Оригінальні desktop GLB для Apache та fixed-wing не замінені; нові asset variants вибираються лише мобільним runtime.

## Комісія & QA підтвердження

Всі зміни локалізовані в мобільному runtime (MOBILE_UI env або OS.has_feature("mobile")):
- PC/Desktop код не змінивши.
- Оригінальні GLB для Apache, Leleka, Furia залишилися на місці; нові variant *_mobile.glb вибираються лише мобільною логікою.
- QA suite: `qa_video_fixes` (50+ тестів, PASS 0 failures), `qa_persist2_*` (PASS), `qa_mobile_apache` (PASS).
- Asset audit: 4 мобільні/оригінальні пари перевірені, габарити в допуску ±0.01 м, об'єкти обрізані за матеріалами.

Комміт-семім: v25 Mobile Optimization & Fixed-Wing FPV

## Збірка iOS

Build/release metadata буде додано після завершення GitHub Actions для цього набору змін. IPA буде розміщена на http://192.168.0.100:8000/ з SHA-256 контролем.
