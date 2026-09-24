#!/usr/bin/env python3
import json, sys, wave
import numpy as np

SR = 48000
rng = np.random.default_rng(11)


def env_ad(n, a, d, curve=4.0):
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), np.exp(-curve * (t - a) / max(d, 1e-4)))
    return e


def fade(x, fi=0.003, fo=0.01):
    n = len(x); a = min(n, int(fi * SR)); b = min(n, int(fo * SR))
    if a: x[:a] *= np.linspace(0, 1, a)
    if b: x[-b:] *= np.linspace(1, 0, b)
    return x


def onepole_lp(x, fc):
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    a = np.exp(-2 * np.pi * fc / SR); y = np.empty_like(x); s = 0.0
    for i in range(len(x)):
        s = (1 - a[i]) * x[i] + a[i] * s; y[i] = s
    return y


def svf_bp(x, fc, q=2.0):
    fc = np.broadcast_to(np.asarray(fc, float), x.shape)
    f = 2 * np.sin(np.pi * np.clip(fc, 20, SR / 6) / SR); damp = 1.0 / q
    lp = bp = 0.0; y = np.empty_like(x)
    for i in range(len(x)):
        hp = x[i] - lp - damp * bp; bp += f[i] * hp; lp += f[i] * bp; y[i] = bp
    return y


def hp1(x, fc):
    return x - onepole_lp(x, fc)


def sine_sweep(f0, f1, dur, shape='exp'):
    n = int(dur * SR); k = np.linspace(0, 1, n)
    f = f0 * (f1 / f0) ** k if shape == 'exp' else f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / SR), f


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def noise_n(m):
    return rng.standard_normal(m)


def pan(x, p):
    p = np.broadcast_to(np.asarray(p, float), x.shape)
    a = (p + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], 1)


def v_swell(e):
    d = e.get('dur', 2.2) + 1.2; n = int(d * SR); t = np.arange(n) / SR
    amp = np.clip(t / 1.5, 0, 1) ** 2 * np.exp(-np.clip(t - 1.6, 0, None) * 2.2)
    sub = np.sin(2 * np.pi * 41 * t) + 0.5 * np.sin(2 * np.pi * 61.5 * t + 0.3) + 0.25 * np.sin(2 * np.pi * 82 * t)
    rum = onepole_lp(noise(d), 180) * 3
    x = (sub * 0.5 + rum * 0.25) * amp
    return pan(x, 0) * 0.9


def v_boop(e):
    f = e['f']; d = 0.42; s, _ = sine_sweep(f * 1.9, f, 0.05)
    n = int(d * SR); t = np.arange(n) / SR
    fr = f * (1 + 0.06 * np.exp(-t * 9) * np.sin(2 * np.pi * 11 * t))
    fr[:len(s)] = np.linspace(f * 1.9, f, len(s))
    x = np.sin(2 * np.pi * np.cumsum(fr) / SR) + 0.2 * np.sin(2 * np.pi * 2 * np.cumsum(fr) / SR)
    x *= env_ad(n, 0.004, 0.32, 5)
    return pan(fade(x), -0.25 if f < 220 else 0.25) * 0.55


def v_whoosh(e):
    d = e.get('dur', 0.3) + 0.12; n = int(d * SR); k = np.linspace(0, 1, n)
    fc = 700 * (9000 / 700) ** (k ** 1.4)
    x = svf_bp(noise(d), fc, 1.6)
    amp = np.clip(k / 0.8, 0, 1) ** 2.5 * np.where(k > 0.8, np.exp(-(k - 0.8) * 30), 1)
    x *= amp
    kk = int(0.8 * n); cm = int(0.03 * SR); click = hp1(noise_n(cm), 3000) * env_ad(cm, 0.0005, 0.02, 6)
    x[kk:kk + len(click)] += click * 0.45
    return pan(fade(x), np.linspace(-0.7, 0.7, n)) * 0.55


def v_punch(e):
    d = 0.5; s, _ = sine_sweep(140, 42, 0.12)
    n = int(d * SR); t = np.arange(n) / SR
    fr = np.concatenate([np.geomspace(140, 42, len(s)), np.full(n - len(s), 42.0)])
    x = np.sin(2 * np.pi * np.cumsum(fr) / SR) * env_ad(n, 0.002, 0.42, 4.5)
    x += 0.3 * onepole_lp(noise(d), 900) * env_ad(n, 0.001, 0.06, 6)
    return pan(fade(x), 0) * 0.8


def v_sparks(e):
    d = e.get('dur', 0.4) + 0.2; n = int(d * SR); out = np.zeros((n, 2))
    for _ in range(46):
        t0 = rng.random() ** 1.8 * d * 0.85; m = int(rng.uniform(0.003, 0.012) * SR)
        g = hp1(noise_n(m), 4000) * env_ad(m, 0.0003, m / SR, 5) * rng.uniform(0.2, 1) * np.exp(-t0 * 4)
        i = int(t0 * SR); out[i:i + m] += pan(g, rng.uniform(-0.8, 0.8))[: n - i]
    return out * 0.22


def v_shimmer(e):
    d = e.get('dur', 0.6) + 0.5; n = int(d * SR); t = np.arange(n) / SR
    x = sum(np.sin(2 * np.pi * f * (1 + 0.015 * t) * t + i) * a for i, (f, a) in enumerate([(1568, 1), (2093, 0.7), (2637, 0.5), (3136, 0.35)]))
    x *= (1 + 0.35 * np.sin(2 * np.pi * 13 * t)) * env_ad(n, 0.08, d - 0.08, 3.5)
    return np.stack([x, np.roll(x, 240)], 1) * 0.05


def v_zoom(e):
    d = e.get('dur', 0.5) + 0.1; n = int(d * SR); k = np.linspace(0, 1, n)
    if e.get('rev'): k = k[::-1]
    fc = 300 * (4000 / 300) ** k
    x = svf_bp(noise(d), fc, 1.2) * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    tone = np.sin(2 * np.pi * np.cumsum(60 * (1 + k)) / SR) * np.sin(np.pi * np.linspace(0, 1, n)) * 0.4
    return pan(fade(x * 0.6 + tone), 0) * 0.4


def v_tick(e):
    f = e.get('f', 2500); g = e.get('g', 1.0); d = 0.06; n = int(d * SR); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * env_ad(n, 0.0008, 0.03, 6) + 0.25 * hp1(noise(d), 5000) * env_ad(n, 0.0002, 0.004, 6)
    return pan(fade(x, 0.0005, 0.005), 0.15 * np.sin(f)) * 0.34 * g


def v_chirp(e):
    f = e.get('f', 2000); d = 0.2; out = np.zeros((int(d * SR), 2))
    s, _ = sine_sweep(f, f * 1.9, 0.035); s *= env_ad(len(s), 0.002, 0.03, 3)
    out[: len(s)] += pan(fade(s), -0.4)
    for j in range(3):
        m = int(0.012 * SR); i = int((0.05 + j * 0.035) * SR); ff = f * (1.25 + 0.3 * j)
        b = np.sin(2 * np.pi * ff * np.arange(m) / SR) * env_ad(m, 0.001, 0.01, 5)
        out[i:i + m] += pan(fade(b, 0.0005, 0.004), -0.2 + 0.2 * j) * 0.6
    return out * 0.2


def v_sweep(e):
    d = e['dur']; n = int(d * SR); k = np.linspace(0, 1, n)
    x = svf_bp(noise(d), 1800 + 900 * np.sin(np.pi * k), 3) * np.sin(np.pi * k) ** 2
    return pan(x, np.linspace(-0.9, 0.9, n)) * 0.2


def v_data(e):
    d = e['dur']; n = int(d * SR) + SR // 10; out = np.zeros((n, 2))
    for _ in range(38):
        t0 = rng.random() * d; m = int(0.008 * SR); ff = rng.uniform(1600, 4200)
        b = np.sin(2 * np.pi * ff * np.arange(m) / SR) * env_ad(m, 0.0008, 0.007, 5) * np.sin(np.pi * t0 / d)
        i = int(t0 * SR); out[i:i + m] += pan(fade(b, 0.0005, 0.003), rng.uniform(-0.9, 0.9))
    return out * 0.17


def bell(f, d, partials=((1, 1), (2.01, 0.35), (2.76, 0.22), (5.4, 0.08)), decay=3.0):
    n = int(d * SR); t = np.arange(n) / SR
    return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * decay * (0.7 + r * 0.5)) for r, a in partials) * np.clip(t / 0.003, 0, 1)


def v_warn(e):
    x = bell(659.3, 1.2) * 0.8; y = bell(987.8, 1.1)
    out = np.zeros((int(1.3 * SR), 2)); out[: len(x)] += pan(x, -0.1); i = int(0.09 * SR); out[i:i + len(y)] += pan(y, 0.1)
    return out * 0.2


def v_error(e):
    out = np.zeros((int(0.6 * SR), 2))
    for j, st in enumerate([0.0, 0.17]):
        d = 0.13; n = int(d * SR); t = np.arange(n) / SR
        x = sum(np.sin(2 * np.pi * 116.5 * h * t) / h for h in (1, 3, 5, 7, 9))
        x = onepole_lp(x, 1400) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t)) * env_ad(n, 0.004, d, 2.5)
        i = int(st * SR); out[i:i + n] += pan(fade(x), 0)
    return out * 0.3


def v_sleep(e):
    d = 0.8; s, _ = sine_sweep(659.3, 293.7, 0.6)
    n = int(d * SR); x = np.zeros(n); x[: len(s)] = s + 0.3 * np.sin(2 * np.pi * np.cumsum(np.geomspace(659.3, 293.7, len(s)) * 2) / SR)
    x[len(s):] = np.sin(2 * np.pi * 293.7 * np.arange(n - len(s)) / SR + 0.0)
    x = onepole_lp(x, 2400) * env_ad(n, 0.02, 0.7, 2.6)
    return pan(fade(x), 0) * 0.2


def v_calm(e):
    a = bell(783.99, 1.4, decay=2.2); b = bell(1174.7, 1.3, decay=2.4)
    out = np.zeros((int(1.5 * SR), 2)); out[: len(a)] += pan(a, -0.2) * 0.7; i = int(0.05 * SR); out[i:i + len(b)] += pan(b, 0.2) * 0.5
    return out * 0.18


def v_roll(e):
    d = e['dur']; n = int(d * SR) + 600; out = np.zeros((n, 2)); rate = 42
    for j in range(int(d * rate)):
        m = int(0.004 * SR); i = int(j / rate * SR)
        b = hp1(noise_n(m), 3500) * env_ad(m, 0.0002, 0.003, 5) * (1 - j / (d * rate)) ** 0.5
        out[i:i + m] += pan(b, 0.5 * np.sin(j))
    return out * 0.06


def v_whip(e):
    d = e['dur'] + 0.15; n = int(d * SR); k = np.linspace(0, 1, n)
    fc = 6500 * (400 / 6500) ** (k ** 0.8)
    x = svf_bp(noise(d), fc, 1.4) * (np.sin(np.pi * np.clip(k * 1.1, 0, 1)) ** 1.2)
    tone = np.sin(2 * np.pi * np.cumsum(900 * (0.25 / 0.9) ** k) / SR) * np.sin(np.pi * k) ** 2 * 0.25
    return pan(fade(x + tone), np.linspace(-0.3, 0.8, n)) * 0.6


def v_land(e):
    b = v_boop({'f': 330}) * 0.9
    p = bell(1318.5, 0.9, decay=3.5)
    out = np.zeros((max(len(b), len(p)), 2)); out[: len(b)] += b; out[: len(p)] += pan(p, 0.35) * 0.18
    return out


def v_rise(e):
    d = e['dur'] + 0.1; n = int(d * SR); k = np.linspace(0, 1, n)
    x = svf_bp(noise(d), 400 * (5000 / 400) ** k, 1.3) * k ** 2
    tone = np.sin(2 * np.pi * np.cumsum(220 * (1 + k)) / SR) * k ** 3 * 0.2
    return pan(fade(x + tone, 0.01, 0.02), 0) * 0.35


def v_glance(e):
    d = 0.14; m = int(d * SR); x = svf_bp(noise_n(m), np.linspace(2500, 5500, m), 2) * env_ad(m, 0.02, 0.1, 4)
    return pan(fade(x), np.linspace(0.2, -0.5, int(d * SR))) * 0.3 + np.pad(v_tick({'f': 2900, 'g': 0.7}), ((0, int(d * SR) - int(0.06 * SR)), (0, 0)))


def v_chord(e):
    d = e['dur'] + 0.2; n = int(d * SR); t = np.arange(n) / SR
    notes = [110.0, 164.81, 220.0, 277.18, 329.63, 493.88]
    x = np.zeros((n, 2))
    for i, f in enumerate(notes):
        for det, p in ((-0.0025, -0.5), (0.0025, 0.5)):
            ph = 2 * np.pi * f * (1 + det) * t
            saw = sum(np.sin(h * ph) / h for h in range(1, 7))
            x += pan(saw * (0.8 if i < 3 else 0.55), p * (0.3 + 0.1 * i))
    x[:, 0] = onepole_lp(x[:, 0], 1100); x[:, 1] = onepole_lp(x[:, 1], 1100)
    amp = np.clip(t / 0.35, 0, 1) ** 1.5 * np.clip((d - t) / 1.2, 0, 1)
    bell_hi = bell(1318.5, 2.2, decay=1.2) * 0.5 + bell(1760.0, 2.2, decay=1.4) * 0.3
    x *= amp[:, None]
    x[: len(bell_hi)] += pan(bell_hi, 0.1) * 0.8
    return x * 0.075


VOICES = {k[2:]: v for k, v in globals().items() if k.startswith('v_')}


def reverb_ir(dur=1.8):
    n = int(dur * SR); t = np.arange(n) / SR
    ir = np.stack([rng.standard_normal(n), rng.standard_normal(n)], 1) * np.exp(-t * 3.6)[:, None]
    ir[:, 0] = onepole_lp(ir[:, 0], 5000); ir[:, 1] = onepole_lp(ir[:, 1], 5000)
    return ir / np.sqrt((ir ** 2).sum(0))


def main():
    ev = json.load(open(sys.argv[1])); dur = ev['duration']
    n = int((dur + 0.02) * SR); dry = np.zeros((n + SR * 3, 2)); send = np.zeros_like(dry)
    t = np.arange(n) / SR
    bed = (np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 82.4 * t + 1) * 0.3) * 0.04
    bed *= np.clip(t / 1.5, 0, 1) * np.clip((dur - t) / 0.4, 0, 1)
    dry[:n] += pan(onepole_lp(bed + onepole_lp(rng.standard_normal(n), 300) * 0.02, 400), 0)
    for e in ev['events']:
        x = VOICES[e['type']](e)
        i = int(round(e['t'] * SR))
        m = min(len(x), len(dry) - i)
        dry[i:i + m] += x[:m]
        wet = {'chord': 0.5, 'warn': 0.5, 'calm': 0.6, 'sleep': 0.6, 'land': 0.5, 'boop': 0.35, 'tick': 0.25, 'chirp': 0.3}.get(e['type'], 0.2)
        send[i:i + m] += x[:m] * wet
    ir = reverb_ir()
    L = len(send) + len(ir)
    wet = np.stack([np.fft.irfft(np.fft.rfft(send[:, c], L) * np.fft.rfft(ir[:, c], L), L)[: len(send)] for c in (0, 1)], 1)
    out = (dry + wet * 0.35)[:n]
    out[-int(0.05 * SR):] *= np.linspace(1, 0, int(0.05 * SR))[:, None]
    out /= max(1e-9, np.abs(out).max()) / 0.5
    with wave.open(sys.argv[2], 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(out, -1, 1) * 32767).astype('<i2').tobytes())
    print(f'wrote {sys.argv[2]}: {dur:.2f}s, {len(ev["events"])} cues')


if __name__ == '__main__':
    main()
