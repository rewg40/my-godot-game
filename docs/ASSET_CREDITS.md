# Источники материалов

Все необходимые файлы находятся в репозитории; интернет при запуске игры не нужен. Текст CC0 включён в [`licenses/CC0-1.0.md`](licenses/CC0-1.0.md).

## Quaternius — анимированные 3D-персонажи

**Лицензия: CC0 1.0.** Автор: Quaternius. В `assets/models/characters/` находятся персонажи из набора Ultimate Animated Character Pack, включая зомби. Файлы GLB содержат скелеты и анимации ходьбы, бега, прыжка и других действий. Оттенки кожи персонажей настроены в игре; оригинальный файл лицензии включён рядом с моделями.

- Набор: https://quaternius.com/packs/ultimatedanimatedcharacter.html
- Зеркало файлов GLB: https://github.com/wellmota/tutory-personagens/tree/main/quaternius-uac

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
