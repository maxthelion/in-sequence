when I add a new drum track and select a new bus as the output, no sound plays. It does play if i goes to master.

---
RESOLVED 2026-06-22: root cause — MainAudioGraph.installMixerBuses rebuilt bus hosts but never re-wired tracks already routed to those buses (installSendBuses did; installMixerBuses did not), so a track routed to a freshly-created bus fell back to preMaster and the bus->master chain was never made. Fix: reconnect bus-routed track outputs after the host-install loop (mirrors installSendBuses), on main under graphLock, no render-path work.
VERIFIED (functional, behavioural) — independent re-run of MixerBusRoutingReconnectTests: 2/2 PASS in 0.06s; the topology test FAILS when the fix is reverted (non-vacuous); regressions MainAudioGraphTests 17/17 + SequencerDocumentSessionMasterBusTests 18/18 green.
