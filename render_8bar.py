#!/usr/bin/env python3
"""8-bar full-kit timing under nav load.
usage: render_8bar.py <in.wav> <out.png> <bpm> <bars>
Top: full waveform with bar lines. Bottom: each sharp-transient onset's offset
from the ideal 16th grid over time — spikes = flams / scheduling jitter.
"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import render_waveform as r


def main():
    wav, out = sys.argv[1], sys.argv[2]
    bpm = float(sys.argv[3])
    bars = int(sys.argv[4])
    sr, x = r.read_wav(wav)
    t = np.arange(len(x)) / sr
    sps = (60.0 / bpm) * (4.0 / 16)   # 16th seconds
    barlen = 16 * sps

    # High-pass (first difference) emphasizes SHARP attack edges (hat/snare/clap
    # + kick click) and suppresses the kick's slow low-frequency body, so the
    # onset times reflect the trigger, not the envelope.
    hp = np.diff(x, prepend=x[:1])
    onsets = np.array([o / sr for o in r.detect_onsets(hp, sr, high_ratio=0.18, low_ratio=0.05, min_gap_s=0.035)])
    t0 = onsets[0] if onsets.size else 0.0
    dev_ms = (onsets - t0 - np.round((onsets - t0) / sps) * sps) * 1000.0

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(18, 7), gridspec_kw={"height_ratios": [2, 1]})
    ax1.plot(t, x, lw=0.3, color="#1f77b4")
    for b in range(bars + 1):
        ax1.axvline(t0 + b * barlen, color="#d62728", lw=1.0, alpha=0.6)
        ax1.text(t0 + b * barlen, max(np.max(x), 0.1) * 0.92, f"{b+1}", color="#d62728", fontsize=8)
    ax1.set_xlim(t0 - 0.05, t0 + bars * barlen + 0.25)
    ax1.set_title(f"Full 808 kit — {bars} bars @ {bpm:.0f} BPM, navigating the UI throughout (red = bar lines)")
    ax1.set_ylabel("amplitude")

    ax2.axhline(0, color="#888", lw=0.6)
    for b in range(bars + 1):
        ax2.axvline(t0 + b * barlen, color="#d62728", lw=0.7, alpha=0.3)
    ax2.scatter(onsets, dev_ms, s=10, color="#2ca02c")
    ax2.set_xlim(t0 - 0.05, t0 + bars * barlen + 0.25)
    ax2.set_ylabel("onset offset\nfrom 16th grid (ms)")
    ax2.set_xlabel("seconds")
    worst = float(np.max(np.abs(dev_ms))) if dev_ms.size else 0.0
    rms = float(np.sqrt(np.mean(dev_ms ** 2))) if dev_ms.size else 0.0
    ax2.set_title(f"per-onset timing deviation — worst {worst:.1f} ms, rms {rms:.1f} ms  (spikes = flams under load)")

    fig.tight_layout()
    fig.savefig(out, dpi=110)
    print(f"onsets={onsets.size}  worst={worst:.1f}ms  rms={rms:.1f}ms")


if __name__ == "__main__":
    main()
