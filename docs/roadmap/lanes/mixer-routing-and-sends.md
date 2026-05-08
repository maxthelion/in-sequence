```markdown
# Lane C - Mixer Routing and Sends

Lane complexity: complicated. Mixer Main Out, Mixer Busses, and Send Effects share one audio graph and routing model, so broad build should proceed only with common lane defaults recorded.

Safe assumptions:
- Bus solo defaults to additive DAW-like solo, not exclusive solo.
- Ordinary busses and sends have global inserts unless a later lane explicitly introduces scene-scoped inserts.
- Bus deletion shows a confirmation with affected routes before rerouting anything to master.
- The master fader is global and post-blend.
- Clip indicators clear manually by default.

Next automation move: promote the next Lane C build item using these defaults as the lane contract. Do not ask for separate prototype approval on each mixer feature unless implementation exposes a new product conflict.
```
