# MIDI Input Routing Follow-Up

`MIDISession.shared.createVirtualInput` currently accepts incoming MIDI before the
phase-2 engine routing exists.

Current status:

- runtime now logs when packets are dropped
- packets are still intentionally discarded until the MIDI-in task lands

Follow-up when Plan 2+ touches MIDI input:

- route the packet list into the engine instead of dropping it
- decide whether the routing boundary lives in `MIDISession`, the engine input
  adapter, or a dedicated MIDI-ingest component
- add a focused integration test for virtual input delivery through the chosen
  path
