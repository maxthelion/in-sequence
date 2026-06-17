# Lane Coordination

Use this file to summarize the current cross-feature lanes, why each lane
belongs together, and what work or review is needed before it can be shown to
the product owner.

## 2026-05-07T10:09Z

Current durable lanes come from `docs/roadmap/context-pack.md`:

- Track Editor Foundation
- Phrase, Scene, And Song Performance
- Mixer Routing And Sends
- Audio Input, Looping, And Autoslice
- Performance Overrides And Pattern Manipulation
- External Control And Automation

Lane C, Mixer Routing And Sends, already has safe defaults recorded in
`docs/roadmap/lanes/mixer-routing-and-sends.md`: additive solo, global
bus/send inserts, delete confirmation with affected routes, post-blend global
master fader, and manual clip clear. That lane no longer needs product-owner
attention before normal PM/build promotion.

The active cross-lane blocker is process-level, not product-level: the roadmap
supervisor is paused after recursive review-of-review pass generation. Do not
schedule broad lane build promotion until `docs/roadmap/agentic-loop/supervisor-diagnosis.md`
exists and says the loop can safely resume.
