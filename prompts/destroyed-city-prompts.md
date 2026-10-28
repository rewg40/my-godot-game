# Промты: разрушенный город (реалистичный 3D-рендер, по одному зданию на ассет)

Один промт = одно здание = один отдельный файл. Чтобы город собирался как пазл,
в **каждый** промт вставляется один и тот же префикс стиля и один и тот же суффикс масштаба.
Камера фиксирована: изометрический 3/4, свет сверху-слева, здания стоят на одной линии земли.

---

## 1. Базовый стилевой префикс (вставляй в начало КАЖДОГО промта)

```
photorealistic 3D render, single isolated destroyed building, PBR materials of
cracked concrete, exposed rusted rebar, broken glass and soot, overcast diffuse
light from upper-left, soft shadows, muted desaturated post-apocalyptic palette
of grey concrete, rust and dust, isometric 3/4 view, no people, no vehicles,
isolated on plain flat light-grey background
```

**Суффикс масштаба (вставляй в конец каждого промта):**

```
consistent scale, ground level aligned at bottom edge, entire building fully
visible, centered composition, square 1:1
```

**Negative prompt:**

```
people, characters, zombies, vehicles, cars, text, watermark, logo, signature,
extra buildings, background scenery, sky gradient, cropped, cut off, multiple
objects, cartoon, illustration, painting, lowres, blurry, oversaturated colors
```

---

## 2. Жилые здания

| # | Файл | Промт (между префиксом и суффиксом) |
|---|------|-------------------------------------|
| 01 | `b01_apartment_5f_torn.png` | `ruined 5-storey Soviet-style apartment block, corner of the facade torn away, exposed floor slabs and hanging rebar, shattered windows, snapped balcony railings` |
| 02 | `b02_apartment_5f_entrance.png` | `damaged 5-storey concrete apartment building, entrance stairwell collapsed into a rubble pile, boarded windows, dark water stains running down the facade` |
| 03 | `b03_tower_9f_burnt.png` | `9-storey prefab panel tower, top three floors burnt out to bare skeleton, blackened soot-covered facade, sagging balcony slabs hanging loose` |
| 04 | `b04_tower_9f_leaning.png` | `9-storey apartment tower leaning about 10 degrees, deep vertical crack through the load-bearing wall, debris spilling from broken balconies` |
| 05 | `b05_house_2f_roof.png` | `two-storey brick house with the roof caved in, broken chimney, weeds growing out of mortar joints, door frame splintered` |
| 06 | `b06_house_burnt.png` | `burnt-out single-family wooden house, charred skeletal frame, collapsed roof beams, ash-covered ground, overgrown dead garden` |
| 07 | `b07_cottage.png` | `small abandoned garden cottage, holes punched in the roof, thick ivy over the walls, broken fence gate, faded peeling paint` |
| 08 | `b08_townhouse.png` | `row of three townhouses with the middle section collapsed into rubble, only two side party walls still standing, thick layer of dust` |
| 09 | `b09_highrise_modern.png` | `ruined modern luxury high-rise, shattered glass curtain wall, twisted steel frame visible, facade panels fallen and stacked at the base` |
| 10 | `b10_dormitory.png` | `long four-storey dormitory block, identical broken windows in a row, faded graffiti, ground-floor doors barricaded with debris` |

## 3. Общественные и коммерческие здания

| # | Файл | Промт |
|---|------|-------|
| 11 | `b11_hospital.png` | `abandoned hospital building, broken red cross sign frame, smashed ambulance bay doors, dark empty ward windows, ivy climbing the walls` |
| 12 | `b12_school.png` | `ruined school building, one wing with a collapsed roof, empty window frames, playground covered in rubble, faded wall mural peeling off` |
| 13 | `b13_church.png` | `damaged stone church, dome punctured and half-collapsed, shattered stained-glass windows, cracked bell tower, overgrown front steps` |
| 14 | `b14_police.png` | `ruined police station, burned-out entrance, broken barred windows, collapsed sandbag barricade, torn flag hanging from a bent pole` |
| 15 | `b15_firestation.png` | `abandoned fire station, empty open garage bays, roof collapsed over the truck bay, soot-covered brick walls` |
| 16 | `b16_supermarket.png` | `looted supermarket building, storefront glass smashed inward, flat roof partially caved in, empty cracked parking apron in front` |
| 17 | `b17_mall.png` | `ruined shopping mall, glass atrium roof caved in, fallen sign frame on the facade, broken escalator visible through the shattered entrance` |
| 18 | `b18_gasstation.png` | `destroyed gas station, canopy collapsed onto the pumps, gutted kiosk, knocked-over fuel dispensers, cracked asphalt, blank corroded sign panels with no letters, faded illegible signage, no brand names, no readable text` |
| 19 | `b19_office_tower.png` | `abandoned glass office tower, facade grid shattered with whole panels missing, rusting steel skeleton exposed at the corner` |
| 20 | `b20_bank.png` | `ruined bank branch, vault wall blown outward, twisted security shutters, cracked marble cladding and debris` |
| 21 | `b21_pharmacy.png` | `small destroyed pharmacy, broken shopfront, looted empty interior visible, faded empty sign box with no letters, cracked floor tiles` |
| 22 | `b22_cafe.png` | `gutted corner cafe, awning collapsed, panoramic windows smashed, overturned terrace furniture buried in debris, blank weathered sign board with no letters` |
| 23 | `b23_cinema.png` | `abandoned cinema, marquee letter board torn and hanging with empty slots, burned-out lobby, roof partially collapsed, ripped empty poster frames` |
| 24 | `b24_hotel.png` | `ruined hotel building, a whole facade section missing, curtains hanging out of broken windows, entrance canopy collapsed` |
| 25 | `b25_factory.png` | `derelict factory hall, corrugated metal walls riddled with holes, skylights broken, rusted pipes along the wall, one short brick chimney` |
| 26 | `b26_warehouse.png` | `abandoned warehouse, dented metal hangar doors buckled, roof section collapsed inward, scattered pallet debris at the gates` |
| 27 | `b27_depot.png` | `ruined bus depot, long row of collapsed garage bays, twisted metal gates, oil-stained cracked concrete yard in front` |
| 28 | `b28_stadium.png` | `crumbling stadium stand, cracked concrete seating tiers, overgrown pitch edge, one floodlight tower collapsed across the tiers` |

## 4. Инфраструктура и доминанты

| # | Файл | Промт |
|---|------|-------|
| 29 | `b29_skyscraper.png` | `ruined skyscraper, top floors collapsed into a jagged crown, twisted steel beams, glass panels hanging loose, no smoke` |
| 30 | `b30_water_tower.png` | `rusted water tower on concrete legs, leaking corroded tank, broken service ladder, faded illegible graffiti, no readable text` |
| 31 | `b31_chimneys.png` | `abandoned power plant chimney pair, cracked concrete stacks, collapsed low buildings at their base, rust and soot staining` |
| 32 | `b32_cooling_tower.png` | `crumbling hyperboloid cooling tower, large hole torn in the shell, moss growing inside, debris at the base` |
| 33 | `b33_tv_tower.png` | `bent TV transmission tower, snapped antenna mast, twisted lattice steelwork, guy wires hanging slack, small concrete base block` |
| 34 | `b34_elevator.png` | `ruined grain elevator silos, one concrete cylinder burst open spilling grain dust, collapsed conveyor gallery leaning against the silos` |
| 35 | `b35_station.png` | `abandoned train station, glass platform roof collapsed, broken station clock with blank face, overgrown tracks at the edge` |
| 36 | `b36_metro.png` | `ruined metro station entrance pavilion, stairwell blocked with rubble, cracked marble cladding, fallen blank sign panels, no readable text` |
| 37 | `b37_parking.png` | `collapsed multi-storey parking garage, tilted concrete slabs, exposed rebar, lowest level crushed, faded painted floor markings` |
| 38 | `b38_autoshop.png` | `wrecked auto repair shop, open bay with a fallen hydraulic lift, scattered tires, dented tin roof, blank weathered sign band with no letters` |
| 39 | `b39_bus_stop.png` | `destroyed bus shelter, glass panels smashed, frame bent, torn blank timetable board, litter around the base` |
| 40 | `b40_crane.png` | `abandoned construction crane, rusted lattice boom, hook and cable hanging loose, standing alone on a small concrete foundation with no building under it` |
| 41 | `b41_unfinished.png` | `unfinished concrete building frame, bare columns and floor slabs, no facade, rusted scaffolding on one side, weeds at the base` |
| 42 | `b42_bridge.png` | `collapsed road bridge, one span broken and hanging into the gap, twisted guardrails, cracked asphalt deck, bridge piers standing on dry ground` |
| 43 | `b43_overpass.png` | `crumbling concrete overpass, a slab section fallen to the ground, exposed rebar, weeds pushing through the cracks of the deck` |
| 44 | `b44_tunnel.png` | `abandoned tunnel portal, cracked concrete arch, retaining wall partially collapsed, dark tunnel mouth half filled with rubble` |
| 45 | `b45_checkpoint.png` | `destroyed military checkpoint, guard booth riddled with bullet holes, collapsed sandbag wall, concrete barriers, sagging barbed wire` |
| 46 | `b46_wall.png` | `long cracked concrete perimeter wall topped with barbed wire, several panels missing leaving gaps, faded illegible graffiti, weeds at the base, no readable text` |

---

## 5. Интерьеры (вставляются в тот же префикс)

Для интерьеров префикс меняется так: вместо `single isolated destroyed building` и
`isolated on plain flat light-grey background` → `single destroyed interior room/space`,
а в суффиксе → `empty room/space, camera at eye level, doorway or opening visible`.

| # | Файл | Промт |
|---|------|-------|
| I01 | `i01_apartment_room.png` | `destroyed apartment living room, ceiling partially collapsed, torn wallpaper, broken window with daylight coming in, overturned furniture, dust` |
| I02 | `i02_stairwell.png` | `ruined apartment stairwell, collapsed concrete steps, exposed rebar, faded illegible graffiti on the walls, debris piled on the landing` |
| I03 | `i03_basement.png` | `dark flooded basement corridor, peeling paint, rusted pipes, cracked walls, water on the floor, single shaft of light from a small window` |
| I04 | `i04_hospital_corridor.png` | `abandoned hospital corridor, overturned gurney, scattered papers, broken ceiling panels, dirty tiled floor, flickering daylight from side windows` |
| I05 | `i05_classroom.png` | `ruined school classroom, broken desks, blackboard cracked and blank with no writing, window glass shattered, plaster fallen from the ceiling` |
| I06 | `i06_subway_platform.png` | `abandoned metro platform, cracked marble walls, torn empty advertising frames, debris on the tracks, dim light from the tunnel mouth` |
| I07 | `i07_lobby.png` | `destroyed office building lobby, collapsed ceiling, reception desk broken in half, shattered glass doors, marble dust on the floor` |
| I08 | `i08_parking_interior.png` | `ruined underground parking level, low cracked concrete ceiling, faded painted floor markings, pillars with peeling paint, puddles on the floor reflecting dim light` |
| I09 | `i09_factory_interior.png` | `derelict factory hall interior, rusted abandoned machinery, broken skylights casting light shafts through dust, concrete floor with oil stains` |
| I10 | `i10_shop_interior.png` | `looted small shop interior, empty shelving units, broken counter, glass shards on the floor, torn blank posters on the walls` |
| I11 | `i11_hotel_room.png` | `ruined hotel room, bed frame broken, outer wall collapsed showing daylight, torn carpet, wardrobe door hanging off its hinges` |
| I12 | `i12_tunnel_interior.png` | `abandoned road tunnel interior, cracked tiled walls, dead lights, collapsed ceiling section ahead, rubble on the asphalt` |

---

## 6. Прогресс генерации ассетов (регенерация после сбоя песочницы)

- [x] b01–b10 — жилые здания
- [ ] b11–b20 — общественные и коммерческие
- [ ] b21–b29 — коммерческие ч.2 + небоскрёб
- [ ] b30–b39 — инфраструктура
- [ ] b40–b46 + i01–i03 — инфраструктура ч.2 и первые интерьеры
- [ ] i04–i12 — интерьеры

## 7. Импорт в Godot (кратко)

1. **Фон.** Рендеры на ровном светло-сером фоне — снимается пакетно (`rembg` или Magic Wand).
2. **2.5D-сцена.** `Sprite3D` с фиксированным поворотом `(-32°, 45°, 0)` под камеру рендеров.
3. **Сетка.** Шаг = ширина «островка» земли, выравнивание по нижней кромке.
4. **Свет сцены.** Пасмурный `WorldEnvironment` + DirectionalLight `-50°/-35°`.
5. **Интерьеры** — отдельные сцены, не смешивать с экстерьером.
6. **Масштаб.** 1024 px ≈ 5 этажей при `pixel_size = 0.015`.

## 8. Правила сборки города

1. Один источник света — `overcast diffuse light from upper-left`.
2. Одна камера — изометрический 3/4 для наружки; интерьеры отдельно.
3. Один масштаб — суффикс `consistent scale, ground level aligned at bottom edge`.
4. Одна палитра — серый бетон, ржавчина, пыль.
5. Фон — `plain flat light-grey background`.
6. Без людей и машин — пропы отдельными ассетами.
7. Именование — `b01_...`, `i01_...` из таблиц.
8. Один сид/модель на серию — главный способ держать стиль.
