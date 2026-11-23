# MASTER PROMPT v28.1 — виправлення останнього коміту + що реально лишилося

> Оновлено після аналізу `ef89ded` (2026-11-19). Попередня редакція радила
> онбординг, реплеї та прогресію — **усе це вже реалізовано**:
> - онбординг: `2569c72` (6 модулів школи, 3-кроковий бойовий тренаж);
> - DVR/реплей: `74608ef` (strike DVR replay), Ghost — `drone/Ghost.gd`;
> - прогресія: `Global.gd` — `career_xp`, `PILOT_RANKS`, `get_daily_challenge()`,
>   `mark_daily_challenge_completed()`, streak, stars/best_time;
> - App Store compliance: `34bffb0` (PrivacyInfo.xcprivacy, ITMS-91053,
>   ITSAppUsesNonExemptEncryption, UIRequiresFullScreen).
> Не переробляй це. Нижче — реальні NEXT STEPS.

## 1. ПРОМТ (копіювати звідси)

```text
ТИ — senior Godot/iOS інженер + QA lead. Проєкт:
C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC (Godot 4.6.1, GDScript).
Працюй тільки в цьому репозиторії. Перед змінами — бекап файлів.

КОНТЕКСТ ОСТАННЬОГО КОМІТУ (ef89ded)
1. combat/bomb_sight.gd: CCIP-розрахунок перенесено з 20 Гц на КОЖЕН кадр,
   крок інтегрування 0.035 → 0.05 с.
2. combat/vehicle.gd: додано _structure_ceiling() — повітряний ШІ над великою
   спорудою тримається >= top+12 м, підйом миттєвий (snap), щоб не перетинав
   арковий дах.
3. test/qa_structure_avoidance.gd: додано перевірку min y гелікоптера над залом.

ЖОРСТКІ ОБМЕЖЕННЯ
- Не ламати 3 графічні пресети, посадку, паузу, ELRS/сенсорний ввід.
- Усі наявні QA мають лишатися зеленими.
- offline-first, без реклами/IAP/акаунта.

P0 — ВИПРАВИТИ САМЕ ЦЕЙ КОМІТ (реальні дефекти)

1. МЕРТВА ЕКСТРАПОЛЯЦІЯ В CCIP.
   _process(): _solve_elapsed += delta → _recompute() → _update_pipper().
   Але _recompute() щоразу обнуляє _solve_elapsed (рядок 116), тому в
   _update_pipper() вираз `vel * minf(_solve_elapsed, 0.2)` завжди = 0.
   Екстраполяція нічого не робить, а розрахунок іде кожен кадр.
   Змінна _tick (рядок 26) взагалі не використовується.
   ВИПРАВИТИ (обрати одне):
   а) рекомендовано для iOS: повернути такт 30 Гц (на desktop — кожен кадр),
      щоб _solve_elapsed реально накопичувався й екстраполяція працювала;
   б) або лишити solve кожен кадр і ВИДАЛИТИ _tick, _solve_elapsed та
      екстраполяційний доданок.
   Оновити застарілі коментарі: bomb_sight.gd:63-65 («without paying for a
   solve each frame»), :113-114 («0.035 s ... 20 Hz solve»),
   ballistics.gd:108-110 (ті самі 20 Hz / 0.035). Зараз там брехня.

2. ВАРТІСТЬ БАЛІСТИКИ НА iPhone.
   simulate() — до 700 ітерацій, кожна викликає height_at() (процедурний
   терен). Було 20 solve/с → тепер ~58 solve/с на iOS = ~3x CPU.
   - Додати headless QA, що міряє час _recompute() і падає при >2 мс.
   - Порівняти accuracy 0.035 vs 0.05 на всіх типах БЧ (не тільки 82mm).
   - Зафіксувати бюджет у docs/ios/REPORT_v28.md.

3. SNAP-ТЕЛЕПОРТ ВИСОТИ АІ.
   `global_position.y = ceiling` — різкий стрибок при перетині межі зони
   (+10 м margin). Замінити на випереджальний набір висоти: дивитися на
   позицію через 1–2 с руху й починати набір ДО входу у footprint.
   Лерп лишати тільки якщо він встигає очистити дах.

4. ДІРИ В qa_structure_avoidance.gd.
   - min_heli_y_over_hall починається з 1.0e9: якщо ШІ облетів зал, перевірка
     «climbs above roof» проходить ПОРОЖНЬО. Додати assert sample_count >= N.
   - Тестується лише Industrial і exclusions[0]. Параметризувати на всі 4 карти
     та всі зони; додати такий самий min-y assert для SHAHED (зараз тільки heli).
   - Невелике: structure_exclusions() викликається 3x за такт на машину
     (vehicle.gd:1864,1916,1942) — закешувати локально.

P1 — ЩО РЕАЛЬНО ЗАЛИШИЛОСЯ НА РІВНІ ПРОДУКТУ

5. ПРОФІЛЮВАННЯ НА РЕАЛЬНОМУ iPhone (головний ризик проєкту, ще не зроблено).
   Xcode Instruments / Metal System Trace на iPhone 14 + старшому (11/SE):
   draw calls, GPU/CPU frame time, thermals, пам'ять, 10+ хв польоту.
   Особливо після п.1–2. Без цього всі графічні рішення — вгадування.

6. TESTFLIGHT ЗАМІСТЬ SIDELOAD.
   Compliance вже є (`34bffb0`), лістинг є (`docs/APPSTORE_LISTING.md`).
   Наступний крок: closed beta 20–50 пілотів → збір фідбеку → App Store.
   Sideload (7 днів) лишати як резерв, не як основний канал.

7. ДРІБНИЦІ, ЯКІ ВАРТО ЗАКРИТИ
   - Known QA noise (`docs/WOW_MOBILE_AND_EN_AUDIT.md:82`): помилки при
     ізольованому інстанціюванні HUDConfig.tscn / HelpPage.tscn.
   - Асинхронні рекорди: експорт/імпорт реплею текстовим кодом (без сервера).

ФОРМАТ ВІДПОВІДІ
1. Що виправлено з P0 (з посиланнями на рядки).
2. Список змінених файлів.
3. Результати QA (імена тестів, failures).
4. Вимір часу _recompute() до/після.
5. Топ-3 ризики.
```

## 2. Команди перевірки

```powershell
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . res://test/qa_structure_avoidance.tscn
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . res://test/qa_bomb_ccip.tscn
& .\Godot_v4.6.1-stable_win64_console.exe --headless --path . --editor --quit
```

## 3. Критерій готовності наступного коміту

| Що | Було | Має бути |
|---|---|---|
| CCIP | solve щокадру + мертва екстраполяція | або чесний 30 Гц з екстраполяцією, або чистий щокадр |
| Коментарі | 20 Hz / 0.035 (застарілі) | відповідають коду |
| Час solve | не мірявся | <2 мс, зафіксовано в QA |
| Політ над спорудою | snap-стрибок | плавний випереджальний набір |
| QA structure | 1 карта, 1 зона, 1 тип | 4 карти, всі зони, heli+shahed, sample_count |
| Профіль iPhone | немає | Instruments-звіт у docs/ios/ |
| Дистрибуція | sideload 7 днів | TestFlight beta |
