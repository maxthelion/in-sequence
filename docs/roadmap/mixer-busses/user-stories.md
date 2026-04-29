# Mixer Busses User Stories

## Stories

### 1. Create a new bus

- **As a:** producer arranging a multi-track session
- **I want:** a button in the mixer that adds a new bus channel
- **So that:** I can group related tracks (e.g. all drums, all synths) for collective processing without affecting the master out
- **Done when:** pressing "Add Bus" creates a named bus strip in the mixer, visible in the busses section, ready to receive routed tracks

### 2. Route a track's output to a bus

- **As a:** producer mixing individual tracks
- **I want:** a routing selector at the bottom of each track strip that lets me choose which bus (or the master out) to send that track's output to
- **So that:** I can consolidate multiple tracks under a single bus fader and process them together
- **Done when:** selecting a bus from the per-track output selector causes that track's audio to flow into the chosen bus rather than directly to the master

### 3. Control a bus with its own fader, pan, mute, and solo

- **As a:** mixer working a live or studio session
- **I want:** each bus to have its own fader, pan knob, mute button, and solo button
- **So that:** I can ride the level of an entire group, pan it in the stereo field, silence it temporarily, or solo it for checking without touching individual tracks
- **Done when:** adjusting bus fader, pan, mute, or solo affects only the tracks routed to that bus and the result is audible in real time

### 4. Insert plugins on a bus

- **As a:** producer wanting group compression or EQ on a bus
- **I want:** an insert effects chain on each bus strip, similar to what's available on individual tracks
- **So that:** I can apply compression, EQ, saturation, or other processing to a whole group of tracks at once
- **Done when:** opening a bus's insert chain lets me add, reorder, bypass, and remove plugin inserts, and the inserted effects are applied to the summed signal of all tracks routed to that bus

### 5. Name and identify buses distinctly

- **As a:** producer managing a session with several buses
- **I want:** to give each bus a custom name and optionally a colour
- **So that:** I can quickly identify which bus corresponds to which group (e.g. "Drums Bus", "Synths Bus") at a glance
- **Done when:** double-clicking a bus name allows inline renaming, and the name persists with the session

## Acceptance Signals

- Adding a bus produces a visible strip in the mixer's busses section within the same interaction
- A track's routing selector lists all current buses by name plus a "Master" option; changing selection is reflected immediately in the mixer signal flow
- Bus fader, pan, mute, and solo controls respond in real time and their state is saved and restored with the session
- Bus inserts open the same insert chain UI used on track strips; effects process the grouped signal audibly
- Renamed buses update everywhere they are referenced (track routing selectors, mixer strip labels)

## Assumptions

- Buses are stereo by default; mono or surround support is out of scope for this item
- A track can route to exactly one bus (or master) at a time — parallel routing or multiple outputs are out of scope here and may belong to a future item or the Send Effects item (6)
- Bus creation, routing UI, and strip controls are confined to the mixer view; arrangement/clip-level representation of buses is not in scope
- The insert chain on buses is the same component used on individual tracks — no new insert-chain implementation is expected, only reuse
- Master out strip behaviour, master inserts, and the inline crossfader are handled by Mixer Main Out (item 4) and must not be duplicated here
- Send FX routing (item 6) is a separate concern; the routing selector on tracks exposes buses only, not send-FX returns
