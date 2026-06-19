# Drum Kits Route To Their Own Bus By Default

Raw product-owner clarification:

> It might also be worth having drumkits go into a new bus by default, rather
> than going straight to master. That allows fx on all of them.

Interpretation for build:

- A new drum group's default destination is a **dedicated bus** (named after the
  kit), not Master.
- Because inserts live on buses, the kit bus is what enables **FX across the
  whole kit** — the kit-level FX tab is the insert chain on this bus.
- The kit bus is the kit's single mixer strip and the routing target the
  collapsed-kit cell points at.
- Surfaced as the default in the Add Drum Group routing step; Master remains a
  non-default option.
</content>
