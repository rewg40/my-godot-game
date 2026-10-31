#!/usr/bin/env bash
# Сжать картинку так, чтобы она прошла лимиты сайта (≤1400 px по длинной стороне, ≤1.5 МБ)
# и положить рядом запись для content/images.json.
#
#   ./tools/img2webp.sh путь/до/файла.png [имя-в-реестре] [макс.сторона] [качество]
#
# Вывод: game-docs/src/content/images/imported/<имя>.webp + JSON-запись в stdout,
# которую можно вставить в content/images.json (или сделать это через сайт).
set -euo pipefail
SRC="${1:?нужен путь к файлу}"; BASE="${2:-$(basename "${SRC%.*}")}"
SIDE="${3:-1400}"; Q="${4:-82}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/game-docs/src/content/images/imported"
mkdir -p "$OUT"
DEST="$OUT/$BASE.webp"

if command -v cwebp >/dev/null 2>&1; then
  cwebp -quiet -resize $SIDE $SIDE -m 6 -q "$Q" "$SRC" -o "$DEST"
elif command -v convert >/dev/null 2>&1; then
  convert "$SRC" -resize "${SIDE}x${SIDE}>" -quality "$Q" "webp:$DEST"
elif command -v ffmpeg >/dev/null 2>&1; then
  ffmpeg -loglevel error -y -i "$SRC" -vf "scale=${SIDE}:${SIDE}:force_original_aspect_ratio=decrease" \
    -c:v libwebp -quality "$Q" "$DEST"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import PIL" 2>/dev/null; then
  python3 - "$SRC" "$DEST" "$SIDE" "$Q" <<'PY'
import sys
from PIL import Image
src, dst, side, q = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
im = Image.open(src)
im.thumbnail((side, side), Image.LANCZOS)
im.convert("RGB").save(dst, "WEBP", quality=q, method=6)
PY
else
  echo "нет cwebp / imagemagick / ffmpeg / Pillow — установи что-то одно" >&2
  exit 1
fi

SIZE=$(wc -c <"$DEST")
if [ "$SIZE" -gt 1500000 ]; then
  echo "⚠️ $DEST = $SIZE байт — больше 1.5 МБ, уменьши SIDE или Q" >&2
fi
cat <<JSON
{
  "id": "$(echo "$BASE" | tr '[:upper:]' '[:lower:]')",
  "name": "$BASE",
  "file": "images/imported/$BASE.webp",
  "caption": "обнови подпись",
  "tags": ["import"],
  "tab": "preview",
  "author": "agent",
  "date": "$(date -u +%F)"
}
JSON
echo "→ $DEST ($SIZE байт)" >&2
