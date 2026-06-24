# Routing Stress Report

- Date: 2026-06-24T17:08:39Z
- App: /Users/maxwilliams/Library/Developer/Xcode/DerivedData/SequencerAI-eqtzejtdpfgahvcbigxlxtvgqtjf/Build/Products/Debug/SequencerAI.app/Contents/MacOS/SequencerAI
- Fixture: audio-rich-routing-sampleonly.seqai (sample-only)
- Mode: offline manual-rendering (HAL suppressed) + offline-render pump
- Op settle: 2s

| # | op | result | masterPeak |
|---|----|--------|------------|
| 0 | transport=play | PASS | -9.480646511202504 |
| 1 | workspace=tracks | PASS | -10.207584562883273 |
| 2 | masterGain=0.5 | PASS | -20.089207989850244 |
| 3 | masterGain=1.5 | PASS | -3.7382185936755614 |
| 4 | masterGain=1 | PASS | -6.807116872338878 |
| 5 | sendAInserts=filter | PASS | -4.486798114810616 |
| 6 | sendBInserts=filter | PASS | -7.0743726080215215 |
| 7 | sendA=filter,bitcrusher | PASS | -5.388383229643674 |
| 8 | sendInserts=cleared | PASS | -0.9512704866808381 |
| 9 | addTrack=monoMelodic | PASS | -2.5998128555883357 |
| 10 | addTrack=polyMelodic | PASS | -1.9373873103967425 |
| 11 | addTrack=slice | PASS | -1.9373873103967425 |
| 12 | scenesMode=browseEdit | **HANG** | stale 4s |

## HANG after op 12 (scenesMode=browseEdit) — status file stale 4s (pid alive)
App stderr tail:
```
2026-06-24 18:08:38.910 SequencerAI[25714:17229592] [SequencerAIAppDelegate] launch version=0.0.1 build=1 gitCommit=unknown gitBranch=unknown gitDirty=unknown attributionID=unknown attributionVersion=unknown
2026-06-24 18:08:38.910 SequencerAI[25714:17229592] [U2] SequencerAIAppDelegate: beginWarmingIfNeeded
2026-06-24 18:08:38.990 SequencerAI[25714:17229592] [VisualFixtureDocumentLoader] materialized audio-rich fixture samples into /Users/maxwilliams/Library/Containers/ai.sequencer.SequencerAI/Data/Library/Application Support/sequencer-ai/samples
2026-06-24 18:08:39.038 SequencerAI[25714:17229592] [MainAudioGraph] manual-rendering (offline) ENABLED for automation — HAL IO unit suppressed
2026-06-24 18:08:39.303 SequencerAI[25714:17229592] [MainAudioGraph] manual-rendering (offline) ENABLED for automation — HAL IO unit suppressed
2026-06-24 18:08:39.428 SequencerAI[25714:17229592] [VisualScenarioCommandRunner] watching command file /Users/maxwilliams/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/sequencer-ai-visual-commands/routing-stress-cmd.env
2026-06-24 18:08:39.830 SequencerAI[25714:17229592] +[IMKClient subclass]: chose IMKClient_Modern
2026-06-24 18:08:39.830 SequencerAI[25714:17229592] +[IMKInputSession subclass]: chose IMKInputSession_Modern
2026-06-24 18:09:00.414 SequencerAI[25714:17229592] [StepGridTap] t=541363.560830 contentPropChangedFromStore noteGrid length=32 notes=12
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574340 step=16 cellStateChanged on->off
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574410 step=13 cellStateChanged on->off
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574426 step=11 cellStateChanged on->off
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574440 step=8 cellStateChanged on->off
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574453 step=5 cellStateChanged on->off
2026-06-24 18:09:00.428 SequencerAI[25714:17229592] [StepGridTap] t=541363.574480 step=3 cellStateChanged on->off
2026-06-24 18:09:02.614 SequencerAI[25714:17229592] [StepGridTap] t=541365.760489 contentPropChangedFromStore sliceTriggers length=16 active=0
```

## Summary

- PASS: 12
- SILENCE: 0
- CRASH: 0
- HANG: 1
- Run aborted at first crash/hang.

## Command-vocab gaps (block fuller coverage; NOT implemented here)

- per-track native insert add/remove (only send-bus inserts have a key)
- routeTrackToBus (assign a track output to a specific mixer bus)
- send routing mode A / A+B / B selection per track
- remove-track / remove-bus
