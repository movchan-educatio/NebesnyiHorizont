# ПРОМПТ для окремої сесії — ВІЗУАЛ карти ЛІС

Скопіюй усе нижче як єдиний промт для нового агента/сесії.

```text
ТИ — технічний художник Godot 4 / QA. Репозиторій:
C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC
Працюй ТІЛЬКИ у своїй зоні:
  maps/lis_forest_freestyle/**   (сцена, GLB, textures, scatter_transforms.json, scripts)
  Assets/Branding/mobile_map_lis_forest_freestyle.png
НЕ чіпай: sceneries/LisLevel.gd, sceneries/BigLevel.gd, autoloads/**, combat/**,
GUI/**, test/**, tools/**, docs/**, project.godot, Maps/oil_rig/**.
Якщо потрібна зміна поза зоною — зупинись і напиши запит, не роби сам.

МЕТА: зробити карту Ліс ВІЗУАЛЬНО ТАКОЮ САМОЮ, як прев'ю джерела,
не ламаючи ігрову логіку (місії, спавни, рух техніки/піхоти працюють і вже
пройдені тестами).

ЕТАЛОН (дивись кадри, не опис):
  C:\Users\USER_UA\Desktop\FPV_Map_Lis\04_previews\
    01_overview_topdown.png
    02_overview_aerial_angle.png
    03..08_fpv_pov_*.png
    09_wireframe_and_collisions.png
    10..15_closeup_*.png
    16..19_fpv_*.png
    20_overview_north_high.png, 21_overview_east.png
Документація: README.md, 05_docs/INTEGRATION_GUIDE.md,
05_docs/INTEGRATION_READINESS.md, 05_docs/FREESTYLE_ELEMENTS_MANIFEST.json.

ПОТОЧНИЙ СТАН (що вже зроблено, НЕ переробляй):
- Асети скопійовані в maps/lis_forest_freestyle/ (181 файл), працюють
  setup_collisions.gd (19 prebuilt + 315 runtime StaticBody3D) і
  scatter_multimesh.gd (83 chunks, 2255 instances).
- Обгортка sceneries/LisLevel.gd/.tscn вже підключає карту до BigLevel:
  фрістайль + усі місії, 8 спавн-зон, авторський маршрут.
- Попередній агент знайшов і виправив 3 баги в scatter_multimesh.gd:
  1) чанки рахувались по Y замість Z;
  2) врахування center (поворот/масштаб) зсувало дерева;
  3) координати з JSON — Blender Z-up, додано конверсію
     (bx,by,bz)_blender -> (bx,bz,-by)_godot, обертання -rz.
  НЕ відкочуй цих виправлень. Перевір, що дерева стоять на землі, а не висять.
- Тест test/qa_v30_maps.gd перевіряє наявність >1500 інстансів рослинності.

ПРОБЛЕМИ, ЯКІ КОРИСТУВАЧ ОПИСАВ:
1. "деякі дерева висять у повітрі" — перевір це знову після своїх правок;
   кожен інстанс має стояти на поверхні terrain.glb, без зависання в повітрі.
2. Карта виглядає як голий піщаний майданчик із поодинокими паличками,
   а в прев'ю — щільний зелений хвойний ліс із річкою, мостами,
   оглядовими вежами, будівлями, купами каменів.
3. Можливо частина MultiMesh відсіюється visibility_range (90–520 м) —
   звіряй з тієї ж висоти/кута, що й прев'ю, перш ніж змінювати щільність.
4. Не додавай нові об'єкти "від себе" — використовуй тільки те, що вже є
   у 01_assets_raw / meshes / FREESTYLE_ELEMENTS_MANIFEST.json.

АЛГОРИТМ:
1. Відкрий прев'ю 02_overview_aerial_angle.png і 01_overview_topdown.png.
2. Зніми поточний кадр: через test/qa_v30_extra_shots.tscn (кадр 01) або
   test/qa_v30_quick_shot.gd (переконайся, що камера на висоті ~150 м,
   як у прев'ю, а не 340 м — інакше MultiMesh відсіюється).
3. Порівняй: розташування/кількість дерев, колір ґрунту й трави, річка,
   наявність мостів/веж/руїн, тіні.
4. Прави ТІЛЬКИ файли своєї зони: параметри VIS_RANGE, масштаби/позиції
   в scatter_multimesh.gd, матеріали текстур (якщо вони білі), саму .tscn.
5. Після кожної зміни — повторний кадр і порівняння з прев'ю. Не кажи
   "схоже", поки не звірив картинки поруч.

КРИТЕРІЙ ГОТОВНОСТІ:
- 21 кадр згенеровано, кадр Лісу візуально збігається з 01/02 прев'ю
  (щільність хвойних, рельєф, річка, відсутність висячих дерев).
- test/qa_v30_maps.tscn: failures=0 (перевірка >1500 інстансів).
- 0 SCRIPT ERROR / SHADER ERROR у логах.
- Звіт: що змінив (файл:рядок), скрін до/після, що НЕ вдалося збігти.

ЗАБОРОНЕНО:
- переписувати BigLevel/LisLevel логіку місій і спавнів;
- міняти Progression/DroneCatalog/комбат;
- робити git checkout/reset/clean (у репозиторії працює інша сесія);
- вбивати процеси Godot, поки йдуть тести.
```
