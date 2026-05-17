# Send Effects Phase 3 Mixer UI Evidence

Captured from the production macOS app on the `auto/roadmap-6-send-effects`
worktree after the Phase 3 mixer UI implementation.

- `send-effects-empty-buses.png` shows the shared mixer with per-track `A` and
  `B` send controls at zero plus fixed `Send A` and `Send B` detail surfaces
  in their explicit empty-chain state.
- `send-effects-nonzero-and-inserts.png` shows non-zero `Send A` and `Send B`
  controls on the selected track, plus populated `Send A` and `Send B` insert
  chains using the shared insert semantics.

The screenshots were driven through `VisualScenarioCommandRunner` so the
captured document state uses authored track-mix send values and authored
send-bus insert mutations rather than mock UI state.
