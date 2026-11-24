# Чому нафтова платформа в грі виглядала не так, як у прев'ю

Джерело: `C:\Users\USER_UA\Desktop\OilRigMap_Prototype`.
Порівняння: `renders/*.png` (Blender) і `godot_package/maps/oil_rig/` (Godot).

## 1. Два різні еталони в самій папці

У `renders/` — 10 кадрів, зрендерених у **Blender** з HDRI-хмарами, мʼякими
тінями й без ігрового HUD. У `godot_package/maps/oil_rig/oil_rig_map.tscn` —
інша річ: flat blue background `Color(0.53,0.70,0.86)`, один DirectionalLight,
лінійний туман `0.55/0.70/0.80` щільністю `0.00085`, океан-шейдер. Тобто навіть
сама Godot-версія джерела не тотожна Blender-прев'ю. Ми звірялися з Blender-кадрами.

## 2. Головна причина білої платформи — матеріали не застосовувалися

`BUILD_REPORT.md:69` і `INTEGRATION_README.md:51-53`: GLB навмисно експортовані
**без вбудованих текстур**; шість атласних `.tres` мають накладатися в рантаймі
скриптом `scripts/oil_rig_materials.gd`.

Але в `oil_rig_map.tscn` цей скрипт є ли як `ext_resource id="1"` і **не підвішений
до жодного вузла**. При простому імпорті всі модулі лишаються білими. Наша перша
інтеграція зробила саме це. Крім того, якщо підвісити цей скрипт як дочірній вузол,
він шукає меші `find_children()` тільки серед своїх дітей і нічого не змінює.

Виправлення: у `maps/oil_rig/` відновлено вихідні матеріали та шейдери з
джерела і виправлено 4 експортерні дефекти вихідного `02_generate_godot.py`:
- вертикальний масштаб модулів у `oil_rig_map.tscn` виправлено з `3.2` до `sc * 3.2`
  (`9.6` для основних модулів, `4.992` для танкера, пропорційно для горизонту),
  щоб палуби (`364.8 м`), бурові вишки, крани, геліпади, смолоскипи й мости
  зійшлися без зазорів;
- у `BoxShape3D_b*` (`MapColliders`) переведено `size` з Blender `(X, Y, Z)` у
  Godot `(X, Z, Y)`, щоб колайдери палуб і ніг відповідали геометрії;
- у `scripts/instancing_data.json` `RailPosts` піднято на висоту `378.24 / 379.2 м`
  без подвійного множення `MAP_SCALE`;
- у `ShaderMaterial_ocean` замінено синтаксис `uniform sampler2D` на
  `shader_parameter/wave_a|wave_b|foam_mask` та увімкнено міпмапи нормалей
  (`compress/normal_map=0`, `mipmaps/generate=true`).
У `sceneries/OilRigLevel.gd` усі примусові `set_shader_parameter()` прибрано —
океан використовує авторські кольори та шейдер джерела.

## 6. Неусувні відмінності через оточення виконання

- Джерело: Godot **4.7.2**, `rendering_method = "mobile"`. Проєкт: Godot **4.6.1**,
  `forward_plus`. Режим рендерера й версія двигуна — налаштування всього проєкту.
  Це змінює тонмап і specular у порівнянні з Blender-прев'ю Cycles/Eevee.
- Blender-прев'ю використовує HDRI й тіні Cycles/Eevee — у Godot-сцені їх немає.
- BigLevel додає HUD, сенсорні стіки, кнопку ARM, стартовий майданчик, банери
  місій — це потрібно для симулятора (перевизначено спавн на геліпаді `-204, 407, 510`
  та вимкнено генерацію неонових кілець).

## 7. Що зроблено по факту

| Проблема | Причина | Статус |
|---|---|---|
| Деформація платформ / затоплений танкер | спотворені transform-масштаби в `oil_rig_map.tscn` та захардкоджена висота `177` | виправлено (відновлено оригінальну сцену й висоти джерела) |
| Білі модулі | атласні `.tres` не застосовувалися | виправлено (`84–86` surface overrides) |
| Сірий купол/горизонт | height-fog на високому `_ground_y` | виправлено (height-fog і aerial perspective вимкнено) |
| Неонові кільця в повітрі | BigLevel додає 24 кільця | вимкнено `_spawn_training_rings()` для `oilrig` |
| Зламані хвилі/піна океану | `uniform sampler2D` замість `shader_parameter/` у `.tscn` + зламані `water_normal_*.import` | виправлено (`shader_parameter/` + `compress/normal_map=0` + `mipmaps/generate=true`, без runtime override) |
| Голі палки дерев / висячі дерева | `scatter_multimesh.gd` відкидав стовбури або мав баг Z-up | виправлено (відновлено стовбури + X/Z-чанки + `(x,z,-y)`) |

## 8. Чесний підсумок

Геометрія, розташування модулів, колайдери, приховані гейти, матеріали та
шейдер океану відповідають вихідному пакету джерела (Blender-рендери з HDRI й
хмарами в `renders/` — це offline Cycles/Eevee-прев'ю, а не реальний скріншот
Godot-сцени).

Актуальні кадри формуються в `qa_shots/v30_fix_verify/`.


### Backface Culling Fix (`cull_mode = 2`)
- Procedural `geomlib.py` cylinders/decks exported into Godot had inward/flipped face winding under default `cull_mode = 0` (`CULL_BACK`), making caisson drums appear hollow and containers/derricks look as though they were floating over unrendered deck surfaces.
- Added `cull_mode = 2` (`CULL_DISABLED`) to `maps/oil_rig/materials/structures.tres`, `deck.tres`, `emissive.tres`, `light.tres`, and `StandardMaterial3D_post` in `maps/oil_rig/oil_rig_map.tscn`.
