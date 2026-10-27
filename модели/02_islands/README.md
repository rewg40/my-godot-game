# 02_islands — Острова

**Сюда кладём:** готовые острова целиком, основания островов, береговую линию,
воду вокруг острова, реки, водопады, атоллы, рифы, отмели, водные растения.

**Сюда не кладём:** обычные тайлы земли без воды (→ `01_terrain_ground/`),
отдельные валуны на суше (→ `03_cliffs_rocks/`), корабли и лодки
(→ `06_props_decor/`), причалы и доки (→ `05_buildings_structures/`).

| Префикс | Источник | Примеры |
|---|---|---|
| `hex_` | Kenney Hexagon Kit | `hex_water-island.glb` — остров в воде, `hex_water.glb`, `hex_water-rocks.glb`, `hex_river-straight.glb` |
| `nat_` | Kenney Nature Kit | `nat_ground_riverBend.glb`, `nat_ground_riverCross.glb`, `nat_ground_riverSide.glb`, `nat_ground_riverRocks.glb` |
| `td_` | Kenney Tower Defense Kit | `td_tile-river-corner.glb`, `td_tile-river-waterfall.glb`, `td_snow-tile-river-straight.glb` |
| `pir_` | Kenney Pirate Kit | `pir_hole.glb` |
| `kay_` | KayKit Medieval Hexagon | `kay_hex_coast_A.glb`, `kay_hex_water.glb`, `kay_hex_river_D.glb`, `kay_waterlily_A.glb`, `kay_waterplant_C.glb` |
| `gen_` | сгенерировано | см. ниже |

## Берега и реки KayKit: две версии каждой модели

У пака KayKit каждый тайл берега и реки есть **с водой** и **без воды**
(суффикс `_waterless`):

```
kay_hex_coast_A.glb            kay_hex_coast_A_waterless.glb
kay_hex_river_D.glb            kay_hex_river_D_waterless.glb
```

Версия `_waterless` — геометрия берега без водной поверхности: берите её, если
вода в игре своя (плоскость, шейдер, анимация, глубина), иначе вода будет
нарисована дважды и начнёт мерцать. Версия с водой удобнее для быстрых сцен и
прототипов. Всего в категории 46 моделей KayKit — 23 пары «с водой / без воды».

## Сгенерированные острова

| Файл | Что это | Ш×В×Г |
|---|---|---|
| `gen_island_a.glb` | Остров с пляжем и скалистым центром | 48.0 × 6.2 × 48.0 м |
| `gen_island_b.glb` | Вулканический остров с кратером | 40.0 × 7.0 × 40.0 м |
| `gen_atoll.glb` | Атолл: кольцо рифа вокруг лагуны | 56.0 × 3.9 × 56.0 м |
| `gen_rock_islet.glb` | Маленький скалистый островок | 20.0 × 6.0 × 20.0 м |
| `gen_island_cluster.glb` | Архипелаг из трёх островов на одной плите | 107.1 × 6.2 × 75.1 м |

У всех сгенерированных островов **уровень моря `y = 0`**, под водой — «юбка»
глубиной 2 м и плоское дно, поэтому стык с плоскостью воды не просвечивает.
Дно лагуны у атолла намеренно ниже `y = 0`, чтобы под водой была чаша.

Чтобы сделать свой остров, добавьте высотную функцию в
`../scripts/generate_islands.py` по образцу `height_island()` и допишите
строку в список `jobs`.

Модели: **97**. Полный список — в `../inventory.json`.
