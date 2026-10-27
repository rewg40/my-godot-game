#!/usr/bin/env bash
# make_all.sh — полностью пересобирает папку «модели» с нуля.
#
#   ./модели/scripts/make_all.sh [путь_к_kenney/3d]
#
# Если путь не указан, репозиторий Kenney скачивается во временный каталог
# (sparse checkout только нужных паков). Скачанные паки: hexagon, nature,
# tower-defense, pirate. Все ассеты Kenney распространяются по CC0 1.0.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$(dirname "$HERE")"
REPO_ROOT="$(dirname "$MODELS_DIR")"
SRC="${1:-}"
TMP_DIR=""

cleanup() { [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

if [ -z "$SRC" ]; then
  TMP_DIR="$(mktemp -d)"
  echo "==> Скачиваю паки Kenney (CC0) во временный каталог…"
  git clone --quiet --depth 1 --filter=blob:none --sparse \
    https://github.com/shorepine/kenney.git "$TMP_DIR/kenney"
  git -C "$TMP_DIR/kenney" sparse-checkout set \
    3d/hexagon 3d/nature 3d/tower-defense 3d/pirate
  SRC="$TMP_DIR/kenney/3d"
fi

if [ ! -d "$SRC" ]; then
  echo "Исходная папка не найдена: $SRC" >&2
  exit 1
fi

echo "==> Очищаю категории…"
cd "$MODELS_DIR"
for d in 0*/; do
  [ -d "$d" ] || continue
  rm -rf "$d"
done
rm -rf textures inventory.json

echo "==> Раскладываю скачанные модели по категориям…"
python3 "$HERE/organize_models.py" "$SRC" "$MODELS_DIR"

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
