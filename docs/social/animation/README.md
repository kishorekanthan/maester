# Maester launch animation: "The Glance"

The two capsules of the Maester mark are eyes that keep watch over your Mac. They wake up, read CPU, GPU, memory, disk and I/O, react to the warn, error and sleep states, drop into the menu bar, and resolve on the end card: **"Eyes on your Mac. Never on you."**

| File | What it is | Use it for |
| --- | --- | --- |
| `maester-glance-16x9.mp4` | Hero, 1920×1080, 60 fps, 11.7 s, H.264 High + AAC (−16 LUFS) | X, LinkedIn, Reddit |
| `maester-glance-16x9-silent.mp4` | Same video with no audio track | Autoplay-muted embeds, Reddit, slides |
| `maester-glance-1x1.mp4` | Hero re-laid out for a square frame, 1080×1080, 60 fps, with sound | LinkedIn and X feeds |
| `maester-glance-1x1-silent.mp4` | Square version with no audio track | Muted feeds |
| `maester-loop.mp4` | Seamless 3.6 s idle loop of the icon, 1080×1080, silent | Reddit, site headers |
| `maester-loop.gif` | The same loop at 540 px, 30 fps (about 1.1 MB) | README header; HN visitors who click through |
| `poster-16x9.png`, `poster-1x1.png` | End-card stills | Video thumbnails and link previews |
| `contact-sheet.png` | The 16:9 hero sampled every 0.5 s | Review |

## Re-rendering

Run `docs/social/animation/src/build.sh`. It needs node with the `playwright` npm package (Chromium), python3 with numpy and Pillow, and ffmpeg with libx264. On 4 cores it takes about 13 minutes.

Environment variables:

- `WORK`: where intermediates go (default `/tmp/maester-anim`).
- `WORKERS`: parallel browser workers (default 3).
- `CRF`: x264 quality for the hero videos (default 16).
- `FFMPEG`: path to ffmpeg (defaults to the one on `PATH`, then `imageio_ffmpeg`).
- `SKIP_RENDER=1`: re-encode from existing masters without rendering frames again.
- `POSTER_T`: time of the poster still in seconds (default 11.2).

The script runs four stages:

1. **Sound.** It dumps the cue list, synthesises the audio, then masters it: a gentle compressor, a limiter, then two-pass linear `loudnorm` to −16 LUFS integrated, −1.5 dBTP.
2. **Frames.** It renders three lossless RGB masters: hero 16:9, hero 1:1 and the loop.
3. **Encodes.** H.264 High, yuv420p, BT.709 tags, +faststart, AAC 192 kb/s. The silent files are stream copies of the video. The loop MP4 uses constant QP 10 with keyframes on its first and last frames, so they decode bit-identically. The GIF uses an ordered-dither palette.
4. **Stills.** The posters are taken from the masters and the contact sheet is built from the 16:9 hero.

## How the source works

- `src/scene.js` draws every frame as a pure function of time. Canvas2D draws the layers, then a WebGL pass adds bloom, radial blur, chromatic aberration, vignette and grain. Motion blur comes from averaging several sub-frame renders within a 180° shutter. The readout digits use the frame's centre time, so they never blur into two glyphs. URL parameters: `mode=hero|loop`, `aspect=16x9|1x1`, `scale`.
- `src/render.js` loads `index.html` in headless Chromium, steps `SCENE.renderFrame(t)` frame by frame across parallel workers, and pipes PNGs into ffmpeg. `--times a,b,c --outdir d` writes preview stills, and `--events file` writes the sound cue list.
- `src/sfx.py` synthesises every sound with numpy (no samples) from that cue list. Because the cues come from the same timeline constants the renderer uses, each sound lands on its frame.
- `src/maester-mark.svg` is the mark, rebuilt by a least-squares fit to `Resources/Maester.icns`. Both capsules are 310 × 436 units with a 76-unit bottom radius and a 122 × 206 slot, tilted 12.0° and 3.94°. The slash runs at 11.99° and is 26.2 units thick, and the gap is 28.3 units.

## Fonts

All fonts are SIL OFL and live in `src/fonts`. They load from local files because the renderer has no network access.

- **Bricolage Grotesque** sets the end card: wordmark 800, slogan 700, meta line 500, URL 600. The local file is Google Fonts' latin subset, instanced at optical size 14 with the weight axis kept variable. That is the cut Google Fonts serves by default, and the one the approved mockup used; canvas text can't select an optical size, so it has to be fixed in the file.
- **JetBrains Mono** sets the readouts.
- **Inter** sets the menu bar.
