The tracks interface for routing is confusing because it collapses two separate
concepts into one flow:

1. The track's sound source / current destination, such as an instrument or
   "no instrument".
2. The mixer and effects route, such as output bus, sends, inserts, and master
   routing.

The current UI presents an `Instrument -> Destination` summary and then also
shows a `Destination & Sends` panel. This makes "destination" do too many jobs:
it reads partly as the sound generator, partly as the mixer target, and partly
as a bus/send editor. The empty-state also says `Add Destination`, when the
likely action is sometimes "add a sound source" and sometimes "change mixer
route".

Desired direction:

- Split the UI into two clearly labelled parts.
- Use a left/right layout with two wells if it fits the page:
  - Left well: sound source / current destination / instrument. This owns
    source selection, no-instrument empty state, instrument preset where
    relevant, and source-specific controls.
  - Right well: mixer and FX. This owns output bus, sends, insert effects,
    master/scene routing, and mixer-route status.
- Avoid a single `Instrument -> Destination` row that implies the sound source
  and mixer route are one object.
- Avoid duplicated route summaries. If the right well shows `Master`, the top
  routing chip should not repeat the same fact without adding meaning.
- Empty states should name the missing thing precisely: `Add Sound Source`,
  `Choose Output`, `Add Insert FX`, etc.

Useful acceptance check:

- With no instrument selected, the sound-source well is visibly empty and offers
  a source action, while the mixer/FX well still shows the current output route.
- With an instrument selected, instrument-specific editing stays in the
  sound-source well, and sends/output/insert FX stay in the mixer/FX well.
- A reviewer can explain where sound is made and where sound is routed without
  relying on the word "destination" to mean both.
