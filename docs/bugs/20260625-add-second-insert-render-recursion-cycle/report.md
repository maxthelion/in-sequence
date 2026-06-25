# Bug: adding a second track insert causes a CoreAudio render recursion (graph cycle)

Found: headless routing-stress rig 2026-06-25 (after the lifecycleLock root-fix).

Op `trackAddInsert=1:native-bitcrusher` (a SECOND native insert on a track that
already has insert-0) hangs. The sample proves it is NOT a lock deadlock: no
thread holds lifecycleLock/graphLock, main is idle in the normal event loop; the
CoreAudio IO render thread is in an UNBOUNDED
`AUGraphMultiBusNode::AllocateInputBlock → renderInputProc → AudioUnitRender`
recursion — i.e. the track-insert-chain splice created a GRAPH CYCLE / feedback
loop when wiring the 2nd insert.

Location: the insert-chain splice in MainAudioGraph.reconnectTrackOutputOnMain /
TrackInsertChainHost (source -> [insert chain] -> chainOutput -> fanout). Adding
a 2nd insert mis-wires into a cycle. Likely interacts with R0's persistent-fanout
rewiring; confirm whether pre-existing (does main hang adding 2 inserts?) or a
regression in the chain/fanout splice.

Evidence: ~/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/routing-stress/
hang-trackAddInsert-1-bitcrusher.sample; reports under .meta/routing-stress/.

Acceptance: add 2+ native inserts on a track during playback — no hang, audio
flows through the full chain in order, no cycle.
