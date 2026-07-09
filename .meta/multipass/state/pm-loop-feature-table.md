# PM Loop Feature Table

- updated: 2026-06-05T01:56Z
- source: restored PM/build manifests, durable summaries, current lifecycle
  evidence, and current merge evidence after Track Fill stash authority repair.
- note: roadmap README metadata still lags several landed features; this table
  reconciles against loop manifests and durable state where those disagree.

| Feature | Intent | Current Status |
| --- | --- | --- |
| Clip History | Turn recent generated/captured material into explicit arrangement material via frozen history source selection, preview, destination-slot choice, and replace confirmation. | Complete and contained in `main`; terminal build loop with historical blocked residue only. |
| Scene Perform | Let performers prepare and execute scene A/B performance overrides for live macro/control changes. | Complete and contained in `main`; terminal build loop, with dirty worktree residue classified as process hygiene. |
| Step Sequencer | Replace fragmented step-cell editing with a unified step cell, transient multi-step selection, batch edits, rotary layer controls, slicer/macro/chord support, and non-persisted clipboard/selection state. | Complete and contained in `main`; terminal build loop with historical blocked residue only. |
| Mixer Main Out | Add a master output strip with crossfade/output control, post-blend FX ownership, metering, clipping indication, and coherent mixer placement. | Complete and merged to `main`; reopen only for new feedback. |
| Mixer Busses | Add bus/group routing and bus strips so tracks can route through intermediate mixer destinations before master. | Complete and contained in `main`; terminal build loop. |
| Send Effects | Add authored Send A/B return paths, engine send topology, send controls, and send-bus insert UI. | Complete and merged to `main`; reopen only for new feedback. |
| Input Audio | Capture and route external/input audio into the app's sequencing/performance workflows. | Complete and contained in `main`; PM and build loops terminal. |
| MIDI Interfaces | Support MIDI/control-surface interaction across settings, phrase workspace, and live workspace. | Locked build loop awaiting hands-on Launchpad Mini MK3 hardware acceptance or explicit accepted limitation; not an unpromoted PM candidate. |
| Modifier Chain Placement | Place source, modifier, and clip history controls in slot-scoped tab/well UI so the source chain and post-source modifiers are clear. | Complete and merged to `main`; older branches are stale process history. |
| Phrase Features | Expand phrase-level arrangement/performance capabilities. | PM handoff consumed by the 2026-06-05T01:29Z project promotion; active build loop `build/phrase-features` owns implementation on branch `auto/roadmap-10-phrase-features` in `.worktrees/roadmap-10-phrase-features`. |
| Song Mode And Phrase Looping | Support song-mode structure and phrase looping behavior. | Complete and contained in `main`; PM and build loops consumed/terminal, with transient terminal PM cadence residue emitted during repair. |
| Drum Parts As A Group | Treat drum-kit parts as coordinated group material with shared pattern/step relationships. | Complete and locally integrated on `main` at `472583cf1fed30a085a19ead5fa5d581de12ffc7`; PM and build loops consumed/terminal, with historical blocked residue only. |
| Autoslice Algorithm | Improve automatic slicing of audio into musically useful regions. | Phase 0 complete and locally merged on `main`; PM handoff consumed by `build/autoslice-algorithm`. Future slicer UI/audition integration needs fresh scope. |
| Audio Looping | Support audio looping workflows. | Locked PM loop on product-owner scope choice: one loop-capable Input Audio track now, or wait for plural/shared input looping. |
| Note Repeat | Add note-repeat performance/editing behavior. | Inventory / architecture stage; not ready for build. |
| Step Order | Allow alternate or controllable step playback order. | Inventory / architecture stage; not ready for build. |
| Fill A Clip From Current Generator | Commit current generator output into a clip. | Folded/closed into Clip History / History by overlap disposition; not an independent PM/build candidate. |
| Track Fill Toggle | Let a performer toggle fill behavior on a track to hear it. | Complete and contained in `main`; PM and build loops consumed/terminal, with transient terminal PM cadence residue emitted during repair. |
| Drum Kit Group View | Show and manage drum kit parts as a grouped view. | Deferred; covered by Drum Parts As A Group for now. |
| Fill Applied To Whole Kit | Apply fill behavior across a whole kit rather than one part. | Deferred until grouped drum-part model is clearer. |
| Observability From Application Logs | Use application logs to surface runtime/build issues for observers and process health. | Inventory / prototype-review stage; not ready for build. |
| Scenes In Phrases | Represent scene changes or scene rails inside phrase workflows. | Inventory / prototype-review stage; selected prototype needs human approval before architecture work. |
| Phrase Cells | Isolate phrase-cell behavior and UX as its own area. | Deferred until reactivated. |
| Track Perform Multi-Select And Latch | Add multi-select/latch behavior to track performance controls. | Complete and contained in `main`; PM and build loops terminal. |
| Selective Scene Inputs | Let master scenes include/exclude selected source inputs. | Deferred; separated from v1 mixer/main-out scope. |
| July 4 Phrase Layers / Global Apply | Repair the July 4 owner-feedback cluster for phrase layer matrix borders, in-place layer selector replacement, Global Apply cell heights, and compact All/Clear controls. | Active PM lane `pm/july-4-phrase-layers-global-apply`; not builder-ready until PM artifact authoring produces a handoff or lock. |
| Track Setup Surface Compression | Compress track setup headers and clip-header controls while improving slicer/sample-player visual economy for bug-intake G7 plus the fresh capture-backed clip-header report. | Active PM lane `pm/track-setup-surface-compression`; initial artifact-author request routed, not builder-ready and not promoted to a build loop. |
