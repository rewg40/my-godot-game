# my-godot-game

Репозиторий для Godot-проектов и 3D-ассетов.

## Проекты

| Проект | Что это |
|---|---|
| [`pepel-i-zvezdy/`](pepel-i-zvezdy/README.md) | **Пепел и Звёзды** — 3D-выживание на заражённом острове на Godot 4: процедурный остров, сутки, зомби, крафт, костры, четыре класса, сохранения |
| [`dismember-test/`](dismember-test/README.md) | **Полигон: меч и конечности** — площадка для проверки ударов: улучшенный остров, медик с мечом, три зомби с 1000 HP, отрубание рук и ног, ползание без ног |

Запуск:

```bash
godot --path pepel-i-zvezdy
godot --path dismember-test
```

## Ассеты в корне

Тяжёлые 3D-модели хранятся разрезанными на части, чтобы обойти лимит GitHub
в 100 МБ на файл:

| Архив | Модель |
|---|---|
| `ZOMBI.7z.001…004` | зомби (90 МБ) |
| `остров 1.7z.001…002` | остров (66 МБ) |
| `персонаж 1.7z.001…003` | персонаж (66 МБ) |

Распаковка в проект:

```bash
python -m pip install py7zr
python pepel-i-zvezdy/tools/unpack_assets.py

python -m pip install py7zr numpy
python dismember-test/tools/prepare_assets.py
```

Второй скрипт, кроме распаковки, режет скульптуры на части (тело, две руки,
две ноги) — это нужно полигону для отрубания конечностей.

Подробности — в [pepel-i-zvezdy/ASSETS.md](pepel-i-zvezdy/ASSETS.md) и
[dismember-test/assets/models/README.md](dismember-test/assets/models/README.md).
Сами GLB-файлы в git не попадают (`*.glb` в `.gitignore`).
