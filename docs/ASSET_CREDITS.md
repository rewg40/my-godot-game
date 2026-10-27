# Источники материалов

Все необходимые файлы находятся в репозитории; интернет при запуске игры не нужен. Текст CC0 включён в [`licenses/CC0-1.0.md`](licenses/CC0-1.0.md).

## Quaternius — анимированные 3D-персонажи

**Лицензия: CC0 1.0.** Автор: Quaternius. В `assets/models/characters/` находятся персонажи из набора Ultimate Animated Character Pack, включая зомби. Файлы GLB содержат скелеты и анимации ходьбы, бега, прыжка и других действий. Оттенки кожи персонажей настроены в игре; оригинальный файл лицензии включён рядом с моделями.

- Набор: https://quaternius.com/packs/ultimatedanimatedcharacter.html
- Зеркало файлов GLB: https://github.com/wellmota/tutory-personagens/tree/main/quaternius-uac

### Новые персонажи

`assets/models/survivors/male.glb` и `female.glb` созданы на основе **Universal Base Characters**, с волосами и анимациями **Universal Animation Library** и **Universal Animation Library 2** от Quaternius (все CC0 1.0). Кости и клипы перенесены на соответствующие скелеты, в цвета вершин добавлены маски одежды; материалы и оттенки одежды задаются в игре. Модели и анимации подготовлены из зеркала проекта Last Light: https://github.com/xustevexu/zombie-game/blob/main/assets/CREDITS.md.

- https://quaternius.itch.io/universal-base-characters
- https://quaternius.itch.io/universal-animation-library
- https://quaternius.itch.io/universal-animation-library-2

## Poly Haven и Game Piggs — окружение

**Лицензия: CC0 1.0.** Фотоматериалы Poly Haven: Leafy Grass (Charlotte Baglioni), Forest Leaves 02, Brown Mud 02, Concrete Wall 008, Weathered Planks, Red Brick 03, Rusty Metal 02, Asphalt 02 и Aerial Beach 01; 3D-модели Fern 02, Rock 07 и Tree Stump 01 (геометрия распакована для совместимости с Godot). Источники и лицензия: https://polyhaven.com/license и страницы соответствующих материалов / моделей. Зеркала: https://github.com/xustevexu/zombie-game, https://github.com/thedoncancel/kimchi-city и https://github.com/ssboroo/Rainy-portfolio.

`assets/models/nature_real/pine.glb`, `grass.glb` и `sorrel.glb` — облегчённые версии Pine Tree 01 и Grass Medium 01 от Rico Cilliers и Rob Tuytel и Shrub Sorrel 01 от Rico Cilliers (Poly Haven, CC0), подготовленные проектом Terrain Studio: https://github.com/HowdyMoto/terrain-tools/blob/main/public/foliage/photoreal/CREDITS.txt. Хвоя использует текстурные карточки; ресурсы изменены по сравнению с оригиналом.

`assets/models/nature_real/broadleaf.glb` основан на **Tree Small 02** от Rico Cilliers (Poly Haven, CC0): https://polyhaven.com/a/tree_small_02. Использована облегчённая версия https://github.com/agrimuitobom/landscape/pull/6 с текстурными листьями; геометрия дополнительно упрощена, текстуры перекодированы, данные распакованы для Godot.

`assets/environment/textures/grass_short.jpg` — уменьшенная и перекодированная версия **Grass 01** от Mykhailo Ohorodnichuk / Game Piggs (CC0), из https://github.com/permabulk69420-pixel/Oasis/blob/main/public/textures/grass/CREDITS.md. Источник: https://game-piggs.com/textures/grass-01/, лицензия: https://game-piggs.com/license/.

## Заброшенный автомобиль

**Abandoned Generic Sedan 2 - Game Ready**, автор Rashad Ibrahimli, лицензия **CC BY 4.0**: https://creativecommons.org/licenses/by/4.0/. Файл `assets/models/props/abandoned_sedan.glb` используется без изменения модели; в игре изменены масштаб, положение и поворот экземпляров. Оригинал: https://sketchfab.com/3d-models/abandoned-generic-sedan-2-game-ready-db2df46c49f9441286c84c66208ef7ac. Зеркало: https://github.com/karimdev671-design/game-assets.

## Kenney — 3D-объекты и звуки

**Лицензия: CC0 1.0.** Автор: Kenney / Kenney.nl. В `assets/models/kenney/` находятся выбранные модели природы, выживания, жилых и промышленных зданий из наборов Nature Kit, Survival Kit, City Kit (Suburban) и City Kit (Industrial), а также их текстуры. `assets/audio/` содержит эффекты из Digital Sounds и Jingle Sounds.

- Наборы: https://kenney.nl/assets
- Зеркало 3D-моделей: https://github.com/shorepine/kenney
- Зеркало звуковых файлов и лицензии: https://github.com/iwenzhou/kenney

## Ninja Adventure — музыка

**Лицензия: CC0 1.0.** Авторы набора: Pixel-boy и AAA; музыка: Pixel-boy. Мелодия `theme_lost_village.ogg` взята из официального Godot-проекта набора.

- Страница и лицензия: https://pixel-boy.itch.io/ninja-adventure-asset-pack
- Официальный проект: https://github.com/pixel-boy/NinjaAdventure

## DejaVu Sans

Файлы `assets/fonts/DejaVuSans*.ttf` распространяются под лицензией Bitstream Vera / DejaVu; полный текст и сведения об авторских правах находятся в [`../assets/fonts/LICENSE-DejaVu.txt`](../assets/fonts/LICENSE-DejaVu.txt).

## Созданные для проекта материалы

`assets/art/shelter_menu.png` — сгенерированная иллюстрация меню. Карта `assets/environment/island_ground.png`, используемая также как текстура 3D-рельефа, создана скриптом `tools/generate_original_art.py`. Несколько игровых объектов (например, маяк, башни и квестовые предметы) собраны из объёмных примитивов в `scripts/prop.gd`.
