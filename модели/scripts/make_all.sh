#!/usr/bin/env bash
# make_all.sh — полностью пересобирает папку «модели» с нуля.
#
#   ./модели/scripts/make_all.sh [путь_к_kenney/3d] [путь_к_kaykit/Assets/gltf]
#
# Оба пути необязательны: если не указаны, репозитории скачиваются во временный
# каталог (sparse checkout, только нужные паки).
#
# Источники:
#   • Kenney  — https://github.com/shorepine/kenney , паки hexagon, nature,
#               tower-defense, pirate. Лицензия CC0 1.0.
#   • KayKit  — https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0 ,
#               каталог addons/kaykit_medieval_hexagon_pack/Assets/gltf. CC0 1.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$(dirname "$HERE")"
KENNEY_SRC="${1:-}"
KAYKIT_SRC="${2:-}"
TMP_DIR=""

cleanup() { [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [ -z "$KENNEY_SRC" ] || [ -z "$KAYKIT_SRC" ]; then
  TMP_DIR="$(mktemp -d)"
fi

if [ -z "$KENNEY_SRC" ]; then
  echo "==> Скачиваю паки Kenney (CC0)…"
  git clone --quiet --depth 1 --filter=blob:none --sparse \
    https://github.com/shorepine/kenney.git "$TMP_DIR/kenney"
  git -C "$TMP_DIR/kenney" sparse-checkout set \
    3d/hexagon 3d/nature 3d/tower-defense 3d/pirate
  KENNEY_SRC="$TMP_DIR/kenney/3d"
fi

if [ -z "$KAYKIT_SRC" ]; then
  echo "==> Скачиваю KayKit Medieval Hexagon Pack (CC0)…"
  git clone --quiet --depth 1 --filter=blob:none --sparse \
    https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0.git \
    "$TMP_DIR/kaykit"
  git -C "$TMP_DIR/kaykit" sparse-checkout set \
    addons/kaykit_medieval_hexagon_pack/Assets/gltf
  KAYKIT_SRC="$TMP_DIR/kaykit/addons/kaykit_medieval_hexagon_pack/Assets/gltf"
fi

[ -d "$KENNEY_SRC" ] || { echo "Исходная папка Kenney не найдена: $KENNEY_SRC" >&2; exit 1; }
[ -d "$KAYKIT_SRC" ] || { echo "Папка KayKit не найдена: $KAYKIT_SRC" >&2; exit 1; }

echo "==> Очищаю категории…"
cd "$MODELS_DIR"
for d in 0*/; do
  [ -d "$d" ] || continue
  rm -rf "$d"
done
rm -rf textures inventory.json

echo "==> Раскладываю модели Kenney по категориям…"
python3 "$HERE/organize_models.py" "$KENNEY_SRC" "$MODELS_DIR"

echo "==> Конвертирую KayKit (.gltf + .bin + атлас → самодостаточный .glb)…"
python3 "$HERE/convert_kaykit.py" "$KAYKIT_SRC" "$MODELS_DIR"

# Атлас пака — один на все 221 модели и весит ~15 КБ; копия нужна, только если
# захотите делать собственные тайлы в этом же стиле.
atlas="$(find "$KAYKIT_SRC" -name 'hexagons_medieval.png' | head -1 || true)"
if [ -n "$atlas" ]; then
  mkdir -p "$MODELS_DIR/textures"
  cp "$atlas" "$MODELS_DIR/textures/kay_hexagons_medieval.png"
fi

echo "==> Генерирую процедурные модели местности и островов…"
python3 "$HERE/generate_islands.py" "$MODELS_DIR"

echo "==> Проверяю целостность всех .glb…"
python3 "$HERE/validate_glb.py" "$MODELS_DIR"

echo "==> Восстанавливаю README категорий…"
for readme in "$HERE"/category_readmes/*.md; do
  [ -e "$readme" ] || continue
  category="$(basename "$readme" .md)"
  mkdir -p "$MODELS_DIR/$category"
  cp "$readme" "$MODELS_DIR/$category/README.md"
done

echo "==> Собираю inventory.json…"
python3 "$HERE/build_inventory.py" "$MODELS_DIR"

echo "==> Готово: $MODELS_DIR"
