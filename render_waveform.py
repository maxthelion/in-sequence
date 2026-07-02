#!/usr/bin/env python3
"""Render a captured bar of drum audio with 16th-note gridlines to check timing.

Usage: render_waveform.py <in.wav> <out.png> [bpm] [steps_per_bar]
Anchors the 16th-note grid to the FIRST detected onset (= step 0) and reports
how far each subsequent onset sits from its nearest grid line.
"""
import sys
import struct
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def read_wav(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:4] == b"RIFF" and data[8:12] == b"WAVE", "not a WAVE file"
    pos = 12
    fmt = None
    samples = None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        csz = struct.unpack_from("<I", data, pos + 4)[0]
        body = data[pos + 8:pos + 8 + csz]
        if cid == b"fmt ":
            audio_format, channels, sample_rate, _, _, bits = struct.unpack_from("<HHIIHH", body, 0)
            fmt = (audio_format, channels, sample_rate, bits)
        elif cid == b"data":
            fmt_code, channels, sample_rate, bits = fmt
            if fmt_code == 3 and bits == 32:      # IEEE float32
                arr = np.frombuffer(body, dtype="<f4")
            elif fmt_code == 1 and bits == 16:    # PCM int16
                arr = np.frombuffer(body, dtype="<i2").astype(np.float32) / 32768.0
            elif fmt_code == 1 and bits == 32:    # PCM int32
                arr = np.frombuffer(body, dtype="<i4").astype(np.float32) / 2147483648.0
            else:
                raise SystemExit(f"unsupported WAV format code={fmt_code} bits={bits}")
            if channels > 1:
                arr = arr.reshape(-1, channels).mean(axis=1)   # mix to mono
            samples = arr
        pos += 8 + csz + (csz & 1)
    return fmt[2], samples


def detect_onsets(x, sr, high_ratio=0.30, low_ratio=0.08, min_gap_s=0.05):
    """Hysteresis onset detection: fire when the envelope rises above a HIGH
    threshold, then re-arm only after it falls below a LOW threshold. One onset
    per hit even on a long decaying voice (e.g. the 808 kick) whose envelope
    ripples — a single rising-edge detector would over-count those ripples."""
    win = max(1, int(sr * 0.003))
    env = np.sqrt(np.convolve(x * x, np.ones(win) / win, mode="same"))
    peak = env.max() if env.size else 0.0
    if peak <= 0:
        return []
    hi, lo = peak * high_ratio, peak * low_ratio
    min_gap = int(sr * min_gap_s)
    onsets, armed, last = [], True, -10 ** 9
    for i in range(len(env)):
        if armed and env[i] > hi and (i - last) >= min_gap:
            onsets.append(i)
            last = i
            armed = False
        elif not armed and env[i] < lo:
            armed = True
    return onsets


def main():
    in_wav, out_png = sys.argv[1], sys.argv[2]
    bpm = float(sys.argv[3]) if len(sys.argv) > 3 else 120.0
    steps_per_bar = int(sys.argv[4]) if len(sys.argv) > 4 else 16

    sr, x = read_wav(in_wav)
    t = np.arange(len(x)) / sr
    seconds_per_step = (60.0 / bpm) * (4.0 / steps_per_bar)   # 16th-note duration

    onsets = detect_onsets(x, sr)
    onset_t = [o / sr for o in onsets]
    t0 = onset_t[0] if onset_t else 0.0   # anchor grid to first hit = step 0

    # Grid lines for one bar of 16th notes from the first onset.
    grid = [t0 + k * seconds_per_step for k in range(steps_per_bar + 1)]

    fig, ax = plt.subplots(figsize=(16, 4.5))
    ax.plot(t, x, lw=0.5, color="#1f77b4")
    for k, g in enumerate(grid):
        ax.axvline(g, color="#d62728", lw=1.0, alpha=0.7)
        ax.text(g, ax.get_ylim()[1] * 0.92, str(k % steps_per_bar),
                color="#d62728", fontsize=8, ha="center")
    for ot in onset_t:
        ax.axvline(ot, color="#2ca02c", lw=0.8, ls="--", alpha=0.6)

    ax.set_xlim(max(0, t0 - 0.03), t0 + steps_per_bar * seconds_per_step + 0.03)
    ax.set_xlabel("seconds")
    ax.set_ylabel("amplitude")
    ax.set_title(f"Default 808 clip — one bar @ {bpm:.0f} BPM  (red = 16th grid, green dashed = detected onset)")
    fig.tight_layout()
    fig.savefig(out_png, dpi=120)

    # Quantitative report: each onset's offset from its nearest grid line.
    print(f"sample_rate={sr}  duration={len(x)/sr:.3f}s  bpm={bpm}  step={seconds_per_step*1000:.2f}ms")
    print(f"onsets_detected={len(onset_t)}  first_onset(step0)={t0:.4f}s")
    print("step  onset_s   nearest_grid  offset_ms")
    worst = 0.0
    for ot in onset_t:
        k = round((ot - t0) / seconds_per_step)
        g = t0 + k * seconds_per_step
        off_ms = (ot - g) * 1000.0
        worst = max(worst, abs(off_ms))
        print(f"{k:>4}  {ot:7.4f}  {g:10.4f}   {off_ms:+7.2f}")
    print(f"worst_abs_offset={worst:.2f}ms")


if __name__ == "__main__":
    main()
