"""젤리 워즈 효과음 생성기 (이슈 #373).

외부 음원 없이 numpy·scipy 로 **합성해서** `assets/sfx/*.wav` 를 만든다 — 라이선스를
따질 것이 없고, 소리를 고치고 싶으면 여기 숫자를 바꿔 다시 돌리면 된다.

    python3 tools/gen_sfx.py

만든 뒤 Godot 이 `.wav.import` 를 만들어야 게임이 읽는다 (에디터를 열거나
`Godot --headless --path . --import`). 소리 이름과 쓰는 곳은 `scripts/sfx.gd` 에 있다.

무기 소리는 `<무기키>_hit`(근접 타격)·`<무기키>_fire`(발사)·`<무기키>_special`(특수 발동),
부딪침은 `clash_<재질>` 이다. 무기키와 재질은 `scripts/sfx.gd` 의 표가 정한다.
"""

import os
import sys
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
RNG = np.random.default_rng(373)


# ─────────────────────────── 재료 ───────────────────────────

def n(d):
    return int(SR * d)


def t_(d):
    return np.arange(n(d)) / SR


def env(d, attack=0.004, decay=10.0):
    """빠르게 올라갔다가 지수로 줄어드는 모양."""
    t = t_(d)
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-decay * t)


def swell(d, peak=0.6, decay=6.0):
    """천천히 부풀었다가(`peak` 비율 지점) 줄어드는 모양 — 바람·충전 소리."""
    t = t_(d) / d
    up = np.clip(t / peak, 0, 1) ** 2
    down = np.exp(-decay * np.clip(t - peak, 0, None))
    return up * down


def sweep(f0, f1, d, curve="exp"):
    """f0 → f1 로 움직이는 주파수 배열."""
    t = t_(d) / d
    if curve == "exp":
        return f0 * (f1 / f0) ** t
    return f0 + (f1 - f0) * t


def osc(freq, shape="sine"):
    """주파수 배열(또는 상수 길이 배열)을 소리로. 위상을 쌓아서 미끄러짐이 매끈하다."""
    phase = 2 * np.pi * np.cumsum(freq) / SR
    if shape == "sine":
        return np.sin(phase)
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(phase))
    if shape == "square":
        return np.tanh(4 * np.sin(phase))
    if shape == "saw":
        return 2 * ((phase / (2 * np.pi)) % 1.0) - 1
    raise ValueError(shape)


def tone(f0, f1, d, shape="sine", curve="exp"):
    return osc(sweep(f0, f1, d, curve), shape)


def const(f, d):
    return np.full(n(d), float(f))


def noise(d):
    return RNG.uniform(-1, 1, n(d))


def lp(x, fc, order=2):
    sos = signal.butter(order, min(fc, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, fc, order=2):
    sos = signal.butter(order, fc, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def metal(f, d, decay=6.0, ratios=(1.0, 2.76, 5.40, 8.93), bright=1.0):
    """종·쇠붙이 울림 — 정수배가 아닌 배음을 겹친다. 높은 배음일수록 빨리 사라진다."""
    t = t_(d)
    out = np.zeros(n(d))
    for i, r in enumerate(ratios):
        amp = (0.6 ** i) * (bright if i else 1.0)
        out += amp * np.sin(2 * np.pi * f * r * t + RNG.uniform(0, 6.28)) * np.exp(-decay * (1 + i * 0.8) * t)
    return out


def bell(f, d, decay=4.0):
    return metal(f, d, decay, ratios=(1.0, 2.0, 3.01, 4.2))


def pluck(f, d, damp=0.996):
    """Karplus-Strong 현 — 활 시위."""
    period = int(SR / f)
    buf = RNG.uniform(-1, 1, period)
    out = np.zeros(n(d))
    for i in range(len(out)):
        out[i] = buf[i % period]
        buf[i % period] = damp * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out


def at(x, offset):
    return np.concatenate([np.zeros(n(offset)), x])


def mix(*parts):
    length = max(len(p) for p in parts)
    out = np.zeros(length)
    for p in parts:
        out[: len(p)] += p
    return out


def am(x, rate, depth=1.0):
    """진폭 떨림 — 모터·회전."""
    t = np.arange(len(x)) / SR
    return x * (1 - depth * 0.5 * (1 + np.sin(2 * np.pi * rate * t)))


def crackle(d, density=60.0, length=0.004):
    """타닥거림 — 짧은 잡음 조각을 흩뿌린다 (전기·불꽃·도화선)."""
    out = np.zeros(n(d))
    count = int(density * d)
    for _ in range(count):
        start = RNG.integers(0, max(1, n(d) - n(length)))
        piece = noise(length) * env(length, 0.0005, 1.0 / length * 3)
        out[start : start + len(piece)] += piece * RNG.uniform(0.3, 1.0)
    return hp(out, 1500)


def whoosh(d, lo=600, hi=3500, peak=0.5):
    return bp(noise(d), lo, hi) * swell(d, peak, 8.0)


def thud(f0=140, f1=50, d=0.18, decay=18.0, click=0.4):
    body = tone(f0, f1, d) * env(d, 0.002, decay)
    knock = lp(noise(d), 900) * env(d, 0.001, decay * 2.5) * click
    return body + knock


def finish(x, peak=0.8, tail=0.012):
    """끝을 살짝 접고 크기를 맞춘다 — 뚝 끊기면 딸깍 소리가 난다."""
    x = np.asarray(x, dtype=np.float64)
    fade = min(n(tail), len(x))
    if fade > 0:
        x[-fade:] *= np.linspace(1, 0, fade)
    x[: n(0.001)] *= np.linspace(0, 1, n(0.001))
    top = np.max(np.abs(x))
    if top > 0:
        x = x / top * peak
    return x


def write(name, x, peak=0.8):
    x = finish(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def notes(freqs, step, d, shape="tri", decay=7.0):
    """짧은 음을 차례로 — 팡파르·차임."""
    return mix(*[at(osc(const(f, d), shape) * env(d, 0.005, decay), i * step) for i, f in enumerate(freqs)])


# ─────────────────────────── 소리 ───────────────────────────
# 크기(peak)는 자주 나는 것일수록 작게 잡는다 — 발걸음·틱이 타격음보다 크면 시끄럽다.

SOUNDS = {}


def sound(name, peak=0.8):
    def deco(fn):
        SOUNDS[name] = (fn, peak)
        return fn
    return deco


# ── 젤리 몸 ──

@sound("jump", 0.45)
def _():
    d = 0.16
    body = tone(260, 720, d, "tri") * env(d, 0.004, 14)
    wob = 1 + 0.05 * np.sin(2 * np.pi * 30 * t_(d))
    return body * wob + 0.2 * lp(noise(d), 1500) * env(d, 0.001, 50)


@sound("land", 0.5)
def _():
    d = 0.16
    return thud(150, 60, d, 22, 0.8) + 0.4 * bp(noise(d), 200, 900) * env(d, 0.002, 30)


@sound("step", 0.22)
def _():
    d = 0.06
    return bp(noise(d), 250, 1100) * env(d, 0.002, 70) + 0.5 * tone(220, 140, d) * env(d, 0.002, 60)


@sound("dive", 0.45)
def _():
    d = 0.22
    return whoosh(d, 400, 2500, 0.3) + 0.5 * tone(700, 220, d, "tri") * swell(d, 0.25, 6)


@sound("hurt", 0.6)
def _():
    d = 0.2
    wobble = sweep(420, 160, d) * (1 + 0.15 * np.sin(2 * np.pi * 38 * t_(d)))
    squish = osc(wobble, "tri") * env(d, 0.003, 14)
    splat = bp(noise(d), 300, 2400) * env(d, 0.001, 35)
    return squish + 0.6 * splat


@sound("death", 0.75)
def _():
    d = 0.6
    splat = bp(noise(d), 200, 3000) * env(d, 0.001, 18)
    wah = osc(sweep(620, 70, d) * (1 + 0.1 * np.sin(2 * np.pi * 12 * t_(d))), "tri") * env(d, 0.01, 4.5)
    return mix(0.8 * splat, wah, 0.6 * thud(120, 40, 0.3, 10))


@sound("fall", 0.55)
def _():
    d = 0.7
    return tone(1400, 260, d, "sine") * swell(d, 0.15, 3.0)


@sound("splash", 0.7)
def _():
    d = 0.6
    wash = hp(noise(d), 700) * env(d, 0.003, 7)
    bubbles = mix(*[at(tone(f, f * 1.6, 0.05) * env(0.05, 0.002, 40), o)
                    for f, o in zip(RNG.uniform(500, 1400, 9), np.sort(RNG.uniform(0.04, 0.45, 9)))])
    return mix(wash, 0.5 * bubbles, 0.5 * thud(110, 50, 0.2, 14))


@sound("fish", 0.65)
def _():
    slap = bp(noise(0.08), 600, 4000) * env(0.08, 0.001, 50)
    d = 0.35
    wash = hp(noise(d), 1200) * env(d, 0.003, 12)
    return mix(slap * 1.2, at(0.6 * wash, 0.02), 0.5 * thud(200, 80, 0.12, 25))


@sound("stun", 0.45)
def _():
    d = 0.12
    birds = [at(tone(f, f * 1.15, d) * env(d, 0.003, 18), o)
             for f, o in [(1900, 0.0), (2300, 0.1), (2050, 0.2), (2500, 0.3)]]
    return mix(*birds)


@sound("bleed", 0.3)
def _():
    d = 0.09
    return tone(1500, 450, d) * env(d, 0.002, 35)


@sound("ready", 0.35)
def _():
    return mix(bell(1320, 0.4, 7), at(0.7 * bell(1980, 0.35, 8), 0.06))


@sound("empowered", 0.4)
def _():
    return mix(notes([1050, 1320, 1570, 2100], 0.045, 0.16, "sine", 16), 0.15 * crackle(0.3, 50))


@sound("charged", 0.45)
def _():
    d = 0.35
    hum = tone(160, 420, d, "saw") * swell(d, 0.8, 8)
    return mix(lp(hum, 2200), 0.5 * bell(1760, 0.3, 9))


@sound("dagger_pickup", 0.4)
def _():
    return mix(metal(3200, 0.15, 25), at(tone(900, 1500, 0.08, "tri") * env(0.08, 0.003, 25), 0.03))


# ── 무기: 근접 타격 ──

@sound("sword_hit")
def _():
    swish = whoosh(0.09, 2000, 7000, 0.6)
    ring = metal(2300, 0.32, 9, bright=0.8)
    return mix(swish, at(0.6 * ring, 0.05), at(0.4 * thud(200, 90, 0.08, 40), 0.05))


@sound("saber_hit", 0.7)
def _():
    d = 0.22
    hum = lp(osc(sweep(150, 95, d), "saw") + osc(sweep(152, 96, d), "saw"), 1800)
    zap = bp(noise(d), 1500, 6000) * env(d, 0.001, 30)
    return mix(hum * env(d, 0.002, 9), 0.8 * zap, 0.3 * crackle(0.12, 120))


@sound("chainsaw_hit", 0.55)
def _():
    d = 0.2
    motor = am(osc(const(62, d), "square"), 31, 0.7)
    grind = am(bp(noise(d), 1800, 5500), 47, 0.6)
    return (0.6 * lp(motor, 1500) + grind) * env(d, 0.004, 6)


@sound("hammer_hit", 0.85)
def _():
    bonk = tone(560, 470, 0.12, "tri") * env(0.12, 0.001, 30)
    return mix(thud(180, 55, 0.32, 11, 1.0), 0.5 * bonk)


@sound("trident_hit")
def _():
    stab = hp(noise(0.06), 2500) * env(0.06, 0.001, 60)
    return mix(stab, at(0.7 * metal(1500, 0.28, 10), 0.01), at(0.5 * thud(170, 80, 0.1, 30), 0.01))


@sound("glove_hit", 0.7)
def _():
    d = 0.16
    cushion = lp(noise(d), 700) * env(d, 0.002, 25)
    return cushion + 0.9 * tone(170, 80, d) * env(d, 0.002, 18)


@sound("shuriken_hit", 0.6)
def _():
    slice_ = hp(noise(0.05), 4000) * env(0.05, 0.001, 70)
    return mix(slice_, at(0.6 * metal(3600, 0.16, 18), 0.01))


@sound("knuckle_hit", 0.8)
def _():
    crack = hp(noise(0.04), 1800) * env(0.04, 0.0005, 90)
    return mix(crack, thud(210, 70, 0.17, 20, 0.7))


@sound("axe_hit", 0.85)
def _():
    chop = whoosh(0.08, 900, 3500, 0.7)
    crack = bp(noise(0.06), 1200, 4000) * env(0.06, 0.001, 50)
    return mix(chop, at(crack, 0.06), at(thud(150, 60, 0.22, 14, 1.0), 0.06))


@sound("pole_hit", 0.75)
def _():
    d = 0.14
    knock = noise(d) * env(d, 0.0008, 45)
    wood = bp(knock, 650, 760, 2) * 6 + bp(knock, 1350, 1500, 2) * 4
    return mix(wood, 0.5 * thud(240, 120, 0.08, 40, 0.2))


@sound("shield_hit", 0.8)
def _():
    return mix(metal(620, 0.3, 9, bright=0.6), bp(noise(0.05), 500, 3000) * env(0.05, 0.001, 50),
               0.6 * thud(160, 70, 0.15, 22))


# ── 무기: 발사 ──

@sound("dagger_fire", 0.5)
def _():
    return mix(whoosh(0.16, 1500, 5000, 0.35), 0.3 * metal(4000, 0.06, 40))


@sound("cannon_fire", 0.8)
def _():
    d = 0.45
    boom = tone(95, 38, d) * env(d, 0.002, 8)
    blast = lp(noise(d), 700) * env(d, 0.001, 12)
    pop = hp(noise(0.03), 2000) * env(0.03, 0.0005, 80)
    return mix(boom, 0.9 * blast, 0.5 * pop)


@sound("bow_fire", 0.6)
def _():
    string = pluck(190, 0.3, 0.993) * env(0.3, 0.001, 9)
    return mix(string, at(0.5 * whoosh(0.12, 1500, 5000, 0.2), 0.02))


@sound("rifle_fire", 0.55)
def _():
    crack = hp(noise(0.08), 1500) * env(0.08, 0.0005, 45)
    return crack + 0.6 * tone(160, 70, 0.08) * env(0.08, 0.001, 35)


@sound("glove_fire", 0.55)
def _():
    d = 0.2
    rocket = lp(noise(d), 1800) * env(d, 0.003, 10)
    return rocket + 0.5 * tone(220, 480, d, "square") * env(d, 0.003, 14) * 0.5


# ── 무기: 특수 발동 ──

@sound("sword_special", 0.65)
def _():
    # 들어 올리는 0.26초 동안 빛이 차오르고, 내려베는 0.12초에 바람이 가른다.
    d = 0.28
    shimmer = tone(600, 1600, d) * swell(d, 0.95, 4) * (1 + 0.3 * np.sin(2 * np.pi * 22 * t_(d)))
    return mix(0.6 * shimmer, at(whoosh(0.14, 1800, 7000, 0.5), 0.24))


@sound("sword_burst", 0.85)
def _():
    chord = mix(bell(880, 0.9, 3.5), 0.7 * bell(1320, 0.8, 4), 0.5 * bell(1760, 0.7, 5))
    rise = hp(noise(0.25), 3000) * swell(0.25, 0.3, 6)
    return mix(0.5 * rise, chord, 0.7 * thud(110, 45, 0.5, 6, 0.5))


@sound("dagger_special", 0.5)
def _():
    back = whoosh(0.2, 1200, 4500, 0.9)
    return mix(back, at(metal(3000, 0.15, 20), 0.18))


@sound("saber_special", 0.6)
def _():
    d = 0.55
    hum = lp(osc(sweep(70, 230, d), "saw") + osc(sweep(71, 232, d), "saw"), 2400) * swell(d, 0.7, 5)
    return hum + 0.4 * crackle(d, 50) * swell(d, 0.7, 5)


@sound("chainsaw_special", 0.65)
def _():
    # 0.45초 제자리에서 돌다가 돌진한다 — 시동이 걸려 회전이 오르고 돌진에서 크게 운다.
    d = 0.9
    f = np.concatenate([sweep(35, 75, 0.45), sweep(75, 95, 0.45)])
    motor = am(osc(f, "square"), 28, 0.5)
    grind = am(bp(noise(d), 1500, 5000), 41, 0.5) * np.concatenate([np.linspace(0.2, 0.5, n(0.45)), np.ones(n(0.45))])
    return (0.7 * lp(motor, 1600) + grind) * swell(d, 0.55, 3)


@sound("hammer_special", 0.6)
def _():
    d = 0.5
    rise = tone(180, 820, d, "sine") * (1 + 0.5 * np.sin(2 * np.pi * 28 * t_(d)))
    return 0.6 * rise * swell(d, 0.85, 6) + crackle(d, 90) * swell(d, 0.6, 3)


@sound("lightning", 0.85)
def _():
    d = 0.7
    crack = hp(noise(0.05), 2000) * env(0.05, 0.0005, 60)
    zap = crackle(0.2, 250)
    rumble = lp(noise(d), 260) * env(d, 0.02, 4)
    return mix(crack, 0.7 * zap, at(1.4 * rumble, 0.03))


@sound("cannon_special", 0.8)
def _():
    d = 0.6
    hiss = bp(noise(d), 600, 3500) * swell(d, 0.15, 4)
    return mix(thud(110, 40, 0.35, 9, 1.0), at(0.6 * hiss, 0.03), 0.4 * tone(300, 700, d, "saw") * swell(d, 0.2, 5) * 0.4)


@sound("cannon_hit", 0.8)
def _():
    d = 0.4
    return lp(noise(d), 1500) * env(d, 0.001, 10) + tone(130, 45, d) * env(d, 0.002, 9)


@sound("bomb_special", 0.5)
def _():
    throw = whoosh(0.14, 700, 3000, 0.4)
    d = 0.55
    fuse = hp(noise(d), 3000) * 0.3 + crackle(d, 70)
    return mix(throw, at(0.6 * fuse * env(d, 0.03, 2.5), 0.1))


@sound("explosion", 0.95)
def _():
    d = 1.0
    blast = lp(noise(d), 900) * env(d, 0.002, 4.5)
    boom = tone(80, 28, d) * env(d, 0.002, 4)
    debris = crackle(0.5, 80)
    return mix(1.2 * blast, boom, at(0.4 * debris, 0.05))


@sound("bow_special", 0.65)
def _():
    strings = [at(pluck(f, 0.3, 0.993) * env(0.3, 0.001, 9), o) for f, o in [(180, 0.0), (205, 0.035), (230, 0.07)]]
    return mix(*strings, at(0.6 * whoosh(0.18, 1500, 6000, 0.2), 0.03))


@sound("trident_special", 0.75)
def _():
    throw = whoosh(0.22, 400, 2500, 0.4)
    return mix(throw, at(0.6 * metal(900, 0.4, 6), 0.06), at(0.35 * crackle(0.3, 80), 0.06))


@sound("glove_special", 0.6)
def _():
    d = 0.35
    ignite = lp(osc(sweep(140, 520, d), "square"), 1600) * swell(d, 0.7, 6)
    return 0.6 * ignite + lp(noise(d), 2500) * swell(d, 0.5, 4)


@sound("shuriken_special", 0.5)
def _():
    d = 0.35
    whirr = am(bp(noise(d), 1800, 6000), 26, 0.85) * env(d, 0.01, 5)
    whistle = tone(2200, 1600, d) * env(d, 0.01, 7)
    return whirr + 0.3 * whistle


@sound("knuckle_special", 0.6)
def _():
    # 0.5초 끌어모은 뒤 강펀치(`knuckle_punch`)가 터진다.
    d = 0.5
    growl = lp(osc(sweep(70, 210, d), "saw"), 900) * swell(d, 0.95, 3)
    return growl + 0.5 * bp(noise(d), 300, 1500) * swell(d, 0.95, 3)


@sound("knuckle_punch", 0.85)
def _():
    crack = hp(noise(0.05), 1500) * env(0.05, 0.0005, 70)
    return mix(crack, thud(180, 45, 0.35, 10, 1.0), 0.5 * whoosh(0.15, 500, 2500, 0.1))


@sound("knuckle_punch_big", 0.95)
def _():
    crack = hp(noise(0.07), 1200) * env(0.07, 0.0005, 50)
    boom = tone(120, 30, 0.7) * env(0.7, 0.002, 5)
    return mix(crack, boom, 0.8 * lp(noise(0.6), 600) * env(0.6, 0.002, 6), 0.4 * bell(660, 0.6, 5))


@sound("axe_special", 0.6)
def _():
    d = 0.3
    return whoosh(d, 500, 3000, 0.5) + 0.4 * tone(200, 600, d, "tri") * swell(d, 0.6, 6)


@sound("axe_slam", 0.95)
def _():
    d = 0.75
    boom = tone(75, 28, d) * env(d, 0.002, 5)
    rumble = lp(noise(d), 350) * env(d, 0.005, 5)
    debris = mix(*[at(bp(noise(0.03), 800, 3000) * env(0.03, 0.001, 80), o) for o in RNG.uniform(0.05, 0.4, 8)])
    return mix(boom, 1.2 * rumble, 0.4 * debris)


@sound("shotgun_special", 0.9)
def _():
    blast = hp(noise(0.3), 400) * env(0.3, 0.0005, 14)
    body = tone(110, 40, 0.3) * env(0.3, 0.001, 12)
    click = lambda: mix(bp(noise(0.03), 1500, 5000) * env(0.03, 0.0005, 90), 0.5 * metal(2500, 0.05, 50))
    return mix(blast, body, at(0.35 * click(), 0.32), at(0.4 * click(), 0.42))


@sound("pole_special", 0.55)
def _():
    d = 0.35
    stretch = osc(sweep(260, 900, d) * (1 + 0.06 * np.sin(2 * np.pi * 18 * t_(d))), "tri") * env(d, 0.01, 5)
    creak = bp(noise(d), 500, 900) * swell(d, 0.5, 6)
    return stretch + 0.5 * creak


@sound("rifle_special", 0.5)
def _():
    click = lambda f: mix(hp(noise(0.03), 2000) * env(0.03, 0.0005, 90), 0.6 * metal(f, 0.08, 30))
    return mix(click(2600), at(click(3100), 0.09))


@sound("shield_special", 0.55)
def _():
    d = 0.35
    whirr = am(bp(noise(d), 500, 2500), 18, 0.8) * env(d, 0.01, 5)
    return mix(whirr, 0.3 * metal(800, 0.2, 10))


@sound("shield_grow", 0.7)
def _():
    return mix(metal(380, 0.6, 4, bright=0.7), 0.5 * tone(180, 480, 0.3, "tri") * swell(0.3, 0.8, 6))


@sound("swap", 0.6)
def _():
    d = 0.35
    f = np.concatenate([sweep(400, 1600, d / 2), sweep(1600, 400, d / 2)])
    shimmer = osc(f + 60 * np.sin(2 * np.pi * 40 * t_(d)[: len(f)]), "sine")
    return shimmer * swell(d, 0.5, 4) + 0.2 * crackle(d, 60)


@sound("dagger_hit", 0.7)
def _():
    shnk = bp(noise(0.07), 2500, 8000) * env(0.07, 0.0005, 45)
    return mix(shnk, at(0.6 * metal(2900, 0.2, 14), 0.01), 0.4 * thud(200, 90, 0.08, 40))


@sound("projectile_hit", 0.5)
def _():
    return thud(230, 90, 0.12, 30, 0.6)


@sound("projectile_land", 0.35)
def _():
    return thud(320, 150, 0.08, 45, 0.9)


# ── 무기끼리 부딪침 ──

@sound("clash_metal", 0.8)
def _():
    click = hp(noise(0.02), 3000) * env(0.02, 0.0003, 120)
    return mix(click, metal(2100, 0.45, 7), 0.8 * metal(2950, 0.4, 8))


@sound("clash_energy", 0.7)
def _():
    d = 0.3
    zap = bp(noise(d), 1200, 7000) * env(d, 0.001, 18)
    hum = lp(osc(const(118, d), "saw") + osc(const(123, d), "saw"), 2000) * env(d, 0.002, 10)
    return mix(zap, 0.6 * hum, 0.6 * crackle(0.2, 200))


@sound("clash_wood", 0.7)
def _():
    d = 0.12
    knock = noise(d) * env(d, 0.0005, 55)
    return mix(bp(knock, 850, 980) * 6 + bp(knock, 1650, 1850) * 5, at(bp(noise(0.08), 900, 1000) * env(0.08, 0.0005, 60) * 4, 0.05))


@sound("clash_heavy", 0.85)
def _():
    return mix(metal(330, 0.55, 5, bright=0.8), thud(150, 60, 0.25, 14, 1.0))


@sound("clash_soft", 0.6)
def _():
    d = 0.16
    return lp(noise(d), 600) * env(d, 0.003, 22) + tone(260, 170, d, "tri") * env(d, 0.003, 18)


@sound("clash_saw", 0.7)
def _():
    d = 0.3
    sparks = am(hp(noise(d), 3500), 55, 0.7) * env(d, 0.002, 9)
    return mix(sparks, 0.5 * metal(3200, 0.25, 12), 0.5 * crackle(d, 150))


@sound("clash_shield", 0.85)
def _():
    click = bp(noise(0.03), 800, 4000) * env(0.03, 0.0005, 90)
    return mix(click, metal(520, 0.6, 5, bright=0.9), 0.5 * metal(1240, 0.4, 8))


# ── 판 진행·화면 ──

@sound("count_beep", 0.45)
def _():
    d = 0.16
    return (osc(const(880, d), "tri") + 0.3 * osc(const(1760, d), "sine")) * env(d, 0.003, 14)


@sound("count_go", 0.6)
def _():
    d = 0.5
    chord = sum(osc(const(f, d), "tri") for f in (1047, 1319, 1568)) / 3
    return mix(chord * env(d, 0.004, 5), 0.3 * hp(noise(0.2), 3000) * env(0.2, 0.002, 15))


@sound("intro", 0.7)
def _():
    sweep_in = whoosh(0.35, 400, 4000, 0.8)
    stab = sum(osc(const(f, 0.7), "saw") for f in (262, 330, 392, 523)) / 4
    return mix(0.7 * sweep_in, at(lp(stab, 3000) * env(0.7, 0.004, 4), 0.3), at(0.8 * thud(110, 45, 0.4, 7), 0.3))


@sound("point", 0.6)
def _():
    # point_gain.gd 의 시각에 맞춘다 — 띠가 쓸려 들어오고(0) 빛이 터지고(0.60)
    # `+1 포인트!` 가 뜬다(0.74).
    band = whoosh(0.25, 800, 5000, 0.4)
    burst = mix(hp(noise(0.2), 3500) * env(0.2, 0.002, 12), bell(1760, 0.5, 6))
    chime = notes([1047, 1319, 1568], 0.06, 0.4, "tri", 6)
    return mix(0.6 * band, at(0.6 * burst, 0.60), at(chime, 0.74))


@sound("point_final", 0.7)
def _():
    band = whoosh(0.25, 800, 5000, 0.4)
    burst = mix(hp(noise(0.4), 2500) * env(0.4, 0.002, 6), bell(1760, 0.8, 4), 0.6 * thud(100, 40, 0.5, 6))
    chime = notes([1047, 1319, 1568, 2093], 0.07, 0.7, "tri", 4)
    return mix(0.6 * band, at(burst, 0.60), at(chime, 0.74))


@sound("victory", 0.7)
def _():
    melody = notes([523, 659, 784, 1047], 0.13, 0.3, "square", 6) * 0.5
    final = sum(osc(const(f, 1.2), "tri") for f in (523, 659, 784, 1047)) / 4 * env(1.2, 0.01, 2.2)
    return mix(lp(melody, 4000), at(final, 0.52), at(0.4 * bell(2093, 1.0, 3), 0.52))


@sound("card_open", 0.45)
def _():
    swish = lambda: hp(noise(0.07), 2500) * swell(0.07, 0.3, 10)
    return mix(swish(), at(swish(), 0.08), at(swish(), 0.16))


@sound("card_move", 0.3)
def _():
    d = 0.04
    return osc(const(1500, d), "square") * env(d, 0.001, 70) * 0.5


@sound("card_pick", 0.5)
def _():
    return notes([784, 1047, 1568], 0.05, 0.3, "tri", 9)


@sound("click", 0.4)
def _():
    d = 0.06
    return tone(800, 1300, d, "tri") * env(d, 0.001, 45)


@sound("confirm", 0.5)
def _():
    return notes([660, 990], 0.08, 0.22, "tri", 12)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = set(sys.argv[1:])
    for name, (fn, peak) in SOUNDS.items():
        if only and name not in only:
            continue
        write(name, fn(), peak)
    print("wrote %d sounds to %s" % (len(only) or len(SOUNDS), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
