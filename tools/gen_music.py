"""젤리 워즈 전투 곡 생성기 (이슈 #484).

외부 음원 없이 numpy·scipy 로 **합성해서** `assets/music/battle_*.ogg` 를 만든다 — 라이선스를
따질 것이 없다. 효과음 생성기(`gen_sfx.py`)와 같은 방식이다.

    python3 tools/gen_music.py              # 세 곡 전부
    python3 tools/gen_music.py rush         # 이름을 주면 그것만 (rush · showdown · groove)

곡은 **악보를 손으로 적어 둔 것**이다 — 아래 `SONGS` 의 멜로디 문자열이 곧 악보다.
`"E5:2 A5:2 r:4"` 는 "E5 를 16분음표 2칸, A5 를 2칸, 4칸 쉼" 이다. 마디 하나는 16칸.

세 곡은 분위기만 이전 곡(Suno 무료 생성, #481)과 맞췄고 **멜로디·구성은 새로 썼다** —
이전 곡은 Suno 소유라 가깝게 베끼면 2차적 저작물이 된다.

ffmpeg 로 ogg 를 만든다(PATH 에 없으면 환경 변수 FFMPEG 로 경로를 준다). 만든 뒤 Godot 이
`.ogg.import` 를 만들어야 게임이 읽는다(`--headless --import`). **반복(loop)은 켜지 않는다** —
`Music` 이 곡이 끝나면(`finished`) 다음 곡을 무작위로 고른다(#463).
"""

import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")
# 곡 음량. 이전 전투 곡이 평균 -17~-18dBFS 였고 `Music.NORMAL_DB` 가 그 기준으로 잡혀 있다.
TARGET_RMS_DB = -18.0
PEAK_LIMIT = 0.89  # -1 dBFS

NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


# ─────────────────────────── 음 이름 · 악보 ───────────────────────────

def midi(name):
    """'C#5' → 73. 'r' 은 쉼(None)."""
    if name == "r":
        return None
    pitch = NOTE_NAMES[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pitch += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return pitch + 12 * (int(rest) + 1)


def freq(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def parse(line):
    """'E5:2 A5:2 r:4' → [(시작칸, 길이칸, midi)] (쉼은 빼고)."""
    events, step = [], 0
    for token in line.split():
        name, length = token.split(":")
        length = int(length)
        m = midi(name)
        if m is not None:
            events.append((step, length, m))
        step += length
    return events, step


CHORDS = {
    # 이름 → 근음에서의 반음 간격
    "m": (0, 3, 7), "": (0, 4, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11),
}


def chord(name):
    """'Am' → (근음 midi 옥타브 3, 간격들). 'F#m7' 같은 것도 읽는다."""
    root = name[0]
    rest = name[1:]
    acc = ""
    while rest and rest[0] in "#b":
        acc += rest[0]
        rest = rest[1:]
    return midi(root + acc + "3"), CHORDS[rest]


# ─────────────────────────── 소리 재료 ───────────────────────────

class Track:
    """한 곡을 그리는 스테레오 버퍼. 칸(16분음표) 단위로 소리를 놓는다."""

    def __init__(self, bpm, bars, tail=2.5):
        self.step = 60.0 / bpm / 4.0
        self.length = int(SR * (bars * 16 * self.step + tail))
        self.buses = {}
        self.rng = np.random.default_rng(484)

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((self.length, 2))
        return self.buses[name]

    def at(self, bar, step):
        return int(SR * (bar * 16 + step) * self.step)

    def put(self, name, start, mono, pan=0.0, gain=1.0):
        """`pan` -1(왼쪽)~1(오른쪽). 등전력 팬."""
        if start >= self.length:
            return
        end = min(self.length, start + len(mono))
        x = mono[: end - start] * gain
        angle = (pan + 1.0) * np.pi / 4.0
        buf = self.bus(name)
        buf[start:end, 0] += x * np.cos(angle)
        buf[start:end, 1] += x * np.sin(angle)


def env(n, a, d, s, r, sustain_len):
    """ADSR. 초 단위 a·d·r, s 는 0~1, sustain_len 은 키를 누르고 있는 시간(초)."""
    t = np.arange(n) / SR
    out = np.empty(n)
    a = max(a, 1e-4)
    held = t < sustain_len
    attack = np.minimum(t / a, 1.0)
    decay = s + (1.0 - s) * np.exp(-np.maximum(t - a, 0.0) / max(d, 1e-4))
    out = np.where(t < a, attack, decay)
    rel_level = out[min(n - 1, int(sustain_len * SR))] if n else 0.0
    release = rel_level * np.exp(-np.maximum(t - sustain_len, 0.0) / max(r, 1e-4))
    return np.where(held, out, release)


def phase(f, n, vib=0.0, vib_rate=5.5, vib_delay=0.12):
    """주파수(고정 또는 배열)로 위상(0~1 순환)을 만든다. 비브라토는 조금 늦게 들어온다."""
    t = np.arange(n) / SR
    fr = np.broadcast_to(np.asarray(f, dtype=float), (n,)).copy()
    if vib:
        depth = np.clip((t - vib_delay) / 0.15, 0.0, 1.0) * vib
        fr *= 2.0 ** (depth * np.sin(2 * np.pi * vib_rate * t) / 12.0)
    return np.cumsum(fr) / SR % 1.0, fr


def blep(p, dt):
    """PolyBLEP — 톱니·사각파의 계단에서 생기는 접힘(알리아싱)을 줄인다."""
    out = np.zeros_like(p)
    m = p < dt
    x = p[m] / dt[m]
    out[m] = x + x - x * x - 1.0
    m2 = p > 1.0 - dt
    x = (p[m2] - 1.0) / dt[m2]
    out[m2] = x * x + x + x + 1.0
    return out


def saw(f, n, vib=0.0):
    p, fr = phase(f, n, vib)
    dt = np.maximum(fr / SR, 1e-6)
    return 2.0 * p - 1.0 - blep(p, dt)


def pulse(f, n, width=0.5, vib=0.0):
    p, fr = phase(f, n, vib)
    dt = np.maximum(fr / SR, 1e-6)
    a = np.where(p < width, 1.0, -1.0)
    a += blep(p, dt)
    a -= blep((p + 1.0 - width) % 1.0, dt)
    return a


def tri(f, n):
    p, _ = phase(f, n)
    return 4.0 * np.abs(p - 0.5) - 1.0


def lowpass(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff, SR * 0.45) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


# ─────────────────────────── 악기 ───────────────────────────

def note_len(tr, steps):
    return steps * tr.step


def inst_lead_square(tr, f, steps, width=0.5):
    hold = note_len(tr, steps) * 0.92
    n = int(SR * (hold + 0.25))
    x = pulse(f, n, width, vib=0.18)
    x = lowpass(x, 6500)
    return x * env(n, 0.006, 0.12, 0.65, 0.08, hold) * 0.32


def inst_lead_saw(tr, f, steps):
    hold = note_len(tr, steps) * 0.95
    n = int(SR * (hold + 0.4))
    x = saw(f, n, vib=0.15) + saw(f * 1.006, n, vib=0.15) * 0.8 + saw(f * 0.994, n) * 0.6
    x = lowpass(x, 4200)
    return x * env(n, 0.015, 0.3, 0.7, 0.18, hold) * 0.16


def inst_lead_funk(tr, f, steps):
    """짧게 튕기는 사각파 + 살짝 올라타는 슬라이드."""
    hold = note_len(tr, steps) * 0.8
    n = int(SR * (hold + 0.15))
    t = np.arange(n) / SR
    bend = f * 2.0 ** (-0.6 * np.exp(-t / 0.025) / 12.0)
    x = pulse(bend, n, 0.3, vib=0.12)
    x = lowpass(x, 5200)
    return x * env(n, 0.004, 0.1, 0.55, 0.05, hold) * 0.3


def inst_bass_pluck(tr, f, steps):
    hold = note_len(tr, steps) * 0.85
    n = int(SR * (hold + 0.08))
    t = np.arange(n) / SR
    bright = saw(f, n)
    # 처음엔 밝고 금방 둥글어지는 플럭 — 필터를 움직이는 대신 밝은 소리와 어두운 소리를 섞는다.
    x = lowpass(bright, 2400) * np.exp(-t / 0.06) + lowpass(bright, 500) + np.sin(2 * np.pi * f * t) * 0.6
    return x * env(n, 0.003, 0.15, 0.7, 0.04, hold) * 0.3


def inst_bass_synth(tr, f, steps):
    hold = note_len(tr, steps) * 0.9
    n = int(SR * (hold + 0.06))
    t = np.arange(n) / SR
    x = lowpass(saw(f, n) + saw(f * 1.004, n) * 0.6, 900) + np.sin(2 * np.pi * f * t) * 0.7
    return x * env(n, 0.004, 0.1, 0.8, 0.03, hold) * 0.28


def inst_bass_funk(tr, f, steps):
    hold = note_len(tr, steps) * 0.75
    n = int(SR * (hold + 0.05))
    t = np.arange(n) / SR
    x = lowpass(pulse(f, n, 0.4), 1400) * np.exp(-t / 0.12) + np.sin(2 * np.pi * f * t) * 0.8
    return x * env(n, 0.002, 0.12, 0.6, 0.03, hold) * 0.36


def inst_arp(tr, f, steps):
    hold = note_len(tr, steps) * 0.6
    n = int(SR * (hold + 0.06))
    x = pulse(f, n, 0.25)
    x = lowpass(x, 5000)
    return x * env(n, 0.002, 0.06, 0.3, 0.03, hold) * 0.12


def inst_pluck(tr, f, steps):
    hold = note_len(tr, steps) * 0.5
    n = int(SR * (hold + 0.2))
    t = np.arange(n) / SR
    x = tri(f, n) + lowpass(saw(f * 2.0, n), 3000) * 0.3 * np.exp(-t / 0.05)
    return x * env(n, 0.002, 0.12, 0.25, 0.1, hold) * 0.16


def inst_clav(tr, f, steps):
    hold = note_len(tr, steps) * 0.4
    n = int(SR * (hold + 0.05))
    t = np.arange(n) / SR
    x = bandpass(pulse(f, n, 0.18), 400, 3500) * np.exp(-t / 0.07)
    return x * env(n, 0.001, 0.05, 0.4, 0.02, hold) * 0.32


def inst_pad(tr, f, steps):
    hold = note_len(tr, steps)
    n = int(SR * (hold + 0.6))
    x = sum(saw(f * d, n) for d in (0.996, 1.0, 1.004)) / 3.0
    x = lowpass(x, 1800)
    return x * env(n, 0.25, 0.5, 0.8, 0.5, hold) * 0.1


def kick(tr, punch=1.0):
    n = int(SR * 0.42)
    t = np.arange(n) / SR
    f = 45.0 + 110.0 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    click = highpass(tr.rng.standard_normal(n), 3000) * np.exp(-t / 0.004) * 0.25
    return np.tanh((body + click) * 1.6 * punch) * 0.55


def snare(tr, tone=190.0, bright=1.0):
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    noise = bandpass(tr.rng.standard_normal(n), 1200, 9000) * np.exp(-t / (0.07 * bright))
    body = np.sin(2 * np.pi * tone * t) * np.exp(-t / 0.05)
    return (noise * 0.55 + body * 0.5) * 0.45


def clap(tr):
    n = int(SR * 0.3)
    t = np.arange(n) / SR
    burst = sum(np.exp(-np.maximum(t - o, 0.0) / 0.012) * (t >= o) for o in (0.0, 0.011, 0.022))
    tailn = np.exp(-t / 0.09)
    x = bandpass(tr.rng.standard_normal(n), 900, 6000) * (burst * 0.6 + tailn * 0.5)
    return x * 0.35


def hat(tr, open_=False):
    d = 0.22 if open_ else 0.045
    n = int(SR * (d * 4))
    t = np.arange(n) / SR
    x = highpass(tr.rng.standard_normal(n), 7000) * np.exp(-t / d)
    return x * (0.16 if open_ else 0.13)


def crash(tr):
    n = int(SR * 2.2)
    t = np.arange(n) / SR
    x = highpass(tr.rng.standard_normal(n), 4500) * np.exp(-t / 0.7)
    return x * 0.14


# ─────────────────────────── 이펙트 · 믹스 ───────────────────────────

def reverb(x, rng, seconds=1.4, mix=0.18, lowcut=300.0):
    """잡음을 지수로 줄인 임펄스 응답으로 컨볼루션 — 방 크기만 정하는 간단한 잔향."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t / (seconds / 6.0))[:, None]
    ir[:, 0] = lowpass(ir[:, 0], 6000)
    ir[:, 1] = lowpass(ir[:, 1], 6000)
    ir /= np.sqrt(np.sum(ir ** 2, axis=0, keepdims=True))
    src = highpass(x.mean(axis=1), lowcut)
    wet = np.stack([signal.fftconvolve(src, ir[:, c])[: len(x)] for c in range(2)], axis=1)
    return x + wet * mix


def sidechain(tr, kicks, depth=0.5, release=0.18):
    """킥이 칠 때마다 크기를 눌렀다 놓는 게인 곡선 (신스웨이브의 '숨쉬는' 느낌)."""
    g = np.ones(tr.length)
    shape_n = int(SR * release * 4)
    t = np.arange(shape_n) / SR
    duck = 1.0 - depth * np.exp(-t / release)
    for start in kicks:
        end = min(tr.length, start + shape_n)
        g[start:end] = np.minimum(g[start:end], duck[: end - start])
    return g[:, None]


def master(mix):
    rms = np.sqrt(np.mean(mix ** 2))
    mix = mix * (10 ** (TARGET_RMS_DB / 20.0) / max(rms, 1e-9))
    # 부드러운 리미터 — 넘는 봉우리만 둥글게 누른다.
    over = np.abs(mix) > 0.7
    mix[over] = np.sign(mix[over]) * (0.7 + (PEAK_LIMIT - 0.7) * np.tanh((np.abs(mix[over]) - 0.7) / (PEAK_LIMIT - 0.7)))
    # 끝 0.3초는 부드럽게 닫는다(잔향 꼬리).
    fade = int(SR * 0.3)
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)[:, None]
    return mix


# ─────────────────────────── 곡을 놓는 도구 ───────────────────────────

def lay_melody(tr, bus, bar0, lines, inst, octave_shift=0, pan=0.0, gain=1.0):
    for i, line in enumerate(lines):
        events, total = parse(line)
        assert total == 16, f"마디 길이가 16칸이 아니다 ({total}): {line}"
        for step, length, m in events:
            f = freq(m + 12 * octave_shift)
            tr.put(bus, tr.at(bar0 + i, step), inst(tr, f, length), pan, gain)


def lay_pattern(tr, bus, bar0, chords, pattern, inst, pan=0.0, gain=1.0):
    """`pattern` 은 [(칸, 길이, 근음 기준 반음)] — 화음마다 근음으로 옮겨 놓는다."""
    for i, name in enumerate(chords):
        root, _ = chord(name)
        for step, length, interval in pattern:
            tr.put(bus, tr.at(bar0 + i, step), inst(tr, freq(root + interval), length), pan, gain)


def lay_arp(tr, bus, bar0, chords, inst, octave=1, every=1, up_down=False, pan=0.0, gain=1.0):
    for i, name in enumerate(chords):
        root, iv = chord(name)
        tones = [root + 12 * octave + x for x in iv] + [root + 12 * (octave + 1)]
        seq = tones + tones[-2:0:-1] if up_down else tones
        for k, step in enumerate(range(0, 16, every)):
            tr.put(bus, tr.at(bar0 + i, step), inst(tr, freq(seq[k % len(seq)]), every), pan, gain)


def lay_pad(tr, bus, bar0, chords, inst=inst_pad, octave=1, gain=1.0):
    for i, name in enumerate(chords):
        root, iv = chord(name)
        for k, x in enumerate(iv):
            pan = (-0.4, 0.4, 0.0, 0.2)[k % 4]
            tr.put(bus, tr.at(bar0 + i, 0), inst(tr, freq(root + 12 * octave + x), 16), pan, gain)


def lay_drums(tr, bar0, bars, kicks=(), snares=(), hats=(), open_hats=(), claps=(), ghosts=(),
              snare_fn=None, kick_list=None, hat_gain=1.0):
    snare_fn = snare_fn or (lambda: snare(tr))
    for b in range(bar0, bar0 + bars):
        for s in kicks:
            start = tr.at(b, s)
            tr.put("drums", start, kick(tr))
            if kick_list is not None:
                kick_list.append(start)
        for s in snares:
            tr.put("drums", tr.at(b, s), snare_fn())
        for s in claps:
            tr.put("drums", tr.at(b, s), clap(tr), 0.1)
        for s in ghosts:
            tr.put("drums", tr.at(b, s), snare_fn(), 0.0, 0.25)
        for s in hats:
            accent = 1.0 if s % 4 == 2 else 0.7
            tr.put("drums", tr.at(b, s), hat(tr), 0.35, accent * hat_gain)
        for s in open_hats:
            tr.put("drums", tr.at(b, s), hat(tr, True), 0.35, hat_gain)


def fill(tr, bar):
    """마디 끝 두 박자 스네어 연타 — 다음 덩어리로 넘어가는 신호."""
    for k, s in enumerate(range(8, 16, 2)):
        tr.put("drums", tr.at(bar, s), snare(tr), 0.0, 0.5 + 0.12 * k)
    for s in (12, 13, 14, 15):
        tr.put("drums", tr.at(bar, s), snare(tr), 0.0, 0.7)


# ─────────────────────────── ① Jelly Rush — 칩튠 160BPM A단조 ───────────────────────────

def song_rush():
    prog_a = ["Am", "F", "C", "G"] * 2
    prog_b = ["F", "G", "Em", "Am", "Dm", "Em", "F", "G"]
    lead_a = [
        "E5:2 A5:2 E5:2 C5:2 D5:2 E5:4 r:2",
        "F5:2 E5:2 D5:2 C5:2 A4:4 C5:4",
        "G4:2 C5:2 E5:2 G5:2 E5:2 D5:2 C5:4",
        "D5:4 B4:2 G4:2 B4:4 D5:4",
        "E5:2 A5:2 E5:2 C5:2 D5:2 E5:2 G5:4",
        "A5:4 G5:2 F5:2 E5:4 C5:4",
        "D5:2 E5:2 G5:2 E5:2 D5:2 C5:2 B4:4",
        "A4:8 r:4 E5:2 G5:2",
    ]
    lead_b = [
        "A5:6 G5:2 F5:4 C5:4",
        "B5:6 A5:2 G5:4 D5:4",
        "G5:4 E5:4 B4:4 E5:4",
        "C6:6 B5:2 A5:8",
        "F5:4 A5:4 D6:4 A5:4",
        "G5:4 B5:4 E6:4 B5:4",
        "C6:2 A5:2 F5:2 A5:2 C6:2 A5:2 F5:2 A5:2",
        "D6:4 B5:4 G5:4 r:4",
    ]
    bass = [(0, 2, -12), (2, 2, -12), (4, 2, 0), (6, 2, -12), (8, 2, -12), (10, 2, 0), (12, 2, -12), (14, 2, 0)]

    tr = Track(160, 42)
    # 0-3 인트로 · 4-11 A · 12-19 B · 20-27 A · 28-31 쉬어 가기 · 32-39 B(한 옥타브 아래 선율 + 아르페지오) · 40-41 끝
    lay_pattern(tr, "bass", 0, prog_a[:4], bass, inst_bass_pluck, gain=0.9)
    lay_drums(tr, 0, 4, kicks=(0, 8), hats=range(2, 16, 4))
    lay_drums(tr, 2, 2, kicks=(0, 4, 8, 12), hats=range(0, 16, 2))
    fill(tr, 3)

    for start, prog, lead in ((4, prog_a, lead_a), (12, prog_b, lead_b), (20, prog_a, lead_a)):
        tr.put("drums", tr.at(start, 0), crash(tr), -0.2)
        lay_pattern(tr, "bass", start, prog, bass, inst_bass_pluck)
        lay_arp(tr, "arp", start, prog, inst_arp, octave=1, every=1, up_down=True, pan=0.35, gain=0.8)
        lay_melody(tr, "lead", start, lead, inst_lead_square, pan=-0.1)
        lay_drums(tr, start, 8, kicks=(0, 4, 8, 12), snares=(4, 12), hats=range(2, 16, 4),
                  open_hats=(14,))
        fill(tr, start + 7)

    # 28-31 쉬어 가기: 반으로 줄인 박자, 패드와 아르페지오만.
    lay_pad(tr, "pad", 28, ["F", "G", "Em", "Am"], gain=1.2)
    lay_arp(tr, "arp", 28, ["F", "G", "Em", "Am"], inst_pluck, octave=2, every=2, pan=-0.3)
    lay_drums(tr, 28, 4, kicks=(0,), snares=(8,), hats=range(0, 16, 4))
    fill(tr, 31)

    tr.put("drums", tr.at(32, 0), crash(tr), 0.2)
    lay_pattern(tr, "bass", 32, prog_b, bass, inst_bass_pluck)
    lay_arp(tr, "arp", 32, prog_b, inst_arp, octave=2, every=1, up_down=True, pan=0.35, gain=0.8)
    lay_melody(tr, "lead", 32, lead_b, inst_lead_square, pan=-0.1)
    lay_melody(tr, "lead2", 32, lead_b, lambda t, f, s: inst_lead_square(t, f, s, 0.25), octave_shift=-1,
               pan=0.3, gain=0.5)
    lay_drums(tr, 32, 8, kicks=(0, 4, 8, 12), snares=(4, 12), hats=range(0, 16, 2), open_hats=(14,))
    fill(tr, 39)

    # 끝: 으뜸화음 한 번 치고 울림.
    tr.put("drums", tr.at(40, 0), crash(tr))
    tr.put("drums", tr.at(40, 0), kick(tr))
    lay_melody(tr, "lead", 40, ["A5:16", "r:16"], inst_lead_square)
    lay_pattern(tr, "bass", 40, ["Am"], [(0, 16, -12)], inst_bass_pluck)
    lay_pad(tr, "pad", 40, ["Am"], gain=1.2)

    mix = (tr.bus("drums") * 0.95 + tr.bus("bass") * 0.9 + tr.bus("arp") * 0.8 + tr.bus("lead") * 1.0
           + tr.bus("lead2") + tr.bus("pad"))
    return master(reverb(mix, tr.rng, 1.2, 0.14))


# ─────────────────────────── ② Gummy Showdown — 신스웨이브 140BPM D단조 ───────────────────────────

def song_showdown():
    prog_a = ["Dm", "Bb", "F", "C"] * 2
    prog_b = ["Gm", "Bb", "F", "A"] * 2
    lead_a = [
        "D5:6 F5:2 A5:8",
        "G5:4 F5:4 D5:8",
        "C5:6 D5:2 F5:4 A5:4",
        "G5:12 E5:4",
        "D5:6 F5:2 A5:6 C6:2",
        "D6:4 C6:4 A5:4 G5:4",
        "F5:6 G5:2 A5:4 C6:4",
        "E5:8 G5:4 E5:4",
    ]
    lead_b = [
        "G5:4 A#5:4 D6:8",
        "F5:4 A#5:4 D6:4 F6:4",
        "C6:8 A5:4 F5:4",
        "E5:4 A5:4 C#6:8",
        "D6:6 C6:2 A#5:4 G5:4",
        "A#5:4 D6:4 F6:8",
        "E6:4 C6:4 A5:4 F5:4",
        "E5:4 A5:4 C#6:4 E6:4",
    ]
    bass = [(s, 2, -12 if (s // 2) % 2 == 0 else 0) for s in range(0, 16, 2)]
    kicks = []

    tr = Track(140, 38)
    # 0-3 인트로(패드+아르페지오) · 4-11 A · 12-19 B · 20-23 쉬어 가기 · 24-31 A · 32-35 B 앞 절반 · 36-37 끝
    lay_pad(tr, "pad", 0, prog_a[:4])
    lay_arp(tr, "arp", 0, prog_a[:4], inst_pluck, octave=2, every=1, pan=0.3)
    lay_drums(tr, 2, 2, hats=range(0, 16, 1), hat_gain=0.6)
    fill(tr, 3)

    def section(start, prog, lead, bars=8):
        tr.put("drums", tr.at(start, 0), crash(tr), -0.2)
        lay_pad(tr, "pad", start, prog[:bars])
        lay_pattern(tr, "bass", start, prog[:bars], bass, inst_bass_synth)
        lay_arp(tr, "arp", start, prog[:bars], inst_pluck, octave=2, every=1, pan=0.3)
        lay_melody(tr, "lead", start, lead[:bars], inst_lead_saw, pan=-0.05)
        lay_drums(tr, start, bars, kicks=(0, 8, 10), snares=(4, 12), hats=range(0, 16, 1),
                  snare_fn=lambda: snare(tr, 170, 1.6), kick_list=kicks, hat_gain=0.55)
        fill(tr, start + bars - 1)

    section(4, prog_a, lead_a)
    section(12, prog_b, lead_b)
    lay_pad(tr, "pad", 20, ["Dm", "Bb", "Gm", "A"], gain=1.3)
    lay_arp(tr, "arp", 20, ["Dm", "Bb", "Gm", "A"], inst_pluck, octave=2, every=2, pan=0.3)
    lay_drums(tr, 20, 4, kicks=(0,), hats=range(0, 16, 2), hat_gain=0.5, kick_list=kicks)
    fill(tr, 23)
    section(24, prog_a, lead_a)
    section(32, prog_b, lead_b, bars=4)

    tr.put("drums", tr.at(36, 0), crash(tr))
    tr.put("drums", tr.at(36, 0), kick(tr))
    lay_melody(tr, "lead", 36, ["D6:16", "r:16"], inst_lead_saw)
    lay_pattern(tr, "bass", 36, ["Dm"], [(0, 16, -12)], inst_bass_synth)
    lay_pad(tr, "pad", 36, ["Dm"], gain=1.3)

    pump = sidechain(tr, kicks, depth=0.55)
    mix = (tr.bus("drums") * 0.9 + tr.bus("bass") * pump * 0.95 + tr.bus("pad") * pump * 1.1
           + tr.bus("arp") * pump * 0.8 + tr.bus("lead"))
    return master(reverb(mix, tr.rng, 2.2, 0.24))


# ─────────────────────────── ③ Sticky Groove — 펑크 116BPM E도리안 ───────────────────────────

def song_groove():
    prog_a = ["Em7", "Em7", "A7", "A7"] * 2
    prog_b = ["Cmaj7", "Bm7", "Am7", "Bm7"] * 2
    lead_a = [
        "r:2 B4:1 D5:1 E5:2 G5:2 E5:1 D5:1 B4:2 r:4",
        "r:2 E5:1 G5:1 A5:2 B5:3 A5:1 G5:2 E5:4",
        "r:2 C#5:1 E5:1 G5:2 A5:2 G5:1 E5:1 C#5:2 r:4",
        "A5:3 G5:1 E5:2 D5:2 E5:8",
    ] * 2
    lead_b = [
        "E5:4 G5:4 B5:6 r:2",
        "D5:4 F#5:4 A5:6 r:2",
        "C5:4 E5:4 G5:6 r:2",
        "B4:2 D5:2 F#5:2 A5:2 B5:8",
        "G5:2 E5:2 B5:4 A5:2 G5:2 E5:4",
        "F#5:2 D5:2 A5:4 G5:2 F#5:2 D5:4",
        "E5:2 C5:2 G5:4 F#5:2 E5:2 C5:4",
        "D5:4 F#5:4 B5:8",
    ]
    bass = [(0, 2, -12), (3, 1, -12), (4, 1, 0), (6, 1, -2), (7, 2, 0), (10, 1, -5),
            (11, 1, -2), (12, 2, -12), (14, 1, -9), (15, 1, -7)]
    stabs = [(2, 1, 0), (6, 1, 0), (10, 1, 0), (13, 1, 0)]

    tr = Track(116, 30)

    def lay_stabs(bar0, prog, gain=1.0):
        for i, name in enumerate(prog):
            root, iv = chord(name)
            for step, length, _ in stabs:
                for k, x in enumerate(iv[1:]):
                    tr.put("clav", tr.at(bar0 + i, step), inst_clav(tr, freq(root + 12 + x), length),
                           (-0.3, 0.0, 0.3)[k % 3], gain)

    groove = dict(kicks=(0, 3, 10), snares=(4, 12), ghosts=(7, 9, 14), hats=range(0, 16, 1),
                  open_hats=(6,), hat_gain=0.75)
    # 0-3 인트로(드럼+베이스) · 4-11 A · 12-19 B · 20-27 A · 28-29 끝
    lay_pattern(tr, "bass", 0, prog_a[:4], bass, inst_bass_funk)
    lay_drums(tr, 0, 4, **groove)
    fill(tr, 3)
    for start, prog, lead in ((4, prog_a, lead_a), (12, prog_b, lead_b), (20, prog_a, lead_a)):
        lay_pattern(tr, "bass", start, prog, bass, inst_bass_funk)
        lay_stabs(start, prog)
        lay_melody(tr, "lead", start, lead, inst_lead_funk, pan=0.05)
        if prog is prog_b:
            lay_pad(tr, "pad", start, prog, octave=1, gain=0.8)
        lay_drums(tr, start, 8, claps=(4, 12), **groove)
        fill(tr, start + 7)

    tr.put("drums", tr.at(28, 0), crash(tr))
    tr.put("drums", tr.at(28, 0), kick(tr))
    lay_stabs(28, ["Em7"])
    lay_melody(tr, "lead", 28, ["E5:2 G5:2 B5:12", "r:16"], inst_lead_funk)
    lay_pattern(tr, "bass", 28, ["Em7"], [(0, 16, -12)], inst_bass_funk)

    mix = (tr.bus("drums") * 0.95 + tr.bus("bass") * 1.0 + tr.bus("clav") * 0.85 + tr.bus("lead")
           + tr.bus("pad"))
    return master(reverb(mix, tr.rng, 1.0, 0.12))


SONGS = {
    "rush": ("battle_rush", song_rush),
    "showdown": ("battle_showdown", song_showdown),
    "groove": ("battle_groove", song_groove),
}


# ─────────────────────────── 저장 ───────────────────────────

def ffmpeg_path():
    found = os.environ.get("FFMPEG") or shutil.which("ffmpeg")
    if not found:
        raise SystemExit("ffmpeg 를 찾을 수 없다 — PATH 에 넣거나 FFMPEG 환경 변수로 경로를 준다")
    return found


def save(name, stereo):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(stereo, -1.0, 1.0) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        out = os.path.join(OUT, name + ".ogg")
        subprocess.run([ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y", "-i", wav_path,
                        "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    rms = 20 * np.log10(np.sqrt(np.mean(stereo ** 2)) + 1e-12)
    peak = 20 * np.log10(np.max(np.abs(stereo)) + 1e-12)
    print(f"{name}.ogg  {len(stereo) / SR:.1f}s  rms {rms:.1f}dB  peak {peak:.1f}dB")


def main(argv):
    names = argv or list(SONGS)
    for key in names:
        file_name, make = SONGS[key]
        save(file_name, make())


if __name__ == "__main__":
    main(sys.argv[1:])
