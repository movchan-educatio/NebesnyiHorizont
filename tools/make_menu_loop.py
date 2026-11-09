"""Click-free loop variant of the menu theme.

The authored track ends at full level while the next playthrough starts nearly
silent, so a forward loop produced an audible 32-second "pulse".  Overlap the
tail with the head and shorten the clip by the fade; the loop join then runs
through adjacent samples of the original recording.
"""
import os
import wave

import numpy as np

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\Audio\menu_theme.wav"
DST = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\Audio\menu_theme_loop.wav"
XFADE_SEC = 0.35


def main() -> None:
    with wave.open(SRC, "rb") as w:
        channels = w.getnchannels()
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)
    data = data.astype(np.float32) / 32768.0
    if channels > 1:
        data = data.reshape(-1, channels)
    xf = int(rate * XFADE_SEC)
    head = data[:xf].copy()
    tail = data[len(data) - xf:].copy()
    t = np.linspace(0.0, 1.0, xf, dtype=np.float32)
    if channels > 1:
        t = t[:, None]
    mix = tail * (1.0 - t) + head * t
    out = np.concatenate([mix, data[xf:len(data) - xf]], axis=0)
    out16 = np.clip(out * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(DST, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out16.tobytes())
    print("[MENULOOP]", DST, "sec", round(len(out16) / rate, 2))


if __name__ == "__main__":
    main()
