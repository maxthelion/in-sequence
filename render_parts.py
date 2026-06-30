#!/usr/bin/env python3
"""Per-part 808 timing: one stacked row per soloed part, each with the 16th grid.

usage: render_parts.py <out.png> <bpm> <label=wav> ...
Each row anchors the 16th grid to that part's FIRST onset and reports how evenly
spaced the part's onsets are (jitter) and their offset from the grid.
"""
import sys
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import render_waveform as r


def main():
    out = sys.argv[1]
    bpm = float(sys.argv[2])
    parts = [(a.split("=", 1)[0], a.split("=", 1)[1]) for a in sys.argv[3:]]
    sps = (60.0 / bpm) * (4.0 / 16)   # 16th-note seconds

    fig, axes = plt.subplots(len(parts), 1, figsize=(16, 2.3 * len(parts)), squeeze=False)
    axes = axes[:, 0]
    for ax, (label, wav) in zip(axes, parts):
        sr, x = r.read_wav(wav)
        t = np.arange(len(x)) / sr
        peak = float(np.max(np.abs(x))) if len(x) else 0.0
        onsets = [o / sr for o in r.detect_onsets(x, sr)]
        t0 = onsets[0] if onsets else 0.0

        ax.plot(t, x, lw=0.5, color="#1f77b4")
        for k in range(17):
            ax.axvline(t0 + k * sps, color="#d62728", lw=0.8, alpha=0.55)
        for ot in onsets:
            ax.axvline(ot, color="#2ca02c", lw=0.8, ls="--", alpha=0.6)
        ax.set_xlim(t0 - 0.04, t0 + 16 * sps + 0.04)
        ax.set_ylabel(label, rotation=0, ha="right", va="center", fontsize=11)
        ax.set_yticks([])

        # Report: offset of each onset from its nearest grid line + spacing.
        offs = [(ot - t0 - round((ot - t0) / sps) * sps) * 1000.0 for ot in onsets]
        worst = max((abs(o) for o in offs), default=0.0)
        gaps = np.diff(onsets) if len(onsets) > 1 else np.array([])
        gap_ms = f"{gaps.mean()*1000:.1f}±{gaps.std()*1000:.1f}" if gaps.size else "—"
        print(f"{label:6} onsets={len(onsets):2}  peak={peak:.2f}  worst_off={worst:5.1f}ms  gap_ms={gap_ms}")
        ax.text(0.005, 0.95, f"{label}: {len(onsets)} onsets, worst {worst:.0f}ms off grid",
                transform=ax.transAxes, va="top", fontsize=8, color="#444")

    axes[-1].set_xlabel("seconds")
    fig.suptitle(f"Per-part 808 timing @ {bpm:.0f} BPM  —  red = 16th grid (anchored to each part's 1st onset), green dashed = onset")
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    print(f"PNG={out}")


if __name__ == "__main__":
    main()
