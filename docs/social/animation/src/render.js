const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, arr) => (v.startsWith('--') ? a.concat([[v.slice(2), arr[i + 1] && !arr[i + 1].startsWith('--') ? arr[i + 1] : true]]) : a), []));
const MODE = args.mode || 'hero', ASPECT = args.aspect || '16x9', SCALE = parseFloat(args.scale || '1');
const FPS = parseFloat(args.fps || '60'), WORKERS = parseInt(args.workers || '3', 10);
const FFMPEG = process.env.FFMPEG || 'ffmpeg';
const url = 'file://' + path.join(__dirname, 'index.html') + `?mode=${MODE}&aspect=${ASPECT}&scale=${SCALE}`;

async function openPage(browser) {
  const W = Math.round((ASPECT === '1x1' ? 1080 : 1920) * SCALE), H = Math.round(1080 * SCALE);
  const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
  page.on('pageerror', e => { console.error('PAGE ERROR', e); process.exit(1); });
  page.on('console', m => { if (m.type() === 'error') console.error('console:', m.text()); });
  await page.goto(url);
  await page.waitForFunction(() => window.SCENE);
  await page.evaluate(() => window.SCENE.ready);
  const info = await page.evaluate(() => ({ W: SCENE.W, H: SCENE.H, duration: SCENE.duration, float: SCENE.float }));
  const cdp = await page.context().newCDPSession(page);
  return { page, cdp, info };
}
async function grab(ctx, t, fi) {
  await ctx.page.evaluate(([t, fi]) => window.SCENE.renderFrame(t, fi), [t, fi]);
  const r = await ctx.cdp.send('Page.captureScreenshot', { format: 'png', optimizeForSpeed: true, captureBeyondViewport: false, clip: { x: 0, y: 0, width: ctx.info.W, height: ctx.info.H, scale: 1 } });
  return Buffer.from(r.data, 'base64');
}
const launch = () => chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--disable-accelerated-2d-canvas', '--disable-gpu-vsync', '--allow-file-access-from-files'] });

(async () => {
  if (args.events) {
    const b = await launch(); const c = await openPage(b);
    const ev = await c.page.evaluate(() => window.SCENE.events());
    fs.writeFileSync(args.events, JSON.stringify(ev, null, 1)); await b.close(); return;
  }
  if (args.times) {
    const b = await launch(); const c = await openPage(b);
    fs.mkdirSync(args.outdir, { recursive: true });
    for (const ts of String(args.times).split(',')) {
      const t = parseFloat(ts), t0 = Date.now();
      const buf = await grab(c, t, Math.round(t * FPS));
      const f = path.join(args.outdir, `${args.prefix || ''}${ASPECT}_${t.toFixed(2)}.png`); fs.writeFileSync(f, buf);
      console.log(f, Date.now() - t0, 'ms');
    }
    await b.close(); return;
  }

  const probeB = await launch(); const probe = await openPage(probeB); const { duration, W, H } = probe.info; await probeB.close();
  const N = args.frames ? parseInt(args.frames, 10) : Math.round(duration * FPS);
  const outFile = args.video, tmp = outFile + '.parts'; fs.mkdirSync(tmp, { recursive: true });
  const chunk = Math.ceil(N / WORKERS); const started = Date.now(); let done = 0;
  await Promise.all(Array.from({ length: WORKERS }, async (_, w) => {
    const a = w * chunk, bEnd = Math.min(N, a + chunk); if (a >= bEnd) return;
    const br = await launch(); const ctx = await openPage(br);
    const seg = path.join(tmp, `part${w}.mkv`);
    const ff = spawn(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-', '-c:v', 'libx264rgb', '-qp', '0', '-preset', 'ultrafast', seg], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let f = a; f < bEnd; f++) {
      const buf = await grab(ctx, f / FPS, f);
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      done++; if (done % 30 === 0) process.stdout.write(`\r${done}/${N} frames  ${((Date.now() - started) / done).toFixed(0)} ms/frame`);
    }
    ff.stdin.end(); await new Promise(r => ff.on('close', r)); await br.close();
  }));
  const list = path.join(tmp, 'list.txt');
  fs.writeFileSync(list, Array.from({ length: WORKERS }, (_, w) => path.join(tmp, `part${w}.mkv`)).filter(f => fs.existsSync(f)).map(f => `file '${f}'`).join('\n'));
  await new Promise((res, rej) => spawn(FFMPEG, ['-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list, '-c', 'copy', outFile], { stdio: 'inherit' }).on('close', c => (c ? rej(new Error('concat failed')) : res())));
  fs.rmSync(tmp, { recursive: true, force: true });
  console.log(`\nwrote ${outFile} (${N} frames, ${W}x${H}) in ${((Date.now() - started) / 1000).toFixed(0)} s`);
})().catch(e => { console.error(e); process.exit(1); });
