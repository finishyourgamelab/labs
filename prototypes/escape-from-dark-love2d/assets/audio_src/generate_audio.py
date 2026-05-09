#!/usr/bin/env python3
"""Procedurally synthesize 8-bit style audio cues and ambient music.

Writes `.ogg` (checked into Git, LÖVE-first) into
`prototypes/escape-from-dark-love2d/assets/audio/`. Optional `--mp3` /
`--all` also emits `.mp3` via lameenc for sharing outside the repo — those
files are normally gitignored or kept local only to save space.
Re-run this script to regenerate the soundtrack; output is deterministic given
the parameters in `BANK` below.

Style targets a NES-era horror prototype: square / triangle / pulse / noise
voices with low sample rate feel, chained into low BPM ambient loops with
sparse melody and detuned drones.

Dependencies:
    pip3 install --user numpy soundfile lameenc
"""
from __future__ import annotations

import math
import os
import random
import struct
import sys
import wave
from pathlib import Path

import numpy as np
import soundfile as sf

try:
    import lameenc  # type: ignore
except ImportError:  # pragma: no cover
    lameenc = None  # type: ignore

SAMPLE_RATE = 22050  # crunchy 8-bit feel
HERE = Path(__file__).resolve().parent
OUT_DIR = HERE.parent / "audio"
OUT_DIR.mkdir(parents=True, exist_ok=True)


def _silence(duration: float) -> np.ndarray:
    return np.zeros(int(duration * SAMPLE_RATE), dtype=np.float32)


def _envelope(length: int, attack: float = 0.01, decay: float = 0.0,
              sustain: float = 1.0, release: float = 0.05) -> np.ndarray:
    """Simple ADSR envelope. attack/decay/release are fractions of length."""
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


def square(freq: float, duration: float, duty: float = 0.5,
           detune: float = 0.0) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SAMPLE_RATE
    f = freq * (1.0 + detune)
    phase = (t * f) % 1.0
    return np.where(phase < duty, 1.0, -1.0).astype(np.float32)


def triangle(freq: float, duration: float) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SAMPLE_RATE
    phase = (t * freq) % 1.0
    return (4.0 * np.abs(phase - 0.5) - 1.0).astype(np.float32)


def saw(freq: float, duration: float) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    t = np.arange(n) / SAMPLE_RATE
    phase = (t * freq) % 1.0
    return (2.0 * phase - 1.0).astype(np.float32)


def noise(duration: float, seed: int = 0, lp: float = 0.6) -> np.ndarray:
    n = int(duration * SAMPLE_RATE)
    if n <= 0:
        return np.zeros(0, dtype=np.float32)
    rng = np.random.default_rng(seed)
    raw = rng.uniform(-1.0, 1.0, n).astype(np.float32)
    if lp > 0:
        # one-pole lowpass to soften white noise into vinyl-like hiss
        out = np.empty_like(raw)
        prev = 0.0
        a = lp
        for i, v in enumerate(raw):
            prev = prev * (1 - a) + v * a
            out[i] = prev
        return out
    return raw


def bitcrush(buf: np.ndarray, bits: int = 6) -> np.ndarray:
    if bits >= 16:
        return buf
    levels = 2 ** bits
    return np.round(buf * (levels / 2)) / (levels / 2)


def hardlimit(buf: np.ndarray, ceiling: float = 0.95) -> np.ndarray:
    return np.clip(buf, -ceiling, ceiling)


def _mix(*tracks: np.ndarray) -> np.ndarray:
    if not tracks:
        return np.zeros(0, dtype=np.float32)
    n = max(t.shape[0] for t in tracks)
    out = np.zeros(n, dtype=np.float32)
    for t in tracks:
        out[: t.shape[0]] += t
    return out


def _layer(buf: np.ndarray, length: int) -> np.ndarray:
    if buf.shape[0] >= length:
        return buf[:length]
    return np.pad(buf, (0, length - buf.shape[0]))


def write_ogg(name: str, buf: np.ndarray) -> Path:
    buf = hardlimit(buf, 0.92)
    target = OUT_DIR / f"{name}.ogg"
    sf.write(str(target), buf.astype(np.float32), SAMPLE_RATE,
             format="OGG", subtype="VORBIS")
    return target


def write_mp3(name: str, buf: np.ndarray, bitrate: int = 96) -> Path:
    """Write a mono mp3 with a small 8-bit-friendly bitrate via lameenc."""
    if lameenc is None:
        raise RuntimeError(
            "lameenc not installed. Install with: pip3 install --user lameenc"
        )
    buf = hardlimit(buf, 0.92).astype(np.float32)
    pcm16 = np.clip(buf * 32767.0, -32768, 32767).astype("<i2").tobytes()
    encoder = lameenc.Encoder()
    encoder.set_bit_rate(bitrate)
    encoder.set_in_sample_rate(SAMPLE_RATE)
    encoder.set_channels(1)
    encoder.set_quality(2)
    mp3_data = encoder.encode(pcm16)
    mp3_data += encoder.flush()
    target = OUT_DIR / f"{name}.mp3"
    target.write_bytes(mp3_data)
    return target


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------


def sfx_pistol() -> np.ndarray:
    crack = noise(0.06, seed=1, lp=0.95) * 0.85
    crack *= _envelope(crack.shape[0], attack=0.02, sustain=0.5, release=0.6)
    body = square(220, 0.07, duty=0.3) * 0.55
    body *= _envelope(body.shape[0], attack=0.0, decay=0.05, sustain=0.6, release=0.95)
    tail = triangle(110, 0.15) * 0.18
    tail *= _envelope(tail.shape[0], attack=0.0, sustain=0.5, release=0.95)
    buf = _mix(crack, body, tail)
    return bitcrush(buf * 0.95, bits=6)


def sfx_dryfire() -> np.ndarray:
    click = noise(0.04, seed=11, lp=0.4) * 0.5
    click *= _envelope(click.shape[0], attack=0.0, sustain=0.5, release=0.95)
    return bitcrush(click, bits=5)


def sfx_hit() -> np.ndarray:
    body = square(140, 0.12, duty=0.25) * 0.6
    body *= _envelope(body.shape[0], attack=0.0, sustain=0.5, release=0.95)
    grit = noise(0.12, seed=2, lp=0.8) * 0.45
    grit *= _envelope(grit.shape[0], attack=0.0, sustain=0.4, release=0.95)
    return bitcrush(_mix(body, grit), bits=5)


def sfx_enemy_die() -> np.ndarray:
    bass = triangle(80, 0.45) * 0.45
    bass *= _envelope(bass.shape[0], attack=0.0, sustain=0.6, release=0.9)
    sweep = np.concatenate([
        square(220 - i * 6, 0.025, duty=0.4) * 0.6
        for i in range(16)
    ])
    sweep *= _envelope(sweep.shape[0], attack=0.0, sustain=0.7, release=0.8)
    rumble = noise(0.45, seed=3, lp=0.3) * 0.35
    rumble *= _envelope(rumble.shape[0], attack=0.05, sustain=0.6, release=0.9)
    return bitcrush(_mix(bass, sweep, rumble), bits=6)


def sfx_player_hurt() -> np.ndarray:
    growl = saw(70, 0.32) * 0.55
    growl *= _envelope(growl.shape[0], attack=0.0, sustain=0.6, release=0.9)
    sting = square(220, 0.07, duty=0.35) * 0.4
    sting *= _envelope(sting.shape[0], attack=0.0, sustain=0.4, release=0.9)
    return bitcrush(_mix(growl, sting), bits=5)


def sfx_pickup() -> np.ndarray:
    notes = [392, 523, 659]
    parts = []
    for i, freq in enumerate(notes):
        seg = triangle(freq, 0.08)
        seg *= _envelope(seg.shape[0], attack=0.02, sustain=0.7, release=0.6)
        parts.append(seg * 0.55)
    buf = np.concatenate(parts)
    return bitcrush(buf, bits=6)


def sfx_search_loop() -> np.ndarray:
    base = triangle(120, 0.4) * 0.35
    base *= _envelope(base.shape[0], attack=0.4, sustain=0.7, release=0.5)
    rust = noise(0.4, seed=4, lp=0.55) * 0.25
    rust *= _envelope(rust.shape[0], attack=0.4, sustain=0.6, release=0.6)
    buf = _mix(base, rust)
    return bitcrush(buf, bits=5)


def sfx_extract_arm() -> np.ndarray:
    parts = []
    for i in range(4):
        seg = square(220 + i * 80, 0.18, duty=0.3) * 0.45
        seg *= _envelope(seg.shape[0], attack=0.05, sustain=0.7, release=0.7)
        parts.append(seg)
        parts.append(_silence(0.04))
    return bitcrush(np.concatenate(parts), bits=6)


def sfx_extract_done() -> np.ndarray:
    chord = _mix(
        triangle(523, 0.6) * 0.45,
        triangle(659, 0.6) * 0.4,
        triangle(784, 0.6) * 0.4,
    )
    chord *= _envelope(chord.shape[0], attack=0.05, sustain=0.7, release=0.6)
    sparkle = []
    for i, f in enumerate([784, 988, 1175, 1318]):
        seg = triangle(f, 0.12)
        seg *= _envelope(seg.shape[0], attack=0.05, sustain=0.7, release=0.6)
        sparkle.append(seg * 0.4)
    sparkle_buf = np.concatenate(sparkle)
    buf = np.concatenate([chord, sparkle_buf])
    return bitcrush(buf, bits=6)


def sfx_alarm() -> np.ndarray:
    wave_lengths = [0.28, 0.28, 0.28, 0.28]
    pieces = []
    for i, dur in enumerate(wave_lengths):
        seg = square(660 if i % 2 == 0 else 440, dur, duty=0.5) * 0.5
        seg *= _envelope(seg.shape[0], attack=0.02, sustain=0.8, release=0.4)
        pieces.append(seg)
    return bitcrush(np.concatenate(pieces), bits=6)


def sfx_heartbeat() -> np.ndarray:
    def thump(freq: float, dur: float, seed: int) -> np.ndarray:
        n = int(dur * SAMPLE_RATE)
        t = np.arange(n) / SAMPLE_RATE
        env = np.exp(-t * 18)
        body = np.sin(2 * math.pi * freq * t) * env
        return body.astype(np.float32) * 0.85

    a = thump(58, 0.25, 0) * 0.9
    rest = _silence(0.12)
    b = thump(48, 0.32, 1) * 0.8
    silence = _silence(0.55)
    return bitcrush(np.concatenate([a, rest, b, silence]) * 1.05, bits=5)


def sfx_step() -> np.ndarray:
    pulse = noise(0.05, seed=5, lp=0.45) * 0.45
    pulse *= _envelope(pulse.shape[0], attack=0.0, sustain=0.5, release=0.95)
    body = triangle(70, 0.06) * 0.25
    body *= _envelope(body.shape[0], attack=0.0, sustain=0.5, release=0.95)
    return bitcrush(_mix(pulse, body), bits=5)


def sfx_whisper() -> np.ndarray:
    base = noise(1.4, seed=6, lp=0.18) * 0.55
    base *= _envelope(base.shape[0], attack=0.3, sustain=0.7, release=0.4)
    ghost = saw(58, 1.4) * 0.18
    ghost *= _envelope(ghost.shape[0], attack=0.4, sustain=0.5, release=0.5)
    return bitcrush(_mix(base, ghost) * 0.9, bits=5)


# ---------------------------------------------------------------------------
# Music — three short ambient loops, one per level.
# ---------------------------------------------------------------------------


def _note_freq(midi: int) -> float:
    return 440.0 * (2 ** ((midi - 69) / 12))


def _arpeggio(notes: list[int], step: float, voices: list[str]) -> np.ndarray:
    out_parts = []
    for i, midi in enumerate(notes):
        f = _note_freq(midi)
        voice = voices[i % len(voices)]
        if voice == "tri":
            seg = triangle(f, step) * 0.3
        elif voice == "sqr":
            seg = square(f, step, duty=0.25) * 0.18
        else:
            seg = saw(f, step) * 0.18
        seg *= _envelope(seg.shape[0], attack=0.05, sustain=0.7, release=0.6)
        out_parts.append(seg)
    return np.concatenate(out_parts)


def _drone(midis: list[int], duration: float) -> np.ndarray:
    parts = []
    for m in midis:
        f = _note_freq(m)
        seg = saw(f, duration) * 0.13
        det = saw(f * 1.005, duration) * 0.1
        parts.append(seg + det)
    base = sum(parts) if parts else np.zeros(int(duration * SAMPLE_RATE), dtype=np.float32)
    fade = np.linspace(0, 1, int(SAMPLE_RATE * 1.2))
    if base.shape[0] > fade.shape[0] * 2:
        base[: fade.shape[0]] *= fade
        base[-fade.shape[0]:] *= fade[::-1]
    return base


def music_basement() -> np.ndarray:
    """LV1 - basement: low triangle drone, sparse minor arpeggio, hiss."""
    duration = 24.0
    drone = _drone([36, 43, 48], duration) * 0.9
    arp = np.concatenate([
        _arpeggio([60, 63, 67, 70, 67, 63], 0.5, ["tri", "tri", "sqr"]),
        _silence(2.0),
        _arpeggio([60, 63, 67, 72, 70, 67], 0.5, ["tri", "tri", "sqr"]),
        _silence(4.5),
    ])
    arp = _layer(arp, drone.shape[0]) * 0.55
    hiss = noise(duration, seed=10, lp=0.12) * 0.18
    pulse = np.zeros_like(drone)
    pulse_step = int(SAMPLE_RATE * 1.6)
    for i in range(0, pulse.shape[0] - pulse_step, pulse_step):
        thump = triangle(48, 0.25) * 0.4
        thump *= _envelope(thump.shape[0], attack=0.0, sustain=0.6, release=0.9)
        pulse[i : i + thump.shape[0]] += thump
    buf = _mix(drone, arp, hiss, pulse)
    return bitcrush(buf * 0.65, bits=7)


def music_morgue() -> np.ndarray:
    """LV2 - morgue: detuned drones, distant bell, broken music box."""
    duration = 26.0
    drone = _drone([34, 41, 53], duration) * 1.0
    bell = np.zeros(int(duration * SAMPLE_RATE), dtype=np.float32)
    timeline = [(0.5, 64), (4.5, 67), (9.0, 60), (13.5, 63), (18.5, 60), (22.0, 67)]
    for at, midi in timeline:
        seg = triangle(_note_freq(midi), 0.9) * 0.45
        seg *= _envelope(seg.shape[0], attack=0.02, sustain=0.55, release=0.95)
        idx = int(at * SAMPLE_RATE)
        end = min(bell.shape[0], idx + seg.shape[0])
        bell[idx:end] += seg[: end - idx]
    music_box_notes = [72, 75, 79, 75, 72, 70]
    box = _arpeggio(music_box_notes, 0.4, ["tri"]) * 0.42
    detune = _arpeggio(music_box_notes, 0.4, ["sqr"]) * 0.18
    box_full = np.concatenate([_silence(6.0), box + detune, _silence(2.0)])
    box_full = _layer(box_full, drone.shape[0])
    hiss = noise(duration, seed=20, lp=0.15) * 0.16
    buf = _mix(drone, bell, box_full, hiss)
    return bitcrush(buf * 0.62, bits=7)


def music_chapel() -> np.ndarray:
    """LV3 - chapel rooftop: tense rising pulse, hymn fragments."""
    duration = 30.0
    drone = _drone([36, 43, 50, 55], duration) * 1.0
    pulse = np.zeros(int(duration * SAMPLE_RATE), dtype=np.float32)
    step = int(SAMPLE_RATE * 0.55)
    for i in range(0, pulse.shape[0] - step, step):
        seg = square(_note_freq(43), 0.15, duty=0.25) * 0.32
        seg *= _envelope(seg.shape[0], attack=0.0, sustain=0.4, release=0.9)
        pulse[i : i + seg.shape[0]] += seg
    hymn_notes = [67, 65, 63, 60, 63, 65, 67, 70]
    hymn = _arpeggio(hymn_notes, 0.6, ["tri", "tri", "sqr"]) * 0.55
    hymn_full = np.concatenate([_silence(8.0), hymn, _silence(4.0), hymn[::-1] * 0.7, _silence(2.0)])
    hymn_full = _layer(hymn_full, drone.shape[0])
    bell_hits = np.zeros_like(drone)
    for at in [3.0, 11.0, 19.0, 26.5]:
        seg = triangle(_note_freq(48), 1.4) * 0.55
        seg *= _envelope(seg.shape[0], attack=0.01, sustain=0.5, release=0.95)
        idx = int(at * SAMPLE_RATE)
        end = min(bell_hits.shape[0], idx + seg.shape[0])
        bell_hits[idx:end] += seg[: end - idx]
    hiss = noise(duration, seed=30, lp=0.18) * 0.18
    buf = _mix(drone, pulse, hymn_full, bell_hits, hiss)
    return bitcrush(buf * 0.6, bits=7)


def music_menu() -> np.ndarray:
    duration = 18.0
    drone = _drone([36, 43, 48], duration) * 0.85
    arp = _arpeggio([60, 63, 67, 70, 72, 70, 67, 63], 0.55, ["tri", "tri", "sqr"]) * 0.5
    arp_full = np.concatenate([_silence(2.0), arp, _silence(2.0), arp * 0.6, _silence(2.0)])
    arp_full = _layer(arp_full, drone.shape[0])
    hiss = noise(duration, seed=40, lp=0.18) * 0.15
    buf = _mix(drone, arp_full, hiss)
    return bitcrush(buf * 0.6, bits=7)


BANK = {
    "sfx_pistol": sfx_pistol,
    "sfx_dryfire": sfx_dryfire,
    "sfx_hit": sfx_hit,
    "sfx_enemy_die": sfx_enemy_die,
    "sfx_player_hurt": sfx_player_hurt,
    "sfx_pickup": sfx_pickup,
    "sfx_search_loop": sfx_search_loop,
    "sfx_extract_arm": sfx_extract_arm,
    "sfx_extract_done": sfx_extract_done,
    "sfx_alarm": sfx_alarm,
    "sfx_heartbeat": sfx_heartbeat,
    "sfx_step": sfx_step,
    "sfx_whisper": sfx_whisper,
    "music_menu": music_menu,
    "music_lv1_basement": music_basement,
    "music_lv2_morgue": music_morgue,
    "music_lv3_chapel": music_chapel,
}


def main() -> int:
    args = sys.argv[1:]
    formats = {"ogg", "mp3"}
    targets: list[str] = []
    for a in args:
        if a == "--ogg":
            formats = {"ogg"}
        elif a == "--mp3":
            formats = {"mp3"}
        elif a == "--all":
            formats = {"ogg", "mp3"}
        else:
            targets.append(a)
    if not targets:
        targets = list(BANK.keys())

    for name in targets:
        if name not in BANK:
            print(f"unknown: {name}", file=sys.stderr)
            return 1
        buf = BANK[name]()
        if "ogg" in formats:
            path = write_ogg(name, buf)
            size = path.stat().st_size
            print(f"wrote {path.relative_to(HERE.parent.parent)}  ({size/1024:.1f} KiB, {buf.shape[0]/SAMPLE_RATE:.2f}s)")
        if "mp3" in formats:
            bitrate = 64 if name.startswith("sfx_") else 96
            path = write_mp3(name, buf, bitrate=bitrate)
            size = path.stat().st_size
            print(f"wrote {path.relative_to(HERE.parent.parent)}  ({size/1024:.1f} KiB, {bitrate}kbps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
