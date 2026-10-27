# 05_buildings_structures — Постройки и конструкции

**Сюда кладём:** дома, башни, замки, стены, ворота, доки, причалы, мосты,
платформы, заборы, лестницы-башни, мачты, флаги, статуи, палатки, ветряки и
водяные мельницы — всё, что построено руками персонажей.

**Сюда не кладём:** природные скалы и камни (→ `03_cliffs_rocks/`),
корабли (→ `06_props_decor/`), тайлы дороги (→ `01_terrain_ground/`).

| Префикс | Источник | Примеры |
|---|---|---|
| `hex_` | Kenney Hexagon Kit | `hex_building-cabin.glb`, `hex_building-castle.glb`, `hex_building-dock.glb`, `hex_building-port.glb`, `hex_bridge.glb`, `hex_unit-tower.glb` |
| `nat_` | Kenney Nature Kit | `nat_bridge_wood.glb`, `nat_bridge_stone.glb`, `nat_fence_gate.glb`, `nat_tent_smallClosed.glb`, `nat_statue_column.glb`, `nat_platform_grass.glb` |
| `pir_` | Kenney Pirate Kit | `pir_structure-platform-dock.glb`, `pir_castle-wall.glb`, `pir_tower-watch.glb`, `pir_mast.glb`, `pir_flag-pirate.glb` |
| `td_` | Kenney Tower Defense Kit | `td_tower-round-base.glb`, `td_tower-square-top-a.glb`, `td_wood-structure.glb`, `td_spawn-round.glb` |
| `kay_` | KayKit Medieval Hexagon | `kay_building_home_A_blue.glb`, `kay_building_castle_red.glb`, `kay_wall_straight_gate.glb`, `kay_fence_wood_straight.glb`, `kay_building_windmill_red.glb` |

## Цвета фракций у KayKit

**18 форм построек** (дома, башни, замок, церковь, таверна, рудник, кузница,
лесопилка, мельницы, колодец, рыночные ряды и т. д.) доступны в **четырёх
цветах фракций**: `blue`, `green`, `red`, `yellow`. Это одна и та же геометрия
с разными UV на общий атлас — удобно для логики «чей форт», но в одной постройке
цвета фракций между собой не смешиваются.

Ещё **21 модель идёт без цвета фракции** (в паке лежат в папке `neutral`):
стены и ворота (`kay_wall_straight.glb`, `kay_wall_corner_A_gate.glb`), заборы
(`kay_fence_wood_straight.glb`), мосты (`kay_building_bridge_A.glb`), сцены,
строительные леса, зернохранилище и разрушенное здание (`kay_building_destroyed.glb`).
Они нейтральные по смыслу: заборы и стены «красными» не бывают.

Плюс **4 знамени** (`kay_flag_blue.glb` … `kay_flag_yellow.glb`) — они переведены сюда
из папки props, чтобы флаги лежали так же, как в Pirate Kit.

Итого в категории **97 моделей KayKit** = 18 форм × 4 цвета + 21 нейтральная + 4 знамени.

Основной набор для острова с пиратским портом: `pir_structure-platform-dock.glb`
(причал) + `pir_tower-watch.glb` (сторожевая башня) + `pir_mast.glb` и
`pir_flag-pirate.glb` (мачты с флагами).

Модели: **250**. Полный список — в `../inventory.json`.
