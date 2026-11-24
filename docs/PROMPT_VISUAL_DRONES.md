# ПРОМПТ для окремої сесії — ВІЗУАЛ 3 нових дронів

Скопіюй усе нижче як єдиний промт для нового агента/сесії.

```text
ТИ — технічний художник Godot 4 / QA. Репозиторій:
C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC
Працюй ТІЛЬКИ у своїй зоні:
  Assets/enemy_drones/**                 (GLB 5 моделей, у т.ч. 3 нові)
  Assets/Drones/enemy_pack/**            (carbon_checker.png тощо)
  maps/**  — НІ, це інші сесії; не чіпай.
НЕ чіпай: autoloads/DroneCatalog.gd (спільний!), combat/**, GUI/**, test/**,
tools/**, docs/**, project.godot, sceneries/**, maps/**.
Потрібна зміна каталогу/коду — запит, не самовільна правка.

МЕТА: три нові керовані дрони KT-0 Wraith, KT-3 Komar, KT-5 Shmel мають
виглядати ТАК, як у стокових прев'ю пакета. Частина БЧ і гвинти мають бути
видно, гвинти обертаються. Користувач скаржився: "частина дронів біла".

ЕТАЛОН (дивись картинки):
  C:\Users\USER_UA\Desktop\Enemy_FPV_Kamikaze_Drones\previews\
    KT0_Wraith_preview.png, KT0_Wraith_bottom.png
    KT3_Komar_preview.png,  KT3_Komar_bottom.png
    KT5_Shmel_preview.png,  KT5_Shmel_bottom.png
    showcase.png, wraith_angles_sheet.png, angles/*.png
Джерельний генератор (читати):
  source/build_kamikaze_drones.py, особливо carbon_mat() (рядок ~53):
    ShaderNodeTexChecker, Scale 95, Color1 (0.012,0.015,0.018),
    Color2 (0.040,0.047,0.055).

ПОТОЧНИЙ СТАН (що вже зроблено, НЕ переробляй):
- GLB скопійовані в Assets/enemy_drones/ (KT0, KT3, KT5 для гравця;
  KT8, KT12 — ворожі камікадзе, інша задача).
- У каталозі це індекси 13 (wraith), 14 (komar), 15 (shmel) з прапорем
  keep_authored_colors:true; синтетичні audio_kind 14/15/16.
- DroneCatalog.attach_model() і DroneSelectScreen._show_model() НЕ викликають
  GlbMaterialUtils.ensure_pbr() для цих трьох (він робив білі моделі).
- DroneCatalog.apply_pack_colors() накладає Carbon_Weave checker-текстуру
  Assets/Drones/enemy_pack/carbon_checker.png, uv1_scale=48, triplanar.
- DronePropellerSystem._setup_blade_pivots() створює 4 півоти для GLB,
  що мають окремі лопаті без motor_FL/propeller_FL; мета spin_dir/spin_axis.

ПРОБЛЕМИ КОРИСТУВАЧА:
- "нова моделька дрона якась біла";
- "подивися, як вони мають виглядати у стокових папках і як у грі";
- Wraith у прев'ю — темне летюче крило з шаховим вуглецем, у грі був білий.

ВАЖЛИВИЙ ФАКТ: glTF не експортує процедурні вузли Blender. У GLB 0 images,
усі Temperature/Accent材料 мають baseColorFactor, а Carbon_Weave — взагалі
білий без текстури. Тому текстура carbon_checker.png — це не "перемалювання",
а відновлення того, що було в .blend. Не міняй інші кольори без потреби:
Accent_Red, Glow_Cyan, Glow_Red, Warhead_* вже мають авторські значення.

АЛГОРИТМ:
1. Відкрий прев'ю KT0/KT3/KT5 і поточні кадри:
     qa_shots/v30_extra_07_new_drone_wraith.png
     qa_shots/v30_extra_08_new_drone_komar.png
     qa_shots/v30_extra_09_new_drone_shmel.png
     qa_shots/v30_extra_18_hangar_new_drones.png
2. Звір: колір крила/рами, наявність шахового вуглецю, червоні/сині акценти,
  видима БЧ, пропелери, емісія LED, дзеркальність/масштаб.
3. Якщо треба — прав ТІЛЬКИ Assets/enemy_drones/** або
   Assets/Drones/enemy_pack/**. Кольори бери з GLB material factor або з
   build_kamikaze_drones.py, а не "на око".
4. Якщо потрібна зміна DroneCatalog.apply_pack_colors() — НЕ роби сам,
   напиши точний patch у звіті; агент застосує.
5. Переконайся, що гвинти обертаються (DroneCatalog.animate_propellers),
   а не застигли: кадр із польоту + test/qa_prop_animation.tscn.

КРИТЕРІЙ ГОТОВНОСТІ:
- Ангар і політ: три моделі кольором/формою збігаються з прев'ю.
- 4 видимі півоти Prop на кожному дроні; RPM-залежне обертання.
- 0 SCRIPT/SHADER ERROR; qa_v30_all.ps1 і qa_all_drones_flight.tscn зелені.
- Звіт: файл:рядок, скрін до/після, список розбіжностей із прев'ю.

ЗАБОРОНЕНО: git checkout/reset/clean; вбивати Godot; міняти інші 13 дронів;
переписувати звук/каталог/код гри без узгодження.
```
