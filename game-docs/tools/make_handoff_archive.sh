#!/usr/bin/env bash
# Собирает «выпуск»: всё, что есть по проекту ZOMBI «Пепел и Звёзды» —
# Кладёт рядом читалку, документацию, сайт, исходники заставок и генераторы — в один zip.
#
# Зачем: github.io у владельца открывается через раз, а материал надо отдать целиком
# и так, чтобы он открывался двойным кликом. Архив — производный: в git не кладётся,
# пересобирается этой командой в любой момент (источник — репозиторий).
#
# Запуск:  bash game-docs/tools/make_handoff_archive.sh [--out КУДА] [--keep]
# По умолчанию пишет ZOMBI-pepel-i-zvezdy-<сборка>.zip в папку рядом с репозиторием.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR=""
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "непонятный аргумент: $1" >&2; exit 2 ;;
  esac
done

STAMP="$(sed -n 's/^const SITE_BUILD = "\([^"]*\)".*/\1/p' "$ROOT/game-docs/src/app.js" | head -1)"
VER="$(printf '%s' "$STAMP" | cut -d' ' -f1)"
[ -n "$VER" ] || VER="$(date +%F)"
NAME="ZOMBI-pepel-i-zvezdy-$VER"
[ -n "$OUT_DIR" ] || OUT_DIR="$(dirname "$ROOT")"
STAGE="${TMPDIR:-/tmp}/$NAME"

rm -rf "$STAGE"
mkdir -p "$STAGE"

# Точная копия нужных папок репозитория (пути внутри документов остаются верными).
mkdir -p "$STAGE/game-docs"
cp -R "$ROOT/game-docs/." "$STAGE/game-docs/"
rm -rf "$STAGE/game-docs/src/_site"
rm -f "$STAGE/game-docs/archive/zombi-chitalka.html"   # она будет в корне архива
find "$STAGE" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

if [ -d "$ROOT/media" ]; then
  mkdir -p "$STAGE/media"
  cp -R "$ROOT/media/." "$STAGE/media/"
fi
[ -f "$ROOT/README.md" ] && cp "$ROOT/README.md" "$STAGE/README.md"
mkdir -p "$STAGE/.github/workflows"
cp "$ROOT/.github/workflows/"*.yml "$STAGE/.github/workflows/"

# Имя файла — латиницей: в кириллических именах zip-архивы иногда «поежают» в проводнике.
[ -f "$ROOT/game-docs/archive/PROCHTAY-MENYA.md" ] \
  && cp "$ROOT/game-docs/archive/PROCHTAY-MENYA.md" "$STAGE/PROCHTAY-MENYA.md"

# Читалка + видео рядом: в этом режиме <video src="video/…"> играется с диска.
python3 "$ROOT/game-docs/tools/build_offline_reader.py" \
  --out "$STAGE/zombi-chitalka.html" --video-dir video

{
  echo "ZOMBI «Пепел и Звёзды» · выпуск $VER"
  echo "собрано: $(TZ=Europe/Moscow date '+%Y-%m-%d %H:%M') по-московски, $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC"
  echo "ветка: $(git -C "$ROOT" rev-parse --abbrev-ref HEAD) · коммит: $(git -C "$ROOT" rev-parse --short HEAD)"
  echo "сайт: https://rewg40.github.io/my-godot-game/"
  echo "читалка: zombi-chitalka.html (открывать двойным кликом, интернет не нужен)"
} > "$STAGE/INFO.txt"

( cd "$STAGE" && find . -type f ! -name SHA256SUMS.txt -print0 \
    | sort -z | xargs -0 sha256sum > SHA256SUMS.txt )

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/$NAME.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -q -r -X "$ZIP" . )

N=$(unzip -l "$ZIP" | tail -1 | awk '{print $2}')
echo "архив: $ZIP"
echo "файлов: $N · размер: $(du -h "$ZIP" | cut -f1)"
echo "sha256: $(sha256sum "$ZIP" | cut -d' ' -f1)"
echo "сборка сайта в архиве: $STAMP"
[ "$KEEP" = 1 ] && echo "черновик остался: $STAGE" || rm -rf "$STAGE"
