# ПРОМПТ для окремої сесії — ВІЗУАЛ карти НАФТОВА ПЛАТФОРМА

Скопіюй усе нижче як єдиний промт для нового агента/сесії.

```text
ТИ — технічний художник Godot 4 / QA. Репозиторій:
C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC
Працюй ТІЛЬКИ у своїй зоні:
  maps/oil_rig/**   (oil_rig_map.tscn, assets/*.glb, textures/**, shaders/**,
                     materials/**, scripts/**, instancing_data.json)
  Assets/Branding/mobile_map_oilrig.png
НЕ чіпай: sceneries/OilRigLevel.gd (спільний!), sceneries/BigLevel.gd,
autoloads/**, combat/**, GUI/**, test/**, tools/**, docs/**, project.godot,
maps/lis_forest_freestyle/**. Потрібна зміна поза зоною — запит, не правка.

МЕТА: платформа у грі має виглядати 1:1 як прев'ю джерела. Не "приємно
схоже", а той самий вигляд: кольори, матеріали, вода, світло, відсутність
"куполів" і висячих елементів. Користувач прямо сказав: Нічого не
перемальовуй і не змінюй — бери вигляд із джерельних файлів.

ЕТАЛОН (HEAD-OF-LINE, дивись картинки):
  C:\Users\USER_UA\Desktop\OilRigMap_Prototype\renders\
    01_overview_4_platforms.png
    02_top_down_plan.png
    03_single_platform_closeup.png
    04_interior_hangar_fpv.png
    05_moonpool_dive_shaft.png
    06_under_deck_arches_water.png
    07_skybridge_corridor.png
    08_derrick_dive_view.png
    09_helipad_and_cranes.png
    10_central_lagoon_tanker.png
Джерельні інструкції (читати повністю):
  INTEGRATION_README.md, BUILD_REPORT.md, TEXTURE_LICENSES.md,
  collision_report.json, godot_package/maps/oil_rig/scripts/oil_rig_materials.gd,
  godot_package/maps/oil_rig/shaders/ocean_water.gdshader,
  godot_package/maps/oil_rig/materials/*.tres,
  scripts/01_build_scene.py, scripts/02_generate_godot.py,
  blender_src/oil_rig_complex.blend.

ПОТОЧНИЙ СТАН (вже зроблено іншою сесією, НЕ переробляй):
- Асети скопійовані без змін у maps/oil_rig/ (33 файли; шляхи res://maps/oil_rig/).
- Обгортка sceneries/OilRigLevel.gd уже:
  * застосовує atlas-матеріали вручну на 86 поверхонь (source helper
    oil_rig_materials.gd НЕ підвішений до жодного вузла у вихідній сцені!);
  * вимикає height-fog BigLevel (він був на y≈411 і топив океан у сірому);
  * ставить flat blue bg = Color(0.53,0.70,0.86) як у source Environment_env;
  * прибирає 24 неонових кільця BigLevel (у джерелі neon rings removed,
    є тільки 49 невидимих Marker3D у FPVGates);
  * ховає fallback Ground MeshInstance3D BigLevel;
  * компенсує кольори океану уніформами (forward_plus на ПК інакше дає сірий).
- GLB експортовані БЕЗ текстур, усі PBR-атласи лежать у textures/
  і накладаються через materials/*.tres. Це не баг, а задум джерела.

ПРОБЛЕМИ КОРИСТУВАЧА (цитуємо):
- "матеріали платформи все ще білі";
- "над картою якийсь наче купол";
- "куполи висять у повітрі";
- "карта взагалі не такая, як у превю";
- "нічого там не перемальовуй і не змінюй".

ПРИЧИНИ, ВЖЕ ВСТАНОВЛЕНІ (не шукай заново):
1. Білі модулі — атласні .tres не застосовувалися (зараз застосовуються).
2. Сірий "купол" — height-fog BigLevel на чужому масштабі (зараз вимкнено).
3. Неонові кільця — додані BigLevel, у джерелі їх немає (зараз вимкнено).
4. Океан смугастий/сірий у forward_plus 4.6.1; джерело — mobile 4.7.2.
   На iOS використовується mobile (rendering_method.mobile="mobile") — це
   правильно. На цьому ПК mobile-рендер зависає, тому зйомка йде у
   forward_plus. Піксельний збіг на iOS треба перевіряти на пристрої.

АЛГОРИТМ:
1. Відкрий renders/01_overview_4_platforms.png і 03_single_platform_closeup.png.
2. Зніми поточний кадр: maps/oil_rig/oil_rig_map.tscn напряму (без BigLevel)
   і через sceneries/OilRigLevel.tscn; порівняй обидва з прев'ю.
3. Перевір у себе в зоні:
   - всі 6 atlas-текстур імпортовані без помилок, NormalGL (не DirectX);
   - flame.gdshader і ocean_water.gdshader компілюються (0 SHADER ERROR);
   - instancing_data.json / MultiMesh rail posts заповнюються (375+ постів);
   - 49 Marker3D fpv_gates і 5 map_spawn_points на місці;
   - WaterKillZone на рівні моря;
   - 937 колайдерів group map_colliders, без конвекс-халів на порожнинах.
4. Якщо щось не сходиться — прави ТІЛЬКИ файли maps/oil_rig/**.
   Не додавай нових об'єктів і не змінюй кольори "від себе": бери з .tres
   та textures/ джерела.
5. Після кожної правки — новий кадр із тієї ж камери, що й у прев'ю.
   Не кажи "готово", поки не звірив картинки поруч із renders/*.png.

КРИТЕРІЙ ГОТОВНОСТІ:
- Кадри 01/03/09 джерела і наші v30_extra_11/12/13/14 збігаються за
  кольором металу/контейнерів, кольором води, відсутністю сірого купола й кілець.
- 0 SCRIPT/SHADER/RESOURCE ERROR у headless --editor --quit.
- qa_v30_maps.tscn і qa_v30_all.ps1 лишаються зеленими.
- Звіт: файл:рядок, скрін до/після, чесний список розбіжностей.

ЗАБОРОНЕНО: git checkout/reset/clean; вбивати процеси Godot під час тестів;
міняти BigLevel/OilRigLevel/код гри; вигадувати нові матеріали замість
джерельних.
```
