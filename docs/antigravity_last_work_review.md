# Звіт: перевірка останньої роботи Antigravity (mobile-polish сесія)

**Дата перевірки:** 23.11.2026
**Проєкт:** `GodotDrone_LOWSPEC` · **Godot:** 4.7.2 stable
**Перевірив:** OpenCode (незалежний рев'ю + headless-прогін + скріншоти)

> Артефакт `polish_report.md` зі скріншота існував лише в IDE Antigravity — у репозиторії його немає.
> Цей звіт — незалежна перевірка фактичних змін у коді, а не переказ того артефакта.

---

## 1. Що саме було зроблено (остання сесія, не закомічено)

Останні правки (23.11, 08:18–08:28) — це пакет «mobile polish verification»:

| Файл | Зміни | Суть |
|---|---|---|
| `GUI/mobile/MobileMenu.gd` | +31 −1 | Синхронізація мобільних rate-профілів (`radio`/`touch`) у `QuadSettings` при збереженні та при запуску місії; прибрано скидання `custom_rates=false` у combat-training гілці |
| `sceneries/BigLevel.gd` | +45 −41 | Освітлення денних місій піднято (exposure 1.12–1.28, ambient 0.86–1.12, sun 2.6–3.35, brightness 1.06; мобільний буст +0.06); у `_apply_weather()` case 3 додано повторне затемнення для нічних місій (special 5/12) |
| `test/qa_mobile_polish_verification.gd` / `.tscn` | нові | Headless QA-тест на 5 пунктів: rates/controls, lighting, freestyle objects, collisions/bores, audio |

Суміжно в робочому дереві лежать правки попередньої polish-сесії (22.11: combat-звук, колізії,
`qa_polish_*` тести) — вони не є частиною останнього пакета, але headless-перевірка покриває весь проєкт.

## 2. Методи перевірки

1. **Headless parse/import check** (`studio.ps1 godot-check`, Godot 4.7.2): **exit 0**, жодної помилки скриптів.
2. **Прогін нового QA-тесту** `res://test/qa_mobile_polish_verification.tscn` (headless, `MOBILE_UI=1`): **OVERALL: PASS, exit 0**.
3. **Статичний рев'ю** всіх нових/змінених ділянок + їхніх викликів (`_load_profiles`, `_build_rates`, `_launch`, `_tune_map_environment`, `_apply_weather`, `ControlProfile`, `TouchControls`, `QuadSettings`).
4. **Візуальна перевірка** через вбудований `DebugShot` (`SHOT_PATH/SHOT_DELAY/SHOT_CAM_*`), mobile-профіль, Industrial: день і ніч. Скріншоти: `qa_shots/review/industrial_day_mobile.png`, `qa_shots/review/industrial_night_mobile.png`.

## 3. Результати QA-тесту (фактичний прогін)

| Пункт | Результат | Ключові числа |
|---|---|---|
| 1 Rates/Controls | PASS | deadzone 0.08 / smoothing 0.15 persist; radio/touch 850/0.35 збережено; rate 300→900 дає 3.00x; expo 0.75: 187.5→51.1 на півстіку, пік 900 |
| 2 Lighting | PASS | industrial 1.260/1.030/2.950 · wetlands 1.280/1.050/2.900 · airport 1.200/0.960/3.050 · uman 1.200/1.000/3.100 (exposure/ambient/sun) |
| 3 Freestyle objects | PASS | industrial 33≥3 · wetlands 63≥2 · airport 389≥4 · uman 82≥3 |
| 4 Collisions & bores | PASS | труби 3/4 просвіти чисті; паливні цистерни airport пролітаються; альтанки/перголи Uman відкриті |
| 5 Audio | PASS | 13 пресетів, 13 унікальних `audio_kind`, 14 моторних стрімів, propwash looping, 3+ кроки, vehicle-стріми валідні |

Побічні повідомлення прогону (не ігрові баги): RID/ObjectDB leak-попередження при виході
(тест звільняє рівні через `queue_free()` і одразу робить `quit()` — частині об'єктів не вистачає кадру;
 плюс статичні кеші `sfx.gd`/sky), warning `[MobilePropPack] no clear site for warehouse`,
кракозябри кирилиці в консолі (codepage Windows).

## 4. Знайдені проблеми

### B1 · СЕРЕДНЯ · НОВИЙ БАГ · взаємне забруднення rate-профілів radio/touch
`GUI/mobile/MobileMenu.gd:2186–2192` + `:3082–3094`.

Механіка:
- `_launch()` тепер **завжди** пише активний профіль у `QuadSettings` і ставить `custom_rates=true`
  (у touch-режимі — це `touch`-рейти, напр. 500/0.3).
- `_load_profiles()` при кожному відкритті меню, якщо `custom_rates==true`, **перезаписує збережений
  `radio`-профіль значеннями з `QuadSettings`**.

Наслідок (відтворюється): політав у touch → повернувся в меню → вкладка «radio» показує touch-рейти
(500 замість 667) → запуск із радіо-пультом летить на touch-рейтах; натискання «ЗБЕРЕГТИ» ще й
закріплює забруднення в `GameSettings.hud_config`. Сенс двох окремих профілів ламається.

**Рекомендація:** запам'ятовувати джерело останньої синхронізації (напр.
`hud_config["mobile_rate_source"] = active_tab` у `_launch`/save) і в `_load_profiles` оновлювати з
`QuadSettings` лише профіль, що збігається з джерелом; або прибрати дзеркало взагалі.

### B2 · НИЗЬКА-СЕРЕДНЯ · НОВИЙ ПОБІЧНИЙ ЕФЕКТ · мобільне меню назавжди вмикає custom_rates у спільному Quad.cfg
`MobileMenu.gd:3087`, видалене скидання `custom_rates=false` (колишній рядок у combat-training гілці,
біля `:3048`). `Quad.cfg` спільний з десктопним `QuadSettingsMenu`: після мобільного запуску десктоп
побачить «custom rates» з мобільними значеннями, а factory-рейти `DroneCatalog.apply()` більше не
застосовуються (`DroneCatalog.gd:696`). Для суто мобільного пристрою це задумано, для спільного
конфіга — небажано. **Рекомендація:** зберігати мобільні рейти окремим ключем/файлом або відновлювати
прапорець при вході в десктопне меню.

### B3 · НИЗЬКА · НОВИЙ · кнопка збереження синхронізує обрану вкладку, а не активний режим вводу
`MobileMenu.gd:2307–2316`. Зберігаючи «radio» під час touch-польотів, гравець підміняє летючі рейти
до наступного `_launch()`. Дрібна неузгодженість з B1; лікується тим самим «джерелом» або синхронізацією
за `TouchControls.touch_mode`, а не за `_rate_tab`.

### B4 · НИЗЬКА (ВІЗУАЛЬНА) · ПЕРЕДУМОВА, АЛЕ НІЧНИЙ ФІКС НЕПОВНИЙ · гори лишаються білими вночі
`shaders/mountain_backdrop.gdshader:2` — `render_mode unshaded, fog_disabled`. Матеріал ігнорує
освітлення/туман, тому нічний кейс `_apply_weather()` (`BigLevel.gd:4843–4852`) затемнює все, крім
гір: на нічному скріншоті (`qa_shots/review/industrial_night_mobile.png`) хребти — яскраво-білі
силуети на темному небі. Порядок нічного фіксу загалом правильний (спершу денний grade, потім
нічні override; сонце гаситься через `_lightning_light == Sun`, `BigLevel.gd:4769,4830`), але
backdrop треба затемнювати окремо: додати uniform `night_factor`/`energy` у шейдер і виставляти його
в case 3 (або `mmat.set_shader_parameter("color_haze", ...)` під ніч).

### B5 · НИЗЬКА · ПЕРЕДУМОВА · напис «BETAFLIGHT» не відповідає режиму кривої
Екран рейтів підписаний «РЕЙТИ ТА ЕКСПОНЕНТА (BETAFLIGHT)» (`MobileMenu.gd:2202`), але `rate_type`
ніде не встановлюється; за замовчуванням `ControlProfile.gd:17` — `RateType.ACTUAL`. Летюча крива
відрізняється від обіцяної на екрані. Нова синхронізація цей розрив закріплює. **Рекомендація:**
або ставити `rate_type=BETAFLIGHT` разом із профілем, або прибрати напис.

### B6 · НИЗЬКА · ПРОГАЛИНА ТЕСТУ · QA не виконує новий код меню
`test/qa_mobile_polish_verification.gd:153–165` відтворює логіку кнопки збереження **вручну**, замість
того щоб натиснути реальну кнопку / викликати `_launch()`. Тому B1–B3 тестом не ловляться. Крім того,
`MOBILE_UI=1` виставляється в `_ready()` тесту (:49) **після** ініціалізації autoloads, тож
`TouchControls.touch_mode` лишається false і touch/radio-гілка `_launch()` не покрита.
**Рекомендація:** додати сценарій «launch у touch → reopen menu → radio profile не змінився».

### B7 · КОСМЕТИКА
- Leak-попередження при виході QA (див. §3) — дати кадр після `queue_free()` перед `quit()`.
- `[MobilePropPack] no clear site for warehouse` — наявний warning розміщення пропсів.
- Зовнішній PrintWindow-захват вікна Godot дає чорний кадр; для скріншотів використовувати `DebugShot`
  (так зроблено в цьому рев'ю).
- День виглядає читабельним, але небо біля горизонту майже суцільно біле
  (`qa_shots/review/industrial_day_mobile.png`) — легка пересвітка, стилістично прийнятно для phone-daylight.

## 5. Що зроблено добре

- Нічний порядок override правильний; сонце/ fill гасяться; exposure/brightness нічі не «протікають»
  у денний grade і навпаки (`on_quality_applied()` теж зберігає ніч).
- Числа освітлення консистентні на всіх 4 картах, включно з override-ами Airport/Uman.
- QA-тест акуратно ізолює конфіг гравця (tmp-шляхи + повний restore у `_restore()`).
- Жодних runtime-помилок скриптів; headless-check і QA — зелені.

## 6. Виправлення, застосовані за запитом (усі пункти B1–B7)

| Пункт | Що змінено |
|---|---|
| **B1** | `GameSettings.gd` — нові `mobile_rate_source()` / `set_mobile_rate_source()` / `clear_mobile_rate_source()` / `restore_desktop_rates_if_mobile_owned()`. `MobileMenu._load_profiles()` тепер дзеркалить QuadSettings лише у профіль-власника; `_sync_profile_to_quad(tab)` — єдина точка синхронізації. Radio-профіль більше не перезаписується touch-рейтами. |
| **B2** | Перед першим мобільним дзеркалом зберігається знімок desktop-рейтів (`mobile_prev_quad`). При вході в десктопне меню (`MainMenu._ready`, `QuadSettingsMenu._ready`) він відновлюється. Desktop-редагування (`QuadSettingsMenu._mark_custom_rates`, `_on_reset_rates_pressed`, `CalibrationScreen`) забирає володіння назад. |
| **B3** | Кнопка «ЗБЕРЕГТИ РЕЙТИ» викликає той самий `_sync_profile_to_quad(_rate_tab)`, що й `_launch()`, і записує власника — синхронізація стала передбачуваною. |
| **B4** | `shaders/mountain_backdrop.gdshader` — новий `uniform float night_dim`, ALBEDO множиться на нього. `BigLevel._tune_map_environment()` скидає 1.0, а нічний кейс `_apply_weather()` ставить 0.10. Гори вночі тепер темні силуети. |
| **B5** | Напис екрану рейтів тепер відображає фактичний режим кривої з `QuadSettings.rate_type` (ACTUAL RATES / BETAFLIGHT / QUICK). |
| **B6** | QA-тест тепер тисне реальну кнопку збереження (не ре-імплементацію), перевіряє дзеркало touch→radio, відновлення desktop-рейтів і нічний `night_dim`; додано guard на відсутність скрипта меню (parse error більше не маскується PASS). |
| **B7** | Лівки levels звільняються `free()` + зайві кадри перед `quit()`; статичні кеші (sfx, destruction_fx, frontline_terrain, mobile_prop_pack, quality_manager) clearing-хелпери викликаються в кінці тесту; `screen_set_orientation` не викликається в headless; для warehouse додано пошук по дзеркальних кутах і масштабах 100/80/65% — warning більше не з'являється; PrintWindow замінено на вбудований `DebugShot`. |
| **Додатково** | Виправлено реальний баг Antigravity: кнопка збереження викликала неіснуючий `GameSettings.save_config()` → замінено на `save_hud_config()` (профілі насправді не зберігалися). `qa_user_fixes_audit` не виставляв `DRONE_KILLCAM_TEST`, через що 3 Kill-Cam перевірки хибно падали в headless — виправлено. |

## 7. Повторна верифікація після виправлень

- `godot-check --editor --quit`: **exit 0**, SCRIPT ERROR / Parse Error — 0.
- `qa_mobile_polish_verification`: **OVERALL: PASS, exit 0**, warn-лог порожній (0 попереджень розміщення/орієнтації/скриптів), включаючи нові перевірки:
  `touch sync + menu reload leaves radio profile intact`, `save button (radio/touch)`,
  `desktop restore undoes mobile mirror`, `night mountain backdrop dimmed (night_dim 0.10)`.
- Регресійний набір (фінальний прогон після всіх правок): `godot-check` → `CHECK_EXIT=0 errors=0`;
  `qa_polish_controls` → `RESULT PASS failures=0`; `qa_polish_audio` → `PASS (failures=0)`;
  `qa_polish_collisions` → `checks=44 failures=0`; `qa_user_fixes_audit` → `failures=0 ALL USER FIX AUDITS PASSED`
  (усі з `errcount=0`). `git diff --check` — без помилок.
- `qa_polish_shots` / `qa_uman_fix` у headless дають таймаут **очікувано** — обидві сцени явно вимагають
  windowed-рендеру для зчитування пікселів; це не регресія.
- Візуальний контроль: `qa_shots/review/industrial_night_mobile_fixed.png` — гори вночі стали темними
  (були білими до фіксу B4).

## 8. Вердикт

**Усі виявлені помилки виправлено.** Функціональні помилки (B1–B6, плюс зламане збереження профілів)
усунені й покриті тестами; косметика B7 — головним чином виправлена.

Залишкові **не-ігрові** повідомлення при виході headless-тесту (`RID allocations leaked`,
`resources still in use`, `ObjectDB instances leaked`) походять від численних статичних resource-кешів
движка/проєкту (~20 модулів: sfx, terrain, material_upgrader, prop_assets тощо) і не впливають на гру —
повне усунення вимагало б масового переписування кешування поза межами цієї сесії.

**Галерея:** `qa_shots/polish/01…06` (до останнього світлового твіка) +
`qa_shots/review/industrial_day_mobile.png`, `qa_shots/review/industrial_night_mobile.png` (після твіка Antigravity,
до фіксу B4) та `qa_shots/review/industrial_night_mobile_fixed.png` (після фіксу B4).
