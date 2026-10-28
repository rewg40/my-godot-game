# Промты: пустой остров с 4 биомами (реалистичный 3D, та же стилевая система, что и город)

Остров разбит на **4 сектора-«дольки»** одного круглого острова: трава, снег, пустыня,
радиоактивная зона. У каждого сектора два прямых вертикальных среза и одна дуга берега —
в Godot они собираются в круглый остров как пирог 2×2. Плюс промт целого острова-референса.

## 1. Базовый стилевой префикс (в начало КАЖДОГО промта)

```
photorealistic 3D render, single isolated empty island terrain piece, PBR ground
materials, overcast diffuse light from upper-left, soft shadows, muted
desaturated palette, isometric 3/4 top-down view, no buildings, no structures,
no people, no animals, no vehicles, no text, isolated on plain flat light-grey
background
```

**Суффикс:** `consistent scale, sea level aligned at bottom edge, entire piece fully visible, centered composition, square 1:1`

**Negative:** `buildings, structures, ruins, people, characters, animals, vehicles, boats, text, watermark, logo, signature, cropped, cut off, multiple objects, cartoon, illustration, painting, lowres, blurry, oversaturated colors`

## 2. Промты

| # | Файл | Промт |
|---|------|-------|
| 00 | `isl00_island_full.png` | `round empty island divided into four equal quadrant biomes with clear blending seams: muted-green grassland, snow-covered frozen ground, pale sand desert with cracked clay, and toxic radioactive zone with glowing green cracks and puddles; rocky coastline ring with shallow water edge` |
| 01 | `isl01_sector_grass.png` | `quarter sector wedge of a round empty island, two straight vertical cut edges and one outer coastline arc; surface is muted-green grassland with gentle hills, dry shrubs and dirt patches` |
| 02 | `isl02_sector_snow.png` | `quarter sector wedge of a round empty island, two straight vertical cut edges and one outer coastline arc; surface is snow-covered frozen ground with frost cracks, bare grey rock outcrops and drifted snow` |
| 03 | `isl03_sector_desert.png` | `quarter sector wedge of a round empty island, two straight vertical cut edges and one outer coastline arc; surface is pale sand dunes, cracked dry clay flats, scattered stones and dead bushes` |
| 04 | `isl04_sector_radioactive.png` | `quarter sector wedge of a round empty island, two straight vertical cut edges and one outer coastline arc; surface is contaminated toxic ground with glowing green cracks, acidic puddles, dead grey grass and faint green mist` |

## 3. Правила сборки острова

1. Один радиус берега и высота срезов у всех долек.
2. Один уровень моря (суффикс обязателен).
3. Один свет — как у городской серии.
4. Стыки: прямые срезы вплотную, сетка 2×2.
5. Пусто = пусто: город садится сверху отдельными ассетами.
6. Палитра приглушённая; кислотный акцент только у радиоактивной зоны.

## 4. Прогресс

- [ ] isl00–isl04 — регенерация после сбоя песочницы
