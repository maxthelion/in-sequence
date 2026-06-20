QA capture blocked by mic-permission dialog after every rebuild — root cause + workarounds

## What happens
Running scripts/visual-scenarios/qa-surface-coverage.sh against a freshly-built
app hangs: a modal "SequencerAI would like to access the microphone" dialog
appears, blocks AVAudioEngine init during warm-up, so the app's document window
never finishes loading, the harness `ensure_document_window` gate times out, and
the run fails with "Timed out waiting for a document window; last title was ''."

## Root cause (confirmed 2026-06-20)
1. **Rebuilds re-prompt.** Debug builds are ad-hoc signed ("Sign to Run
   Locally"), so every rebuild produces a new code signature (cdhash). TCC keys
   the mic grant to the signature, so each rebuild is seen as a "new" app and
   re-prompts. We rebuild constantly, so a prior grant never survives.
2. **The 210550 override is installed but insufficient.**
   `VisualScenarioLaunchOverrides.installIfConfigured()` (SequencerAIAppDelegate.swift:123)
   DOES run before warm-up and DOES set
   `MainAudioGraph.simulateAudioInputConnectionForTesting` +
   `liveAudioInputAuthorizedOverrideForTesting` (isConfigured is satisfied via the
   `SEQUENCER_AI_VISUAL_COMMAND_FILE` env the harness exports). But those flags
   only gate whether MainAudioGraph CONNECTS the live input node. The prompt
   fires earlier, from AVAudioEngine IO-unit instantiation during warm-up
   (sampled stack: `mainMixerNode -> GetOutputNode -> GetIOUnit ->
   AudioComponentInstanceNew -> CoreAudio HAL`), a path those flags don't cover.
3. **TCC dialogs cannot be auto-dismissed.** macOS deliberately rejects
   synthetic clicks/keystrokes on permission prompts (peekaboo returns a
   focus-verification TIMEOUT; osascript keystrokes are blocked). So a
   harness-side auto-clicker is not a viable workaround by design.

## Workarounds (ranked)

### A. Durable: stable code signing (recommended for unattended/CI capture)
Sign the debug build with a STABLE identity (a persistent self-signed cert or a
Developer ID) instead of ad-hoc, so the code signature — and therefore the TCC
mic grant — survives rebuilds. Grant once; never prompted again.
- Where: SequencerAI.xcodeproj / project.yml `CODE_SIGN_IDENTITY` (+ a fixed
  signing cert in the keychain).
- Tradeoff: needs a signing cert set up once; doesn't remove the (harmless)
  grant, just makes it persist.

### B. Durable: suppress mic access in automation mode (recommended belt-and-suspenders)
Extend the 210550 override so that when `VisualScenarioCommandRunner.isConfigured`
the app never accesses an input-capable audio unit at all, so macOS never
prompts (no access attempted) regardless of signature. Concretely:
- Skip `warmAudioInstrumentChoices()` in automation mode (the AU-cache warm is a
  perf optimization captures don't need, and it is the sampled prompt source), and
- ensure the document-load audio graph builds output-only (no input element) when
  isConfigured.
- Tradeoff: needs to confirm it covers the document-load path too, and one
  build+run to verify (a correct fix is self-verifying: no prompt appears even on
  the new signature). This is the cleanest fix for fully unattended capture.

### C. Interim: widen the gate + manual Allow (already applied)
qa-surface-coverage.sh `ensure_document_window` deadline was widened 10s -> 45s
so an operator has time to click Allow before the gate expires. After clicking
Allow once, the SAME binary won't re-prompt — so subsequent capture runs work
UNTIL the next rebuild. Requires a human present for the first run after any
rebuild.

## Recommendation
For unattended capture, implement B (no prompt ever) and/or A (grant persists).
C is the operator-present stopgap and is in place now.

## Status
- C applied (gate widened, committed).
- A / B not yet implemented — A is a build-config change, B is an engine change
  needing one verification run.
