```markdown
# Lane C - Mixer Routing and Sends Supervisor Note

Lane complexity: complicated. Mixer Main Out, Mixer Busses, and Send Effects share the audio graph, routing model, insert semantics, scene A/B mixer state, meters, and clipping behavior, so broad build work should proceed only with lane-level defaults recorded.

Safe assumptions:
- Bus solo defaults to additive solo, matching the safer DAW-like behavior unless the product later explicitly chooses exclusive solo.
- Ordinary busses and sends have global inserts; scene-scoped inserts are out of scope unless added by a later lane decision.
- Bus deletion shows a confirmation with affected routes before rerouting to master.
- The master fader is global and post-blend.
- Clip indicators clear manually by default, not on a timer.

Next automation move: allow PM/build promotion for Lane C items using these defaults. Escalate only if implementation shows these assumptions conflict with the existing audio graph or scene model.
```
