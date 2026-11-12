# Рішення щодо анімацій мобільної піхоти

## Поточний стан

- Runtime-солдат: `soldier_detailed_merged.glb` (один скінований body mesh).
- `DetailedSoldierRig` керує скелетом процедурно: idle breathing, walk/run
  blend, crouch, aim/scan, fire recoil, reload, hit reaction, death; crouch —
  додаткова поза.
- Мобільний animation LOD: 30/15/0 Hz; чотириракурсний impostor для дальнього
  LOD. Все це вже перевірене `qa_mobile_infantry_lod`.

## Рішення

**Окремі AnimationPlayer-кліпи на цій ітерації не створюємо.**

Причини:

1. Скінований rig уже рухається процедурно і проходить QA; baked-кліпи для
   того самого skeleton дублюють pipeline і додають 6–8 бінарних активів, які
   неможливо якісно перевірити в цьому середовищі без візуального review.
2. Перехід на AnimationPlayer вимагає окремого AnimationTree/state machine,
   реекспорту GLB з вагами та повторного вимірювання вартості на iPhone.
3. Поточні процедурні стани дають змогу точніше підлаштовувати поведінку під
   AI (наприклад, walk/run blend керується швидкістю без кроссфейдів).

## Що покращуємо замість кліпів

- Синхронізація ніг/землі, положення зброї, переходи aim/recoil/reload,
  читабельність hit/death — у `detailed_soldier_rig.gd`.
- Детермінований розсинхрон ходьби між бійцями (снайпери більше не марширують
  у ногу).
- Мобільні LOD/impostor залишаються джерелом правди для дальніх юнітів.

## Коли повернутися до AnimationPlayer-кліпів

Якщо власник підтвердить, що процедурні рухи недостатні для магазинного
рівня:

1. Авторити 6–8 кліпів (idle, walk, run, aim, fire, reload, hit, death) для
   того самого skeleton.
2. Експортувати одним GLB із named actions.
3. Підключити через AnimationTree і зберегти мобільний animation LOD.
4. Порівняти фізику з процедурною версією на iPhone через AltStore і додати
   `qa_mobile_animation_clips` перед заміною.

До виконання цих кроків у звітах позначати: процедурні skeletal actions,
а не AnimationPlayer clips.
