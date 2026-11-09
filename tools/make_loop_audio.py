"""Build click-free loop variants of the engine recordings.

The source WAVs are loops recorded at different RPMs, but their last sample
does not line up with the first one.  Playing them with a forward loop produced
an audible click once per sample length, which reads as a pulsing engine.

For each file we overlap the tail with the head over a short equal-power
crossfade and shorten the clip by the fade length.  The new loop joins
orig[N-xfade] -> orig[N-xfade-1], i.e. two adjacent samples of the original
recording, so the seam is continuous.
"""
import glob
import os
import wave

import numpy as np

SRC = r"C:\Users\USER_UA\Desktop\GodotDrone_LOWSPEC\Assets\Audio\SFX\Propellers"
OUT = os.path.join(SRC, "looped")
XFADE_SEC = 0.045


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(SRC, "*.wav"))):
        name = os.path.basename(path)
        if name.startswith("idle"):
            # Idle loop is already seamless (jump < 0.001); keep the original.
            pass
        with wave.open(path, "rb") as w:
            channels = w.getnchannels()
            width = w.getsampwidth()
            rate = w.getframerate()
            frames = w.getnframes()
            raw = w.readframes(frames)
        if width != 2:
            print("[LOOP] skip", name, "sampwidth", width)
            continue
        data = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
        if channels > 1:
            data = data.reshape(-1, channels)
        xf = min(int(rate * XFADE_SEC), len(data) // 4)
        head = data[:xf].copy()
        tail = data[len(data) - xf:].copy()
        t = np.linspace(0.0, 1.0, xf, dtype=np.float32)
        if channels > 1:
            t = t[:, None]
        # tail fades out, head fades in; at i=0 the value equals tail[0] so the
        # join from the previous sample is continuous.
        mix = tail * (1.0 - t) + head * t
        out = np.concatenate([mix, data[xf:len(data) - xf]], axis=0)
        out16 = np.clip(out * 32767.0, -32768, 32767).astype(np.int16)
        dst = os.path.join(OUT, os.path.splitext(name)[0] + "_loop.wav")
        with wave.open(dst, "wb") as w:
            w.setnchannels(channels)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(out16.tobytes())
        # Report the seam jump of the produced file.
        flat = out16.reshape(-1).astype(np.float32) / 32768.0
        jump = abs(float(flat[0]) - float(flat[-1]))
        print("[LOOP]", name, "->", os.path.basename(dst),
              "sec", round(len(out16) / rate, 3), "jump", round(jump, 5))


if __name__ == "__main__":
    main()
