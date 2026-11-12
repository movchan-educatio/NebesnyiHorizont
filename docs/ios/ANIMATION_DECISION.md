# Рішення щодо анімацій мобільної піхоти

## Поточний стан

- Runtime-солдат: `soldier_detailed_merged.glb` (один скінований body mesh).
- `DetailedSoldierRig` керує скелетом процедурно: idle breathing, walk/run
  blend, crouch, aim/scan, fire recoil, reload, hit reaction, death; crouch —
  додаткова поза.
- Мобільний animation LOD: 30/15/0 Hz; чотириракурсний impostor для дальнього
  LOD. Все це вже перевірене `qa_mobile_infantry_lod`.

## Рішення

Gameplay лишається процедурним, але тепер **є 8 окремих AnimationPlayer
кліпів**, згенерованих із тих самих процедурних поз:

- `Assets/combat/animations/soldier_{Idle,Walk,Run,Aim,Fire,Reload,Hit,Death}.tres`
- Генератор: `tools/build_soldier_clips.gd` (детермінований bake поз rig).
- На мобільному ризі створюється `ClipPreview` AnimationPlayer з бібліотекою
  з 8 кліпів; QA `qa_mobile_animation_clips` перевіряє, що всі кліпи
  завантажуються і програються на skeleton без помилок.
- Перехід gameplay на AnimationTree можливий пізніше без зміни асетів.

## Коли повернутися до AnimationTree в бою

1. Порівняти кліпи з процедурною версією на iPhone через AltStore.
2. Підключити AnimationTree із blend між Walk/Aim та одноразовими Fire/Reload.
3. Зберегти мобільний animation LOD і impostor.
4. Додати `qa_mobile_animation_tree` перед заміною.
