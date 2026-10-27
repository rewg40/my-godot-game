# 04_vegetation — Растительность

**Сюда кладём:** деревья, пальмы, траву, цветы, пни, мох, камыши, посевы —
всё живое, что растёт на острове и что можно срубить, сжечь или использовать
как декор.

**Сюда не кладём:** деревянные постройки, мосты, заборы и частоколы
(→ `05_buildings_structures/`), тайлы травы как поверхность
(→ `01_terrain_ground/`), кувшинки и водные растения (→ `02_islands/`).

| Префикс | Источник | Примеры |
|---|---|---|
| `nat_` | Kenney Nature Kit | `nat_tree_simple.glb`, `nat_tree_cone.glb`, `nat_tree_pineDefaultA.glb`, `nat_grass_large.glb`, `nat_flower_purpleA.glb`, `nat_stump_old.glb`, `nat_hanging_moss.glb` |
| `pir_` | Kenney Pirate Kit | `pir_palm-straight.glb`, `pir_palm-detailed-bend.glb`, `pir_grass-plant.glb` — тропики для островов |
| `td_` | Kenney Tower Defense Kit | `td_detail-tree.glb`, `td_snow-detail-tree.glb`, `td_detail-crystal.glb` |
| `hex_` | Kenney Hexagon Kit | `hex_unit-tree.glb` |
| `kay_` | KayKit Medieval Hexagon | `kay_tree_single_A.glb`, `kay_trees_A_large.glb`, `kay_trees_B_cut.glb` |

Для тропического острова берите пальмы из Pirate Kit (`pir_palm-*`) — они
совпадают по стилистике с песком `pir_patch-sand.glb` из `01_terrain_ground/`.

У KayKit деревья идут по размеру (`_small` / `_medium` / `_large`) и отдельно
версии пней (`_cut`) — удобно показывать вырубку. `kay_hills_A_trees.glb` при
этом — **холм с деревьями**, то есть местность, и лежит в `01_terrain_ground/`.

Модели: **148**. Полный список — в `../inventory.json`.
