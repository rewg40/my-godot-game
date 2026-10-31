#!/usr/bin/env bash
# make-splash.sh — пересборка видеозаставок «Пепел и Звёзды» из ключевых кадров галереи.
#
#   ./game-docs/tools/make-splash.sh            # собрать всё (2 видео + петли для сайта)
#   ./game-docs/tools/make-splash.sh --stills    # только still-картинки галереи
#   ./game-docs/tools/make-splash.sh --no-webp   # не делать анимированные webp-петли
#
# Находы:
#   game-docs/src/content/images/preview/*.webp  — ключевые кадры + постеры + анимированные петли
#                                                  (их видит сайт; каждый ≤1400 px и ≤1.4 МБ)
#   game-docs/src/content/video/*.mp4            — вебовские копии заставок, их играет <video> на сайте
#   media/splash/splash-intro.{mp4,ogv}          — мастер заставки перед меню (39 с, титры внутри)
#   media/splash/splash-awakening.{mp4,ogv}      — мастер заставки пробуждения (12.8 с)
#   media/splash/boot_splash.png                 — картинка application/boot_splash в project.godot
# .ogv (Theora) — то, что Godot 4 умеет играть «из коробки» через VideoStreamPlayer; .mp4 — для сайта.
#
# Требования: ffmpeg (подойдёт static-билд из pip imageio-ffmpeg), ImageMagick 6+ с DejaVu.
# ffmpeg берётся из PATH, иначе из python3 -c 'import imageio_ffmpeg;…'.
# Текст рисуется НЕ фильтром drawtext (его нет в static-сборках), а PNG-плашками через
# `convert -annotate` + `overlay` — так кириллица и переносы не зависят от fontconfig.
set -euo pipefail

W=1280 H=720 FPS=24 XFADE=0.6
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PREV="$ROOT/game-docs/src/content/images/preview"
OUT="$ROOT/media/splash"
WORK=${SPLASH_WORK:-/tmp/splash-work}
FONTB=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
FONTR=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf

DO_STILLS=1 DO_VIDEO=1 DO_LOOPS=1
for a in "$@"; do
  case "$a" in
    --stills) DO_VIDEO=0; DO_LOOPS=0 ;;
    --no-webp) DO_LOOPS=0 ;;
    *) echo "неизвестный флаг: $a" >&2; exit 2 ;;
  esac
done

FF=$(command -v ffmpeg || true)
if [ -z "$FF" ]; then
  FF=$(python3 -c 'import imageio_ffmpeg,sys;sys.stdout.write(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null || true)
fi
[ -n "$FF" ] || { echo "ffmpeg не найден (поставь ImageMagick + `pip install imageio-ffmpeg`)" >&2; exit 1; }
command -v convert >/dev/null || { echo "ImageMagick (convert) не найден" >&2; exit 1; }
echo "ffmpeg: $FF"

# ---------------------------------------------------------------- карточка текста
# card <out.png> <pointsize> <color> <dy> <text>   — color с суффиксом -r = обычный шрифт
card() {
  local out=$1 ps=$2 color=$3 dy=$4; shift 4
  local text="$*" f=$FONTB
  if [[ "$color" == *-r ]]; then color=${color%-r}; f=$FONTR; fi
  convert -size "${W}x${H}" "xc:none" -font "$f" -pointsize "$ps" -fill "$color" \
    -kerning 3 -gravity center -annotate "+0+${dy}" "$text" "$out"
}

# card-multi <out.png> <dy-first> <leading> <ps> <color> <t1> <t2> …
card-multi() {
  local out=$1 dy=$2 lead=$3 ps=$4 color=$5; shift 5
  local f=$FONTB
  if [[ "$color" == *-r ]]; then color=${color%-r}; f=$FONTR; fi
  local args=() i=0
  for t in "$@"; do
    args+=(-font "$f" -pointsize "$ps" -fill "$color" -kerning 3 -gravity center \
      -annotate "+0+$((dy + i * lead))" "$t")
    i=$((i + 1))
  done
  convert -size "${W}x${H}" xc:none "${args[@]}" "$out"
}

# ---------------------------------------------------------------- still-картинки галереи
mkdir -p "$PREV" "$WORK" "$OUT"
SRC_ART=${SRC_ART:-$HOME/.th/art}
if [ "$DO_STILLS" = 1 ]; then
  echo "→ still: $PREV"
  for f in "$SRC_ART"/0*.png; do
    [ -e "$f" ] || continue
    b=$(basename "$f" .png)
    convert "$f" -resize "${W_MAX:-1400}x${W_MAX:-1400}>" -modulate 100,88 -quality 82 \
      -define webp:method=6 "$PREV/$b.webp"
  done
fi
for n in 01-ash-plains 02-null-city 03-needle 04-sito-lab 05-fields-of-sleep 06-awakening; do
  [ -e "$PREV/$n.webp" ] || { echo "нет кадра $PREV/$n.webp — положи PNG в \$SRC_ART и запусти --stills" >&2; exit 1; }
done

grade() { # grade <in> <out> — единый колор + нижняя полоса под титры (читаемость на светлом фоне)
  convert "$1" -resize "${W}x${H}^" -gravity center -extent "${W}x${H}" \
    -modulate 96,74,99 -attenuate 0.55 +noise Gaussian -brightness-contrast -6x8 "$2"
  convert -size "${W}x300" "gradient:#0b101600-#0b1016cc" "$WORK/band.png"
  convert "$2" "$WORK/band.png" -gravity south -composite "$2"
}

if [ "$DO_VIDEO" != 1 ]; then echo "готово (только still)"; exit 0; fi

# ---------------------------------------------------------------- сегменты интро
S="$WORK/seg"; rm -rf "$S"; mkdir -p "$S"

# 0 — чёрная плашка-зачин
convert -size "${W}x${H}" xc:black "$S/00-base.png"
card "$S/00-a.png" 26 "#8ea2b8-r" -76 "ЗЕМЛЯ · 3610 ГОД"
card "$S/00-b.png" 34 "#dfe7f2" 6 "пепел помнит всех, кто дышал слишком громко"
D0=4.2

# 1..5 — ключевые кадры + нижний титр локации
locs=(
  "01-ash-plains|ПЕПЕЛЬНЫЕ РАВНИНЫ · «СТЕКЛО»|48 × 48 км пепла · шаг вправо — и он услышит"
  "05-fields-of-sleep|ПОЛЯ СНА|спящие встают не на свет, а на звук"
  "02-null-city|НУЛЕВОЙ ГОРОД|затопленная метролия · «Игла» в четырёх километрах"
  "04-sito-lab|СТАНЦИЯ «СИТО»|36 часов до Порога · изоляция, а не лечение"
  "03-needle|«ИГЛА»|орбитальный лифт · протокол «объект закрыт»"
)
i=1
for row in "${locs[@]}"; do
  IFS='|' read -r art cap sub <<<"$row"
  printf -v nn '%02d' $i
  grade "$PREV/$art.webp" "$S/$nn-base.png"
  card "$S/$nn-a.png" 40 "#e8eef7" 214 "$cap"
  card "$S/$nn-b.png" 24 "#9fb2c7-r" 262 "$sub"
  i=$((i + 1))
done
DL=5.4

# 6 — титры поверх затемнённого пепельного кадра
grade "$PREV/01-ash-plains.webp" "$S/06-base.png"
convert "$S/06-base.png" -blur 0x2 -evaluate multiply 0.5 "$S/06-base.png"
card "$S/06-t.png" 76 "#f2f6fb" -150 "ПЕПЕЛ И ЗВЁЗДЫ"
card "$S/06-s.png" 28 "#b9c8da-r" -84 "Ash & Stars · выживание на тихом материке · Godot 4.x"
card-multi "$S/06-c1.png" 60 34 21 "#e2ebf6-r" \
  "продакшн и идея — rewg40" \
  "сценарий, механики, исследование и сеть — библия проекта (агент Arena)" \
  "ключевые кадры — 6 концептов по плейлисту галереи" \
  "звук — процедурный дрон, ветер и сердцебиение"
card-multi "$S/06-c2.png" 214 30 19 "#8ba0b8-r" \
  "заставка пересобирается одной командой: game-docs/tools/make-splash.sh" \
  "всё живёт в этом репозитории · никаких внешних ссылок и чужих прав"
D6=9.0

# 7 — «нажми любую кнопку»
convert -size "${W}x${H}" xc:black "$S/07-base.png"
card "$S/07-a.png" 30 "#dfe7f2" 0 "НАЖМИ ЛЮБУЮ КНОПКУ · → ГЛАВНОЕ МЕНЮ"
D7=3.4

seg() { # seg <nn> <dur> <overlay:st:d> …  (overlay = "<png>|<in>|<out>")
  local nn=$1 dur=$2; shift 2
  local inputs=(-loop 1 -t "$dur" -i "$S/$nn-base.png")
  fc="[0:v]fps=$FPS,scale=2560:1440,format=rgba,zoompan=z='min(1.0007*on\,1.09)':d=1:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${W}x${H}:fps=${FPS}[bg]"
  local last=bg k=1 spec o st du
  for spec in "$@"; do
    IFS='|' read -r o st du <<<"$spec"
    inputs+=(-loop 1 -t "$dur" -i "$o")
    fc+=";[${k}:v]format=rgba,fade=t=in:st=${st}:d=0.7:alpha=1,fade=t=out:st=${du}:d=0.7:alpha=1[t${k}]"
    fc+=";[${last}][t${k}]overlay=0:0:eof_action=pass[o${k}]"
    last="o$k"; k=$((k + 1))
  done
  fc+=";[${last}]format=yuv420p[v]"
  "$FF" -hide_banner -loglevel error -y "${inputs[@]}" -filter_complex "$fc" -map "[v]" \
    -t "$dur" -r $FPS -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p "$S/$nn.mp4"
  echo "$S/$nn.mp4"
}

echo "→ сегменты интро"
SEGFILES=()
SEGFILES+=("$(seg 00 $D0 "$S/00-a.png|0.6|2.9" "$S/00-b.png|1.5|3.6")")
i=1
for i in 1 2 3 4 5; do
  printf -v nn '%02d' $i
  SEGFILES+=("$(seg $nn $DL "$S/$nn-a.png|0.5|$DL" "$S/$nn-b.png|1.0|$DL")")
done
SEGFILES+=("$(seg 06 $D6 "$S/06-t.png|0.4|$D6" "$S/06-s.png|1.0|$D6" "$S/06-c1.png|2.2|$D6" "$S/06-c2.png|5.0|$D6")")
SEGFILES+=("$(seg 07 $D7 "$S/07-a.png|0.2|$D7")")

# ---------------------------------------------------------------- склейка xfade
n=${#SEGFILES[@]}
DURS=($D0 $(printf '%.1f ' $DL $DL $DL $DL $DL) $D6 $D7)
INPUTS=(); for f in "${SEGFILES[@]}"; do INPUTS+=(-i "$f"); done
fc=""; acc=0; prev="[0:v]"
for ((j = 1; j < n; j++)); do
  acc=$(awk -v a="$acc" -v d="${DURS[$((j - 1))]}" -v x=$XFADE 'BEGIN{printf "%.3f", a + d - x}')
  out="[x$j]"
  [ $j = $((n - 1)) ] && out="[vx]"
  fc+="${prev}[${j}:v]xfade=transition=fade:duration=$XFADE:offset=${acc}${out};"
  prev=$out
done
SUM=0
for d in "${DURS[@]}"; do SUM=$(awk -v a="$SUM" -v b="$d" 'BEGIN{printf "%.3f", a+b}'); done
TOTAL=$(awk -v s="$SUM" -v x="$XFADE" -v n="$n" 'BEGIN{printf "%.3f", s - x*(n-1)}')
echo "длительность интро: ${TOTAL}s"

# ---------------------------------------------------------------- звук интро
AUD="$WORK/intro-audio.m4a"
"$FF" -hide_banner -loglevel error -y -f lavfi \
  -i "anoisesrc=color=brown:seed=7:amplitude=0.55:duration=$TOTAL" \
  -f lavfi -i "sine=frequency=53:duration=$TOTAL" \
  -f lavfi -i "sine=frequency=79.5:duration=$TOTAL" \
  -filter_complex \
  "[0:a]lowpass=f=420,volume='0.30+0.16*sin(2*PI*t/9)':eval=frame,afade=t=in:d=2.5,afade=t=out:st=$(awk -v t=$TOTAL 'BEGIN{printf "%.2f", t-2.2}'):d=2.2[wind];\
   [1:a]volume=0.10,afade=t=in:st=1:d=3[dr1];[2:a]volume=0.06,afade=t=in:st=2:d=4[dr2];\
   [dr1][dr2]amix=inputs=2:normalize=0[drone];\
   [wind][drone]amix=inputs=2:normalize=0,highpass=f=28,alimiter=limit=0.85[a]" \
  -map "[a]" -c:a aac -b:a 96k "$AUD"

# ---------------------------------------------------------------- финальная сборка
"$FF" -hide_banner -loglevel error -y "${INPUTS[@]}" -i "$AUD" -filter_complex \
  "${fc}[vx]fade=t=in:st=0:d=0.8,format=yuv420p[vo]" \
  -map "[vo]" -map "${n}:a" -t "$TOTAL" -r $FPS \
  -c:v libx264 -preset slow -crf 25 -movflags +faststart -c:a aac -b:a 96k \
  "$OUT/splash-intro.mp4"
"$FF" -hide_banner -loglevel error -y -i "$OUT/splash-intro.mp4" \
  -c:v libtheora -q:v 5 -c:a libvorbis -q:a 3 -vf "scale=${W}:${H}" \
  "$OUT/splash-intro.ogv"

# постер для сайта + кадр титров
"$FF" -hide_banner -loglevel error -y -ss $(awk -v t=$TOTAL 'BEGIN{printf "%.2f", t-13}') -i "$OUT/splash-intro.mp4" \
  -frames:v 1 "$WORK/intro-title.png"
convert "$WORK/intro-title.png" -resize "1400x1400>" -quality 82 -define webp:method=6 "$PREV/splash-title-card.webp"

# ---------------------------------------------------------------- заставка пробуждения
A="$WORK/aw"; rm -rf "$A"; mkdir -p "$A"
convert -size "${W}x${H}" xc:black "$A/0-base.png"
card "$A/0-a.png" 24 "#7f93a9-r" 0 "ЗЕМЛЯ · ПЕЛЕНА · 3610 · СУТКИ 1"
grade "$PREV/06-awakening.webp" "$A/1-base.png"
card "$A/1-hud.png" 22 "#c9f0d0-r" -286 "кислород 6:20:14 · скафандр 62% · фонарь 1/4"
card "$A/1-b.png" 34 "#eaf1f8" 250 "дыши тише"
convert -size "${W}x${H}" xc:black "$A/2-base.png"
card "$A/2-a.png" 54 "#f2f6fb" -30 "ПРОБУЖДЕНИЕ"
card "$A/2-b.png" 22 "#9fb2c7-r" 34 "АКТ I · «ПЕПЕЛ И ЖЕТОН» · ты проснулся на «Сите» с чужим ключом в руке"

seg2() {
  local nn=$1 dur=$2; shift 2
  local inputs=(-loop 1 -t "$dur" -i "$A/$nn-base.png")
  fc="[0:v]fps=$FPS,scale=2560:1440,format=rgba,zoompan=z='min(1.0009*on\,1.14)':d=1:x='iw/2-(iw/zoom/2)':y='ih/3-(ih/zoom/3)':s=${W}x${H}:fps=${FPS}[bg]"
  local last=bg k=1 spec o st du
  for spec in "$@"; do
    IFS='|' read -r o st du <<<"$spec"
    inputs+=(-loop 1 -t "$dur" -i "$o")
    fc+=";[${k}:v]format=rgba,fade=t=in:st=${st}:d=0.8:alpha=1${du:+,fade=t=out:st=${du}:d=0.6:alpha=1}[t${k}]"
    fc+=";[${last}][t${k}]overlay=0:0:eof_action=pass[o${k}]"
    last="o$k"; k=$((k + 1))
  done
  fc+=";[${last}]format=yuv420p[v]"
  "$FF" -hide_banner -loglevel error -y "${inputs[@]}" -filter_complex "$fc" -map "[v]" \
    -t "$dur" -r $FPS -c:v libx264 -preset medium -crf 20 "$A/$nn.mp4"
  echo "$A/$nn.mp4"
}
echo "→ сегменты пробуждения"
AW0=$(seg2 0 3.0 "$A/0-a.png|0.8|2.2")
AW1=$(seg2 1 7.0 "$A/1-hud.png|1.2|7.0" "$A/1-b.png|3.4|7.0")
AW2=$(seg2 2 4.2 "$A/2-a.png|0.2|4.2" "$A/2-b.png|0.9|4.2")
ATOTAL=13.2
"$FF" -hide_banner -loglevel error -y -i "$AW0" -i "$AW1" -i "$AW2" -filter_complex \
  "[0:v][1:v]xfade=transition=fadeblack:duration=0.5:offset=2.5[a];[a][2:v]xfade=transition=fadeblack:duration=0.5:offset=8.6,format=yuv420p,fade=t=out:st=12.7:d=0.5[v]" \
  -map "[v]" -r $FPS -c:v libx264 -preset slow -crf 24 "$WORK/aw-silent.mp4"
"$FF" -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=44:duration=$ATOTAL" \
  -f lavfi -i "anoisesrc=color=pink:seed=3:amplitude=0.35:duration=$ATOTAL" \
  -filter_complex \
  "[0:a]volume='0.22*exp(-6*mod(t,1.05))+0.05':eval=frame,lowpass=f=140[heart];\
   [1:a]bandpass=f=520:width_type=h:w=380,volume='0.05+0.05*sin(2*PI*t/3.1)':eval=frame[breath];\
   [heart][breath]amix=inputs=2:normalize=0,afade=t=in:d=1,afade=t=out:st=12.3:d=0.9,alimiter=limit=0.8[a]" \
  -map "[a]" -c:a aac -b:a 96k "$WORK/aw-audio.m4a"
"$FF" -hide_banner -loglevel error -y -i "$WORK/aw-silent.mp4" -i "$WORK/aw-audio.m4a" \
  -map 0:v -map 1:a -c:v copy -c:a copy -shortest -movflags +faststart "$OUT/splash-awakening.mp4"
"$FF" -hide_banner -loglevel error -y -i "$OUT/splash-awakening.mp4" \
  -c:v libtheora -q:v 5 -c:a libvorbis -q:a 3 "$OUT/splash-awakening.ogv"
"$FF" -hide_banner -loglevel error -y -ss 5.5 -i "$OUT/splash-awakening.mp4" -frames:v 1 "$WORK/aw-frame.png"
convert "$WORK/aw-frame.png" -resize "1400x1400>" -quality 82 -define webp:method=6 "$PREV/splash-awakening-frame.webp"

# ---------------------------------------------------------------- производные: сайт + Godot
# 1) вебовские mp4 в content/video — их показывает сайт (маленькие, со своим poster);
#    исходники в media/splash/ остаются для движка и не публикуются на Pages.
WEB="$ROOT/game-docs/src/content/video"
mkdir -p "$WEB"
for v in splash-intro splash-awakening; do
  "$FF" -hide_banner -loglevel error -y -i "$OUT/$v.mp4" -vf "scale=960:-2,fps=$FPS" \
    -c:v libx264 -preset slow -crf 33 -pix_fmt yuv420p -c:a aac -b:a 64k -movflags +faststart \
    "$WEB/$v.mp4"
done
# 2) boot_splash.png — картинка, которая грузится ДО сцены заставки (project.godot:
#    application/boot_splash). Здесь нет «нажми любую кнопку»: на этом этапе ещё нечего нажимать.
convert "$S/06-base.png" "$S/06-t.png" -gravity center -composite "$WORK/boot-1.png"
convert "$WORK/boot-1.png" "$S/06-s.png" -gravity center -composite "$OUT/boot_splash.png"
# 3) постер для <video> на сайте = кадр с титрами (уже лежит как splash-title-card.webp)

# ---------------------------------------------------------------- webp-петли для сайта
if [ "$DO_LOOPS" = 1 ]; then
  echo "→ анимированные петли (600 px, 8 fps)"
  "$FF" -hide_banner -loglevel error -y -i "$OUT/splash-intro.mp4" -ss 3.6 -t 4.8 \
    -vf "fps=8,scale=600:-1" -c:v libwebp_anim -quality 72 -compression_level 6 \
    -loop 0 "$PREV/splash-intro-loop.webp" || rm -f "$PREV/splash-intro-loop.webp"
  "$FF" -hide_banner -loglevel error -y -i "$OUT/splash-awakening.mp4" -ss 2.5 -t 4.8 \
    -vf "fps=8,scale=600:-1" -c:v libwebp_anim -quality 72 -compression_level 6 \
    -loop 0 "$PREV/splash-awakening-loop.webp" || rm -f "$PREV/splash-awakening-loop.webp"
fi

ls -l "$OUT" "$PREV"
echo "готово."
