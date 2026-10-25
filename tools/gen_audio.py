# -*- coding: utf-8 -*-
"""NEON RUSH 程序化音频合成：synthwave 循环 BGM + 全套音效，纯 stdlib 输出 WAV。"""
import math, wave, struct, os, random

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets')
os.makedirs(OUT, exist_ok=True)
random.seed(7)

def clamp(v, a=-1.0, b=1.0):
    return a if v < a else b if v > b else v

def save(name, samples, gain=0.9):
    peak = max(1e-9, max(abs(s) for s in samples))
    norm = min(1.0, gain / peak)
    path = os.path.join(OUT, name)
    with wave.open(path, 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(clamp(s * norm) * 32767)) for s in samples))
    print(f'{name}: {len(samples)/SR:.2f}s')

def saw(ph): return 2.0 * (ph - math.floor(ph + 0.5))
def sqr(ph): return 1.0 if (ph % 1.0) < 0.5 else -1.0

def lowpass(sig, cutoff):
    out = [0.0] * len(sig)
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    y = 0.0
    for i, s in enumerate(sig):
        y += a * (s - y)
        out[i] = y
    return out

def env_ad(i, n, attack_s, decay_pow=2.0):
    a = int(attack_s * SR)
    if i < a:
        return i / max(1, a)
    return (1.0 - (i - a) / max(1, n - a)) ** decay_pow

# ---------------- SFX ----------------
def sfx_pickup():
    n = int(0.20 * SR); out = []
    for i in range(n):
        t = i / SR
        f = 660 * (2 ** (min(1.0, t / 0.12) * 7 / 12))
        v = (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(4 * math.pi * f * t)) * env_ad(i, n, 0.004) ** 1.5
        out.append(v * 0.8)
    save('sfx_pickup.wav', out)

def sfx_jump():
    n = int(0.28 * SR); out = []
    for i in range(n):
        t = i / SR
        f = 280 + 420 * min(1.0, t / 0.18)
        v = math.sin(2 * math.pi * f * t) * env_ad(i, n, 0.006) ** 1.4
        v += 0.18 * saw(t * f * 2.0) * env_ad(i, n, 0.02)
        out.append(v * 0.8)
    save('sfx_jump.wav', out)

def sfx_lane():
    n = int(0.09 * SR); out = []
    lp_noise = 0.0
    for i in range(n):
        t = i / SR
        lp_noise += 0.35 * ((random.random() * 2 - 1) - lp_noise)
        v = lp_noise * env_ad(i, n, 0.003) ** 2.0 * 0.7
        v += 0.3 * math.sin(2 * math.pi * 190 * t) * env_ad(i, n, 0.002)
        out.append(v)
    save('sfx_lane.wav', out)

def sfx_crash():
    n = int(0.85 * SR); out = []
    lp = 0.0; lp2 = 0.0
    for i in range(n):
        t = i / SR
        noise = random.random() * 2 - 1
        lp += 0.28 * (noise - lp)
        lp2 += (2.0 - 1.85 * min(1.0, t / 0.8)) * (lp - lp2)
        v = lp2 * env_ad(i, n, 0.004, 3.2) * 1.4
        boom_f = 120 * (1 - min(1.0, t / 0.5)) + 38
        v += 0.9 * math.sin(2 * math.pi * boom_f * t) * env_ad(i, n, 0.002, 2.4)
        out.append(v)
    save('sfx_crash.wav', lowpass(out, 3800))

# ---------------- BGM ----------------
def bgm():
    bpm = 112.0
    beat = 60.0 / bpm
    bars = 4
    total = int(bars * 4 * beat * SR)
    mix = [0.0] * total

    def add(start_s, sig):
        s0 = int(start_s * SR) % total
        for i, v in enumerate(sig):
            mix[(s0 + i) % total] += v   # 尾音回绕 => 无缝循环

    roots = [55.0, 43.65, 65.41, 49.0]        # Am F C G
    chords = [(55, 65.41, 82.41), (43.65, 55, 65.41), (65.41, 82.41, 98.0), (49, 61.74, 82.41)]

    for bar in range(bars):
        t0 = bar * 4 * beat
        root, third, fifth = chords[bar]

        # 底鼓：四踩
        for b in range(4):
            n = int(0.14 * SR); seg = []
            for i in range(n):
                t = i / SR
                f = 150 * (1 - min(1.0, t / 0.12)) + 42
                seg.append(math.sin(2 * math.pi * f * t) * env_ad(i, n, 0.001, 2.6))
            add(t0 + b * beat, [x * 0.95 for x in seg])

        # 镲：反拍
        for b in range(4):
            n = int(0.05 * SR); seg = []
            for i in range(n):
                seg.append((random.random() * 2 - 1) * env_ad(i, n, 0.001, 3.0))
            add(t0 + (b + 0.5) * beat, lowpass(seg, 9000))

        # 贝斯：8 分符点律动
        pattern = [(0, 1.0), (0.5, 0.7), (0.75, 0.9), (1.5, 0.7), (2.0, 1.0), (2.5, 0.7), (3.0, 0.85), (3.5, 0.7)]
        for off, amp in pattern:
            n = int(0.30 * SR); seg = []
            for i in range(n):
                t = i / SR
                v = 0.6 * saw(root * t) + 0.4 * saw(root * 2 * t + 0.3)
                seg.append(v * env_ad(i, n, 0.004, 2.2) * amp)
            add(t0 + off * beat, lowpass(seg, 700))

        # 铺底和声：每小节一个持续 detune 锯齿和弦
        n = int(4 * beat * SR); seg = []
        for i in range(n):
            t = i / SR
            v = 0.0
            for j, f in enumerate((root * 2, third * 2, fifth * 2)):
                v += 0.11 * saw(f * 1.003 * t) + 0.11 * saw(f * 0.997 * t + 0.5)
            seg.append(v * env_ad(i, n, 0.4, 1.2) ** 0.6)
        add(t0, lowpass(seg, 1500))

        # 引导旋律：小节尾一个高音钩子
        hook = {0: 220.0, 1: 174.61, 2: 261.63, 3: 196.0}[bar]
        n = int(1.2 * beat * SR); seg = []
        for i in range(n):
            t = i / SR
            v = 0.5 * sqr(hook * 2 * t) + 0.5 * math.sin(2 * math.pi * hook * 2 * t)
            seg.append(v * env_ad(i, n, 0.01, 1.8) * 0.5)
        add(t0 + 2 * beat, lowpass(seg, 2600))

    # 轻压限
    out = [math.tanh(v * 1.4) * 0.8 for v in mix]
    save('music_loop.wav', out)

sfx_pickup(); sfx_jump(); sfx_lane(); sfx_crash(); bgm()
print('全部音频生成完毕 ->', os.path.abspath(OUT))
