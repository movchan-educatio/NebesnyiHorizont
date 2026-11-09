"""Generate the menu theme loop and the UI click as 16-bit WAV files.

Run: python tools/make_menu_audio.py
Outputs: Assets/audio/menu_theme.wav, Assets/audio/menu_click.wav
"""
import math
import os
import struct
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Assets", "audio")
os.makedirs(OUT, exist_ok=True)
SR = 44100


def write_wav(path, samples):
    samples = np.clip(samples, -1.0, 1.0)
    data = (samples * 32767.0).astype(np.int16)
    with wave.open(path, "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(data.tobytes())


def note_hz(name, octave):
    # Equal temperament from A4 = 440 Hz.
    semis = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4,
             "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    return 440.0 * (2.0 ** ((semis[name] + (octave - 4) * 12) / 12.0))


def pad_voice(freq, duration, attack=2.2, release=2.0, gain=0.16):
    n = int(duration * SR)
    t = np.arange(n) / SR
    env = np.ones(n, dtype=np.float64)
    a = int(attack * SR)
    r = int(release * SR)
    if a > 0:
        env[:a] = np.linspace(0, 1, a) ** 1.6
    if r > 0:
        env[-r:] *= np.linspace(1, 0, r) ** 1.3
    # Soft additive pad: fundamental + octave + a fifth above, detuned slightly.
    sig = (np.sin(2 * math.pi * freq * t)
           + 0.35 * np.sin(2 * math.pi * freq * 2.002 * t)
           + 0.22 * np.sin(2 * math.pi * freq * 1.498 * t)
           + 0.10 * np.sin(2 * math.pi * freq * 3.001 * t))
    return sig * env * gain


def pluck(freq, duration=1.1, gain=0.10):
    n = int(duration * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 4.5)
    sig = (np.sin(2 * math.pi * freq * t)
           + 0.35 * np.sin(2 * math.pi * freq * 2.0 * t)
           + 0.15 * np.sin(2 * math.pi * freq * 3.0 * t))
    return sig * env * gain


def build_theme():
    bar = 4.0
    progression = [
        ("A", 2, ["A", "C", "E", "A"]),
        ("F", 2, ["F", "A", "C", "F"]),
        ("C", 3, ["C", "E", "G", "C"]),
        ("G", 2, ["G", "B", "D", "G"]),
    ]
    total = bar * len(progression) * 2 + 2.0  # two passes + tail
    buf = np.zeros((int(total * SR), 2), dtype=np.float64)
    offset = 0.0
    for _pass in range(2):
        for root, octave, chord in progression:
            base = note_hz(root, octave)
            # Pad: root, third, fifth, octave.  Long attack so chords bloom.
            for interval, note in zip([0.0, 4.0, 7.0, 12.0], chord):
                freq = note_hz(note, octave + (1 if interval == 12.0 else 0))
                voice = pad_voice(freq, bar + 2.4, attack=2.0, release=2.2,
                                  gain=0.085 if interval else 0.12)
                start = int(offset * SR)
                end = min(len(buf), start + len(voice))
                buf[start:end, 0] += voice[:end - start]
                buf[start:end, 1] += voice[:end - start] * 0.96
            # Sparse arpeggio, 8th notes with rests, an octave above the pad.
            pattern = [0, 2, 1, 3, 2, 1, 3, 0]
            for step in range(8):
                if (step + _pass) % 5 == 4:
                    continue
                note = chord[pattern[step]]
                freq = note_hz(note, octave + 2)
                voice = pluck(freq, 1.3, 0.075)
                start = int((offset + step * 0.5 + 0.06) * SR)
                end = min(len(buf), start + len(voice))
                pan = 0.35 + 0.3 * (step % 2)
                buf[start:end, 0] += voice[:end - start] * (1.0 - pan)
                buf[start:end, 1] += voice[:end - start] * pan
            offset += bar
    # Gentle low drone under everything.
    drone = pad_voice(note_hz("A", 1), total, 3.0, 3.0, 0.045)
    buf[:len(drone), 0] += drone
    buf[:len(drone), 1] += drone
    # Crossfade the tail into the head for a seamless loop.
    fade = int(1.6 * SR)
    head = buf[:fade].copy()
    buf[-fade:] = buf[-fade:] * np.linspace(1, 0, fade)[:, None] + \
        head * np.linspace(0, 1, fade)[:, None]
    buf = buf[:-fade]
    # Normalise and apply gentle stereo width.
    peak = float(np.max(np.abs(buf))) or 1.0
    buf *= 0.34 / peak
    return buf


def build_click():
    n = int(0.085 * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 55.0)
    tone = (np.sin(2 * math.pi * 1450 * t) * 0.55
            + np.sin(2 * math.pi * 820 * t) * 0.25)
    thump = np.sin(2 * math.pi * 220 * t) * np.exp(-t * 120.0) * 0.35
    rng = np.random.default_rng(7)
    noise = rng.normal(0, 0.08, n) * np.exp(-t * 150.0)
    sig = (tone + thump + noise) * env
    sig *= 0.35 / max(float(np.max(np.abs(sig))), 1e-6)
    return np.stack([sig, sig], axis=1)


if __name__ == "__main__":
    theme = build_theme()
    write_wav(os.path.join(OUT, "menu_theme.wav"), theme)
    click = build_click()
    write_wav(os.path.join(OUT, "menu_click.wav"), click)
    print("theme", theme.shape, theme.shape[0] / SR, "s")
    print("click", click.shape, click.shape[0] / SR, "s")
