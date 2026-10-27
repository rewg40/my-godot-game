# 06_props_decor — Реквизит и декор

**Сюда кладём:** всё, что не рельеф, не растение и не постройка: бочки, ящики,
сундуки, мешки, бочки с водой, тачки, паллеты, приставные лестницы, облака,
мишени, а также игровые объекты из Tower Defense Kit — противников, оружие,
снаряды и маркеры выбора.

**Сюда не кладём:** причалы, помосты и платформы (→ `05_buildings_structures/`),
камни и валуны (→ `03_cliffs_rocks/`), острова и воду (→ `02_islands/`).

| Префикс | Источник | Примеры |
|---|---|---|
| `pir_` | Kenney Pirate Kit | `pir_barrel.glb`, `pir_crate.glb`, `pir_chest.glb`, `pir_cannon.glb`, `pir_ship-pirate-large.glb`, `pir_ship-wreck.glb`, `pir_boat-row-small.glb`, `pir_tool-shovel.glb` |
| `nat_` | Kenney Nature Kit | `nat_campfire_stones.glb`, `nat_log_stack.glb`, `nat_canoe.glb`, `nat_bed.glb`, `nat_pot_large.glb` |
| `td_` | Kenney Tower Defense Kit | `td_enemy-ufo-a.glb`, `td_weapon-cannon.glb`, `td_weapon-catapult.glb`, `td_selection-a.glb` |
| `hex_` | Kenney Hexagon Kit | `hex_unit-ship.glb`, `hex_unit-ship-large.glb` |
| `kay_` | KayKit Medieval Hexagon | `kay_barrel.glb`, `kay_crate_open.glb`, `kay_sack.glb`, `kay_wheelbarrow.glb`, `kay_cloud_big.glb`, `kay_resource_lumber.glb` |

Из KayKit сюда попали и **облака** (`kay_cloud_big.glb`, `kay_cloud_small.glb`) —
их вешают в небо, а не на землю. Палатка KayKit (`kay_tent.glb`) лежит здесь,
хотя у Nature Kit палатки в `05_buildings_structures/` — у паков разная
логика, ориентируйтесь на то, где уже лежит похожая модель в вашей сцене.

`pir_ship-wreck.glb` (кораблекрушение) хорошо смотрится на отмели у берега
острова — ставьте так, чтобы корпус частично уходил под плоскость воды.

Модели: **75**. Полный список — в `../inventory.json`.
