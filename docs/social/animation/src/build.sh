#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; OUT="$(dirname "$SRC")"
WORK="${WORK:-/tmp/maester-anim}"; mkdir -p "$WORK"
FFMPEG="${FFMPEG:-$(command -v ffmpeg || python3 -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())')}"
export FFMPEG NODE_PATH="${NODE_PATH:-$(npm root -g)}"
WORKERS="${WORKERS:-3}"
ff() { "$FFMPEG" -hide_banner -loglevel error -y "$@"; }
COLOR=(-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv)
TOYUV="scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,format=yuv420p"

echo "== 1/4 sound (cue list comes from the renderer's timeline)"
node "$SRC/render.js" --events "$WORK/events.json"
python3 "$SRC/sfx.py" "$WORK/events.json" "$WORK/sfx_raw.wav"
PRE="acompressor=threshold=-26dB:ratio=2.5:attack=4:release=140:makeup=2,alimiter=level_in=2.2:limit=0.5:attack=2:release=60:level=disabled"
MEAS=$("$FFMPEG" -hide_banner -i "$WORK/sfx_raw.wav" -af "$PRE,loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json" -f null - 2>&1 | sed -n '/^{/,/^}/p')
LN=$(python3 -c "import json,sys;m=json.loads(sys.argv[1]);print(f\"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}:measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}:linear=true\")" "$MEAS")
ff -i "$WORK/sfx_raw.wav" -af "$PRE,$LN" -ar 48000 -c:a pcm_s16le "$WORK/sfx.wav"

if [ -z "${SKIP_RENDER:-}" ]; then
  echo "== 2/4 frames (deterministic, 60 fps, lossless RGB masters)"
  node "$SRC/render.js" --mode hero --aspect 16x9 --video "$WORK/hero_16x9.mkv" --workers "$WORKERS"
  node "$SRC/render.js" --mode hero --aspect 1x1 --video "$WORK/hero_1x1.mkv" --workers "$WORKERS"
  node "$SRC/render.js" --mode loop --aspect 1x1 --video "$WORK/loop_1x1.mkv" --workers "$WORKERS"
fi

echo "== 3/4 encodes"
X264=(-c:v libx264 -profile:v high -level 4.2 -preset slow -crf ${CRF:-16} -g 120 -r 60 "${COLOR[@]}" -movflags +faststart)
ff -i "$WORK/hero_16x9.mkv" -i "$WORK/sfx.wav" -map 0:v -map 1:a -vf "$TOYUV" "${X264[@]}" -c:a aac -b:a 192k -ar 48000 -shortest "$OUT/maester-glance-16x9.mp4"
ff -i "$OUT/maester-glance-16x9.mp4" -map 0:v -c:v copy -an -movflags +faststart "$OUT/maester-glance-16x9-silent.mp4"
ff -i "$WORK/hero_1x1.mkv" -i "$WORK/sfx.wav" -map 0:v -map 1:a -vf "$TOYUV" "${X264[@]}" -c:a aac -b:a 192k -ar 48000 -shortest "$OUT/maester-glance-1x1.mp4"
ff -i "$OUT/maester-glance-1x1.mp4" -map 0:v -c:v copy -an -movflags +faststart "$OUT/maester-glance-1x1-silent.mp4"
ff -i "$WORK/loop_1x1.mkv" -vf "$TOYUV" -c:v libx264 -profile:v high -level 4.2 -preset slow -qp 10 -force_key_frames 0,3.583 -g 240 -r 60 "${COLOR[@]}" -movflags +faststart -an "$OUT/maester-loop.mp4"
ff -i "$WORK/loop_1x1.mkv" -vf "fps=30,scale=540:540:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle" -loop 0 "$OUT/maester-loop.gif"

echo "== 4/4 stills"
POSTER_T="${POSTER_T:-11.2}"
ff -ss "$POSTER_T" -i "$WORK/hero_16x9.mkv" -frames:v 1 "$OUT/poster-16x9.png"
ff -ss "$POSTER_T" -i "$WORK/hero_1x1.mkv" -frames:v 1 "$OUT/poster-1x1.png"
rm -rf "$WORK/sheet"; mkdir -p "$WORK/sheet"
ff -i "$WORK/hero_16x9.mkv" -vf "fps=2,scale=480:270:flags=lanczos" "$WORK/sheet/f_%03d.png"
python3 - "$WORK/sheet" "$OUT/contact-sheet.png" <<'PY'
import glob, sys
from PIL import Image, ImageDraw, ImageFont
fs = sorted(glob.glob(sys.argv[1] + '/f_*.png')); cols = 6; tw, th, lab = 480, 270, 30
rows = (len(fs) + cols - 1) // cols
M = Image.new('RGB', (cols * tw + (cols + 1) * 8, rows * (th + lab) + (rows + 1) * 8), (14, 18, 16))
d = ImageDraw.Draw(M)
try: font = ImageFont.truetype('DejaVuSans.ttf', 18)
except Exception: font = ImageFont.load_default()
for i, f in enumerate(fs):
    x = 8 + (i % cols) * (tw + 8); y = 8 + (i // cols) * (th + lab + 8)
    M.paste(Image.open(f).convert('RGB'), (x, y + lab)); d.text((x + 2, y + 5), f'{i * 0.5:.1f} s', fill=(166, 245, 200), font=font)
M.save(sys.argv[2], optimize=True)
PY

echo "== QA"
for f in maester-glance-16x9.mp4 maester-glance-16x9-silent.mp4 maester-glance-1x1.mp4 maester-glance-1x1-silent.mp4 maester-loop.mp4 maester-loop.gif poster-16x9.png poster-1x1.png contact-sheet.png; do
  printf '%-34s %8s KB\n' "$f" "$(( $(stat -c %s "$OUT/$f") / 1024 ))"
done
"$FFMPEG" -hide_banner -i "$OUT/maester-glance-16x9.mp4" -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary/,$p' | grep -E "I:|Peak:|LRA:" || true
