#!/usr/bin/env python3
"""合成洛克人風格的 8-bit OGG（程序音效／背景循環），輸出到 ../audio/

依賴：pip3 install --user numpy soundfile
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

SAMPLE_RATE = 22050
HERE = Path(__file__).resolve().parent
OUT_DIR = HERE.parent / "audio"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def _silence(duration: float) -> np.ndarray:
    return np.zeros(int(duration * SAMPLE_RATE), dtype=np.float32)


def _envelope(length: int, attack: float = 0.01, decay: float = 0.0,
              sustain: float = 1.0, release: float = 0.05) -> np.ndarray:
    a = max(1, int(length * attack))
    d = max(0, int(length * decay))
    r = max(1, int(length * release))
    s = max(0, length - a - d - r)
    env = np.concatenate([
        np.linspace(0.0, 1.0, a, dtype=np.float32),
        np.linspace(1.0, sustain, d, dtype=np.float32) if d else np.array([], dtype=np.float32),
        np.full(s, sustain, dtype=np.float32),
        np.linspace(sustain, 0.0, r, dtype=np.float32),
    ])
    if env.shape[0] < length:
        env = np.pad(env, (0, length - env.shape[0]))
    return env[:length]


def square(freq: float, duration: float, duty: float = 0.5) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SAMPLE_RATE
    phase = (t * freq) % 1.0
    return np.where(phase < duty, 1.0, -1.0).astype(np.float32)


def triangle(freq: float, duration: float) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SAMPLE_RATE
    phase = (t * freq) % 1.0
    return (4.0 * np.abs(phase - 0.5) - 1.0).astype(np.float32)


def noise(duration: float, seed: int = 0, lp: float = 0.7) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    rng = np.random.default_rng(seed)
    raw = rng.uniform(-1.0, 1.0, n).astype(np.float32)
    out = np.empty_like(raw)
    prev = 0.0
    for i, v in enumerate(raw):
        prev = prev * (1 - lp) + v * lp
        out[i] = prev
    return out


def bitcrush(buf: np.ndarray, bits: int = 6) -> np.ndarray:
    levels = 2 ** bits
    return np.round(buf * (levels / 2)) / (levels / 2)


def hardlimit(buf: np.ndarray, ceiling: float = 0.92) -> np.ndarray:
    return np.clip(buf, -ceiling, ceiling)


def _mix(*tracks: np.ndarray) -> np.ndarray:
    if not tracks:
        return np.zeros(0, dtype=np.float32)
    n = max(t.shape[0] for t in tracks)
    out = np.zeros(n, dtype=np.float32)
    for t in tracks:
        out[: t.shape[0]] += t
    return out


def write_ogg(name: str, buf: np.ndarray) -> Path:
    buf = hardlimit(buf)
    path = OUT_DIR / f"{name}.ogg"
    sf.write(str(path), buf.astype(np.float32), SAMPLE_RATE,
             format="OGG", subtype="VORBIS")
    return path


def sfx_jump() -> np.ndarray:
    n = int(0.11 * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    f0, f1 = 180.0, 520.0
    freq = f0 + (f1 - f0) * (t / t[-1])
    phase = np.cumsum(freq / SAMPLE_RATE) % 1.0
    wave = np.where(phase < 0.45, 1.0, -1.0).astype(np.float32)
    wave *= _envelope(wave.shape[0], attack=0.02, sustain=0.55, release=0.45)
    return bitcrush(wave * 0.78, bits=6)


def sfx_shoot() -> np.ndarray:
    pew = square(980, 0.035, duty=0.22) * 0.55
    pew *= _envelope(pew.shape[0], attack=0.0, decay=0.35, sustain=0.35, release=0.65)
    tick = noise(0.02, seed=7, lp=0.9) * 0.55
    tail = triangle(440, 0.055) * 0.28
    tail *= _envelope(tail.shape[0], attack=0.0, sustain=0.4, release=0.85)
    return bitcrush(_mix(pew, tick, tail), bits=6)


def sfx_land() -> np.ndarray:
    thump = noise(0.06, seed=3, lp=0.35) * 0.65
    thump *= _envelope(thump.shape[0], attack=0.0, sustain=0.45, release=0.9)
    box = triangle(95, 0.07) * 0.35
    return bitcrush(_mix(thump, box), bits=5)


def sfx_hit_enemy() -> np.ndarray:
    ping = square(1320, 0.045, duty=0.25) * 0.42
    ping *= _envelope(ping.shape[0], attack=0.0, sustain=0.55, release=0.75)
    ring = triangle(880, 0.06) * 0.32
    return bitcrush(_mix(ping, ring), bits=6)


def sfx_enemy_die() -> np.ndarray:
    parts = []
    for i in range(14):
        f = 380 - i * 22
        seg = square(max(f, 60), 0.028, duty=0.35) * 0.5
        seg *= _envelope(seg.shape[0], attack=0.0, sustain=0.6, release=0.7)
        parts.append(seg)
    sweep = np.concatenate(parts)
    boom = noise(0.22, seed=9, lp=0.5) * 0.45
    boom *= _envelope(boom.shape[0], attack=0.02, sustain=0.5, release=0.88)
    return bitcrush(_mix(_layer(sweep, boom.shape[0]), boom), bits=6)


def sfx_player_hurt() -> np.ndarray:
    zap = square(220, 0.09, duty=0.3) * 0.55
    zap *= _envelope(zap.shape[0], attack=0.0, sustain=0.5, release=0.85)
    zap2 = square(165, 0.11, duty=0.45) * 0.38
    grit = noise(0.14, seed=11, lp=0.75) * 0.4
    return bitcrush(_mix(zap, zap2, grit), bits=5)


def sfx_charge_ping() -> np.ndarray:
    seq = []
    for f in (523, 659, 784):
        seg = triangle(f, 0.06)
        seg *= _envelope(seg.shape[0], attack=0.03, sustain=0.65, release=0.55)
        seq.append(seg * 0.45)
    return bitcrush(np.concatenate(seq), bits=6)


def _note_freq(midi: int) -> float:
    return 440.0 * (2 ** ((midi - 69) / 12))


def _layer(buf: np.ndarray, length: int) -> np.ndarray:
    if buf.shape[0] >= length:
        return buf[:length]
    return np.pad(buf, (0, length - buf.shape[0]))


def music_stage_loop() -> np.ndarray:
    """約 16 秒動作關卡循環：低音 + 琶音 + 稀疏鼓點。"""
    duration = 16.0
    n = int(duration * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE

    # Bass pulse (square on roots)
    bass_pat = [
        (0.0, 48), (0.5, 48), (1.0, 53), (1.5, 55),
        (2.0, 48), (2.5, 48), (3.0, 53), (3.5, 58),
    ]
    bass = np.zeros(n, dtype=np.float32)
    beat = 0.5
    for loop in range(int(duration / (len(bass_pat) * beat)) + 2):
        base_t = loop * len(bass_pat) * beat
        for i, (_step, midi) in enumerate(bass_pat):
            at = base_t + i * beat
            if at >= duration:
                break
            seg = square(_note_freq(midi), beat * 0.92, duty=0.42) * 0.22
            seg *= _envelope(seg.shape[0], attack=0.02, sustain=0.65, release=0.35)
            idx = int(at * SAMPLE_RATE)
            end = min(n, idx + seg.shape[0])
            bass[idx:end] += seg[: end - idx]

    # Hi-hat-ish noise on offbeats
    hat = np.zeros(n, dtype=np.float32)
    step_s = beat / 2
    steps = int(duration / step_s)
    for i in range(steps):
        if i % 2 != 1:
            continue
        at = i * step_s
        seg = noise(0.03, seed=100 + i, lp=0.85) * 0.22
        seg *= _envelope(seg.shape[0], attack=0.0, sustain=0.35, release=0.9)
        idx = int(at * SAMPLE_RATE)
        end = min(n, idx + seg.shape[0])
        hat[idx:end] += seg[: end - idx]

    # Arpeggiated lead (bright minor pentatonic flair)
    melody_notes = [72, 75, 79, 82, 79, 75, 72, 70, 72, 75, 79, 84, 82, 79, 75, 72]
    step_m = 0.125
    lead_parts = []
    for midi in melody_notes:
        f = _note_freq(midi)
        seg = triangle(f, step_m * 0.92) * 0.26
        seg *= _envelope(seg.shape[0], attack=0.03, sustain=0.7, release=0.45)
        lead_parts.append(seg)
    lead = np.concatenate(lead_parts)
    lead = _layer(lead, n)

    # Pad drone (soft)
    drone = np.sin(2 * math.pi * _note_freq(48) * t).astype(np.float32) * 0.08
    drone += np.sin(2 * math.pi * _note_freq(55) * t).astype(np.float32) * 0.06

    buf = _mix(bass, hat, lead, drone)
    buf *= 0.72
    # Seamless-ish loop: fade ends (short)
    fade = int(0.04 * SAMPLE_RATE)
    buf[:fade] *= np.linspace(0, 1, fade, dtype=np.float32)
    buf[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    return bitcrush(buf, bits=7)


def music_title() -> np.ndarray:
    """較緩慢標題畫面叮叮咚咚。"""
    duration = 12.0
    n = int(duration * SAMPLE_RATE)
    notes = [60, 64, 67, 72, 67, 64, 60, 58, 60, 64, 67, 71, 74, 71, 67, 64]
    step = 0.38
    parts = []
    for midi in notes:
        f = _note_freq(midi)
        seg = triangle(f, step * 0.95) * 0.32
        seg *= _envelope(seg.shape[0], attack=0.06, sustain=0.72, release=0.42)
        harmony = square(f / 2, step * 0.95, duty=0.5) * 0.12
        harmony *= _envelope(harmony.shape[0], attack=0.08, sustain=0.65, release=0.45)
        parts.append(_mix(seg, harmony))
    mel = np.concatenate(parts)
    mel = _layer(mel, n)
    t = np.arange(n) / SAMPLE_RATE
    pad = np.sin(2 * math.pi * _note_freq(43) * t).astype(np.float32) * 0.07
    buf = _mix(mel, pad) * 0.68
    fade = int(0.05 * SAMPLE_RATE)
    buf[:fade] *= np.linspace(0, 1, fade, dtype=np.float32)
    buf[-fade:] *= np.linspace(1, 0, fade, dtype=np.float32)
    return bitcrush(buf, bits=7)


BANK = {
    "sfx_jump": sfx_jump,
    "sfx_shoot": sfx_shoot,
    "sfx_land": sfx_land,
    "sfx_hit_enemy": sfx_hit_enemy,
    "sfx_enemy_die": sfx_enemy_die,
    "sfx_player_hurt": sfx_player_hurt,
    "sfx_charge_ping": sfx_charge_ping,
    "music_stage": music_stage_loop,
    "music_title": music_title,
}


def main() -> int:
    targets = [a for a in sys.argv[1:] if not a.startswith("-")]
    if not targets:
        targets = list(BANK.keys())
    for name in targets:
        if name not in BANK:
            print(f"unknown: {name}", file=sys.stderr)
            return 1
        buf = BANK[name]()
        path = write_ogg(name, buf)
        print(f"wrote {path} ({buf.shape[0] / SAMPLE_RATE:.2f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
