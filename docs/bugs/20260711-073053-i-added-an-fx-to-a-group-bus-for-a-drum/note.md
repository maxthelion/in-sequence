I added an fx to a group bus for a drum kit. It stopped audio. Pressing play started audio again. But the level is not showing on the bus, and I don't think the effect is playing. This seems like an audiograph problem. We did a lot of work to make that more robust, but it needs to work in all scenarios.

Status: RESOLVED 56ef102e

Mixer-bus insert topology now mutates only the affected host behind its stable
gain/meter node; the engine, unrelated routes, and bus meter remain live.
