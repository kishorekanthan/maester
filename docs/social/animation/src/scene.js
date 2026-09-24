(() => {
'use strict';
const Q = new URLSearchParams(location.search);
const MODE = Q.get('mode') || 'hero';
const ASPECT = Q.get('aspect') || '16x9';
const SCALE = parseFloat(Q.get('scale') || '1');
const SQ = ASPECT === '1x1';
const W = Math.round((SQ ? 1080 : 1920) * SCALE), H = Math.round(1080 * SCALE);
const S = H / 1080;
const BASE = 0.654 * S;
const FPS = 60;

const PI = Math.PI, TAU = 2 * PI, D2R = PI / 180;
const clamp = (x, a = 0, b = 1) => (x < a ? a : x > b ? b : x);
const lerp = (a, b, k) => a + (b - a) * k;
const seg = (t, a, b) => clamp((t - a) / (b - a));
const sstep = (a, b, x) => { const k = seg(x, a, b); return k * k * (3 - 2 * k); };
const E = {
  lin: k => k,
  inOutSine: k => -(Math.cos(PI * k) - 1) / 2,
  outSine: k => Math.sin(k * PI / 2),
  inCubic: k => k * k * k,
  outCubic: k => 1 - (1 - k) ** 3,
  inOutCubic: k => (k < 0.5 ? 4 * k * k * k : 1 - (-2 * k + 2) ** 3 / 2),
  outQuart: k => 1 - (1 - k) ** 4,
  inOutQuart: k => (k < 0.5 ? 8 * k ** 4 : 1 - (-2 * k + 2) ** 4 / 2),
  outQuint: k => 1 - (1 - k) ** 5,
  inOutQuint: k => (k < 0.5 ? 16 * k ** 5 : 1 - (-2 * k + 2) ** 5 / 2),
  outExpo: k => (k >= 1 ? 1 : 1 - 2 ** (-10 * k)),
  inExpo: k => (k <= 0 ? 0 : 2 ** (10 * k - 10)),
  inOutExpo: k => (k <= 0 ? 0 : k >= 1 ? 1 : k < 0.5 ? 2 ** (20 * k - 10) / 2 : (2 - 2 ** (-20 * k + 10)) / 2),
  outBack: (k, s = 1.70158) => 1 + (s + 1) * (k - 1) ** 3 + s * (k - 1) ** 2,
};

function spring(t, f = 2, z = 0.5) {
  if (t <= 0) return 0;
  const w = TAU * f, wd = w * Math.sqrt(1 - z * z);
  return 1 - Math.exp(-z * w * t) * (Math.cos(wd * t) + (z * w / wd) * Math.sin(wd * t));
}

function kf(t, keys) {
  if (t <= keys[0][0]) return keys[0][1];
  for (let i = 1; i < keys.length; i++) {
    const [t1, v1, e] = keys[i];
    if (t <= t1) { const [t0, v0] = keys[i - 1]; return lerp(v0, v1, (e || E.inOutCubic)(seg(t, t0, t1))); }
  }
  return keys[keys.length - 1][1];
}
const hash = n => { const s = Math.sin(n * 127.1 + 311.7) * 43758.5453; return s - Math.floor(s); };
function vnoise(x) { const i = Math.floor(x), f = x - i, u = f * f * (3 - 2 * f); return lerp(hash(i), hash(i + 1), u); }
function mulberry32(a) { return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }
const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
const mixc = (a, b, k) => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
const rgba = (c, a = 1) => `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${clamp(a).toFixed(4)})`;
const desat = (c, k, br = 1) => { const l = 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]; return [lerp(c[0], l, k) * br, lerp(c[1], l, k) * br, lerp(c[2], l, k) * br]; };
const pulse = (t, a, peak, b) => (t < a || t > b ? 0 : t < peak ? E.outCubic(seg(t, a, peak)) : 1 - E.inOutSine(seg(t, peak, b)));

const C = {
  green: hex('#4ade80'), cream: hex('#f2efe6'), dark: hex('#12241c'), mint: hex('#a6f5c8'),
  white: [255, 255, 255], sil: hex('#0c1a14'), pupil: hex('#0e1c16'),
  glowCalm: hex('#1d9e5e'), glowWarn: hex('#e8900c'), glowErr: hex('#ec2f55'), glowSleep: hex('#5a5890'),
  accWarn: hex('#fbbf24'), accErr: hex('#fb7185'), accSleep: hex('#a9a6d6'),
  trCalm: hex('#a6f5c8'), trWarn: hex('#fcd34d'), trErr: hex('#fda4af'), trSleep: hex('#8f8db3'),
};

const BODY = { w: 310, h: 436, rb: 76 };
const SLOT = { w: 122, h: 206, y: -21 };
const GREEN = { cx: 385.3, cy: 491.5, a: 12.0 };
const CREAM = { cx: 639.9, cy: 545.6, a: 3.94 };
const GAP = 28.3;
const SL = { x: 206.1, y: 570.0, a: 11.99, t: 26.2 };
const MC = { x: 505, y: 520 };
const EYE = { x: 515, y: 500 };
const BADGE = { x: 808, y: 322, r: 74, ring: 18 };
const slashY = x => SL.y + (x - SL.x) * Math.tan(SL.a * D2R);
for (const b of [GREEN, CREAM]) {
  const r = b.a * D2R, c = Math.cos(r), s = Math.sin(r), dx = SL.x - b.cx, dy = SL.y - b.cy;
  b.lp = [c * dx + s * dy, -s * dx + c * dy]; b.la = SL.a - b.a;
}
function makeBodyPath() {
  const hw = BODY.w / 2, hh = BODY.h / 2, rb = BODY.rb, p = new Path2D();
  p.moveTo(-hw, -hh + hw); p.arc(0, -hh + hw, hw, PI, 0); p.lineTo(hw, hh - rb);
  p.arc(hw - rb, hh - rb, rb, 0, PI / 2); p.lineTo(-hw + rb, hh); p.arc(-hw + rb, hh - rb, rb, PI / 2, PI); p.closePath();
  return p;
}
const BP = makeBodyPath();

const TL = {
  riseG: 0.26, riseC: 0.42,
  slash: 1.45, slashEnd: 1.63,
  flood: 1.53, floodEnd: 2.0,
  sheen: 1.95,
  zoomIn: 2.2, zoomInEnd: 2.75,
  open: 2.5,
  traces: 2.62,
  sweep: 2.95, sweepEnd: 3.75,
  glL: 3.05, glR: 3.5, glC: 3.95, blink: 4.28,
  conv: 3.3,
  pull: 4.45, pullEnd: 4.9,
  warn: 4.8, error: 5.5, sleep: 6.2, calm: 6.9,
  whip: 7.3, land: 7.62, mbBlink: 7.8,
  out: 8.0, outEnd: 8.42,
  card: 8.18, second: 8.88, cardBlink: 10.15,
  end: 11.7,
};
const ZT = SQ ? 1.62 : 2.3;
const ZS = SQ ? 1.28 : 1.6;

const out = document.getElementById('out'); out.width = W; out.height = H;
const mk = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; const x = c.getContext('2d'); return [c, x]; };
const [scene, sx] = mk(W, H);
const BW = Math.round(W / 2), BH = Math.round(H / 2);
const [bgc, bx] = mk(BW, BH);
const [bgc2, bx2] = mk(BW, BH);
const [cre, cx1] = mk(W, H);
const [grn, cx2] = mk(W, H);
const GW = Math.round(W / 4), GH = Math.round(H / 4);
const [glw, gx] = mk(GW, GH);
const [glw2, gx2] = mk(Math.round(W / 8), Math.round(H / 8));

function camera(t) {
  let z = kf(t, [[0, 0.96], [1.45, 1.1, E.inOutSine], [1.585, 1.36, E.outExpo], [2.2, 1.2, E.inOutCubic],
    [TL.zoomInEnd, ZT, E.inOutQuint], [TL.pull, ZT + 0.12, E.inOutSine], [TL.pullEnd, ZS, E.inOutQuint],
    [TL.whip, ZS + 0.07, E.inOutSine], [TL.land, 0.5, E.inOutExpo], [TL.out, 0.47, E.lin], [TL.outEnd + 0.3, 0.92, E.inOutCubic],
    [TL.end, 0.86, E.outCubic]]);
  let cx = kf(t, [[TL.zoomIn, MC.x], [TL.zoomInEnd, EYE.x, E.inOutQuint], [TL.pull, EYE.x], [TL.pullEnd, MC.x, E.inOutQuint]]);
  let cy = kf(t, [[TL.zoomIn, MC.y], [TL.zoomInEnd, EYE.y, E.inOutQuint], [TL.pull, EYE.y], [TL.pullEnd, MC.y + 10, E.inOutQuint]]);

  const g = glance(t); const follow = seg(t, 2.6, 2.9) * (1 - seg(t, TL.pull, TL.pull + 0.3));
  cx += g.ox * 0.35 * follow; cy += g.oy * 0.3 * follow;

  z += 0.05 * pulse(t, TL.warn, TL.warn + 0.12, TL.error) ;
  const eT = t - TL.error; let shx = 0, shy = 0;
  if (eT > 0 && eT < 0.5) { const a = Math.exp(-eT * 9) * 9; shx = a * Math.sin(eT * TAU * 17); shy = a * 0.6 * Math.sin(eT * TAU * 23 + 1); }
  cy += 8 * sstep(TL.sleep, TL.calm, t) * (1 - sstep(TL.calm, TL.calm + 0.3, t));

  const rb = 0.075 * pulse(t, 1.455, 1.51, 1.8) + 0.06 * pulse(t, TL.whip + 0.06, TL.whip + 0.2, TL.land - 0.02)
    + 0.035 * pulse(t, TL.zoomIn + 0.1, TL.zoomIn + 0.33, TL.zoomInEnd + 0.05) + 0.03 * pulse(t, TL.out, TL.out + 0.2, TL.out + 0.5);
  const ca = 0.009 * pulse(t, 1.455, 1.5, 1.85) + 0.008 * pulse(t, TL.whip + 0.06, TL.whip + 0.2, TL.land)
    + 0.004 * pulse(t, TL.error, TL.error + 0.04, TL.error + 0.3);
  return { z, cx: cx + shx, cy: cy + shy, rb, ca };
}
function w2s(x, y, cam, depth = 1) {
  const z = 1 + (cam.z - 1) * depth, s = BASE * z;
  const cxd = lerp(MC.x, cam.cx, depth), cyd = lerp(MC.y, cam.cy, depth);
  return [(x - cxd) * s + W / 2, (y - cyd) * s + H / 2, s];
}

function glance(t) {
  let ox = kf(t, [[TL.glL - 0.02, 0], [TL.glL + 0.16, -38, E.outBack], [TL.glR - 0.02, -38], [TL.glR + 0.18, 38, E.outBack],
    [TL.glC - 0.02, 38], [TL.glC + 0.2, 0, E.outBack]]);
  let oy = kf(t, [[TL.glC - 0.02, 0], [TL.glC + 0.2, -10, E.outBack], [TL.pull, -10], [TL.pullEnd, 0, E.inOutCubic]]);
  ox += kf(t, [[TL.second - 0.02, 0], [TL.second + 0.16, -32, E.outBack], [TL.cardBlink + 0.06, -32], [TL.cardBlink + 0.1, 0, E.inOutSine]]);
  oy += kf(t, [[TL.second - 0.02, 0], [TL.second + 0.16, 24, E.outBack], [TL.cardBlink + 0.06, 24], [TL.cardBlink + 0.1, 0, E.inOutSine]]);
  const att = pulse(t, TL.card + 0.1, TL.card + 0.4, TL.second + 0.1);
  return { ox, oy, att };
}
function blinkK(t, t0, d = 0.17) {
  const k = seg(t, t0, t0 + d); if (k <= 0 || k >= 1) return 1;
  return k < 0.4 ? lerp(1, 0.05, E.inOutSine(k / 0.4)) : lerp(0.05, 1, E.outCubic((k - 0.4) / 0.6));
}
function stateW(t) {
  const warn = sstep(TL.warn, TL.warn + 0.12, t) * (1 - sstep(TL.error, TL.error + 0.12, t));
  const error = sstep(TL.error, TL.error + 0.12, t) * (1 - sstep(TL.sleep, TL.sleep + 0.14, t));
  const sleep = sstep(TL.sleep, TL.sleep + 0.2, t) * (1 - sstep(TL.calm, TL.calm + 0.16, t));
  return { warn, error, sleep, calm: 1 - warn - error - sleep };
}
function stateG(t) {
  const on = (a) => spring(t - a, 3.2, 0.42), off = (a) => clamp(spring(t - a, 3.4, 0.6), 0, 1.2);
  return {
    warn: on(TL.warn) * (1 - off(TL.error)),
    error: on(TL.error) * (1 - off(TL.sleep)),
    sleep: spring(t - TL.sleep, 1.6, 0.7) * (1 - clamp(spring(t - TL.calm, 3.0, 0.45), 0, 1.3)),
  };
}
const stateMix = (w, calm, warn, err, sleep) => {
  let c = calm.map(v => v * w.calm);
  c = c.map((v, i) => v + warn[i] * w.warn + err[i] * w.error + sleep[i] * w.sleep); return c;
};

function rise(t, t0, dir) {
  const k = spring(t - t0, 1.55, 0.52), dt = 1 / 240;
  const v = (spring(t - t0 + dt, 1.55, 0.52) - spring(t - t0 - dt, 1.55, 0.52)) / (2 * dt);
  const a = (spring(t - t0 + dt, 1.55, 0.52) - 2 * k + spring(t - t0 - dt, 1.55, 0.52)) / (dt * dt);
  const ty = (1 - k) * 1250;
  const vel = v * 1250;
  const stretch = 0.2 * Math.tanh(vel / 2600) - 0.11 * Math.tanh(Math.max(0, -a * 1250) / 16000) * seg(t, t0 + 0.2, t0 + 0.3);
  const sy = 1 + stretch, sxx = 1 / Math.sqrt(sy);
  const rk = spring(t - t0 - 0.05, 1.3, 0.45);
  return { tx: (1 - spring(t - t0, 1.2, 0.6)) * 70 * dir, ty, rot: (1 - rk) * -22 * dir, sx: sxx, sy, active: t > t0 - 0.01 };
}

function markParams(t) {
  const P = {};
  const g = rise(t, TL.riseG, 1), c = rise(t, TL.riseC, -1);
  const sw = stateW(t), sg = stateG(t);

  let open = kf(t, [[TL.open, 0], [TL.open + 0.12, 0.55, E.outCubic], [TL.open + 0.2, 0.12, E.inOutSine], [TL.open + 0.36, 1, E.outBack]]);
  open *= blinkK(t, TL.blink) * blinkK(t, TL.calm - 0.02, 0.2) * blinkK(t, TL.mbBlink, 0.16) * blinkK(t, TL.cardBlink, 0.2);
  const gl = glance(t);
  const slot = (side) => ({
    ox: gl.ox + sg.warn * 0 + sg.sleep * 0,
    oy: gl.oy - 12 * sg.warn + 8 * sg.error + 44 * sg.sleep,
    sx: (1 + 0.14 * sg.warn + 0.1 * sg.error - 0.02 * sg.sleep) * (1 + 0.07 * gl.att),
    sy: open * (1 + 0.14 * sg.warn - 0.68 * sg.error - 0.6 * sg.sleep) * (1 + 0.07 * gl.att),
    rot: side * 13 * sg.error,
  });
  const shakeT = t - TL.error; const shake = shakeT > 0 && shakeT < 0.45 ? Math.exp(-shakeT * 10) * 10 * Math.sin(shakeT * TAU * 19) : 0;
  P.g = { tx: g.tx + shake, ty: g.ty + 16 * sg.sleep, rot: g.rot - 4 * sg.sleep, sx: g.sx * (1 + 0.03 * sg.warn + 0.02 * sg.error), sy: g.sy * (1 + 0.03 * sg.warn - 0.03 * sg.error - 0.02 * sg.sleep), slot: slot(1), on: g.active };
  P.c = { tx: c.tx + shake, ty: c.ty + 16 * sg.sleep, rot: c.rot + 4 * sg.sleep, sx: c.sx * (1 + 0.03 * sg.warn + 0.02 * sg.error), sy: c.sy * (1 + 0.03 * sg.warn - 0.03 * sg.error - 0.02 * sg.sleep), slot: slot(-1), on: c.active };

  P.flood = 560 * E.outCubic(seg(t, TL.flood, TL.floodEnd));
  P.floodEdge = (1 - seg(t, TL.floodEnd - 0.15, TL.floodEnd + 0.1)) * seg(t, TL.flood, TL.flood + 0.03);
  P.rim = 0.9 * seg(t, 0.2, 0.8) * (1 - seg(t, TL.flood, TL.floodEnd + 0.2));

  P.head = lerp(-120, 1140, E.inOutQuart(seg(t, TL.slash, TL.slashEnd)));
  P.slashT = t < TL.slash ? 0 : lerp(0, SL.t, clamp(spring(t - TL.slash - 0.02, 3.2, 0.35), 0, 2));
  P.blade = t >= TL.slash && t < TL.slashEnd + 0.9;

  const ds = 0.72 * sw.sleep, br = 1 - 0.3 * sw.sleep;
  P.colG = desat(C.green, ds, br); P.colC = desat(C.cream, ds, br);
  P.mono = 0; P.square = 0;
  P.glowCol = stateMix(sw, C.glowCalm, C.glowWarn, C.glowErr, C.glowSleep);
  P.accent = stateMix(sw, C.mint, C.accWarn, C.accErr, C.accSleep);
  P.wash = 1 - sw.calm;
  P.glowK = 0.55 * seg(t, TL.flood, TL.floodEnd) * (1 - 0.45 * sw.sleep) + 0.35 * pulse(t, TL.calm, TL.calm + 0.1, TL.calm + 0.7);
  P.catch = 0.9 * seg(t, TL.open + 0.2, TL.open + 0.45) * (1 - seg(t, TL.whip, TL.whip + 0.2)) * (1 - 0.7 * sw.sleep);
  P.reflect = seg(t, TL.conv + 0.1, TL.conv + 0.5) * (1 - seg(t, TL.pull, TL.pullEnd)) + 0.6 * (sw.warn + sw.error) ;
  P.sheen = seg(t, TL.sheen, TL.sheen + 0.45);
  P.glint = [seg(t, TL.calm + 0.08, TL.calm + 0.5), seg(t, TL.card + 0.95, TL.card + 1.5)];

  P.badge = badgeState(t);
  return P;
}
function badgeState(t) {
  const pop = spring(t - TL.warn, 3.4, 0.4);
  const toErr = spring(t - TL.error, 3.6, 0.45);
  const toSleep = seg(t, TL.sleep, TL.sleep + 0.25);
  const gone = seg(t, TL.calm, TL.calm + 0.22);
  return {
    on: t > TL.warn && t < TL.calm + 0.25,
    scale: pop * (1 + 0.18 * pulse(t, TL.error, TL.error + 0.06, TL.error + 0.3)) * (1 + 0.5 * gone),
    fill: 1 - E.inOutCubic(toSleep), errK: clamp(toErr), errRot: (1 - clamp(toErr, 0, 1.2)) * -90,
    dots: E.outCubic(toSleep) * (1 - gone), spin: (t - TL.sleep) * 70, alpha: 1 - gone,
    col: mixc(mixc(C.accWarn, C.accErr, clamp(toErr)), C.accSleep, toSleep),
  };
}

function setX(c, X) { c.setTransform(1, 0, 0, 1, 0, 0); c.translate(X.x, X.y); c.rotate(X.rot * D2R); c.scale(X.s, X.s); c.translate(-MC.x, -MC.y); }
function bodyXf(c, b, st) {
  c.translate(b.cx + st.tx, b.cy + st.ty); c.rotate((b.a + st.rot) * D2R);
  c.translate(0, BODY.h / 2); c.scale(st.sx, st.sy); c.translate(0, -BODY.h / 2);
}
function slotPath(c, st) {
  const w = SLOT.w * st.slot.sx, h = Math.max(SLOT.h * st.slot.sy, 0.001);
  c.save(); c.translate(st.slot.ox, SLOT.y + st.slot.oy); c.rotate(st.slot.rot * D2R);
  c.beginPath(); c.roundRect(-w / 2, -h / 2, w, h, Math.min(w, h) / 2); c.restore();
  return { w, h };
}
function paintBody(c, X, b, st, col, P, isCream, t) {
  const brand = col;
  c.save(); setX(c, X); bodyXf(c, b, st);
  const full = P.flood >= 559;
  c.fillStyle = rgba(full ? brand : C.sil); c.fill(BP);
  c.save(); c.clip(BP);
  if (!full && P.flood > 0) {
    c.save(); c.translate(b.lp[0], b.lp[1]); c.rotate(b.la * D2R);
    c.fillStyle = rgba(brand); c.fillRect(-3000, -P.flood, 6000, 2 * P.flood);
    if (P.floodEdge > 0) {
      for (const sgn of [-1, 1]) {
        const y = sgn * P.flood, gr = c.createLinearGradient(0, y - sgn * 60, 0, y + sgn * 4);
        gr.addColorStop(0, rgba(C.mint, 0)); gr.addColorStop(0.85, rgba([225, 255, 238], 0.85 * P.floodEdge)); gr.addColorStop(1, rgba(C.white, 0));
        c.fillStyle = gr; c.fillRect(-3000, Math.min(y - sgn * 60, y + sgn * 4), 6000, 64);
      }
    }
    c.restore();
  }

  const gr = c.createLinearGradient(0, -BODY.h / 2, 0, BODY.h / 2);
  gr.addColorStop(0, 'rgba(255,255,255,0.035)'); gr.addColorStop(0.4, 'rgba(255,255,255,0)'); gr.addColorStop(1, 'rgba(0,30,12,0.13)');
  c.fillStyle = gr; c.fillRect(-BODY.w, -BODY.h, BODY.w * 2, BODY.h * 2);

  if (P.wash > 0.001) { c.globalCompositeOperation = 'source-atop'; c.fillStyle = rgba(P.accent, 0.10 * P.wash); c.fillRect(-BODY.w, -BODY.h, BODY.w * 2, BODY.h * 2); c.globalCompositeOperation = 'source-over'; }

  const rimA = Math.max(P.rim, 0.55 * P.wash);
  if (rimA > 0.01) {
    c.strokeStyle = rgba(P.rim > 0.3 * P.wash ? C.mint : P.accent, rimA); c.lineWidth = 5 / X.s * S + 3; c.stroke(BP);
    c.strokeStyle = rgba(C.white, rimA * 0.35); c.lineWidth = 1.2 / X.s * S + 0.6; c.stroke(BP);
  }
  c.restore();

  c.globalCompositeOperation = 'destination-out'; c.fillStyle = '#000';
  if (st.slot.sy * SLOT.h > 0.6) { slotPath(c, st); c.fill(); }
  if (P.slashT > 0.2) {
    c.save(); c.translate(b.lp[0], b.lp[1]); c.rotate(b.la * D2R);

    const hx = P.head, hy = slashY(hx);
    const inv = worldToLocal(b, st, hx, hy); const along = (inv[0] - b.lp[0]) * Math.cos(b.la * D2R) + (inv[1] - b.lp[1]) * Math.sin(b.la * D2R);
    c.fillRect(-3000, -P.slashT / 2, 3000 + along, P.slashT); c.restore();
  }
  c.restore();
  if (isCream) {
    c.globalCompositeOperation = 'destination-out'; c.fillStyle = '#000'; c.strokeStyle = '#000';
    c.save(); setX(c, X); bodyXf(c, GREEN, P.g);
    c.fill(BP); c.lineWidth = 2 * GAP / P.g.sx; c.lineJoin = 'round'; c.stroke(BP); c.restore();
    if (P.badge && P.badge.on && P.badge.fill > 0.01) {
      c.save(); setX(c, X); c.beginPath(); c.arc(BADGE.x, BADGE.y, (BADGE.r + BADGE.ring) * P.badge.scale * P.badge.fill, 0, TAU); c.fill(); c.restore();
    }
  }
  c.globalCompositeOperation = 'destination-over';
  if (st.slot.sy * SLOT.h > 0.6 && !P.mono) {
    c.save(); setX(c, X); bodyXf(c, b, st); slotPath(c, st); c.fillStyle = rgba(P.square ? C.dark : C.pupil); c.fill(); c.restore();
  }
  c.globalCompositeOperation = 'source-over';

  if (st.slot.sy * SLOT.h > 8 && (P.catch > 0.01 || P.reflect > 0.01)) {
    c.save(); setX(c, X); bodyXf(c, b, st); const d = slotPath(c, st); c.clip();
    c.translate(st.slot.ox, SLOT.y + st.slot.oy); c.rotate(st.slot.rot * D2R);
    if (P.reflect > 0.01) {
      const trc = P.accent;
      c.globalCompositeOperation = 'lighter';
      const rg = c.createRadialGradient(0, d.h * 0.35, 0, 0, d.h * 0.35, d.w * 0.9);
      rg.addColorStop(0, rgba(trc, 0.22 * P.reflect)); rg.addColorStop(1, rgba(trc, 0)); c.fillStyle = rg; c.fillRect(-d.w, -d.h, d.w * 2, d.h * 2);
      c.beginPath();
      for (let i = 0; i <= 24; i++) {
        const u = i / 24, x = (u - 0.5) * d.w * 1.1, v = traceVal(isCream ? 2 : 0, u, t);
        const y = d.h * 0.18 - v * d.h * 0.28; i ? c.lineTo(x, y) : c.moveTo(x, y);
      }
      c.strokeStyle = rgba(trc, 0.55 * P.reflect); c.lineWidth = 2.2; c.stroke();
      const sy = lerp(-d.h / 2, d.h / 2, (t * 0.9) % 1);
      c.fillStyle = rgba(trc, 0.18 * P.reflect); c.fillRect(-d.w, sy, d.w * 2, 2.5);
      c.globalCompositeOperation = 'source-over';
    }
    if (P.catch > 0.01) {
      const r = d.w * 0.11, x = -d.w * 0.16, y = -d.h / 2 + d.w * 0.34;
      const rg = c.createRadialGradient(x, y, 0, x, y, r * 1.6);
      rg.addColorStop(0, rgba(C.white, P.catch)); rg.addColorStop(0.55, rgba(C.white, P.catch * 0.95)); rg.addColorStop(0.64, rgba(C.white, P.catch * 0.15)); rg.addColorStop(1, rgba(C.white, 0));
      c.fillStyle = rg; c.beginPath(); c.arc(x, y, r * 1.6, 0, TAU); c.fill();
      c.fillStyle = rgba(C.white, P.catch * 0.55); c.beginPath(); c.arc(d.w * 0.12, -d.h / 2 + d.w * 0.62, r * 0.32, 0, TAU); c.fill();
    }
    c.restore();
  }
}
function worldToLocal(b, st, X, Y) {
  const dx = X - (b.cx + st.tx), dy = Y - (b.cy + st.ty), r = (b.a + st.rot) * D2R, c = Math.cos(r), s = Math.sin(r);
  let lx = c * dx + s * dy, ly = -s * dx + c * dy;
  lx /= st.sx; ly = (ly - BODY.h / 2) / st.sy + BODY.h / 2; return [lx, ly];
}
function paintBadge(c, X, B) {
  if (!B || !B.on || B.alpha <= 0.01) return;
  c.save(); setX(c, X); c.translate(BADGE.x, BADGE.y); c.globalAlpha = B.alpha;
  const r = BADGE.r * B.scale;
  if (B.fill > 0.01) {
    const rf = r * B.fill;
    c.fillStyle = rgba(B.col); c.beginPath(); c.arc(0, 0, rf, 0, TAU); c.fill();
    c.fillStyle = rgba(C.dark);

    c.save(); c.globalAlpha *= (1 - B.errK); c.scale(B.fill * B.scale, B.fill * B.scale);
    c.beginPath(); c.roundRect(-11, -46, 22, 58, 11); c.fill(); c.beginPath(); c.arc(0, 32, 12, 0, TAU); c.fill(); c.restore();
    c.save(); c.globalAlpha *= B.errK; c.scale(B.fill * B.scale, B.fill * B.scale); c.rotate((45 + B.errRot) * D2R);
    c.beginPath(); c.roundRect(-11, -42, 22, 84, 11); c.fill(); c.beginPath(); c.roundRect(-42, -11, 84, 22, 11); c.fill(); c.restore();
  }
  if (B.dots > 0.01) {
    c.rotate(B.spin * D2R); c.strokeStyle = rgba(B.col, B.dots); c.lineCap = 'round'; c.lineWidth = 14;
    const n = 12, rr = r * 0.78 * (0.6 + 0.4 * B.dots);
    for (let i = 0; i < n; i++) { const a = (i / n) * TAU; c.beginPath(); c.moveTo(Math.cos(a) * rr * 0.82, Math.sin(a) * rr * 0.82); c.lineTo(Math.cos(a) * rr * 1.08, Math.sin(a) * rr * 1.08); c.stroke(); }
  }
  c.restore();
}
function paintSquare(c, X, k, P) {
  if (k <= 0.001) return;
  c.save(); setX(c, X); c.globalAlpha = k;

  c.shadowColor = 'rgba(0,0,0,0.55)'; c.shadowBlur = 60 * X.s; c.shadowOffsetY = 26 * X.s;
  c.fillStyle = rgba(C.dark); c.beginPath(); c.roundRect(96, 96, 832, 832, 224); c.fill();
  c.shadowColor = 'transparent';
  const gr = c.createLinearGradient(0, 96, 0, 928); gr.addColorStop(0, 'rgba(255,255,255,0.05)'); gr.addColorStop(1, 'rgba(0,0,0,0.10)');
  c.fillStyle = gr; c.fill();
  c.strokeStyle = 'rgba(166,245,200,0.16)'; c.lineWidth = 10; c.beginPath(); c.roundRect(101, 101, 822, 822, 219); c.stroke();
  c.restore();
}
function paintSheen(c, X, k, dir = 1) {
  if (k <= 0 || k >= 1) return;
  c.save(); setX(c, X); c.globalCompositeOperation = 'source-atop';
  const x = lerp(80, 980, E.inOutSine(k));
  c.translate(x, 520); c.rotate(-24 * D2R);
  const gr = c.createLinearGradient(-90, 0, 90, 0);
  gr.addColorStop(0, 'rgba(255,255,255,0)'); gr.addColorStop(0.5, `rgba(255,255,255,${0.2 * Math.sin(k * PI)})`); gr.addColorStop(1, 'rgba(255,255,255,0)');
  c.fillStyle = gr; c.fillRect(-90, -700, 180, 1400); c.restore();
}
function paintGlint(c, X, k, a = 1, clipSq = false) {
  if (k <= 0 || k >= 1) return;
  const x = lerp(200, 800, E.inOutSine(k)), y = slashY(x) - SL.t / 2 - 2;
  c.save(); setX(c, X); c.globalCompositeOperation = 'lighter';
  if (clipSq) { c.beginPath(); c.roundRect(96, 96, 832, 832, 224); c.clip(); }
  const s = Math.sin(k * PI) * a;
  let rg = c.createRadialGradient(x, y, 0, x, y, 70); rg.addColorStop(0, `rgba(255,255,255,${0.9 * s})`); rg.addColorStop(0.2, `rgba(200,255,225,${0.35 * s})`); rg.addColorStop(1, 'rgba(166,245,200,0)');
  c.fillStyle = rg; c.beginPath(); c.arc(x, y, 70, 0, TAU); c.fill();
  c.translate(x, y); c.rotate(SL.a * D2R); c.scale(1, 0.04);
  rg = c.createRadialGradient(0, 0, 0, 0, 0, 260); rg.addColorStop(0, `rgba(230,255,240,${0.8 * s})`); rg.addColorStop(1, 'rgba(166,245,200,0)');
  c.fillStyle = rg; c.beginPath(); c.arc(0, 0, 260, 0, TAU); c.fill();
  c.restore();
}

function drawMark(ctx, X, P, t) {
  cx1.setTransform(1, 0, 0, 1, 0, 0); cx1.clearRect(0, 0, W, H);
  cx2.setTransform(1, 0, 0, 1, 0, 0); cx2.clearRect(0, 0, W, H);
  const colG = P.mono ? mixc(P.colG, C.white, P.mono) : P.colG, colC = P.mono ? mixc(P.colC, C.white, P.mono) : P.colC;
  if (P.c.on) paintBody(cx1, X, CREAM, P.c, colC, P, true, t);
  paintBadge(cx1, X, P.badge);
  if (P.g.on) paintBody(cx2, X, GREEN, P.g, colG, P, false, t);
  paintSheen(cx1, X, P.sheen); paintSheen(cx2, X, P.sheen);

  if (P.glowK > 0.005) {
    gx.setTransform(1, 0, 0, 1, 0, 0); gx.globalCompositeOperation = 'source-over'; gx.clearRect(0, 0, GW, GH);
    gx.filter = `blur(${(10 * S * Math.sqrt(X.s / BASE)).toFixed(2)}px)`; gx.drawImage(cre, 0, 0, GW, GH); gx.drawImage(grn, 0, 0, GW, GH); gx.filter = 'none';
    gx.globalCompositeOperation = 'source-in'; gx.fillStyle = rgba(P.glowCol); gx.fillRect(0, 0, GW, GH);
    ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = clamp(P.glowK); ctx.drawImage(glw, 0, 0, W, H); ctx.restore();
  }
  paintSquare(ctx, X, P.square, P);

  if (P.mono < 0.99) {
    ctx.save(); ctx.globalAlpha = 1 - P.mono; ctx.fillStyle = rgba(C.dark);
    for (const [b, st] of [[CREAM, P.c], [GREEN, P.g]]) { if (!st.on) continue; ctx.save(); setX(ctx, X); bodyXf(ctx, b, st); ctx.fill(BP); ctx.restore(); }
    ctx.restore();
  }
  ctx.drawImage(cre, 0, 0); ctx.drawImage(grn, 0, 0);
  for (const g of P.glint) paintGlint(ctx, X, g, P.square ? 0.8 : 1, P.square > 0.5);
}

const SPARKS = (() => {
  const r = mulberry32(7), list = [];
  const bursts = [[205, 26], [512, 16], [548, 20], [792, 26]];
  for (const [x0, n] of bursts) {
    const k = seg(x0, -120, 1140);
    let lo = 0, hi = 1; for (let i = 0; i < 30; i++) { const m = (lo + hi) / 2; (lerp(-120, 1140, E.inOutQuart(m)) < x0 ? (lo = m) : (hi = m)); }
    const tb = lerp(TL.slash, TL.slashEnd, lo);
    for (let i = 0; i < n; i++) {
      const ang = SL.a * D2R + (r() - 0.35) * 1.5 + (r() < 0.5 ? -PI / 2 : PI / 2) * r() * 0.8;
      const sp = 500 + r() * 1300;
      list.push({ t0: tb + r() * 0.03, x: x0, y: slashY(x0), vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp - 200 * r(), life: 0.28 + r() * 0.55, w: 1 + r() * 2.2 });
    }
  }

  for (let i = 0; i < 40; i++) {
    const m = r(), x0 = lerp(-120, 1140, E.inOutQuart(m));
    if (x0 < 190 || x0 > 810) continue;
    const ang = SL.a * D2R + PI + (r() - 0.5) * 1.1, sp = 250 + r() * 700;
    list.push({ t0: lerp(TL.slash, TL.slashEnd, m), x: x0, y: slashY(x0), vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp, life: 0.2 + r() * 0.35, w: 0.8 + r() * 1.4 });
  }
  return list;
})();
function sparkPos(s, tau) { const k = 3.2, f = (1 - Math.exp(-k * tau)) / k; return [s.x + s.vx * f, s.y + s.vy * f + 700 * tau * tau]; }
function drawBlade(ctx, X, P, t) {
  if (!P.blade) return;
  ctx.save(); setX(ctx, X); ctx.globalCompositeOperation = 'lighter'; ctx.lineCap = 'round';
  const hx = P.head, hy = slashY(hx), moving = t < TL.slashEnd, fade = 1 - seg(t, TL.slashEnd, TL.slashEnd + 0.5);
  const tailX = moving ? Math.max(-400, hx - 900) : hx - 900;

  if (moving || fade > 0) {
    const a = moving ? 1 : fade;
    const gr = ctx.createLinearGradient(tailX, slashY(tailX), hx, hy);
    gr.addColorStop(0, 'rgba(166,245,200,0)'); gr.addColorStop(0.75, `rgba(166,245,200,${0.25 * a})`); gr.addColorStop(1, `rgba(240,255,246,${0.95 * a})`);
    for (const [lw, al] of [[46, 0.10], [14, 0.35], [3.2, 1]]) {
      ctx.strokeStyle = gr; ctx.globalAlpha = al; ctx.lineWidth = lw; ctx.beginPath(); ctx.moveTo(tailX, slashY(tailX)); ctx.lineTo(hx, hy); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  const fl = moving ? 1 : Math.max(0, 1 - (t - TL.slashEnd) * 5);
  if (fl > 0 && hx > -100 && hx < 1150) {
    let rg = ctx.createRadialGradient(hx, hy, 0, hx, hy, 130); rg.addColorStop(0, `rgba(255,255,255,${fl})`); rg.addColorStop(0.15, `rgba(220,255,235,${0.6 * fl})`); rg.addColorStop(1, 'rgba(74,222,128,0)');
    ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(hx, hy, 130, 0, TAU); ctx.fill();
    ctx.save(); ctx.translate(hx, hy); ctx.scale(1, 0.035);
    rg = ctx.createRadialGradient(0, 0, 0, 0, 0, 900); rg.addColorStop(0, `rgba(235,255,245,${0.9 * fl})`); rg.addColorStop(1, 'rgba(166,245,200,0)');
    ctx.fillStyle = rg; ctx.beginPath(); ctx.arc(0, 0, 900, 0, TAU); ctx.fill(); ctx.restore();
  }

  for (const s of SPARKS) {
    const tau = t - s.t0; if (tau < 0 || tau > s.life) continue;
    const a = 1 - tau / s.life, [x, y] = sparkPos(s, tau), [x0, y0] = sparkPos(s, Math.max(0, tau - 0.022));
    ctx.strokeStyle = `rgba(${lerp(255, 120, 1 - a) | 0},255,${lerp(240, 170, 1 - a) | 0},${a})`; ctx.lineWidth = s.w * (0.5 + a);
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x, y); ctx.stroke();
  }
  ctx.restore();
}
function drawCutGlow(ctx, X, P, t) {
  const a = pulse(t, TL.slash + 0.05, TL.slashEnd, TL.slashEnd + 0.8);
  if (a <= 0) return;
  ctx.save(); setX(ctx, X); ctx.globalCompositeOperation = 'lighter'; ctx.lineCap = 'round';
  const x0 = 190, x1 = Math.min(P.head, 810);
  if (x1 <= x0) { ctx.restore(); return; }
  for (const [lw, al] of [[30, 0.12], [8, 0.4], [2, 0.8]]) { ctx.strokeStyle = rgba(C.mint, al * a); ctx.lineWidth = lw; ctx.beginPath(); ctx.moveTo(x0, slashY(x0)); ctx.lineTo(x1, slashY(x1)); ctx.stroke(); }
  ctx.restore();
}

const BOKEH = (() => { const r = mulberry32(21), a = []; for (let i = 0; i < 34; i++) a.push({ x: r() * 2400 - 700, y: r() * 1700 - 330, d: 0.15 + r() * 0.75, s: 6 + r() * 26, ph: r() * TAU, sp: 0.2 + r() * 0.5 }); return a; })();
function drawBackground(t, cam, P, extra) {
  const c = bx, w = BW, h = BH, k = BW / W;
  c.setTransform(1, 0, 0, 1, 0, 0); c.globalCompositeOperation = 'source-over'; c.globalAlpha = 1; c.filter = 'none';
  c.fillStyle = '#020604'; c.fillRect(0, 0, w, h);
  const light = extra.light;
  const [mx, my] = w2s(MC.x, MC.y, cam, 0.45);
  const glowCol = P.glowCol;

  const breathe = 0.85 + 0.15 * Math.sin(t * 2.2 - 1.2);
  let rg = c.createRadialGradient(mx * k, my * k, 0, mx * k, my * k, h * 1.25);
  rg.addColorStop(0, rgba(mixc([8, 50, 31], glowCol, 0.3), 0.85 * light)); rg.addColorStop(0.5, rgba([4, 28, 18], 0.65 * light)); rg.addColorStop(1, 'rgba(2,6,4,0)');
  c.fillStyle = rg; c.fillRect(0, 0, w, h);
  rg = c.createRadialGradient(mx * k, my * k, 0, mx * k, my * k, h * 0.62 * (0.8 + 0.2 * cam.z));
  rg.addColorStop(0, rgba(glowCol, 0.5 * light * breathe)); rg.addColorStop(0.5, rgba(glowCol, 0.11 * light * breathe)); rg.addColorStop(1, rgba(glowCol, 0));
  c.globalCompositeOperation = 'lighter'; c.fillStyle = rg; c.fillRect(0, 0, w, h);

  rg = c.createRadialGradient(w * 0.92, h * 0.02, 0, w * 0.92, h * 0.02, h * 0.9);
  rg.addColorStop(0, rgba([14, 96, 76], 0.28 * light)); rg.addColorStop(1, 'rgba(16,110,86,0)'); c.fillStyle = rg; c.fillRect(0, 0, w, h);

  const rays = extra.rays;
  if (rays > 0.01) {
    c.save(); c.translate(mx * k, my * k); c.rotate(t * 0.05);
    for (let i = 0; i < 18; i++) {
      const a0 = (i / 18) * TAU + 0.35 * Math.sin(i * 7.3), wdt = 0.05 + 0.06 * hash(i * 3.1), L = h * (0.9 + 0.5 * hash(i));
      const al = rays * (0.05 + 0.08 * hash(i * 1.7)) * (0.6 + 0.4 * Math.sin(t * 1.3 + i));
      const gr = c.createRadialGradient(0, 0, 0, 0, 0, L); gr.addColorStop(0, rgba(mixc(C.mint, glowCol, 0.5), al)); gr.addColorStop(1, rgba(glowCol, 0));
      c.fillStyle = gr; c.beginPath(); c.moveTo(0, 0); c.arc(0, 0, L, a0 - wdt, a0 + wdt); c.closePath(); c.fill();
    }
    c.restore();
  }

  const grid = extra.grid;
  if (grid > 0.01) {
    const sp = 40, [ox, oy, s] = w2s(0, 0, cam, 0.35), step = sp * s * k;
    if (step > 3) {
      const x0 = ((ox * k) % step + step) % step, y0 = ((oy * k) % step + step) % step, rad = Math.max(w, h) * 0.75;
      c.fillStyle = rgba(C.mint, 1); const ds = Math.max(0.7, 1.1 * S * Math.sqrt(s / BASE));
      for (let y = y0; y < h; y += step) for (let x = x0; x < w; x += step) {
        const d = Math.hypot(x - mx * k, y - my * k) / rad, a = grid * 0.16 * clamp(1 - d) * (0.7 + 0.3 * hash(Math.round(x / step) * 13 + Math.round(y / step) * 7));
        if (a < 0.01) continue; c.globalAlpha = a; c.fillRect(x - ds / 2, y - ds / 2, ds, ds);
      }
      c.globalAlpha = 1;
    }
  }

  const bk = extra.bokeh;
  if (bk > 0.01) {
    for (const b of BOKEH) {
      const [x, y, s] = w2s(b.x + 30 * Math.sin(t * b.sp + b.ph), b.y + 20 * Math.cos(t * b.sp * 0.8 + b.ph) - t * 8, cam, b.d);
      const r = b.s * s * k * 0.6, al = bk * (0.05 + 0.10 * (1 - b.d)) * (0.6 + 0.4 * Math.sin(t * 1.7 + b.ph));
      const gr = c.createRadialGradient(x * k, y * k, 0, x * k, y * k, r);
      gr.addColorStop(0, rgba(mixc(C.mint, glowCol, 0.4), al)); gr.addColorStop(0.7, rgba(mixc(C.mint, glowCol, 0.4), al * 0.6)); gr.addColorStop(1, rgba(C.mint, 0));
      c.fillStyle = gr; c.beginPath(); c.arc(x * k, y * k, r, 0, TAU); c.fill();
    }
  }
  c.globalCompositeOperation = 'source-over';

  const blur = (1.2 + 5.5 * clamp((cam.z - 1) / 1.6) + extra.blurAdd) * S;
  bx2.setTransform(1, 0, 0, 1, 0, 0); bx2.filter = `blur(${blur.toFixed(2)}px)`; bx2.drawImage(bgc, 0, 0); bx2.filter = 'none';
  sx.drawImage(bgc2, 0, 0, W, H);
}

const TEL = [
  { k: 'CPU', dec: 0, unit: '%', base: 0.34, amp: 0.5, v: [17, 86, 99, 17] },
  { k: 'GPU', dec: 0, unit: '%', base: 0.5, amp: 0.35, v: [49, 52, 71, 49] },
  { k: 'MEM', dec: 1, unit: ' GiB', base: 0.6, amp: 0.18, v: [15.6, 27.4, 29.1, 15.6] },
  { k: 'DISK', dec: 0, unit: '%', base: 0.36, amp: 0.1, v: [36, 36, 36, 36] },
  { k: 'I/O', dec: 1, unit: ' MB/s', base: 0.3, amp: 0.45, v: [11.3, 84.2, 0.4, 11.3] },
];
TEL.forEach((it, i) => {
  const t0 = TL.traces + i * 0.12 + 0.12, R = 0.26;
  it.vals = [[0, 0], [t0, 0], [t0 + 0.34, it.v[0]], [TL.warn + 0.05, it.v[0]], [TL.warn + 0.05 + R, it.v[1]], [TL.error + 0.05, it.v[1]], [TL.error + 0.05 + R, it.v[2]], [TL.calm + 0.05, it.v[2]], [TL.calm + 0.05 + R, it.v[3]]];
  it.digits = Math.max(...it.v).toFixed(0).length + it.dec;
});

function teleSlots() {
  const m = Math.round(W * 0.06);
  if (SQ) { const w = 286 * S, g = (W - 2 * m - 3 * w) / 2; return [
    { x: m, y: 132 * S, w }, { x: W - m - w, y: 132 * S, w }, { x: m, y: 930 * S, w }, { x: W - m - w, y: 930 * S, w }, { x: m + w + g, y: 930 * S, w }]; }
  const w = 300 * S;
  return [{ x: m, y: 360 * S, w }, { x: m, y: 560 * S, w }, { x: W - m - w, y: 360 * S, w }, { x: W - m - w, y: 560 * S, w }, { x: m, y: 760 * S, w }];
}
const SLOTS = teleSlots();
function traceVal(i, u, t) {
  const it = TEL[i] || TEL[0], tau = t - (1 - u) * 2.4;
  let v = it.base + it.amp * (0.55 * (vnoise(tau * 3.1 + i * 9.7) - 0.5) + 0.35 * (vnoise(tau * 9.3 + i * 3.3) - 0.5));
  const sw = stateW(tau);
  const jag = vnoise(tau * 22 + i) - 0.5;
  v += sw.warn * ([0.5, 0.12, 0.3, 0.02, 0.4][i] + 0.25 * jag);
  v += sw.error * ([0.62, 0.3, 0.33, 0.05, -0.2][i] + 0.5 * jag);
  v = lerp(v, 0.08 + 0.02 * jag, sw.sleep * 0.9);
  return clamp(v, 0.02, 0.98);
}
function trColor(tau) { const sw = stateW(tau); return stateMix(sw, C.trCalm, C.trWarn, C.trErr, C.trSleep); }
function valueAt(it, t) { return kf(FRAME_T, it.vals.map((v, j) => [v[0], v[1], E.outQuart])); }
let FRAME_T = 0;
function drawRolling(c, xRight, y, v, dec, fontPx, col, alpha, digits) {
  const n = Math.round(v * 10 ** dec);
  c.font = `600 ${fontPx}px "JetBrains Mono"`; const cw = c.measureText('0').width, lh = fontPx * 1.1;
  let x = xRight;
  c.save(); c.textAlign = 'left'; c.textBaseline = 'alphabetic';
  for (let k = 0; k < digits; k++) {
    if (k === dec && dec > 0) { x -= cw * 0.62; c.fillStyle = rgba(col, alpha); c.fillText('.', x - cw * 0.19, y); }
    x -= cw;
    const d = Math.floor(n / 10 ** k) % 10;
    if (k > dec && n < 10 ** k) continue;
    c.fillStyle = rgba(col, alpha); c.fillText(String(d), x, y);
  }
  c.restore();
}
function pupilScreen(b, st, X) {
  const r = (b.a + st.rot) * D2R, lx = st.slot.ox, ly = SLOT.y + st.slot.oy;
  const wx = b.cx + st.tx + Math.cos(r) * lx - Math.sin(r) * ly, wy = b.cy + st.ty + Math.sin(r) * lx + Math.cos(r) * ly;
  const cr = Math.cos(X.rot * D2R), sr = Math.sin(X.rot * D2R), dx = (wx - MC.x) * X.s, dy = (wy - MC.y) * X.s;
  return [X.x + cr * dx - sr * dy, X.y + sr * dx + cr * dy];
}
function drawTelemetry(t, cam, P, X) {
  const vis = seg(t, TL.traces - 0.05, TL.traces + 0.2) * (1 - seg(t, TL.whip - 0.05, TL.whip + 0.15));
  if (vis <= 0.001) return;
  const c = sx, sw = stateW(t), fs = S;
  const dim = 1 - 0.45 * sw.sleep;
  const heads = [];

  const px = -(cam.cx - MC.x) * 0.25 * S, py = -(cam.cy - MC.y) * 0.2 * S;
  TEL.forEach((it, i) => {
    const L = SLOTS[i]; if (!L) return;
    const t0 = TL.traces + i * 0.12, draw = E.outCubic(seg(t, t0, t0 + 0.75)), la = seg(t, t0 + 0.05, t0 + 0.3);
    if (draw <= 0) return;
    const x0 = L.x + px, y0 = L.y + py, wpx = L.w, hpx = 60 * S;
    const col = trColor(t);
    c.save(); c.globalAlpha = vis * dim;
    c.font = `600 ${(27 * fs).toFixed(1)}px "JetBrains Mono"`; c.fillStyle = rgba(C.mint, 0.78 * la);
    c.letterSpacing = `${(2 * fs).toFixed(1)}px`; c.textBaseline = 'alphabetic'; c.fillText(it.k, x0, y0 - 16 * fs); c.letterSpacing = '0px';
    c.font = `500 ${(22 * fs).toFixed(1)}px "JetBrains Mono"`;
    const uw = c.measureText(it.unit).width; c.fillStyle = rgba(col, 0.75 * la); c.textAlign = 'right'; c.fillText(it.unit, x0 + wpx, y0 - 16 * fs); c.textAlign = 'left';
    drawRolling(c, x0 + wpx - uw - 4 * fs, y0 - 16 * fs, valueAt(it, t), it.dec, 42 * fs, mixc(C.white, col, 0.15), 0.97 * la, it.digits);
    c.fillStyle = rgba(C.mint, 0.16 * la); c.fillRect(x0, y0 + hpx + 2, wpx * draw, 1);
    for (let j = 0; j <= 10; j++) if (j / 10 <= draw) c.fillRect(x0 + wpx * j / 10, y0 + hpx - 1, 1, 4);
    const N = 64, pts = [];
    for (let j = 0; j <= N; j++) { const u = j / N; if (u > draw + 1e-6) break; pts.push([x0 + u * wpx, y0 + 6 + (1 - traceVal(i, u, t)) * (hpx - 8)]); }
    if (pts.length > 1) {
      const gr = c.createLinearGradient(x0, 0, x0 + wpx, 0);
      for (let j = 0; j <= 6; j++) gr.addColorStop(j / 6, rgba(trColor(t - (1 - j / 6) * 2.4), 1));
      c.beginPath(); c.moveTo(pts[0][0], y0 + hpx); for (const p of pts) c.lineTo(p[0], p[1]); c.lineTo(pts[pts.length - 1][0], y0 + hpx); c.closePath();
      const ag = c.createLinearGradient(0, y0, 0, y0 + hpx); ag.addColorStop(0, rgba(col, 0.16)); ag.addColorStop(1, rgba(col, 0)); c.fillStyle = ag; c.fill();
      c.beginPath(); pts.forEach((p, j) => (j ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])));
      c.lineJoin = 'round'; c.strokeStyle = gr; c.globalAlpha = vis * dim * 0.22; c.lineWidth = 6 * S; c.stroke();
      c.globalAlpha = vis * dim; c.lineWidth = 1.9 * S; c.stroke();
      const hp = pts[pts.length - 1]; heads.push({ p: hp, col, i });
      c.globalCompositeOperation = 'lighter';
      const rg = c.createRadialGradient(hp[0], hp[1], 0, hp[0], hp[1], 16 * S); rg.addColorStop(0, rgba(C.white, 0.95)); rg.addColorStop(0.25, rgba(col, 0.6)); rg.addColorStop(1, rgba(col, 0));
      c.fillStyle = rg; c.beginPath(); c.arc(hp[0], hp[1], 16 * S, 0, TAU); c.fill();
    }
    c.restore();
  });

  const cv = seg(t, TL.conv, TL.conv + 0.6), cvA = cv * (1 - seg(t, TL.pull - 0.1, TL.pull + 0.25)) + 0.5 * (sw.warn + sw.error) * seg(t, TL.warn, TL.warn + 0.2);
  if (cvA > 0.005 && P.g.slot.sy > 0.2) {
    const pg = pupilScreen(GREEN, P.g, X), pc = pupilScreen(CREAM, P.c, X);
    c.save(); c.globalCompositeOperation = 'lighter';
    for (const h of heads) {
      const tgt = Math.abs(h.p[0] - pg[0]) < Math.abs(h.p[0] - pc[0]) ? pg : pc;
      const p0 = h.p, p3 = tgt, mxp = (p0[0] + p3[0]) / 2, p1 = [mxp, p0[1]], p2 = [mxp, p3[1]];
      const B = u => { const a = 1 - u; return [a * a * a * p0[0] + 3 * a * a * u * p1[0] + 3 * a * u * u * p2[0] + u * u * u * p3[0], a * a * a * p0[1] + 3 * a * a * u * p1[1] + 3 * a * u * u * p2[1] + u * u * u * p3[1]]; };
      const drawU = E.outCubic(clamp(cv * 1.4 - h.i * 0.08));
      const lg = c.createLinearGradient(p0[0], p0[1], p3[0], p3[1]); lg.addColorStop(0, rgba(h.col, 0.45 * cvA)); lg.addColorStop(0.8, rgba(h.col, 0.2 * cvA)); lg.addColorStop(1, rgba(h.col, 0));
      c.strokeStyle = lg; c.lineWidth = 1.3 * S; c.beginPath();
      for (let j = 0; j <= 40; j++) { const u = (j / 40) * drawU, q = B(u); j ? c.lineTo(q[0], q[1]) : c.moveTo(q[0], q[1]); } c.stroke();
      for (let m = 0; m < 3; m++) {
        const u = ((t - TL.conv) * 0.9 + m / 3 + h.i * 0.17) % 1; if (u > drawU) continue;
        const q = B(E.inOutSine(u)), a = Math.sin(u * PI) * cvA;
        const rg = c.createRadialGradient(q[0], q[1], 0, q[0], q[1], 7 * S); rg.addColorStop(0, rgba(C.white, 0.9 * a)); rg.addColorStop(1, rgba(h.col, 0));
        c.fillStyle = rg; c.beginPath(); c.arc(q[0], q[1], 7 * S, 0, TAU); c.fill();
      }
    }
    c.restore();
  }

  const swk = seg(t, TL.sweep, TL.sweepEnd);
  if (swk > 0 && swk < 1) {
    const x = lerp(-0.15 * W, 1.15 * W, E.inOutSine(swk)), a = Math.sin(swk * PI);
    c.save(); c.globalCompositeOperation = 'lighter';
    const bw = 340 * S, gr = c.createLinearGradient(x - bw, 0, x + bw * 0.25, 0);
    gr.addColorStop(0, rgba(C.mint, 0)); gr.addColorStop(0.72, rgba(C.mint, 0.05 * a)); gr.addColorStop(0.8, rgba(C.mint, 0.075 * a)); gr.addColorStop(1, rgba(C.mint, 0));
    c.fillStyle = gr; c.fillRect(x - bw, 0, bw * 1.25, H);
    c.restore();
  }
}

const MB = { h: (SQ ? 112 : 136) * S, cy: H * 0.42 };
const MU = MB.h / 64;
function mbTop(t) {
  const k = E.outCubic(seg(t, TL.whip, TL.land - 0.04)), ex = E.inCubic(seg(t, TL.out, TL.out + 0.3));
  return lerp(-MB.h - 60 * S, MB.cy - MB.h / 2, k) - ex * 120 * S;
}
let MBL = null;
function menuBarLayout() {
  const fz = 23 * MU, pad = 30 * MU;
  sx.font = `600 ${fz}px Inter`;
  const clock = SQ ? 'Wed 9:41' : 'Wed 23 Sep  9:41';
  const cw = sx.measureText(clock).width;
  const xs = {}; let x = W - pad - cw; xs.clock = x;
  x -= 34 * MU; xs.cc = x - 14 * MU; x -= 58 * MU; xs.wifi = x - 12 * MU; x -= 56 * MU; xs.batt = x - 30 * MU; x -= 70 * MU; xs.search = x - 8 * MU; x -= 64 * MU;
  xs.glyph = x - 20 * MU; x -= 76 * MU; xs.other = x - 10 * MU; xs.leftLimit = x - 40 * MU;
  return { fz, clock, xs };
}
function glyphXf(t) { const hpx = MB.h * 0.5; return { x: MBL.xs.glyph, y: mbTop(t) + MB.h * 0.5 + 1.5 * MU, s: hpx / 500, rot: 0 }; }
function drawMenuBar(t) {
  const top = mbTop(t); if (top + MB.h < -2) return;
  const fade = 1 - seg(t, TL.out, TL.out + 0.26); if (fade <= 0) return;
  const L = MBL, c = sx, cy = top + MB.h / 2;
  c.save(); c.globalAlpha = fade;

  const bz = c.createLinearGradient(0, top - 160 * S, 0, top);
  bz.addColorStop(0, '#020403'); bz.addColorStop(1, '#070b09'); c.fillStyle = bz; c.fillRect(0, top - H, W, H);
  c.fillStyle = 'rgba(255,255,255,0.10)'; c.fillRect(0, top - 1 * S, W, 1 * S);

  const sd = c.createLinearGradient(0, top, 0, top + H * 0.7); sd.addColorStop(0, 'rgba(0,0,0,0.0)'); sd.addColorStop(1, 'rgba(0,0,0,0.35)');
  c.fillStyle = sd; c.fillRect(0, top, W, H);

  c.fillStyle = 'rgba(12,20,16,0.58)'; c.fillRect(0, top, W, MB.h);
  c.fillStyle = 'rgba(255,255,255,0.05)'; c.fillRect(0, top + MB.h - 1 * S, W, 1 * S);
  const white = 'rgba(245,248,246,0.95)';
  c.fillStyle = white; c.strokeStyle = white; c.lineCap = 'round'; c.lineJoin = 'round';
  c.textBaseline = 'middle'; c.textAlign = 'left';

  const A = (a) => { c.globalAlpha = a * fade; };
  let lx = 34 * MU; A(0.9); c.beginPath(); c.arc(lx + 8 * MU, cy, 8 * MU, 0, TAU); c.fill(); lx += 38 * MU;
  c.font = `500 ${L.fz}px Inter`; c.fillStyle = 'rgba(245,248,246,0.8)';
  for (const m of ['File', 'Edit', 'View', 'Window', 'Help']) { const w = c.measureText(m).width; if (lx + w > L.xs.leftLimit) break; c.fillText(m, lx, cy + 1 * MU); lx += w + 26 * MU; }
  A(1); c.fillStyle = white;
  c.font = `600 ${L.fz}px Inter`; c.fillText(L.clock, L.xs.clock, cy + 1 * MU);
  c.lineWidth = 2.4 * MU;
  { const x = L.xs.cc; for (const [dy, on] of [[-6, 1], [6, 0]]) { c.beginPath(); c.roundRect(x - 13 * MU, cy + dy * MU - 4.5 * MU, 26 * MU, 9 * MU, 4.5 * MU); c.stroke(); c.beginPath(); c.arc(x + (on ? 8.5 : -8.5) * MU, cy + dy * MU, 2.5 * MU, 0, TAU); c.fill(); } }
  { const x = L.xs.wifi, y = cy + 9 * MU; for (const r of [7, 13.5, 20]) { c.beginPath(); c.arc(x, y, r * MU, -PI * 0.75, -PI * 0.25); c.stroke(); } c.beginPath(); c.arc(x, y, 2.4 * MU, 0, TAU); c.fill(); }
  { const x = L.xs.batt, bw = 38 * MU, bh = 18 * MU; c.lineWidth = 2 * MU; A(0.6); c.beginPath(); c.roundRect(x - bw / 2, cy - bh / 2, bw, bh, 5 * MU); c.stroke(); A(1);
    c.beginPath(); c.roundRect(x - bw / 2 + 3 * MU, cy - bh / 2 + 3 * MU, (bw - 6 * MU) * 0.8, bh - 6 * MU, 2.5 * MU); c.fill(); A(0.6); c.beginPath(); c.roundRect(x + bw / 2 + 2 * MU, cy - 3.5 * MU, 3 * MU, 7 * MU, 1.5 * MU); c.fill(); A(1); }
  { const x = L.xs.search; c.lineWidth = 2.4 * MU; c.beginPath(); c.arc(x - 2 * MU, cy - 2 * MU, 7.5 * MU, 0, TAU); c.stroke(); c.beginPath(); c.moveTo(x + 3.5 * MU, cy + 3.5 * MU); c.lineTo(x + 9 * MU, cy + 9 * MU); c.stroke(); }
  { const x = L.xs.other; A(0.75); c.lineWidth = 2.2 * MU; c.beginPath(); c.roundRect(x - 11 * MU, cy - 11 * MU, 22 * MU, 22 * MU, 6 * MU); c.stroke(); c.beginPath(); c.moveTo(x - 5 * MU, cy + 1 * MU); c.lineTo(x - 1 * MU, cy + 5 * MU); c.lineTo(x + 6 * MU, cy - 4 * MU); c.stroke(); A(1); }

  const hk = seg(t, TL.land, TL.land + 0.12) * (1 - seg(t, TL.out - 0.05, TL.out + 0.1));
  if (hk > 0) { c.fillStyle = `rgba(255,255,255,${0.10 * hk})`; c.beginPath(); c.roundRect(L.xs.glyph - 38 * MU, top + 9 * MU, 76 * MU, MB.h - 18 * MU, 9 * MU); c.fill(); }

  const ck = seg(t, TL.land + 0.08, TL.land + 0.24) * (1 - seg(t, TL.out - 0.02, TL.out + 0.12));
  if (ck > 0) {
    const e = E.outBack(clamp(ck), 1.6), fz = 17 * MU, txt = 'all clear';
    c.font = `600 ${fz}px Inter`; const tw = c.measureText(txt).width, cw = tw + 52 * MU, ch = 36 * MU;
    const x = L.xs.glyph, y = top + MB.h + 12 * MU;
    c.save(); c.globalAlpha = clamp(ck * 1.4) * fade; c.translate(x, y); c.scale(lerp(0.85, 1, e), lerp(0.85, 1, e));
    c.shadowColor = 'rgba(0,0,0,0.45)'; c.shadowBlur = 24 * MU; c.shadowOffsetY = 6 * MU;
    c.fillStyle = 'rgba(22,30,26,0.92)'; c.beginPath(); c.roundRect(-cw / 2, 0, cw, ch, ch / 2); c.fill(); c.shadowColor = 'transparent';
    c.strokeStyle = 'rgba(255,255,255,0.09)'; c.lineWidth = 1 * MU; c.stroke();
    c.fillStyle = rgba(C.green); c.beginPath(); c.arc(-cw / 2 + 20 * MU, ch / 2, 5 * MU, 0, TAU); c.fill();
    c.fillStyle = 'rgba(240,246,242,0.95)'; c.textBaseline = 'middle'; c.textAlign = 'left'; c.fillText(txt, -cw / 2 + 34 * MU, ch / 2 + 1 * MU);
    c.restore();
  }
  c.restore();
}
function drawLandPing(t) {
  if (t < TL.land || t > TL.land + 0.7) return;
  const k = seg(t, TL.land, TL.land + 0.7), G = glyphXf(t), c = sx;
  c.save(); c.globalCompositeOperation = 'lighter';
  for (const [d, r1, a] of [[0, 50, 0.9], [0.12, 74, 0.45]]) {
    const kk = seg(t, TL.land + d, TL.land + d + 0.55); if (kk <= 0 || kk >= 1) continue;
    c.strokeStyle = rgba(C.mint, a * (1 - kk)); c.lineWidth = (3.5 * (1 - kk) + 0.8) * MU;
    c.beginPath(); c.arc(G.x, G.y, lerp(18, r1, E.outCubic(kk)) * MU, 0, TAU); c.stroke();
  }
  const rg = c.createRadialGradient(G.x, G.y, 0, G.x, G.y, 60 * MU); rg.addColorStop(0, rgba(C.green, 0.5 * (1 - k))); rg.addColorStop(1, rgba(C.green, 0));
  c.fillStyle = rg; c.beginPath(); c.arc(G.x, G.y, 60 * MU, 0, TAU); c.fill();
  c.restore();
}

const CARD_FONT = '"Bricolage Grotesque"';
function cardLayout() {
  const L = {};
  if (SQ) {
    Object.assign(L, { icon: 120 * S, word: 114 * S, gap: 26 * S, rowY: 350 * S, slPx: 65 * S, slY: [522 * S, 592 * S], metaPx: 30 * S, metaY: 724 * S, urlPx: 32 * S, urlY: 774 * S });
  } else {
    Object.assign(L, { icon: 138 * S, word: 132 * S, gap: 30 * S, rowY: 330 * S, slPx: 76 * S, slY: [516 * S, 598 * S], metaPx: 36 * S, metaY: 740 * S, urlPx: 38 * S, urlY: 798 * S });
  }
  sx.font = `800 ${L.word}px ${CARD_FONT}`; sx.letterSpacing = `${(-0.035 * L.word).toFixed(2)}px`;
  L.wordW = sx.measureText('Maester').width - (-0.035 * L.word); sx.letterSpacing = '0px';
  const rowW = L.icon + L.gap + L.wordW; L.iconX = (W - rowW) / 2 + L.icon / 2; L.wordX = L.iconX + L.icon / 2 + L.gap;
  return L;
}
let CARD = null;
const cardSettle = t => lerp(1.03, 1, E.outCubic(seg(t, TL.card, TL.card + 2.2)));
function iconXf(settle) {
  const s = (CARD.icon / 832) * settle, cx = W / 2 + (CARD.iconX - W / 2) * settle, cy = H / 2 + (CARD.rowY - H / 2) * settle;
  return { x: cx + (MC.x - 512) * s, y: cy + (MC.y - 512) * s, s, rot: 0 };
}
function revealText(c, txt, x, y, k, rise, blurMax) {
  if (k <= 0) return;
  const e = E.outCubic(k);
  c.save(); c.globalAlpha *= clamp(k * 1.5);
  if (k < 1) c.filter = `blur(${((1 - e) * blurMax * S).toFixed(2)}px)`;
  c.fillText(txt, x, y + (k < 1 ? (1 - e) * rise * S : 0)); c.restore();
}
function drawCard(t) {
  const L = CARD, c = sx; if (t < TL.card) return;
  const settle = cardSettle(t);
  c.save(); c.translate(W / 2, H / 2); c.scale(settle, settle); c.translate(-W / 2, -H / 2);
  c.font = `800 ${L.word}px ${CARD_FONT}`; c.textBaseline = 'middle'; c.textAlign = 'left'; c.letterSpacing = `${(-0.035 * L.word).toFixed(2)}px`;
  const word = 'Maester'; let x = L.wordX;
  const gy0 = L.rowY - L.word * 0.4, gy1 = L.rowY + L.word * 0.4;
  const gr = c.createLinearGradient(0, gy0, 0, gy1); gr.addColorStop(0, '#ffffff'); gr.addColorStop(0.3, '#ffffff'); gr.addColorStop(1, '#a6f5c8');
  c.fillStyle = gr;
  for (let i = 0; i < word.length; i++) {
    const ch = word[i], cw = c.measureText(ch).width + (-0.035 * L.word);
    revealText(c, ch, x, L.rowY + 2 * S, seg(t, TL.card + 0.02 + i * 0.04, TL.card + 0.42 + i * 0.04), 34, 10);
    x += cw;
  }
  c.textAlign = 'center';
  c.font = `700 ${L.slPx}px ${CARD_FONT}`; c.letterSpacing = `${(-0.035 * L.slPx).toFixed(2)}px`;
  const kA = seg(t, TL.card + 0.28, TL.card + 0.6), kB = seg(t, TL.second, TL.second + 0.28);
  c.fillStyle = '#ffffff';
  revealText(c, 'Eyes on your Mac.', W / 2 + 0.0175 * L.slPx, L.slY[0], kA, 20, 7);
  if (kB > 0) {
    const e = E.outBack(kB, 2.2), sc = kB < 1 ? lerp(0.86, 1, e) : 1;
    c.save(); c.translate(W / 2 + 0.0175 * L.slPx, L.slY[1]); c.scale(sc, sc); c.globalAlpha *= clamp(kB * 2);
    c.fillStyle = '#5fe79a'; c.fillText('Never on you.', 0, 0);
    if (kB < 1) { c.globalCompositeOperation = 'lighter'; c.globalAlpha = 0.35 * Math.sin(kB * PI); c.fillText('Never on you.', 0, 0); }
    c.restore();
  }
  c.letterSpacing = '0px';
  c.font = `500 ${L.metaPx}px ${CARD_FONT}`; c.letterSpacing = `${(0.01 * L.metaPx).toFixed(2)}px`; c.fillStyle = 'rgba(208,246,224,0.64)';
  revealText(c, 'Free · Open source · No telemetry · macOS 15+', W / 2, L.metaY, seg(t, TL.second + 0.34, TL.second + 0.64), 10, 4);
  c.letterSpacing = '0px';
  c.font = `600 ${L.urlPx}px ${CARD_FONT}`; c.fillStyle = '#8fe8b6';
  revealText(c, 'github.com/kishorekanthan/maester', W / 2, L.urlY, seg(t, TL.second + 0.44, TL.second + 0.74), 10, 3);
  c.restore();
}

function lerpXf(A, B, k, arc, twist) {
  const s = Math.exp(lerp(Math.log(A.s), Math.log(B.s), k));
  const nx = -(B.y - A.y), ny = B.x - A.x, nl = Math.hypot(nx, ny) || 1, off = Math.sin(k * PI) * arc;
  return { x: lerp(A.x, B.x, k) + nx / nl * off, y: lerp(A.y, B.y, k) + ny / nl * off, s, rot: lerp(A.rot, B.rot, k) + Math.sin(k * PI) * twist };
}
function markXf(t, cam) {
  const [px, py, s] = w2s(MC.x, MC.y, cam, 1);
  let X = { x: px, y: py, s, rot: 0 };
  const kw = seg(t, TL.whip, TL.land);
  if (kw > 0) {
    const G = glyphXf(t);
    const [ax, ay, as] = w2s(MC.x, MC.y, camera(TL.whip), 1);
    X = lerpXf({ x: ax, y: ay, s: as, rot: 0 }, G, E.inOutExpo(kw), 160 * S, -16);
    if (t >= TL.land) X.s = G.s * lerp(1.5, 1, spring(t - TL.land, 4.2, 0.33));
  }
  const ko = seg(t, TL.out, TL.outEnd);
  if (ko > 0) X = lerpXf(glyphXf(Math.min(t, TL.out)), iconXf(cardSettle(t)), E.inOutCubic(ko), -60 * S, 0);
  return X;
}
function heroSubframe(t) {
  if (!MBL) MBL = menuBarLayout();
  if (!CARD) CARD = cardLayout();
  const cam = camera(t), P = markParams(t);

  P.mono = clamp(seg(t, TL.whip + 0.1, TL.land - 0.04)) * (1 - seg(t, TL.out + 0.08, TL.out + 0.4));
  P.square = E.outCubic(seg(t, TL.out + 0.12, TL.outEnd));
  if (t > TL.whip) { P.glowK *= (1 - seg(t, TL.whip, TL.whip + 0.25)); P.glowK += 0.3 * seg(t, TL.out + 0.2, TL.outEnd + 0.3); P.glowCol = C.glowCalm; }
  if (P.mono > 0.5) P.catch = 0;
  const light = 0.06 + 0.94 * E.inOutSine(seg(t, 0.05, 1.4)) * (0.9 + 0.1 * Math.sin(t * 3.1)) + 0.25 * pulse(t, TL.flood, TL.flood + 0.1, TL.floodEnd + 0.4);
  const rays = seg(t, TL.flood, TL.floodEnd + 0.3) * (1 - 0.6 * seg(t, TL.zoomIn, TL.zoomInEnd)) * (1 - 0.8 * seg(t, TL.whip, TL.land)) + 0.75 * seg(t, TL.out, TL.outEnd + 0.5);
  const grid = 0.35 + 0.65 * seg(t, TL.flood, TL.floodEnd);
  const mbOn = t > TL.whip && t < TL.out + 0.6;
  sx.setTransform(1, 0, 0, 1, 0, 0); sx.globalAlpha = 1; sx.globalCompositeOperation = 'source-over'; sx.filter = 'none';
  drawBackground(t, cam, P, { light, rays, grid, bokeh: seg(t, 0.2, 1.2), blurAdd: 5 * seg(t, TL.whip, TL.land) * (1 - seg(t, TL.out, TL.outEnd)) });
  const X = markXf(t, cam);
  if (mbOn) drawMenuBar(t);
  drawMark(sx, X, P, t);
  drawCutGlow(sx, X, P, t);
  drawBlade(sx, X, P, t);
  drawTelemetry(t, cam, P, X);
  drawLandPing(t);
  drawCard(t);
  const fin = seg(t, 0, 0.35); if (fin < 1) { sx.fillStyle = `rgba(0,0,0,${1 - fin})`; sx.fillRect(0, 0, W, H); }
}
function heroPost(t) {
  const cam = camera(t);
  let ctr = [0.5, 0.5];
  if (t > TL.whip && t < TL.out) { const G = glyphXf(t); ctr = [G.x / W, 1 - G.y / H]; }
  return {
    rb: cam.rb, ca: cam.ca, ctr,
    bloom: 0.5 + 0.4 * pulse(t, TL.slash, TL.slash + 0.1, TL.floodEnd + 0.3), thresh: 0.965,
    vig: 0.45, grain: 0.02, flash: 0.08 * pulse(t, TL.slash + 0.05, TL.slash + 0.1, TL.slash + 0.45),
  };
}
function heroSamples(t) {
  const r = (a, b) => t >= a && t <= b;
  if (r(TL.whip - 0.02, TL.land + 0.2)) return 12;
  if (r(TL.slash - 0.02, TL.slash + 0.3)) return 9;
  if (r(TL.out - 0.02, TL.outEnd + 0.05)) return 7;
  if (r(0.25, 1.1) || r(TL.zoomIn, TL.zoomInEnd + 0.05) || r(TL.pull, TL.pullEnd)) return 5;
  if (r(TL.open, TL.blink + 0.25) || r(TL.warn, TL.calm + 0.45) || r(TL.mbBlink, TL.mbBlink + 0.2) || r(TL.cardBlink, TL.cardBlink + 0.22) || r(TL.second, TL.second + 0.25)) return 3;
  if (r(TL.card, TL.second + 0.75)) return 2;
  return 1;
}

function heroEvents() {
  const ev = [];
  const cross = (t0) => { for (let t = t0; t < t0 + 1.5; t += 1 / 600) if (spring(t - t0, 1.55, 0.52) >= 1) return t; return t0 + 0.4; };
  ev.push({ t: 0.0, type: 'swell', dur: 2.2 });
  ev.push({ t: cross(TL.riseG), type: 'boop', f: 196 }); ev.push({ t: cross(TL.riseC), type: 'boop', f: 247 });
  ev.push({ t: TL.slash - 0.03, type: 'whoosh', dur: 0.32 });
  ev.push({ t: TL.slash + 0.01, type: 'punch' });
  ev.push({ t: TL.slash + 0.04, type: 'sparks', dur: 0.45 });
  ev.push({ t: TL.flood, type: 'shimmer', dur: 0.7 });
  ev.push({ t: TL.zoomIn + 0.02, type: 'zoom', dur: 0.55 });
  ev.push({ t: TL.open, type: 'tick', f: 2400 }); ev.push({ t: TL.open + 0.2, type: 'tick', f: 2000 }); ev.push({ t: TL.open + 0.3, type: 'tick', f: 2900 });
  TEL.forEach((_, i) => { ev.push({ t: TL.traces + i * 0.12, type: 'chirp', f: 1700 + i * 240 }); });
  ev.push({ t: TL.sweep, type: 'sweep', dur: TL.sweepEnd - TL.sweep });
  ev.push({ t: TL.glL, type: 'tick', f: 3100 }); ev.push({ t: TL.glR, type: 'tick', f: 3300 }); ev.push({ t: TL.glC, type: 'tick', f: 2800 });
  ev.push({ t: TL.conv, type: 'data', dur: 1.1 });
  ev.push({ t: TL.blink, type: 'tick', f: 2600 });
  ev.push({ t: TL.pull, type: 'zoom', dur: 0.45, rev: 1 });
  ev.push({ t: TL.warn, type: 'warn' }); ev.push({ t: TL.error, type: 'error' }); ev.push({ t: TL.sleep, type: 'sleep' }); ev.push({ t: TL.calm, type: 'calm' });
  for (const s of [TL.warn, TL.error, TL.calm]) ev.push({ t: s + 0.06, type: 'roll', dur: 0.32 });
  ev.push({ t: TL.whip - 0.05, type: 'whip', dur: TL.land - TL.whip + 0.05 });
  ev.push({ t: TL.land, type: 'land' });
  ev.push({ t: TL.land + 0.1, type: 'tick', f: 3600, g: 0.6 });
  ev.push({ t: TL.mbBlink, type: 'tick', f: 4200, g: 0.45 });
  ev.push({ t: TL.out, type: 'rise', dur: TL.outEnd - TL.out });
  ev.push({ t: TL.card + 0.1, type: 'chord', dur: TL.end - TL.card - 0.1 });
  ev.push({ t: TL.second, type: 'glance' });
  ev.push({ t: TL.second + 0.36, type: 'tick', f: 2200, g: 0.4 }); ev.push({ t: TL.second + 0.46, type: 'tick', f: 2800, g: 0.35 });
  ev.push({ t: TL.cardBlink, type: 'tick', f: 2600, g: 0.35 });
  return { duration: TL.end, events: ev.sort((a, b) => a.t - b.t) };
}

const LOOP = 3.6;
function loopSubframe(t) {
  t = ((t % LOOP) + LOOP) % LOOP;
  if (!CARD) CARD = cardLayout();
  const c = sx; c.setTransform(1, 0, 0, 1, 0, 0); c.globalAlpha = 1; c.globalCompositeOperation = 'source-over'; c.filter = 'none';

  c.fillStyle = '#03100a'; c.fillRect(0, 0, W, H);
  let rg = c.createRadialGradient(W / 2, H * 0.46, 0, W / 2, H * 0.46, H * 0.75);
  rg.addColorStop(0, '#13643f'); rg.addColorStop(0.55, '#0a3322'); rg.addColorStop(1, '#03100a'); c.fillStyle = rg; c.fillRect(0, 0, W, H);
  rg = c.createRadialGradient(W * 0.9, 0, 0, W * 0.9, 0, H * 0.8); rg.addColorStop(0, 'rgba(18,120,92,0.35)'); rg.addColorStop(1, 'rgba(18,120,92,0)'); c.fillStyle = rg; c.fillRect(0, 0, W, H);
  c.fillStyle = 'rgba(166,245,200,0.07)';
  const st = 36 * S; for (let y = st / 2; y < H; y += st) for (let x = st / 2; x < W; x += st) c.fillRect(x - 0.8 * S, y - 0.8 * S, 1.6 * S, 1.6 * S);

  const br = Math.sin(PI * seg(t, 0.35, 1.45)) ** 2;
  const iconPx = 560 * S, cx = W / 2, cy = H * 0.46;
  rg = c.createRadialGradient(cx, cy, iconPx * 0.3, cx, cy, iconPx * 0.78);
  rg.addColorStop(0, `rgba(74,222,128,${0.16 + 0.10 * br})`); rg.addColorStop(1, 'rgba(74,222,128,0)');
  c.globalCompositeOperation = 'lighter'; c.fillStyle = rg; c.beginPath(); c.arc(cx, cy, iconPx * 0.8, 0, TAU); c.fill(); c.globalCompositeOperation = 'source-over';

  const tr = E.inOutCubic(seg(t, 0.3, 1.7)), fade = 1 - seg(t, 2.55, 3.25);
  if (tr > 0 && fade > 0) {
    const y0 = H * 0.875, x0 = W * 0.14, x1 = W * 0.86, pts = [];
    for (let j = 0; j <= 120; j++) {
      const u = j / 120; if (u > tr) break;
      const e = Math.exp(-(((u - 0.5) / 0.035) ** 2)), bump = -e * 34 * S + Math.exp(-(((u - 0.535) / 0.02) ** 2)) * 16 * S;
      pts.push([lerp(x0, x1, u), y0 + bump + (vnoise(u * 40) - 0.5) * 7 * S * (1 - e)]);
    }
    c.save(); c.globalAlpha = fade; c.lineJoin = 'round';
    const lg = c.createLinearGradient(x0, 0, x1, 0); lg.addColorStop(0, 'rgba(166,245,200,0)'); lg.addColorStop(0.2, 'rgba(166,245,200,0.8)'); lg.addColorStop(0.8, 'rgba(166,245,200,0.8)'); lg.addColorStop(1, 'rgba(166,245,200,0)');
    c.beginPath(); pts.forEach((p, j) => (j ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])));
    c.strokeStyle = lg; c.globalAlpha = fade * 0.25; c.lineWidth = 6 * S; c.stroke(); c.globalAlpha = fade; c.lineWidth = 2 * S; c.stroke();
    if (tr < 1 || true) { const h = pts[pts.length - 1]; const hk = fade * (1 - seg(t, 1.7, 2.1)) ; const rg2 = c.createRadialGradient(h[0], h[1], 0, h[0], h[1], 16 * S); rg2.addColorStop(0, `rgba(255,255,255,${0.95 * hk})`); rg2.addColorStop(1, 'rgba(166,245,200,0)'); c.globalCompositeOperation = 'lighter'; c.fillStyle = rg2; c.beginPath(); c.arc(h[0], h[1], 16 * S, 0, TAU); c.fill(); }
    c.restore();
  }

  const s = iconPx / 832;
  const X = { x: cx + (MC.x - 512) * s, y: cy + (MC.y - 512) * s, s, rot: 0 };
  const P = markParams(-1);
  const inh = 0.012 * br;

  const fw = sstep(0.22, 0.5, t) * (1 - sstep(1.85, 2.2, t));
  const ox = lerp(-32, 32, E.inOutCubic(seg(t, 0.3, 1.7))) * fw, oy = 16 * fw;
  const open = blinkK(t, 2.45, 0.19);
  for (const b of [P.g, P.c]) { b.tx = 0; b.ty = 0; b.rot = 0; b.sx = 1 - inh * 0.4; b.sy = 1 + inh; b.on = true; b.slot = { ox, oy, sx: 1, sy: open, rot: 0 }; }
  Object.assign(P, { flood: 560, floodEdge: 0, rim: 0, head: 2000, slashT: SL.t, blade: false, colG: C.green, colC: C.cream, mono: 0, square: 1, glowCol: C.glowCalm, accent: C.mint, wash: 0, glowK: 0, catch: 0, reflect: 0, sheen: 0, glint: [seg(t, 2.75, 3.25)], badge: null });
  drawMark(c, X, P, t);
}

function loopSamples(t) { const r = (a, b) => t >= a && t <= b; return r(1.05, 2.3) || r(2.42, 2.7) ? 3 : 1; }

const gl = out.getContext('webgl2', { preserveDrawingBuffer: true, antialias: false, alpha: false, premultipliedAlpha: false });
const FLOAT = !!gl.getExtension('EXT_color_buffer_float');
const VS = `#version 300 es
in vec2 p; out vec2 uv; void main(){ uv = p*0.5+0.5; gl_Position = vec4(p,0.,1.); }`;
const FS = {
  acc: `#version 300 es
precision highp float; in vec2 uv; uniform sampler2D src; uniform float w; out vec4 o; void main(){ o = vec4(texture(src, uv).rgb*w, w); }`,
  bright: `#version 300 es
precision highp float; in vec2 uv; uniform sampler2D src; uniform vec2 px; uniform float th; out vec4 o;
void main(){ vec3 c = vec3(0.); for(int i=0;i<4;i++){ vec2 d = vec2(float(i%2)-.5, float(i/2)-.5)*px*2.; c += texture(src, uv+d).rgb; } c *= .25;
  float l = max(c.r, max(c.g, c.b)); float k = smoothstep(th, th+0.2, l); o = vec4(c*k, 1.); }`,
  blur: `#version 300 es
precision highp float; in vec2 uv; uniform sampler2D src; uniform vec2 dir; out vec4 o;
void main(){ float wt[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216); vec3 c = texture(src, uv).rgb*wt[0];
  for(int i=1;i<5;i++){ c += texture(src, uv+dir*float(i)).rgb*wt[i]; c += texture(src, uv-dir*float(i)).rgb*wt[i]; } o = vec4(c,1.); }`,
  comp: `#version 300 es
precision highp float; in vec2 uv; uniform sampler2D acc, b1, b2; uniform vec2 res, ctr; uniform float rb, ca, bloom, vig, grain, seed, flash; out vec4 o;
float h(vec2 p){ p = fract(p*vec2(443.897, 441.423)); p += dot(p, p.yx+19.19); return fract((p.x+p.y)*p.x); }
vec3 samp(vec2 q){ vec2 d = (q-ctr); if(ca<=0.) return texture(acc, q).rgb; return vec3(texture(acc, q - d*ca).r, texture(acc, q).g, texture(acc, q + d*ca).b); }
void main(){
  vec3 c;
  if(rb > 0.0005){ c = vec3(0.); for(int i=0;i<20;i++){ float s = 1. - rb*float(i)/19.; c += samp(ctr + (uv-ctr)*s); } c /= 20.; }
  else c = samp(uv);
  c += texture(b1, uv).rgb*bloom*0.9 + texture(b2, uv).rgb*bloom*0.8;
  c += flash*vec3(0.75, 1., 0.85);
  vec2 q = (uv-.5)*vec2(res.x/res.y, 1.); c *= 1. - vig*smoothstep(0.45, 1.25, length(q));
  vec3 hi = max(c-0.93, 0.); c = min(c, 0.93) + 0.07*(1.-exp(-hi/0.07));
  float n = h(uv*res + seed) + h(uv*res*1.37 + seed*1.93) - 1.; float l = dot(c, vec3(.3,.59,.11));
  c += n*grain*(0.35 + 0.65*(1.-l));
  c += (h(uv*res + seed*3.1) - .5)/255.;
  o = vec4(c, 1.);
}`,
};
function prog(fs) {
  const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s)); return s; };
  const p = gl.createProgram(); gl.attachShader(p, sh(gl.VERTEX_SHADER, VS)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs));
  gl.bindAttribLocation(p, 0, 'p'); gl.linkProgram(p); if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  const u = {}; const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS); for (let i = 0; i < n; i++) { const a = gl.getActiveUniform(p, i); u[a.name] = gl.getUniformLocation(p, a.name); }
  return { p, u };
}
const PR = Object.fromEntries(Object.entries(FS).map(([k, v]) => [k, prog(v)]));
const vb = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, vb); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
function mkTex(w, h, fl) {
  const t = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, t);
  if (fl) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null); else gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
  for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
  const f = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, f); gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
  return { t, f, w, h };
}
const srcTex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, srcTex);
for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.NEAREST], [gl.TEXTURE_MAG_FILTER, gl.NEAREST], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
const ACC = mkTex(W, H, FLOAT);
const B4a = mkTex(Math.round(W / 4), Math.round(H / 4), FLOAT), B4b = mkTex(Math.round(W / 4), Math.round(H / 4), FLOAT);
const B8a = mkTex(Math.round(W / 8), Math.round(H / 8), FLOAT), B8b = mkTex(Math.round(W / 8), Math.round(H / 8), FLOAT);
function pass(pr, target, uni, texs) {
  gl.useProgram(pr.p); gl.bindFramebuffer(gl.FRAMEBUFFER, target ? target.f : null); gl.viewport(0, 0, target ? target.w : W, target ? target.h : H);
  let unit = 0; for (const [name, tex] of Object.entries(texs)) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, tex); gl.uniform1i(pr.u[name], unit++); }
  for (const [name, v] of Object.entries(uni)) { const l = pr.u[name]; if (l == null) continue; Array.isArray(v) ? gl[`uniform${v.length}f`](l, ...v) : gl.uniform1f(l, v); }
  gl.drawArrays(gl.TRIANGLES, 0, 3);
}
function blur2(a, b, r) { pass(PR.blur, b, { dir: [r / a.w, 0] }, { src: a.t }); pass(PR.blur, a, { dir: [0, r / a.h] }, { src: b.t }); }

function renderFrame(t, frameIndex = Math.round(t * FPS)) {
  const hero = MODE === 'hero';
  const n = hero ? heroSamples(t) : loopSamples(t), shutter = 0.5 / FPS; FRAME_T = t;
  gl.bindFramebuffer(gl.FRAMEBUFFER, ACC.f); gl.viewport(0, 0, W, H); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
  gl.enable(gl.BLEND); gl.blendFunc(gl.ONE, gl.ONE);
  for (let i = 0; i < n; i++) {
    const ts = n === 1 ? t : t + shutter * ((i + 0.5) / n - 0.5);
    hero ? heroSubframe(ts) : loopSubframe(ts);
    gl.bindTexture(gl.TEXTURE_2D, srcTex); gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, scene);
    pass(PR.acc, ACC, { w: 1 / n }, { src: srcTex });
  }
  gl.disable(gl.BLEND);
  const pp = hero ? heroPost(t) : { rb: 0, ca: 0, ctr: [0.5, 0.5], bloom: 0.5, thresh: 0.965, vig: 0.3, grain: 0, flash: 0 };
  pass(PR.bright, B4a, { px: [1 / W, 1 / H], th: pp.thresh }, { src: ACC.t });
  blur2(B4a, B4b, 1.6); blur2(B4a, B4b, 2.6);
  pass(PR.bright, B8a, { px: [1 / B4a.w, 1 / B4a.h], th: 0 }, { src: B4a.t });
  blur2(B8a, B8b, 2.0); blur2(B8a, B8b, 3.2);
  pass(PR.comp, null, { res: [W, H], ctr: pp.ctr, rb: pp.rb, ca: pp.ca, bloom: pp.bloom, vig: pp.vig, grain: pp.grain, seed: hero ? (frameIndex % 997) * 1.618 : 0.0, flash: pp.flash }, { acc: ACC.t, b1: B4a.t, b2: B8a.t });
  gl.finish();
}

window.SCENE = {
  W, H, FPS, MODE, ASPECT, duration: MODE === 'hero' ? TL.end : LOOP,
  renderFrame, events: () => heroEvents(), float: FLOAT,
  ready: (async () => {
    await Promise.all(['500 20px Inter', '600 20px Inter', '700 20px Inter', '800 20px Inter', '500 20px "JetBrains Mono"', '600 20px "JetBrains Mono"', '500 20px "Bricolage Grotesque"', '600 20px "Bricolage Grotesque"', '700 20px "Bricolage Grotesque"', '800 20px "Bricolage Grotesque"'].map(f => document.fonts.load(f)));
    await document.fonts.ready;
    const faces = [...document.fonts].filter(f => f.status === 'loaded').map(f => f.family.replaceAll('"', ''));
    for (const need of ['Inter', 'JetBrains Mono', 'Bricolage Grotesque']) if (!faces.includes(need)) throw new Error('font not loaded: ' + need);
    return true;
  })(),
};
})();
