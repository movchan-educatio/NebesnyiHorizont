# Forge prop layer (mobile maps)

Hand-sculpted war-wear assets rebuilt in Blender 5.2 from the owner's
`3 д асети` catalogue.  They add a third decoration layer on top of the existing
20 small props and 5 large landmarks per frontline map.

## What ships

- `Assets/handcrafted/forge/` — 40 GLB files, 10 per map:
  - Steppe: LEP pylon, collapsed arch, harvester skeleton, breached bunker,
    pillbox bridge, radar revetment, watchtower, broken gully bridge,
    Rozhnovsky tower, concrete slab fort.
  - Village: breached khata, split brick house, holed kolkhoz hangar,
    twin-silo bridge, culture-house portico, brick church belfry, wooden river
    bridge, wrecked fuel canopy, cowbarn slalom, timber windmill.
  - Industrial: breached smokestack, gantry-crane portal, unfinished workshop,
    pipe-rack overpass, breached cooling tower, workshop truss roof, loading
    canopy, hangar-rib tunnel, blast-furnace shell, transformer-yard portal.
  - Wetlands: flooded pumping station, half-sunk barge, wooden trestle
    causeway, flooded bunker stilts, rotting marsh watchtower, flooded power
    pylon, abandoned hydro lock, camo radar mound, marsh boardwalk tower,
    military Bailey truss span.
- Baked albedo textures are embedded in each GLB as Basis Universal; no
  extracted PNG copies are committed.  Each file is one mesh + one material.
- Imported with `gltf/embedded_image_handling=2`; the exported mobile build
  transcodes them through the normal ETC2/ASTC path.

## Placement and budget

- `scripts/util/mobile_prop_pack.gd` owns `FORGE_SITES` and `_place_forge()`.
- Ten objects per map are placed in the open middle ring, after the 20 small
  props and before the five far-edge landmarks.
- Distance LOD: `650 + height * 12` clamped to 650–1200 m.  Shadows stay on.
- Collision:
  - compact solid ruins (≤14 m) get a full box collider;
  - towers, portals, bridges, hangars, breached/ruined shells and other
    fly-through assets get a 2.8 m base plinth only, so the authored openings
    remain passable.
- The half-sunk river barge is placed by the water-site search and sunk 2 m
  below the waterline; QA marks it as floating so the dry-ground scan skips it.
- Runtime cost per map: 10 extra draw calls at close range (one mesh/material
  each), culled past the LOD range.  The whole layer is mobile-gated in
  `frontline_terrain.gd`.

## Verification

`test/qa_mobile_map_views.gd` now checks `forge >= 8`, spacing, ground contact
and colliders, and captures a `*_forge.png` close-up per map.  Headless run:

```powershell
$env:MOBILE_UI = '1'
$env:MOBILE_MAP_SHOT_DIR = 'C:\...\qa_shots\forge'
Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  test/qa_mobile_map_views.tscn -- SteppeLevel
```

Expected pack line: `props=35 forge=10 large=5 spacing_overlaps=0 float_bad=0
collider_bad=0`.

## Known limits

- GLB materials use baked albedo plus constant roughness/metallic; there are
  no normal maps, so the procedural Blender bump does not survive the export.
- Real iPhone frame time with all ten forge objects visible has **not** been
  measured.  Treat desktop/headless numbers as functional checks only.
- Asset provenance still needs the owner's final licence review before public
  distribution; the geometry was rebuilt locally and no external textures were
  added.
