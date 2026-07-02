#!/usr/bin/env python3
"""Robust flam analysis for the 8-bar full-kit capture.

Fixes two artifacts of render_8bar.py:
  1. Grid anchored to the FIRST onset (often the masterRender start pop /
     step-0 cold hit) -> anchor instead to the MODE of onset phases.
  2. Single global deviation hides voice populations -> cluster residuals
     and report population centers, sizes, and per-step multi-onset gaps.

usage: flam_analysis.py <in.wav> <bpm>
"""
import sys
import numpy as np
sys.path.insert(0, "/Users/maxwilliams/dev/in-sequence/.worktrees/drum-timing")
import render_waveform as r


def main():
    wav, bpm = sys.argv[1], float(sys.argv[2])
    sr, x = r.read_wav(wav)
    sps = (60.0 / bpm) * (4.0 / 16)

    hp = np.diff(x, prepend=x[:1])
    # Lower min_gap than render_8bar (35ms) so close flam pairs stay separate.
    onsets = np.array([o / sr for o in r.detect_onsets(hp, sr, high_ratio=0.18,
                                                       low_ratio=0.05,
                                                       min_gap_s=0.012)])
    if onsets.size < 8:
        print(f"too few onsets: {onsets.size}")
        return

    # Phase of each onset within the 16th grid (unknown anchor).
    phases = np.mod(onsets, sps)
    # Circular mode via histogram (1 ms bins) -> dominant population anchor.
    bins = np.arange(0, sps + 0.001, 0.001)
    hist, edges = np.histogram(phases, bins=bins)
    anchor = edges[np.argmax(hist)] + 0.0005

    # Residual of each onset vs the dominant-population grid, wrapped to +-sps/2.
    res = np.mod(onsets - anchor + sps / 2, sps) - sps / 2
    res_ms = res * 1000.0

    print(f"onsets={onsets.size}  anchor_phase={anchor*1000:.1f}ms  step={sps*1000:.1f}ms")

    # Population clustering: 3ms-resolution histogram of residuals.
    hbins = np.arange(-sps * 500, sps * 500 + 3, 3.0)  # ms
    h, he = np.histogram(res_ms, bins=hbins)
    print("\nresidual populations (3ms bins with >=3 onsets):")
    for i, c in enumerate(h):
        if c >= 3:
            print(f"  {he[i]:+7.1f}..{he[i+1]:+7.1f} ms : {c:3d} onsets")

    # Main population stats (within +-10ms of 0 after anchoring).
    main = res_ms[np.abs(res_ms) <= 10.0]
    out = res_ms[np.abs(res_ms) > 10.0]
    print(f"\nmain population: n={main.size}  worst={np.max(np.abs(main)) if main.size else 0:.2f}ms  "
          f"rms={np.sqrt(np.mean(main**2)) if main.size else 0:.2f}ms")
    print(f"outside +-10ms: n={out.size}")
    if out.size:
        print("  outlier residuals (ms):", " ".join(f"{v:+.1f}" for v in sorted(out)))
        # Where in time do outliers fall (first 2s = start-up vs steady)?
        out_times = onsets[np.abs(res_ms) > 10.0]
        print("  outlier times (s):     ", " ".join(f"{v:.2f}" for v in sorted(out_times)))

    # Per-step pair analysis: onsets landing on the SAME grid step but split
    # by >5ms = flam pair candidates (visible only if detector separates them).
    steps = np.round((onsets - anchor) / sps).astype(int)
    print("\nsame-step onset pairs (potential flams, gap in ms):")
    found = False
    for s in np.unique(steps):
        group = np.sort(onsets[steps == s])
        if group.size > 1:
            gaps = np.diff(group) * 1000.0
            for g in gaps:
                if g > 5.0:
                    found = True
                    print(f"  step {s:4d} @ {group[0]:7.3f}s : gap {g:.1f}ms")
    if not found:
        print("  none > 5ms")


if __name__ == "__main__":
    main()
