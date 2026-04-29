# Roadmap Intent Log

This file preserves the user's raw input for roadmap planning before it is normalized into item IDs, front matter, notes, stories, specs, or plans.

## 2026-04-29 - Roadmap Working Process

Raw input:

```text
I want to plan the roadmap a bit. There are several areas that need building out. In many cases, the underlying model is correct, but the UX doesn't work. Make a note of the whole list, and then let's work through various steps for each. Ideally, we can have workers doing some of the steps while we're still discussing. First, I want you to ask me to clarify briefly what needs to be addressed in relation to the feature. Then I want you to draw up some user stories that describe the goals people will want to achieve. Then you need to look at what exists and report back about how it differs. Then you'll build a few prototypes. I'll give you some instructions for that. You'll look at the prototypes and see whether they constitute a good user experience. You will use a UX checklist with things like progressive disclosure, not repeating information, grouping interactions that form a similar part of the flow etc. After that, we'll spec the feature out and have it built. Put this plan in the docs directory as "working through a roadmap". 
```

## 2026-04-29 - HTML Prototype Guidelines

Raw input:

```text
HTML prototype guidelines (Balsamiq-style)
Aesthetic

Monochrome base — greyscale for all structural elements (text, borders, backgrounds, dividers)
System font stack only (no custom typography); a single sans-serif is fine
Hand-drawn or sketchy feel optional but helpful — it telegraphs "not production"
No shadows, gradients, rounded corners beyond minimal, or decorative flourishes
Generous whitespace; don't compress to look "designed"

Semantic color (the only color)

One accent for primary/interactive elements
Reserved roles: hover, focus, selected, disabled, error, success, "new/changed"
Six or seven semantic colors maximum, each used consistently across the prototype
Color encodes state, never brand or hierarchy

Stub treatment for off-path elements

Dashed borders, hatched fills, or greyed-out text for anything not under test
Placeholder labels like "→ [settings]" or "[user menu]" rather than fully realized UI
Stubs should be unmistakable — reviewers shouldn't waste attention on them
Click handlers on stubs can console.log or show a toast saying "stubbed"

Information architecture first

Decide screens, regions, transitions, and hierarchy before drawing
One primary action per screen; secondary actions visibly subordinate
Consistent location for navigation, status, and primary action across screens
Progressive disclosure — don't show what isn't needed yet
Group related things by proximity; separate unrelated things

Behavioral fidelity over visual fidelity

Real interactions on the path under test (clicks change state, forms validate, transitions happen)
Loading, empty, error, and partial states all reachable
Reversibility where it matters (undo, cancel, back)
Stub everything off-path; don't fake interactivity you haven't thought through

Fixture data

Opinionated and adversarial — long names, empty lists, 400-item lists, weird states, diacritics, edge cases
Avoid bland Lorem Ipsum; use data that surfaces hard cases
Same fixtures across variants so comparisons are fair

Interaction budget

State the budget explicitly ("primary goal in ≤2 interactions")
Annotate the actual click-path so it's verifiable
Don't hide complexity behind misleading affordances to meet the budget

Scope discipline

Detail on the path under test; stubs everywhere else
Adjacent screens (entry and exit) shown enough to ground the flow
Resist the urge to "complete" the prototype — incompleteness is a feature

Technical

Single HTML file where possible; inline CSS and JS
No build step, no framework gravity, no design system imports
Tailwind via CDN is fine; vanilla CSS is finer
Keep it forkable — someone should be able to copy the file and diverge in 30 seconds

The test

Could a reviewer mistake this for a production proposal? If yes, it's too polished
Are differences between variants strategic or cosmetic? Only strategic differences are worth showing
Can someone tell what's stubbed without being told? They should be able to
```

## 2026-04-29 - Roadmap Feature List

Raw input:

```text
Clip history
Scene perform
Step sequencer
Mixer main out
Mixer busses
Send effects
Input audio
Midi interfaces
Modifier chain placement 
Phrase features- length etc
Interaction between song mode and looping a phrase
Making drum parts feel part of a group
Autoslice algorithm 
Audio loopin
Note repeat
Step order
Fill a clip from current generator 
Toggle fill on a track to hear it
Drum kit group view
Fill applied to whole kit?
```

## 2026-04-29 - Per-Feature Directories

Raw input:

```text
Let's keep a directory for each one with the spec, prototypes etc together
```

## 2026-04-29 - PM Mode And Automation

Raw input:

```text
i want to work with you as a project manager. We won't build anything. That means that we should revisit the behaviour tree and add automation. Ideally, we can create a deterministic script that looks at the stuff on the backlog and identiifies the likely next action for each. create an experimental one here now.
```

## 2026-04-29 - Integer IDs And Metadata

Raw input:

```text
let's use integers for each item id. So we can reference. And add some front matter with meta status like blocked by, priority etc
```

## 2026-04-29 - Intent Log

Raw input:

```text
Also keep an intent file with my raw input. So we can look back later
```

## 2026-04-29 - Observability Backlog Item

Raw input:

```text
add an item to the backlog about observability. Essentially, I'd like a running script that looks at our application logs and creates issues for them. Ideally, it knows which commit an issue came from, so a sweeper agent can fix stuff or leave it to the active worker. You might need to think through the logic of this a bit more
```

## 2026-04-29 - Background User Story Pass

Raw input:

```text
ok, so ideally, an agent can do a first pass at user stories in the background as part of the behaviour tree. They should also be able to mark it as blocked on open questions to me if they don't have enough to go on
```

## 2026-04-29 - PM Assistant Role

Raw input:

```text
Maybe we add a pm assistant role to the behaviour tree so that they can get on with this stuff. 
```

## 2026-04-29 - Separate PM And Implementation Elves

Raw input:

```text
Yes, I think that's it. We might have other elves that do actual work if it's been specced out, but they'd be on a different loop, with different permissions
```

## 2026-04-29 - Mixer Reference Artifact

Raw input:

```text
add this as an artefact to the item about the mixer

[User provided an embedded screenshot of a dark mixer interface with multiple input/channel strips, pan controls, mono/stereo labels, solo/mute controls, long vertical faders/meters, lower gain controls, and a right-hand MASTER MIX panel containing a master meter plus bus/group rows such as "octa ab", "pedals?", "octa cd", and "Samplers".]
```

## 2026-04-29 - End-Of-Response Attention Checks

Raw input:

```text
going back to the session start hook, I'm not sure that's the right place. Eg I'd like you to tell me that there are some items needing attention when you finish responding
```

## 2026-04-29 - Start Clarifying Roadmap Items

Raw input:

```text
ok, let's start clarifying some of the other items
```

## 2026-04-29 - Roadmap PM Automation

Raw input:

```text
ok, but can you set up an automation so that the work is done automatically, rather than orchestrating yourself
```

## 2026-04-29 - Separate User And Agent Next Items

Raw input:

```text
There needs to be separate next items for you and for the agent.
```

## 2026-04-29 - Roadmap PM Automation Cadence

Raw input:

```text
I set it to 10 mins
```

## 2026-04-29 - Clip History Clarification

Raw input:

```text
ok, so with clip history, the idea is that you can have a generator running for a track, but you might want more predictability, or you might hear something that was really nice and want to capture it. There should be a button on the generator view that opens a modal. It should have a screen showing the notes that have been generated by the chain, going back 16 bars. Playback switches to a virtual clip of the historical output over a single bar. The length of the clip should be modifiable. The patterns of the track should be shown at the bottom as a "save to pattern slot". This creates a new clip in that slot.
```

## 2026-04-29 - Deterministic Clarification Capture

Raw input:

```text
that took you a little while. Perhaps make it more deterministic with scripts. 
```

## 2026-04-29 - Clarification Before Capture

Raw input:

```text
If you think that my intention is too vague to leave to the assistant, don't use the script, ask clarifying questions etc
```

## 2026-04-29 - Scenes In Phrases Backlog Item

Raw input:

```text
There's a separate need to address scenes in phrases. Is that captured as another item?
```

## 2026-04-29 - Scene Perform Clarification

Raw input:

```text
the cross fader is a bit too wide. The UI should probably be 3 cells side by side, with the fader in between the scene cells. There's a separate need to address scenes in phrases. Is that captured as another item?
```

## 2026-04-29 - Step Sequencer Clarification

Raw input:

```text
Re item 3, there are a number of different views that contain a step sequencer. There are different things that can be done in each. But fundamentally, they need to be using similar UI primitives. Whether we are toggling a step on or off, setting a value for it, or choosing an option, it should be all contained in the same UI area. A step needs to combine various pieces of information: whether it is playing now, whether it is selected, whether it is active, and its current value for a given layer. If a step is selected (maybe right click), we could potentially make the macro/layer cells above it editable with their own suitable controls. More than one step could be edited. If steps are selected, we could have some controls underneath for clear, copy, paste etc.
```

## 2026-04-29 - Mixer Main Out Clarification

Raw input:

```text
The mixer should be separated into sections, individual tracks, busses (incl. sends), and master out. The master out should allow adding insert effects. We should have proper decibel meters indicating clipping. It should show scene a and b with the crossfader.
```

## 2026-04-29 - Mixer Busses Clarification

Raw input:

```text
For item 5, we should have a button to add a new bus. There should be a selector at the bottom of tracks to route their output to the bus
```

## 2026-04-29 - Send Effects Clarification

Raw input:

```text
re 6, let's just have 2 default busses for send a and b. Other tracks can route part of their output to them. Effects can be added as inserts.
```

## 2026-04-29 - Mixer Busses Clarification

Raw input:

```text
the other busses should allow inserts too
```

## 2026-04-29 - Input Audio Clarification

Raw input:

```text
Re input audio, we should be able to edit our preferences and select an audio interface. We should be able to create an audio track that takes the input and sends it into the mixer. Additionally, we should be able to record the input to a record buffer. On its track page, there should be an option to switch between the input coming in, and the recorded loop. It should be possible to schedule a record trigger, like the octotrack does. It should share some similarity with the slicer track UI - with a waveform. When recording, the length should default to 1, 2, 4, 8 bars.
```
