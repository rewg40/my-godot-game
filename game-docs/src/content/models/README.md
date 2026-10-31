# Превью 3D-моделей

Сюда кладутся **лёгкие превью** моделей для сайта: `.glb` / `.gltf` (крутятся прямо на сайте через
three.js), максимум ~24 МБ на файл (лимит GitHub для web-коммита).

Реестр — `../models.json`. Формат записи:

```json
{ "id": "chr-mark-01", "name": "Марк · базовая модель", "file": "models/chr_mark_01.glb",
  "description": "28k tri, 2K×4, Humanoid-риг", "tags": ["character","lod0"],
  "tab": "mechanics/assets", "size_mb": 3.4, "tris": 28000, "date": "2026-10-30" }
```

Полноценные исходники (`.blend`, FBX с текстурами, LOD-сеты) — **не сюда**: их место в
Godot-проекте (`Ostrov/godot/art/`) или в Git LFS. Здесь только то, что приятно показать глазами.
