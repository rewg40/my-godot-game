# Промты: бесшовные PBR-текстуры для города и острова

Текстуры генерируются отдельно от ассетов: **albedo-тайл** на каждую поверхность.
Normal и roughness карты достраиваются скриптом `scripts/make_pbr_maps.py` из яркости
albedo. Дальше автосборка подключает их к материалам Godot.

## 1. Базовый стилевой префикс (в начало КАЖДОГО промта)

```
seamless tileable PBR texture, full-frame top-down orthographic view of a flat
surface, uniform neutral overcast lighting, no directional shadows, no specular
highlights, no perspective, no vignette, muted desaturated post-apocalyptic
palette matching grey concrete rust and dust, high detail, texture fills the
entire frame, edges match perfectly for tiling, square 1:1
```

**Negative:** `objects, props, people, text, watermark, border, frame, visible seam, tiling artifacts, perspective, horizon, sky, vignette, gradient lighting, blur, lowres, cartoon, illustration`

## 2. Промты текстур (albedo)

| # | Файл | Промт |
|---|------|-------|
| t01 | `t01_concrete_cracked.png` | `cracked grey concrete surface with dust, hairline fractures and faint dark stains` |
| t02 | `t02_plaster_wall.png` | `weathered concrete wall plaster with soot streaks, peeling patches and thin cracks` |
| t03 | `t03_rusted_metal.png` | `corroded rusted metal plate surface, orange-brown rust patches over dark grey steel, scratches` |
| t04 | `t04_brick_old.png` | `old damaged brick masonry surface, chipped bricks, cracked grey mortar, soot, irregular brick sizes to hide tiling` |
| t05 | `t05_asphalt_cracked.png` | `cracked worn asphalt surface with potholes, gravel spots and faded patches` |
| t06 | `t06_grass_muted.png` | `muted dry grassland surface with dirt patches, sparse dead weeds, desaturated green, fine even grain to hide tiling` |
| t07 | `t07_snow_frozen.png` | `packed frozen snow surface with frost cracks, wind drifts and grey ice patches` |
| t08 | `t08_sand_desert.png` | `pale desert sand surface with wind ripples and cracked dry clay patches` |
| t09 | `t09_toxic_ground.png` | `dark contaminated soil surface with faint glowing green cracks and acidic stains` |
| t10 | `t10_rubble_gravel.png` | `concrete rubble and gravel debris surface, broken chunks, rebar bits, dust` |

## 3. Деривация PBR-карт

```
python3 scripts/make_pbr_maps.py assets/textures/albedo assets/textures
```

- `normal/*_normal.png` — нормаль из градиента яркости (Sobel, wrap для бесшовности);
- `roughness/*_roughness.png` — шероховатость 0.60–0.95 из инвертированной яркости;
- печать `seam_err` — метрика шва тайла (комфортно ≤ 0.10).

## 4. Правила

1. Только поверхность, без объектов.
2. Равномерный свет, без теней и бликов.
3. Палитра та же, что у города и острова.
4. Шов заметен (seam_err > 0.12) — перегенерировать.
5. Именование `tNN_имя.png` — скрипт сам разложит карты.

## 5. Прогресс

- [ ] t01–t10 — регенерация albedo после сбоя песочницы
- [ ] normal/roughness — прогнать скрипт
- [ ] материалы/.import/стенд — `python3 scripts/build_godot_project.py`
