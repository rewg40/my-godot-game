# Источники материалов

Все необходимые файлы находятся в репозитории; интернет при запуске игры не нужен. Текст CC0 включён в [`licenses/CC0-1.0.md`](licenses/CC0-1.0.md).

## Новые остров и главный герой, предоставленные пользователем

`assets/models/environment/user_island.glb` и `assets/models/hero/user_hero.glb` подготовлены соответственно из файлов `остров 1.glb` и `персонаж 1.glb`, загруженных пользователем. Автор и условия лицензии этих моделей не указаны; их **нельзя считать CC0**. Исходные архивы находятся в ветке пользователя `main`, а игровые GLB в этой ветке оптимизированы для проекта. Предыдущий файл `Остров .glb` сохранён без изменений, но больше не используется как игровой остров.

Новая сетка острова упрощена с 1 499 850 до 120 000 треугольников, развёртка и текстуры базового цвета, нормалей и металличности/шероховатости сохранены. Повёрнутая и масштабированная модель занимает прежние 128 × 88 м и используется как для изображения, так и для физической коллизии. Маски дорог, безопасных позиций и карта в `assets/environment/user_island_*.png` созданы из неё скриптом `tools/prepare_user_island.py`; эти данные не заменяют саму модель.

Сетка главного героя упрощена с 1 500 000 до 60 000 треугольников с сохранением трёх текстур. В исходной модели не было скелета и анимаций, поэтому адаптированы скелет и девять клипов из указанного ниже CC0-набора Quaternius; веса и суставы кистей подогнаны к новой геометрии. Только игрок использует эту модель: NPC и зомби не заменялись. Бита и копьё привязаны к анимированной правой руке.

Подготовку можно повторить при наличии исходных GLB, Python 3 и Node.js:

```sh
python3 -m venv /tmp/shards-model-python
. /tmp/shards-model-python/bin/activate
pip install numpy==2.4.6 scipy==1.17.1 Pillow==13.0.0
npm install --prefix /tmp/shards-model-node @gltf-transform/core@4.2.1 @gltf-transform/extensions@4.2.1 @gltf-transform/functions@4.2.1 meshoptimizer@0.22.0 mikktspace@1.1.1
NODE_PATH=/tmp/shards-model-node/node_modules node tools/optimize_uploaded_model.cjs '/путь/к/остров 1.glb' assets/models/environment/user_island.glb 120000
NODE_PATH=/tmp/shards-model-node/node_modules node tools/optimize_uploaded_model.cjs '/путь/к/персонаж 1.glb' /tmp/hero-optimized.glb 60000
python3 tools/rig_user_hero.py /tmp/hero-optimized.glb assets/models/hero/user_hero.glb
python3 tools/prepare_user_island.py
```

## Модель зомби, предоставленная пользователем

`assets/models/zombie/user_zombie.glb` создана из файла `ZOMBI.glb`, предоставленного пользователем. Автор и условия лицензии исходной модели не указаны; не следует считать её CC0. Для игры сетка упрощена с 1 500 000 до 37 500 треугольников, три текстуры уменьшены с 4096×4096 до 2048×2048 и перекодированы. Исходник был статичным, без скелета и анимаций: для него самостоятельно добавлены скелет и простые анимации ожидания, ходьбы, бега и атаки. Все игровые варианты заражённых используют эту модель с разным масштабом.

Скрипты `tools/optimize_user_zombie.cjs` и `tools/rig_user_zombie.py` позволяют повторить подготовку при наличии исходного GLB. Оригинал и архивы в игровой ветке не хранятся. Например, в Linux с установленными Python 3 и Node.js:

```sh
python3 -m venv /tmp/shards-zombie-python
. /tmp/shards-zombie-python/bin/activate
pip install numpy==2.4.6 scipy==1.17.1 Pillow==13.0.0
npm install --prefix /tmp/shards-zombie-node @gltf-transform/core@4.2.1 @gltf-transform/extensions@4.2.1 @gltf-transform/functions@4.2.1 meshoptimizer@0.22.0 mikktspace@1.1.1
NODE_PATH=/tmp/shards-zombie-node/node_modules node tools/optimize_user_zombie.cjs /путь/к/ZOMBI.glb /tmp/zombie-optimized.glb
python3 tools/rig_user_zombie.py /tmp/zombie-optimized.glb assets/models/zombie/user_zombie.glb
```

## Бейсбольная бита

**Bloody Baseball Bat with Nails**, автор Sviatoslav Semenov (svyasem), лицензия **CC BY 4.0**: https://creativecommons.org/licenses/by/4.0/. Оригинал: https://sketchfab.com/3d-models/bloody-baseball-bat-with-nails-425e6efd8d81408fa63ff2c2962840d1. Файл `Bloody Baseball Bat with Nails.glb` предоставлен пользователем и используется без изменения геометрии и текстур; в игре скорректированы положение и поворот, модель привязана к кости руки. Анимация замаха создана на основе клипа Quaternius, указанного ниже.

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

**Лицензия: CC0 1.0.** Фотоматериалы Poly Haven: Leafy Grass (Charlotte Baglioni), Forest Leaves 02, Brown Mud 02, Concrete Wall 008, Weathered Planks, Red Brick 03, Rusty Metal 02, Asphalt 02, Aerial Beach 01 и Aerial Rocks 02 (`assets/environment/textures/rock_diff_1k.jpg`); 3D-модели Fern 02, Rock 07 и Tree Stump 01 (геометрия распакована для совместимости с Godot). Источники и лицензия: https://polyhaven.com/license и страницы соответствующих материалов / моделей. Зеркала: https://github.com/xustevexu/zombie-game, https://github.com/thedoncancel/kimchi-city и https://github.com/ssboroo/Rainy-portfolio.

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

`assets/art/shelter_menu.png` — сгенерированная иллюстрация меню. Прежняя карта `assets/environment/island_ground.png` создана скриптом `tools/generate_original_art.py`; текущая карта создаётся из предоставленной модели острова. Несколько игровых объектов (например, маяк, башни и квестовые предметы) собраны из объёмных примитивов в `scripts/prop.gd`.
