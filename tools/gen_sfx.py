"""젤리 워즈 효과음 생성기 (이슈 #373, 현실감 고도화 #376).

외부 음원 없이 numpy·scipy 로 **합성해서** `assets/sfx/*.wav` 를 만든다 — 라이선스를
따질 것이 없고, 소리를 고치고 싶으면 여기 숫자를 바꿔 다시 돌리면 된다.

    python3 tools/gen_sfx.py            # 전부
    python3 tools/gen_sfx.py jump land  # 이름을 주면 그것만

만든 뒤 Godot 이 `.wav.import` 를 만들어야 게임이 읽는다 (에디터를 열거나
`Godot --headless --path . --import`). 소리 이름과 쓰는 곳은 `scripts/sfx.gd` 에 있다.

무기 소리는 `<무기키>_hit`(근접 타격)·`<무기키>_fire`(발사)·`<무기키>_special`(특수 발동),
무기키는 `scripts/sfx.gd` 의 표가 정한다. **무기 소리만 만든다** (#379) — 젤리 몸·판 진행·
화면·무기끼리 부딪침 소리는 사용자가 들어 본 뒤 뺐다. 예외로 경기 시작·무기 선택·승리·패배
넷은 사용자 요청으로 새로 만들어 붙였다 (#400, 아래 "경기 진행").

**현실감은 "실제 소리가 어떻게 생기는지"를 흉내 내는 데서 나온다** (#376):
  - 쇠·나무는 재질 공명(모달 합성)으로 친다 — 막대·판·종의 실제 모드 비율, 높은 모드일수록
    빨리 죽음, 쇠는 짝지은 모드의 미세한 맥놀이. 때리는 것의 단단함은 첫 충격 길이로 준다.
  - 총성은 초음속 크랙 + 총구 폭풍 + 저음 + 반사음, 폭발은 닫혀 가는 저역 필터 + 서브 붐 +
    파편, 전기톱은 2행정 엔진의 점화 주기, 물은 기포 공명(Minnaert)이다.
  - 마지막에 소리 크기에 맞는 잔향(방·야외·큰 공간)을 건다 — 마른 소리는 귀 바로 앞에서 난다.
"""

import os
import sys
import wave
import zlib

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
RNG = np.random.default_rng(376)


# ─────────────────────────── 기본 재료 ───────────────────────────

def n(d):
    return max(1, int(SR * d))


def t_(d):
    return np.arange(n(d)) / SR


def noise(d):
    return RNG.standard_normal(n(d)) * 0.35


def pink(d):
    """분홍 잡음 — 바람·우르릉처럼 저역이 두꺼운 잡음."""
    white = RNG.standard_normal(n(d))
    spec = np.fft.rfft(white)
    f = np.fft.rfftfreq(len(white), 1 / SR)
    f[0] = 1
    spec /= np.sqrt(f)
    x = np.fft.irfft(spec, len(white))
    return x / (np.max(np.abs(x)) + 1e-9) * 0.5


def env(d, attack=0.002, decay=10.0):
    """빠르게 올라갔다가 지수로 줄어드는 모양."""
    t = t_(d)
    return np.minimum(t / max(attack, 1e-5), 1.0) * np.exp(-decay * t)


def bell_env(d, peak=0.5, sharp=2.0):
    """가운데(`peak` 비율)가 불룩한 모양 — 지나가는 바람·도플러."""
    t = t_(d) / d
    left = np.clip(t / peak, 0, 1)
    right = np.clip((1 - t) / (1 - peak), 0, 1)
    return np.where(t < peak, left, right) ** sharp


def ramp(d, a, b, curve="exp"):
    t = t_(d) / d
    if curve == "exp":
        return a * (b / a) ** t
    return a + (b - a) * t


def osc(freq, shape="sine", phase0=0.0):
    phase = 2 * np.pi * np.cumsum(freq) / SR + phase0
    if shape == "sine":
        return np.sin(phase)
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    if shape == "square":
        return np.tanh(3 * np.sin(phase))
    raise ValueError(shape)


def const(f, d):
    return np.full(n(d), float(f))


def drift(d, rate=6.0, depth=0.02):
    """느리게 흔들리는 값(1 ± depth) — 엔진 회전수·사람 손의 떨림."""
    k = max(4, int(d * rate) + 4)
    pts = RNG.standard_normal(k)
    x = np.interp(np.linspace(0, k - 1, n(d)), np.arange(k), pts)
    return 1 + depth * x / (np.max(np.abs(x)) + 1e-9)


def _sos(kind, fc, order=2):
    nyq = SR * 0.45
    if kind == "band":
        lo, hi = fc
        return signal.butter(order, [max(lo, 20), min(hi, nyq)], "band", fs=SR, output="sos")
    return signal.butter(order, min(max(fc, 20), nyq), kind, fs=SR, output="sos")


def lp(x, fc, order=2):
    return signal.sosfilt(_sos("low", fc, order), x)


def hp(x, fc, order=2):
    return signal.sosfilt(_sos("high", fc, order), x)


def bp(x, lo, hi, order=2):
    return signal.sosfilt(_sos("band", (lo, hi), order), x)


def reson(x, f, q=20.0):
    """좁은 공명 — 통·관·몸통이 한 주파수를 키우는 것."""
    b, a = signal.iirpeak(min(f, SR * 0.45), q, fs=SR)
    return signal.lfilter(b, a, x)


def tv(x, fc, kind="low", width=1.6, block=128):
    """시간에 따라 움직이는 필터. `fc` 는 x 와 같은 길이(또는 상수)."""
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    out = np.empty_like(x)
    zi = None
    for s in range(0, len(x), block):
        e = min(s + block, len(x))
        f = fc[(s + e) // 2]
        if kind == "band":
            sos = _sos("band", (f / width, f * width))
        else:
            sos = _sos(kind, f)
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[s:e], zi = signal.sosfilt(sos, x[s:e], zi=zi)
    return out


def at(x, offset):
    return np.concatenate([np.zeros(n(offset)), x])


def mix(*parts):
    length = max(len(p) for p in parts)
    out = np.zeros(length)
    for p in parts:
        out[: len(p)] += p
    return out


def fit(x, d):
    """길이를 d초로 자르거나 늘린다(곱하기 전에 맞출 때)."""
    m = n(d)
    return x[:m] if len(x) >= m else np.concatenate([x, np.zeros(m - len(x))])


def sat(x, drive=2.0):
    """부드러운 포화 — 큰 소리가 마이크·귀에서 눌리는 모양."""
    return np.tanh(drive * x) / np.tanh(drive)


# ─────────────────────────── 물리 흉내 ───────────────────────────

BAR = (1.0, 2.756, 5.404, 8.933, 13.34, 18.64)          # 양끝 자유 막대 (칼날·자루)
PLATE = (1.0, 1.59, 2.14, 2.30, 2.65, 2.92, 3.16, 3.50, 4.15, 4.80)  # 원판 (방패)
CHURCH = (0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0, 4.2)     # 종
WOOD = (1.0, 2.57, 4.03, 5.6)
GLOCK = (1.0, 2.76, 5.40)
MARIMBA = (1.0, 3.93, 9.17)


def modal(f0, ratios, d, base=3.0, slope=0.0012, amps=None, beat=0.0, hard=0.0004, jitter=0.004):
    """재질 공명. 모드마다 감쇠가 `base + slope·주파수` 라 높은 모드가 빨리 죽는다.

    `beat` 는 짝지은 모드의 어긋남 — 쇠가 "웅웅" 맥놀이하는 것. `hard` 는 때린 순간의
    길이(초) — 길수록 무른 것이 때린 것이라 높은 모드가 덜 울린다.
    """
    t = t_(d)
    out = np.zeros(len(t))
    for i, r in enumerate(ratios):
        f = f0 * r * (1 + RNG.uniform(-jitter, jitter))
        if f > SR * 0.45:
            continue
        a = amps[i] if amps is not None else 1.0 / (1 + 0.7 * i)
        rate = base + slope * f
        ph = RNG.uniform(0, 2 * np.pi)
        out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-rate * t)
        if beat:
            out += 0.7 * a * np.sin(2 * np.pi * f * (1 + beat) * t + ph * 1.7) * np.exp(-rate * 1.15 * t)
    pulse = np.hanning(max(3, n(hard)))
    return np.convolve(out, pulse / pulse.sum())[: len(t)]


def strike(d=0.03, lo=800, hi=9000, decay=120.0):
    """맞닿는 순간의 짧은 잡음 — 모든 타격의 '탁'."""
    return bp(noise(d), lo, hi) * env(d, 0.0002, decay)


def thump(f0=110, f1=45, d=0.22, decay=16.0):
    """몸통에 전해지는 저음 쿵 — 음높이가 빨리 떨어진다."""
    return osc(ramp(d, f0, f1)) * env(d, 0.001, decay)


def squelch(d=0.16, f0=1100, f1=300, wet=1.0):
    """젤리의 물컹함 — 공명이 아래로 미끄러지는 젖은 잡음 + 기포 몇 개."""
    body = tv(noise(d), ramp(d, f0, f1), "band", 1.35) * env(d, 0.003, 14) * 2.2
    pops = mix(*[at(bubble(RNG.uniform(500, 1400), 0.04, 0.6, 70), RNG.uniform(0, d * 0.6))
                 for _ in range(3)])
    return mix(body, 0.35 * wet * pops)


def flesh(d=0.09, bright=1.0):
    """몸에 맞는 소리 — 젖은 '퍽'. 높은 대역의 짧은 찰싹 + 몸통 저음."""
    slap = bp(noise(d), 500, 3500 * bright) * env(d, 0.0003, 70)
    return mix(slap, 0.8 * thump(150, 60, 0.14, 24), 0.4 * squelch(0.1, 900, 350, 0.3))


def whoosh(d, f0=500, f1=1800, f2=None, width=1.5, peak=0.55, flutter=0.0):
    """휘두르는 바람. 공명 주파수가 지나가며 오르내리는 것이 도플러다."""
    if f2 is None:
        fc = ramp(d, f0, f1)
    else:
        half = n(d) // 2
        fc = np.concatenate([np.linspace(f0, f1, half), np.linspace(f1, f2, n(d) - half)])
    x = tv(pink(d) + 0.4 * noise(d), fc, "band", width) * bell_env(d, peak, 1.6)
    if flutter:
        x *= 0.6 + 0.4 * np.abs(np.sin(np.pi * flutter * t_(d)))
    return x * 3.0


def grains(d, rate, lo=900, hi=6000, grain=0.0007, fade=4.0):
    """알갱이 소리 — 흙·자갈이 밟히는 바스락, 파편, 튀는 불꽃."""
    out = np.zeros(n(d))
    count = RNG.poisson(rate * d)
    for _ in range(count):
        tpos = RNG.exponential(d / fade) if fade else RNG.uniform(0, d)
        s = int(tpos * SR)
        if s >= len(out) - n(grain) * 3:
            continue
        g = noise(grain * RNG.uniform(0.6, 2.5))
        g *= np.hanning(len(g))
        out[s : s + len(g)] += g * RNG.uniform(0.2, 1.0)
    return bp(out, lo, hi) * 3


def crackle(d, rate=200.0, fade=0.0):
    """전기·불꽃의 타닥 — 아주 짧고 날카로운 알갱이."""
    return grains(d, rate, 1500, 12000, 0.00025, fade)


def bubble(f0, d=0.06, rise=0.5, decay=50.0):
    """기포 하나의 공명 (Minnaert) — 터지며 음이 올라간다. 물보라·물방울의 재료."""
    t = t_(d)
    f = f0 * (1 + rise * t / d)
    return osc(f) * np.exp(-decay * t) * np.minimum(t / 0.0006, 1)


def pluck(f, d, damp=0.996, bright=0.5):
    """Karplus-Strong 현 — 활 시위."""
    period = int(SR / f)
    buf = lp(RNG.uniform(-1, 1, period * 2), 2000 + 8000 * bright)[-period:]
    out = np.zeros(n(d))
    for i in range(len(out)):
        j = i % period
        out[i] = buf[j]
        buf[j] = damp * 0.5 * (buf[j] + buf[(j + 1) % period])
    return out


def scrape(d, f0=3000, f1=5000, rough=40.0):
    """쇠가 쇠 위를 미끄러지는 소리 — 좁은 공명 + 거친 떨림."""
    x = tv(noise(d), ramp(d, f0, f1), "band", 1.08) * 4
    t = t_(d)
    return x * (0.6 + 0.4 * np.sin(2 * np.pi * rough * t + 3 * np.sin(2 * np.pi * 7 * t)))


def click(d=0.006, f=3500, ring=0.02):
    """기계 딸깍 — 날카로운 첫소리 + 짧은 쇠 울림."""
    return mix(strike(d, 1500, 12000, 900), 0.25 * modal(f, (1.0, 2.3, 3.9), ring, 120, 0.004))


def fm_brass(f, d, bright=3.0, vib=5.5):
    """금관 — 소리가 커질수록 밝아지는 FM. 팡파르용."""
    t = t_(d)
    a = np.minimum(t / 0.04, 1) * np.exp(-1.2 * np.maximum(t - 0.05, 0))
    fv = f * (1 + 0.006 * np.sin(2 * np.pi * vib * t) * np.clip((t - 0.12) * 5, 0, 1))
    ph = 2 * np.pi * np.cumsum(fv) / SR
    return np.sin(ph + bright * a * np.sin(ph)) * a


# ─────────────────────────── 공간 ───────────────────────────

def _ir(d, damp0, damp1, early):
    t = t_(d)
    tail = noise(d) * np.exp(-6.9 * t / d)
    tail = tv(tail, ramp(d, damp0, damp1), "low")
    tail[: n(0.006)] *= np.linspace(0, 1, n(0.006))
    ir = np.zeros(len(t))
    ir[0] = 1.0
    for delay, g in early:
        ir[n(delay)] += g
    ir += tail / np.sqrt(np.sum(tail ** 2) + 1e-9) * 0.9
    return ir


SPACES = {}


def space(kind):
    if kind not in SPACES:
        SPACES[kind] = {
            "room": _ir(0.45, 7000, 1800, [(0.007, 0.35), (0.013, 0.25), (0.021, 0.2), (0.033, 0.12)]),
            "hall": _ir(1.4, 6000, 900, [(0.019, 0.3), (0.037, 0.22), (0.061, 0.15)]),
            "outdoor": _ir(1.6, 4500, 500, [(0.09, 0.28), (0.21, 0.14), (0.43, 0.06)]),
        }[kind]
    return SPACES[kind]


def verb(x, kind="room", wet=0.15):
    """잔향을 섞는다. 건조음은 그대로 두고 젖은 소리만 더한다."""
    ir = space(kind)
    y = signal.fftconvolve(x, ir[1:])
    y /= np.max(np.abs(y)) + 1e-9
    y *= np.max(np.abs(x))
    return mix(x, wet * y)


def finish(x, peak=0.8, tail=0.02):
    """끝을 접고 꼬리의 무음을 잘라 크기를 맞춘다."""
    x = np.asarray(x, dtype=np.float64)
    x = hp(x, 25)
    top = np.max(np.abs(x)) + 1e-12
    loud = np.where(np.abs(x) > top * 0.0015)[0]
    if len(loud):
        x = x[: min(len(x), loud[-1] + n(0.01))]
    fade = min(n(tail), len(x))
    x[-fade:] *= np.linspace(1, 0, fade) ** 2
    x[: n(0.0005)] *= np.linspace(0, 1, n(0.0005))
    x = x / (np.max(np.abs(x)) + 1e-12) * peak
    return x


def write(name, x, peak=0.8):
    x = finish(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


# ─────────────────────────── 큰 소리 묶음 ───────────────────────────

def gunshot(boom=70.0, blast_lp=6000.0, blast_decay=45.0, barrel=700.0, size=1.0, tail=0.32):
    """총성: 초음속 크랙(N파) → 총구 폭풍(넓은 잡음 + 총열 공명) → 저음 → 반사음·야외 잔향."""
    nw = np.linspace(1, -1, n(0.0007))
    crack = hp(mix(nw, np.zeros(n(0.01))), 2500) * 0.9
    d = 0.3
    burst = noise(d) * env(d, 0.0002, blast_decay)
    blast = mix(lp(burst, blast_lp) * 2.2, reson(burst, barrel, 6) * 1.6)
    low = thump(boom * 2.2, boom, 0.25, 14) * size
    x = sat(mix(crack, at(blast, 0.0008), low), 2.5)
    echo = lp(x, 2500)
    x = mix(x, at(0.22 * echo, 0.085), at(0.1 * echo, 0.19))
    return verb(x, "outdoor", tail)


def explosion(size=1.0, d=1.6):
    """폭발: 첫 충격 → 닫혀 가는 저역 필터의 폭풍 → 서브 붐 → 떨어지는 파편 → 우르릉."""
    first = strike(0.02, 300, 12000, 160) * 1.5
    body = tv(pink(d) + noise(d) * 0.5, ramp(d, 7000 * size, 250), "low") * env(d, 0.004, 3.2 / size) * 2.6
    sub = osc(ramp(d * 0.6, 70, 28)) * env(d * 0.6, 0.003, 4.5 / size) * 1.4 * size
    debris = at(grains(d * 0.8, 70, 700, 5000, 0.002, 2.5) * 0.5, 0.08)
    rumble = lp(pink(d), 160) * env(d, 0.08, 2.2) * 1.8
    x = sat(mix(first, body, sub, debris, rumble), 2.2)
    return verb(x, "outdoor", 0.4)


def engine(f, d, load=0.0):
    """2행정 엔진(전기톱). `f` 는 점화 주파수 배열. 배기 공명과 체인 소리를 얹는다."""
    f = fit(f, d) * drift(d, 9, 0.03)
    phase = np.cumsum(f) / SR
    frac = phase % 1.0
    pulses = np.exp(-frac * 9) * (1 + 0.35 * RNG.standard_normal(len(frac)))
    exhaust = mix(reson(pulses, 280, 4) * 1.4, reson(pulses, 820, 5), reson(pulses, 2100, 6) * 0.5)
    chain = hp(noise(d), 3500) * (0.5 + 0.5 * np.exp(-((phase * 2) % 1.0) * 4)) * (0.6 + load)
    return sat(mix(lp(exhaust, 5000) * 1.2, chain * 0.7), 1.8)


def saber_hum(d, f=92.0, freq=None):
    """광선검 웅 — 브라운관 험(두 톱니가 어긋나 맥놀이) + 영사기 모터 지직.
    `freq` 를 주면 그 주파수 배열을 따라간다(휘두를 때의 도플러·켜질 때의 솟음)."""
    fv = const(f, d) if freq is None else fit(freq, d)
    hum = osc(fv, "saw") + osc(fv * 1.013, "saw") * 0.8
    hum = mix(lp(hum, 1200) * 0.9, reson(hum, 230, 3) * 0.6)
    buzz = bp(noise(d), 2000, 6000) * (0.5 + 0.5 * np.sin(2 * np.pi * fv.mean() * 2 * t_(d))) * 0.18
    return mix(hum, buzz)


def thunder(d=1.8):
    """천둥: 날카로운 갈라짐 → 바로 뒤의 큰 터짐 → 굴러가는 우르릉(여러 번 솟는다)."""
    rip = crackle(0.05, 6000) * 1.4
    blast = lp(noise(0.35), 3500) * env(0.35, 0.001, 9) * 2
    roll_env = np.zeros(n(d))
    for c in RNG.uniform(0.1, d * 0.75, 5):
        roll_env += np.exp(-((t_(d) - c) / RNG.uniform(0.08, 0.2)) ** 2) * RNG.uniform(0.4, 1.0)
    roll = lp(pink(d), 300) * roll_env * np.exp(-1.2 * t_(d)) * 3
    x = sat(mix(rip, at(blast, 0.01), at(roll, 0.03), at(osc(ramp(0.5, 60, 30)) * env(0.5, 0.005, 6), 0.02)), 2)
    return verb(x, "outdoor", 0.35)


def water(d=0.9, size=1.0):
    """물보라: 수면을 치는 찰싹 → 물 덩이가 튀는 쏴 → 크고 작은 기포들."""
    slap = mix(strike(0.04, 400, 8000, 90) * 1.5, thump(140, 60, 0.15, 20) * 0.6 * size)
    spray = hp(noise(d), 1800) * env(d, 0.01, 5.5 / size) * 1.4
    pops = [at(bubble(RNG.uniform(250, 2500) / np.sqrt(size), RNG.uniform(0.02, 0.08),
                      RNG.uniform(0.3, 1.2), RNG.uniform(30, 90)) * RNG.uniform(0.2, 0.8),
               RNG.exponential(d * 0.3)) for _ in range(int(28 * size))]
    return verb(mix(slap, spray, *pops), "room", 0.12)


# ─────────────────────────── 소리 ───────────────────────────
# 크기(peak)는 자주 나는 것일수록 작게 잡는다 — 발걸음·틱이 타격음보다 크면 시끄럽다.

SOUNDS = {}


def sound(name, peak=0.8):
    def deco(fn):
        SOUNDS[name] = (fn, peak)
        return fn
    return deco


@sound("charged", 0.48)
def _():
    # 힘이 차오르는 전기 웅 — 험의 음이 오르고 지직이 촘촘해진다.
    d = 0.45
    f = ramp(d, 80, 180)
    hum = lp(osc(f, "saw") + osc(f * 1.5, "saw") * 0.4, 2500) * (t_(d) / d) ** 0.7
    return verb(mix(hum, crackle(d, 400) * (t_(d) / d), at(modal(1800, BAR, 0.4, 6, 0.0005) * 0.4, d - 0.05)), "room", 0.12)


@sound("dagger_pickup", 0.42)
def _():
    scr = scrape(0.08, 2500, 4000) * env(0.08, 0.005, 25) * 0.6
    clink = at(modal(3100, BAR, 0.35, 8, 0.0008, hard=0.0002), 0.06)
    grip = at(strike(0.02, 600, 3000, 150) * 0.6, 0.09)
    return verb(mix(scr, clink, grip), "room", 0.12)


# ── 무기: 근접 타격 ──

@sound("sword_hit", 0.82)
def _():
    swing = whoosh(0.13, 700, 3200, 1500, width=1.3, peak=0.6)
    cut = at(mix(strike(0.02, 2500, 12000, 200) * 1.2, flesh(0.1)), 0.1)
    ring = at(modal(1250, BAR, 0.9, 4, 0.0007, beat=0.0025, hard=0.0002) * 0.35, 0.1)
    return verb(mix(swing * 0.7, cut, ring), "room", 0.14)


@sound("saber_hit", 0.72)
def _():
    d = 0.3
    w = 1 + 0.1 * bell_env(d, 0.4, 1.5)
    swing = saber_hum(d, freq=92 * w) * bell_env(d, 0.4, 1.2) * 1.3
    burn = at(mix(crackle(0.14, 1500), bp(noise(0.14), 1500, 7000) * env(0.14, 0.001, 18)) * 0.9, 0.08)
    return verb(mix(swing, burn), "room", 0.14)


@sound("chainsaw_hit", 0.6)
def _():
    d = 0.24
    run = engine(ramp(d, 120, 95), d, load=0.6)
    bite = bp(noise(d), 900, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 63 * t_(d))) * 1.2
    return verb(mix(run, bite * env(d, 0.003, 8), 0.4 * squelch(d, 900, 400)) * env(d, 0.003, 3), "room", 0.1)


@sound("hammer_hit", 0.88)
def _():
    impact = mix(thump(100, 38, 0.4, 9) * 1.6, lp(strike(0.05, 100, 2500, 70), 1800) * 1.4)
    handle = modal(210, WOOD, 0.25, 18, 0.01) * 0.25
    return verb(sat(mix(impact, handle, flesh(0.12, 0.8), 0.6 * squelch(0.25, 700, 180)), 1.6), "room", 0.16)


@sound("trident_hit", 0.8)
def _():
    stab = mix(strike(0.015, 2500, 12000, 260) * 1.2, flesh(0.1, 1.2))
    prongs = mix(*[modal(f, BAR, 0.7, 5, 0.0008, hard=0.0003) for f in (1380, 1445, 1515)]) * 0.18
    return verb(mix(stab, at(prongs, 0.004)), "room", 0.14)


@sound("glove_hit", 0.72)
def _():
    # 권투 글러브 — 가죽 찰싹 + 묵직한 몸통, 쇠 울림이 없다.
    leather = bp(noise(0.05), 350, 2200) * env(0.05, 0.0005, 60) * 1.5
    return verb(mix(leather, thump(115, 55, 0.18, 18) * 1.3, 0.4 * squelch(0.12, 800, 350)), "room", 0.12)


@sound("shuriken_hit", 0.62)
def _():
    tick = strike(0.008, 4000, 14000, 700) * 1.3
    ring = modal(4100, BAR, 0.35, 10, 0.0008, hard=0.00015) * 0.3
    return verb(mix(tick, ring, at(flesh(0.07, 1.4) * 0.6, 0.003)), "room", 0.12)


@sound("knuckle_hit", 0.8)
def _():
    crack = strike(0.02, 1200, 9000, 180) * 1.4
    clink = modal(2700, (1.0, 2.4, 4.1), 0.18, 15, 0.002) * 0.15
    return verb(mix(crack, thump(140, 55, 0.18, 20) * 1.2, clink, 0.3 * squelch(0.1, 900, 400)), "room", 0.12)


@sound("axe_hit", 0.88)
def _():
    swing = whoosh(0.16, 350, 1600, 800, width=1.4, peak=0.65)
    chop = at(mix(strike(0.03, 800, 6000, 120) * 1.5, thump(130, 50, 0.25, 12) * 1.4, flesh(0.12, 0.9)), 0.13)
    ring = at(modal(820, BAR, 0.6, 5, 0.0009, beat=0.003, hard=0.0004) * 0.2, 0.13)
    return verb(mix(swing * 0.8, chop, ring), "room", 0.15)


@sound("pole_hit", 0.78)
def _():
    swing = whoosh(0.12, 300, 1100, width=1.6, peak=0.6) * 0.6
    knock = at(mix(modal(430, WOOD, 0.3, 14, 0.012, hard=0.0006) * 1.5, strike(0.015, 800, 5000, 250),
                   thump(130, 70, 0.1, 30)), 0.09)
    return verb(mix(swing, knock), "room", 0.14)


@sound("shield_hit", 0.82)
def _():
    plate = modal(330, PLATE, 0.45, 9, 0.002, beat=0.004, hard=0.0012) * 0.8
    return verb(mix(strike(0.03, 400, 5000, 120) * 1.2, plate, thump(110, 50, 0.2, 16) * 1.2, 0.3 * squelch(0.1, 800, 400)), "room", 0.15)


# ── 무기: 발사 ──

@sound("dagger_fire", 0.5)
def _():
    return verb(whoosh(0.18, 900, 3500, 1800, width=1.3, peak=0.4, flutter=22), "room", 0.1)


@sound("cannon_fire", 0.85)
def _():
    return gunshot(boom=55, blast_lp=3500, blast_decay=22, barrel=320, size=1.6, tail=0.45)


@sound("bow_fire", 0.62)
def _():
    # 시위가 놓이는 '퉁' + 줄 떨림 + 활대 울림 + 화살이 찢는 바람.
    string = pluck(118, 0.35, 0.991, 0.4) * env(0.35, 0.0005, 7)
    limb = thump(95, 60, 0.12, 30) * 0.9
    arrow = at(whoosh(0.12, 1800, 4500, width=1.3, peak=0.15) * 0.6, 0.008)
    return verb(mix(string * 0.9, limb, arrow), "outdoor", 0.15)


@sound("rifle_fire", 0.6)
def _():
    return gunshot(boom=90, blast_lp=8000, blast_decay=60, barrel=900, size=0.7, tail=0.25)


@sound("glove_fire", 0.58)
def _():
    # 로켓 주먹 하나 — 점화 '퍽' + 짧은 분사 쉬익.
    d = 0.32
    pop = mix(strike(0.02, 200, 3000, 150) * 1.2, thump(120, 60, 0.1, 30))
    jet = mix(lp(pink(d), 2500) * 2, hp(noise(d), 3000) * 0.6) * env(d, 0.01, 7) * (1 + 0.3 * np.sin(2 * np.pi * 37 * t_(d)))
    return verb(mix(pop, jet), "outdoor", 0.15)


# ── 무기: 특수 발동 ──

@sound("sword_special", 0.68)
def _():
    # 들어 올리는 0.26초 — 칼을 뽑아 날을 세우는 쇳소리, 0.24초부터 크게 내려벤다.
    draw = scrape(0.24, 2800, 5200) * bell_env(0.24, 0.7, 1.2) * 0.45
    ring = at(modal(1350, BAR, 0.6, 3.5, 0.0005, beat=0.002) * 0.25, 0.2)
    swing = at(whoosh(0.16, 500, 2600, 900, width=1.3, peak=0.5), 0.23)
    return verb(mix(draw, ring, swing), "hall", 0.15)


@sound("sword_burst", 0.88)
def _():
    # 빛기둥 — 공기가 빨려 들어가는 소리(거꾸로 된 잔향) 뒤의 큰 충격과 길게 우는 쇠 공명.
    swell = verb(noise(0.3) * env(0.3, 0.001, 12), "hall", 1.0)[::-1][-n(0.3):] * 0.8
    hit = at(mix(thump(90, 32, 0.6, 6) * 1.5, strike(0.04, 200, 9000, 70) * 1.2), 0.28)
    shimmer = at(mix(modal(660, CHURCH, 1.6, 1.5, 0.0004, beat=0.002) * 0.5,
                     modal(1320, BAR, 1.2, 2.5, 0.0004, beat=0.002) * 0.25), 0.28)
    return verb(sat(mix(swell, hit, shimmer), 1.5), "hall", 0.3)


@sound("dagger_special", 0.52)
def _():
    back = whoosh(0.25, 1200, 3800, width=1.3, peak=0.85, flutter=18)
    catch = at(mix(modal(3000, BAR, 0.3, 9, 0.001, hard=0.0002) * 0.5, strike(0.02, 500, 3000, 160) * 0.8), 0.24)
    return verb(mix(back, catch), "room", 0.12)


@sound("saber_special", 0.65)
def _():
    # 켜지는 '치-잉' — 음이 바닥에서 솟아오르고 지직거리며 웅이 자리 잡는다.
    d = 0.7
    f = np.concatenate([ramp(0.22, 25, 92), const(92, d - 0.22)])
    hum = saber_hum(d, freq=f) * np.minimum(t_(d) / 0.05, 1) * 1.2
    snap = mix(crackle(0.25, 2500, 3) * 0.8, bp(noise(0.25), 2500, 9000) * env(0.25, 0.001, 12))
    return verb(mix(hum * env(d, 0.01, 1.5), snap), "room", 0.12)


@sound("chainsaw_special", 0.68)
def _():
    # 제자리 0.45초: 줄을 당겨 시동 → 회전이 치솟음, 돌진: 최고 회전으로 운다.
    pull = mix(strike(0.03, 300, 3000, 100), thump(80, 50, 0.1, 25)) * 0.8
    d = 1.0
    f = np.concatenate([ramp(0.12, 25, 40), ramp(0.33, 40, 150), ramp(d - 0.45, 150, 165, "lin")])
    run = engine(f, d, load=0.2) * fit(np.concatenate([np.linspace(0.4, 1, n(0.45)), np.ones(n(d))]), d)
    return verb(mix(pull, at(run * env(d + 0.05, 0.02, 0.6)[: n(d)], 0.03)), "outdoor", 0.12)


@sound("hammer_special", 0.62)
def _():
    # 망치에 전기가 감긴다 — 변압기 험이 커지고 아크가 튄다.
    d = 0.6
    hum = osc(const(120, d), "square") + 0.5 * osc(const(240, d), "square")
    hum = lp(hum, 3500) * (t_(d) / d) ** 0.8 * 0.5
    arcs = crackle(d, 700) * (0.3 + t_(d) / d)
    whine = osc(ramp(d, 400, 1600)) * (t_(d) / d) ** 2 * 0.15
    return verb(mix(hum, arcs, whine, at(crackle(0.06, 6000) * 1.2, d - 0.06)), "room", 0.12)


@sound("lightning", 0.9)
def _():
    return thunder(1.8)


@sound("cannon_special", 0.85)
def _():
    # 미사일 — 발사 쿵 + 로켓 모터가 그르렁거리며 멀어진다.
    launch = gunshot(boom=60, blast_lp=3000, blast_decay=25, barrel=400, size=1.2, tail=0.2) * 0.8
    d = 1.1
    burble = 1 + 0.5 * np.sin(2 * np.pi * 31 * t_(d) + 4 * np.sin(2 * np.pi * 7 * t_(d)))
    motor = tv(pink(d) * burble + noise(d) * 0.4, ramp(d, 4000, 600), "low") * env(d, 0.03, 2.2) * 2.5
    return verb(mix(launch, at(motor, 0.04)), "outdoor", 0.25)


@sound("cannon_hit", 0.82)
def _():
    return explosion(0.55, 0.9)


@sound("bomb_special", 0.52)
def _():
    throw = whoosh(0.16, 600, 2000, width=1.5, peak=0.5) * 0.8
    d = 0.8
    fuse = mix(crackle(d, 1100) * 0.7, hp(noise(d), 4000) * 0.5 * drift(d, 30, 0.4)) * env(d, 0.02, 2)
    return verb(mix(throw, at(fuse, 0.08)), "room", 0.1)


@sound("explosion", 0.95)
def _():
    return explosion(1.0, 1.8)


@sound("bow_special", 0.66)
def _():
    # 세 발을 메긴 강한 시위 — 더 깊은 '퉁', 화살 셋이 조금씩 어긋나 찢고 간다.
    string = pluck(100, 0.45, 0.992, 0.5) * env(0.45, 0.0005, 6) * 1.1
    limb = thump(85, 50, 0.15, 22) * 1.1
    arrows = [at(whoosh(0.16, 1600, 4800, width=1.25, peak=0.15) * 0.5, o) for o in (0.005, 0.025, 0.045)]
    return verb(mix(string, limb, *arrows), "outdoor", 0.18)


@sound("trident_special", 0.78)
def _():
    # 무거운 창을 던지는 깊은 바람 + 갈래가 바람을 가르며 내는 휘파람 + 전기 기운.
    d = 0.45
    heave = whoosh(d, 220, 900, 500, width=1.6, peak=0.35) * 1.2
    whistle = osc(ramp(d, 1900, 1500)) * bell_env(d, 0.4, 2) * 0.08
    return verb(mix(heave, whistle, crackle(d, 250, 2) * 0.3), "outdoor", 0.15)


@sound("glove_special", 0.62)
def _():
    # 로켓 점화 — 그르렁거리는 분사가 커지며 밝아진다.
    d = 0.5
    burble = 1 + 0.4 * np.sin(2 * np.pi * 27 * t_(d))
    jet = tv(pink(d) * burble + noise(d) * 0.5, ramp(d, 500, 4500), "low") * (t_(d) / d) ** 0.8 * 2.6
    return verb(mix(strike(0.03, 200, 2500, 90), jet), "outdoor", 0.15)


@sound("shuriken_special", 0.52)
def _():
    d = 0.45
    spin = whoosh(d, 2200, 4200, 2600, width=1.25, peak=0.3, flutter=26)
    return verb(spin * env(d, 0.005, 2.5), "outdoor", 0.12)


@sound("knuckle_special", 0.62)
def _():
    # 0.5초 끌어모은다 — 가죽이 조여 삐걱이고 낮은 압력이 차오른다. 뒤이어 강펀치가 터진다.
    d = 0.5
    creak = grains(d, 120, 300, 2000, 0.003, 0) * 0.6
    pressure = tv(pink(d), ramp(d, 120, 600), "low") * (t_(d) / d) ** 1.5 * 2.5
    return verb(mix(creak, pressure, whoosh(d, 200, 800, width=1.8, peak=0.95) * 0.5), "room", 0.1)


@sound("knuckle_punch", 0.88)
def _():
    air = whoosh(0.12, 400, 1500, width=1.5, peak=0.7) * 0.6
    hit = at(mix(strike(0.03, 600, 8000, 130) * 1.6, thump(110, 38, 0.35, 10) * 1.6, flesh(0.12, 1.1)), 0.1)
    return verb(sat(mix(air, hit), 1.8), "room", 0.18)


@sound("knuckle_punch_big", 0.95)
def _():
    air = whoosh(0.15, 300, 1300, width=1.6, peak=0.7) * 0.7
    hit = at(sat(mix(strike(0.05, 300, 9000, 80) * 1.8, thump(90, 28, 0.7, 5) * 2.0, flesh(0.15, 1.2),
                     lp(pink(0.6), 400) * env(0.6, 0.002, 6) * 2), 2.4), 0.12)
    return verb(mix(air, hit), "hall", 0.25)


@sound("axe_special", 0.62)
def _():
    # 땅을 박차고 솟는다 — 흙 튀는 소리 + 몸과 도끼가 크게 도는 바람.
    kick = mix(grains(0.1, 600, 800, 5000, 0.001, 5), thump(100, 50, 0.12, 25))
    rise = whoosh(0.4, 250, 1200, 700, width=1.6, peak=0.45) * 1.1
    return verb(mix(kick, at(rise, 0.02)), "outdoor", 0.15)


@sound("axe_slam", 0.95)
def _():
    hit = sat(mix(strike(0.05, 200, 6000, 70) * 1.8, thump(70, 25, 0.8, 4.5) * 2.2), 2.2)
    earth = lp(pink(1.0), 350) * env(1.0, 0.004, 4) * 2.2
    debris = at(grains(0.8, 90, 500, 4500, 0.003, 3) * 0.7, 0.05)
    ring = modal(700, BAR, 0.6, 5, 0.001, beat=0.003) * 0.15
    return verb(mix(hit, earth, debris, ring), "outdoor", 0.35)


@sound("shotgun_special", 0.92)
def _():
    shot = gunshot(boom=60, blast_lp=5000, blast_decay=30, barrel=550, size=1.4, tail=0.35)
    # 펌프 — 손잡이를 당기는 마찰과 '철', 밀어 넣는 '컥'.
    slide = lambda d: bp(noise(d), 1500, 6000) * bell_env(d, 0.5, 1) * 0.35
    pump = mix(slide(0.07), at(click(0.008, 2600, 0.04) * 1.4, 0.07),
               at(slide(0.06), 0.13), at(click(0.008, 2200, 0.05) * 1.6, 0.19))
    return mix(shot, at(verb(pump, "room", 0.1), 0.38))


@sound("pole_special", 0.58)
def _():
    # 봉이 쑥 늘어난다 — 마디가 미끄러져 나오는 마찰과 끝에서 잠기는 '탁'.
    d = 0.32
    slide = tv(noise(d), ramp(d, 500, 1400), "band", 1.3) * bell_env(d, 0.6, 1) * 2
    lock = at(mix(modal(520, WOOD, 0.2, 18, 0.01, hard=0.0005) * 1.4, click(0.006, 1800, 0.02)), d - 0.02)
    return verb(mix(whoosh(0.3, 300, 900, width=1.7) * 0.4, slide, lock), "room", 0.12)


@sound("rifle_special", 0.52)
def _():
    # 장전 손잡이 — 당기는 '철' + 마찰 + 놓아서 닫히는 '척'.
    back = click(0.008, 2400, 0.05) * 1.4
    slide = at(bp(noise(0.05), 1800, 6000) * bell_env(0.05, 0.4, 1) * 0.35, 0.01)
    home = at(mix(click(0.01, 1900, 0.07) * 1.8, thump(180, 120, 0.04, 60) * 0.4), 0.09)
    return verb(mix(back, slide, home), "room", 0.1)


@sound("shield_special", 0.58)
def _():
    # 던진 방패 — 원판이 돌며 바람을 '웅웅' 썰고, 판이 낮게 운다.
    d = 0.5
    spin = whoosh(d, 600, 1500, 900, width=1.4, peak=0.3, flutter=14)
    hum = modal(330, PLATE, d, 3, 0.002, beat=0.006) * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t_(d))) * 0.12
    return verb(mix(spin, hum), "outdoor", 0.12)


@sound("shield_grow", 0.72)
def _():
    # 방패가 커진다 — 쇠판이 늘어나며 낮게 신음하고 '쿵' 하고 자리 잡는다.
    d = 0.45
    groan = tv(noise(d), ramp(d, 180, 420), "band", 1.08) * bell_env(d, 0.7, 1.2) * 4
    settle = at(mix(modal(260, PLATE, 0.8, 4, 0.0015, beat=0.004, hard=0.001), thump(90, 45, 0.25, 12)), d - 0.05)
    return verb(mix(groan, settle), "hall", 0.18)


@sound("swap", 0.62)
def _():
    # 순간이동 — 공기가 빨려 들어가는 소리(거꾸로 된 잔향)와 반대편에서 '펑' 메우는 소리.
    puff = mix(lp(noise(0.08), 3000) * env(0.08, 0.001, 30), thump(130, 60, 0.1, 25) * 0.6)
    suck = verb(puff, "hall", 1.0)[::-1][-n(0.25):] * 0.8
    pop = at(mix(puff * 1.2, whoosh(0.2, 2000, 600, width=1.6, peak=0.15) * 0.6), 0.25)
    return verb(mix(suck, pop), "room", 0.15)


@sound("dagger_hit", 0.72)
def _():
    stab = mix(strike(0.012, 3000, 13000, 400) * 1.3, flesh(0.1, 1.3))
    tick = modal(3400, BAR, 0.25, 12, 0.001, hard=0.0002) * 0.2
    return verb(mix(stab, tick), "room", 0.12)


@sound("projectile_hit", 0.55)
def _():
    return verb(mix(strike(0.015, 1200, 9000, 300), flesh(0.1, 1.1) * 1.1), "room", 0.1)


@sound("projectile_land", 0.38)
def _():
    thunk = mix(strike(0.02, 300, 3000, 180) * 1.2, thump(170, 80, 0.08, 40), grains(0.1, 500, 700, 4000, 0.001, 5) * 0.5)
    return verb(thunk, "room", 0.1)


# ── 경기 진행 (#400) ──
# #379 에서 판 진행·화면 소리를 다 뺐는데, 경기의 큰 마디 넷만 사용자 요청으로 다시 붙였다.
# 예전 소리(`intro`·`card_pick`·`victory`)를 되살린 것이 아니라 새로 만든 것이다.

@sound("match_start", 0.74)
def _():
    # 경기 표지 — 바람이 차오르다 북·쇠 타격과 짧은 금관 화음이 '빰!' 하고 터진다.
    d = 0.42
    riser = tv(pink(d) + noise(d) * 0.4, ramp(d, 400, 7000), "band", 1.7) * (t_(d) / d) ** 2.2 * 3
    stab = sum(fm_brass(f, 0.9, 3.2) for f in (392, 494, 587, 784)) / 3.2
    hit = mix(thump(80, 32, 0.8, 4.5) * 1.8, strike(0.04, 200, 10000, 70) * 1.3,
              modal(196, CHURCH, 1.4, 2.0, 0.0008, beat=0.003) * 0.35, stab * 0.9,
              hp(noise(1.2), 5000) * env(1.2, 0.002, 3.5) * 0.25)
    return verb(mix(riser, at(sat(hit, 1.6), d - 0.02)), "hall", 0.32)


@sound("weapon_pick", 0.6)
def _():
    # 무기를 집는다 — 손에 쥐는 '착'과 칼날이 뽑히는 짧은 '슁', 위로 오르는 맑은 두 음.
    grab = mix(click(0.005, 2600, 0.03) * 1.2, thump(240, 150, 0.05, 60) * 0.5)
    shing = at(mix(scrape(0.16, 4200, 6500, 30) * env(0.16, 0.004, 22) * 0.5,
                   modal(1760, BAR, 0.5, 7, 0.0008, beat=0.002, hard=0.0002) * 0.3), 0.02)
    chime = mix(at(modal(1319, GLOCK, 0.6, 5, 0.0003), 0.05), at(modal(1976, GLOCK, 0.7, 4.5, 0.0003), 0.13)) * 0.42
    return verb(mix(grab, shing, chime), "room", 0.14)


@sound("victory", 0.74)
def _():
    # 승리 — 솔·도·미·솔로 뛰어오르는 금관 뒤에 길게 뻗는 도 장조 화음, 팀파니와 심벌.
    lead = mix(*[at(fm_brass(f, dur, 3.0) * 0.6, o) for f, dur, o in
                 [(392, 0.13, 0.0), (523, 0.13, 0.12), (659, 0.13, 0.24), (784, 0.3, 0.36)]])
    chord = at(sum(fm_brass(f, 1.6, 2.6, 5.0) for f in (262, 523, 659, 784, 1047)) / 3.4, 0.62)
    timp = mix(*[at(mix(modal(98, (1.0, 1.5, 1.98, 2.44), 0.8, 3.5, 0.001, hard=0.003) * 0.7,
                        thump(98, 70, 0.35, 7)), o) for o in (0.36, 0.62)])
    cymbal = at(hp(noise(1.8), 6000) * env(1.8, 0.003, 2.2) * 0.35, 0.62)
    return verb(lp(mix(lead, chord, timp, cymbal), 7000), "hall", 0.3)


@sound("defeat", 0.66)
def _():
    # 패배 — 반음씩 내려가는 어두운 트롬본 '빠-빠-빠-빠아~', 마지막 음이 떨리며 처진다.
    notes = mix(*[at(fm_brass(f, dur, 1.6, 0.1), o) for f, dur, o in
                  [(311, 0.3, 0.0), (294, 0.3, 0.34), (277, 0.3, 0.68)]])
    d = 1.3
    t = t_(d)
    fall = 262 * (1 - 0.06 * np.clip((t - 0.5) / 0.8, 0, 1)) * (1 + 0.025 * np.sin(2 * np.pi * 6 * t) * np.clip(t * 2, 0, 1))
    a = np.minimum(t / 0.05, 1) * np.exp(-1.6 * np.maximum(t - 0.4, 0))
    ph = 2 * np.pi * np.cumsum(fall) / SR
    last = at(np.sin(ph + 1.4 * a * np.sin(ph)) * a, 1.02)
    tuba = at(mix(thump(70, 55, 0.5, 5) * 0.6, lp(osc(const(65, 0.9), "saw"), 300) * env(0.9, 0.04, 3) * 0.3), 1.02)
    return verb(lp(mix(notes, last, tuba), 2600), "hall", 0.25)


# ── 카운트다운 (#403) ──
# 레이싱 게임 출발 신호 — 같은 높이의 '뚜' 셋 뒤에 한 옥타브 높은 '땅!'. #379 에서 뺀
# 예전 `count_beep`(삑)·`count_go`(에어혼)과 이름만 같고 새로 만든 소리다.

def start_tone(f, d, hold, bright=0.35):
    """출발 신호기 음 — 사인에 약간의 사각파를 섞은 전자음. 바로 서고, `hold` 동안 버틴 뒤 빠르게 꺼진다."""
    t = t_(d)
    tone = osc(const(f, d)) + osc(const(f, d), "square") * bright + osc(const(2 * f, d)) * 0.15
    shape = np.minimum(t / 0.004, 1) * np.where(t < hold, 1.0, np.exp(-(t - hold) * 18))
    return lp(tone * shape, 6000)


@sound("count_beep", 0.5)
def _():
    # 뚜 — 짧고 평평한 전자음. 셋이 같은 높이여야 '아직'으로 들린다. 0.42초마다 오므로
    # 잔향은 짧은 방으로 — 큰 공간이면 꼬리가 다음 '뚜'에 겹쳐 뭉개진다.
    return verb(start_tone(587, 0.24, 0.15), "room", 0.12)


@sound("count_go", 0.62)
def _():
    # 땅! — 한 옥타브 위, 더 밝고 길게 끌다 천천히 꺼진다.
    d = 0.75
    tone = start_tone(1175, d, 0.38, 0.5) * (1 - 0.25 * np.clip((t_(d) - 0.1) / 0.6, 0, 1))
    return verb(tone, "hall", 0.18)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    global RNG
    for name, (fn, peak) in SOUNDS.items():
        if only and name not in only:
            continue
        # 소리마다 이름으로 난수를 새로 잡는다 — 한 소리를 고치거나 빼도 다른 소리의
        # 잡음 결이 바뀌지 않는다 (#379). 그래서 이름만 주고 그 소리 하나를 다시 만들 수 있다.
        RNG = np.random.default_rng(zlib.crc32(name.encode()))
        SPACES.clear()
        write(name, fn(), peak)
    print("wrote %d sounds to %s" % (len(only) or len(SOUNDS), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
