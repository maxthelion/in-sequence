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

## 2026-04-29 - MIDI Interfaces Clarification

Raw input:

```text
Re item 8 - there might already be a plan for it elsewhere. Essentially, we need a way for midi interfaces to control stuff in a view. Ideally, what we receive from the controller doesn't change, we just route it to different stuff in the ui based on the state. So if we are on live track perform mode, it would have the colours of the tracks and their toggle states.
```

## 2026-04-29 - Modifier Chain Placement Clarification

Raw input:

```text
Re item 9. The track UI is a bit confusing re source and modifiers. I'd like it to be a bit like source and modifier slots are tabs. In each, there is a sort of UI well/holder that can contain an item. For the source, this would be either a clip, or a generator. The model should be that the current source can be removed, making a plus button for adding a new source (rather than the current "switch to generator source"). The options when the source is empty should be add new blank clip, select clip from pool, new blank generator, select generator. This UI needs to be quick, the most likely flow is that the track starts with a clip, and the user wants to remove it for a generator. Selecting other options should be the progressive disclosure. Maybe we have a modal for those options, ideally it stays within the same screen. Similar treatment for the modifiers well.
```

## 2026-04-29 - Phrase Features Clarification

Raw input:

```text
There are a couple of things to add. In the phrase button (Phrase A), there should be controls for setting how many bars a phrase should be, and how many times it repeats. There should also be a button for playing a phrase on a permanent loop. This is essentially what the free mode vs song mode is. Then performance modes use the phrase as a baseline and can potentially save back into it. Also the arrows for switching pages of tracks should be in the top left and right corners of the matrix, as cells either side of the track names with some indication of whether there are actually tracks in the next page. The layer selector should be more central and aligned with the grid. It shouldn't change horizontal width with different layers.
```

## 2026-04-29 - Phrase Cells Backlog Split

Raw input:

```text
There's another bunch of stuff to capture about phrase cells. Make that a separate item that we can get to later.
```

## 2026-04-29 - Song Mode And Phrase Looping Clarification

Raw input:

```text
Re item 11, I kind of described it in the last item about the phrase grid. Perhaps the only other addition would be that when we are in free play mode, the bar at the top should show the current playing phrase. It should also have a button that allows cueing up a next phrase for when this cycle finishes. This can open a dropdown for now. There should be a button on each option to switch immediately.
```

## 2026-04-29 - Song Mode And Phrase Looping Clarification

Raw input:

```text
This also changes the "basis phrase" on the tracks UI. When the current/cued phrase changes in free play or phrase looping, the Tracks UI basis phrase should update to reflect that phrase.
```

## 2026-04-29 - Drum Parts As A Group Clarification

Raw input:

```text
At the moment, the individual drum tracks seem to have no relation to each other. At the top of the pages, there should be an option to shift left or right through the parts within a drum track, and a button to open a view for the drum track itself. This will need some prototyping. Essentially it would be good to have a view of all the steps for each of the parts as a matrix with the name of the part on the left. Otherwise it's hard to visualise what all the steps are doing. The wrinkle is that patterns are independent for each part, so there's no guarantee they'll be playing together. One idea is to have a kit pattern selector that contains sets of track pattern ids. Another wrinkle is that some tracks might have generators, and different layers. So not everything will be editable from a single UI.
```

## 2026-04-29 - Drum Parts As A Group Clarification

Raw input:

```text
The drum kit view would also allow setting up an alternative destination for the parts, for example a shared destination, and defining what a trigger relates to in that model. For example, each part could be a different MIDI channel, or each part could be a different MIDI note.
```

## 2026-04-29 - Autoslice Algorithm Clarification

Raw input:

```text
Re item 13, the auto slice algorithm should be slightly smarter. I'm not sure what kind of prior art there is around this. The length of the sample can give some indication of a bpm assuming it is 1 bar, 2 bars etc. But there's also the question of whether the transients approximately line up to a grid of 16. The problematic cases are where the snippet of audio isn't exactly a loop - is slightly longer (shorter presents worse challenges). Then it would be nice if there are a bunch of suggested loop start ends. Maybe it looks at the transients to see if they are snares, kicks, hi hats etc. It feels like pattern matching that humans do intuitively, but could be determined by a heuristic. Perhaps we can explore several different options in isolation. Eg don't build it into the app yet. Just take a few samples, and build a couple of simple interfaces demonstrating how it handles the loops.
```

## 2026-04-29 - Audio Looping Clarification

Raw input:

```text
I think this might duplicate the input audio idea as it relates to tracks. A second idea that is lower priority is to have a separate live looping page that allows toggling record and playback of capable tracks at a macro level.
```

## 2026-04-29 - Fill A Clip From Current Generator Deferred

Raw input:

```text
Let's skip 17 for now
```

## 2026-04-29 - Track Perform Multi-Select And Latch Backlog Item

Raw input:

```text
add an item for multi-select and latch on the track perform screen
```

## 2026-04-29 - Note Repeat Clarification

Raw input:

```text
Re item 15, note repeat should be an option on the perform page for tracks, like fill. When it is toggled on, it should record the quantized step and then for that track, it should keep playing that step until it is released. The interval should be in the layer, for example repeat 16, repeat 32, repeat 64. Some of these are sub-step intervals, so we might need to look into how the sequencer handles that.
```

## 2026-04-29 - Step Order Clarification

Raw input:

```text
This is like note repeat. It basically overrides the sequential playhead for the track. It could be some sort of lookup so that step 0 in an array of 16 actually maps to 9. Whole sections of steps could be moved around, or notes added. In future we might want more messing around like adding layers. Example: [0,1,2,3,3,3,3,3,7,8,9,0,1,2,3]. The difficulty is that the actual layer modification needs to be selectable. Maybe there's one for the project, and it just gets toggled on or off.
```

## 2026-04-29 - Toggle Fill On A Track To Hear It Clarification

Raw input:

```text
When in the track editor, there's no way to toggle the fill status for it. We need one so that we can preview the fill pattern playing.
```

## 2026-04-29 - Drum Kit Group View Covered By Item 12

Raw input:

```text
I think this got covered in Making drum parts feel part of a group
```

## 2026-04-29 - Fill Applied To Whole Kit Deferred

Raw input:

```text
I think this can be deferred
```

## 2026-04-29 - Scenes In Phrases Clarification

Raw input:

```text
The phrase view should have two modes: tracks and scenes. In the scene version, A and B scene slots should be configurable per phrase, as well as the position of the slider. I imagine a similar matrix with only 3 columns for A, crossfader, and B. Different modes for the crossfader should be allowed, such as value for the whole phrase, or bars within it having different values.
```

## 2026-04-29 - Phrase Cells Deferred

Raw input:

```text
Let's defer this
```

## 2026-04-30T10:22:06Z - Scene Perform Feedback

- **Applies to:** prototypes
- **Feedback file:** `docs/roadmap/scene-perform/feedback/20260430-102206-prototypes-feedback.md`

Raw input:

```text
Let's take out "save blend pos" "reset" and record them as a new feature which is about live performing scenes. It brings up a lot of questions about where it's stored. Likewise, let's take out the revert and save to scene features. At the moment, if the scene is modified, it modifies the original. Those other behaviours can be a new feature. 
```

## 2026-04-30T10:38:03Z - Step Sequencer Feedback

- **Applies to:** prototypes
- **Feedback file:** `docs/roadmap/step-sequencer/feedback/20260430-103803-prototypes-feedback.md`

Raw input:

```text
I don't want a UI to pop up when a step is selected.  Depending on the layer that is selected, the inside of the toggle step should change. If it a value like velocity, the bar should be draggable. For some tracks, there are more limited options. Eg a slicer step needs to highlight the slice that's selected. A chord step in the chord generator needs to highlight the chord. Try a variant where the layers above it have a rotary control that can be modified to change the selected steps. I think we're slightly struggling with context in this wireframe - the different variations of tracks, and the way that steps are used is the nuance. I think there are some screenshots in this directory.
```

## 2026-05-03T15:30:24Z - Scenes In Phrases Feedback

- **Applies to:** prototypes
- **Feedback file:** `docs/roadmap/scenes-in-phrases/feedback/20260503-153024-prototypes-feedback.md`

Raw input:

```text
The current item 22 prototypes are the wrong shape because they do not understand the existing track-oriented phrase page they are meant to extend. The scene/phrase concept should be added to the current Phrase Matrix shape: tracks across the top, phrases down the rows, one cell per track/layer, with phrase controls and track paging as already shown in the current app. Do not prototype this as an unrelated standalone scene page.
```

## 2026-06-10 - Library Page: Project Pool vs Global Assets

Raw input:

```text
I want to think about the library page. What I'm thinking is that there should be a split between stuff that has been included into the current project versus all the sort of libraries that may be assets that exist as sort of global things and they should be in categories like breaks that can go into the slicer. Also the recorded audio from the input audio channels should go in there and also samples specifically drum kits should be listed and when we create a new drum track in the tracks menu, there should be a way of selecting one of the drum kits that's been added into the project pool at the moment. It's a sort of global thing yeah
```

## 2026-06-10 - Drum Kits As Sound Collections + Global Pattern Templates

Raw input:

```text
Regarding the audio pool/library. There are a few changes I would make. 1. Drum kits should be a collection of sounds for different drum parts such as kick snare etc. The current enum that links it to a pattern can be removed. There could be a pool of sounds for each part (a selection of kicks etc). When creating a drum track, the modal should have the option to choose a kit from the global pool. That populates the sounds. There should be a separate concept of predefined "patterns" that can be applied to a drum track group. Essentially, each part has a type/tag based on the instrument. The "pattern" is a collection of clips for each part that get inserted into the track. In the creation modal, choosing the sounds should be the first aspect, and then there should be a second option to prepopulate from a template. These templates should be global. There should also be a way of imposing one of these templates on a drum group after it's created via the kit view.
```

## 2026-06-10 - Step Order Creation Moves To The Library

Raw input:

```text
the phrase UI is still a bit broken. I thought we had fixed this in one of the branches. Basically when the left box is selected, a phrase edit interface appears below the row with step order, and length and repeat. The latter two should be in the box on the left for editing. The step order stuff shouldn't be here. Creating a new step order should probably be in the library. Likewise, there should be global step order presets that are in there. In any case, it shouldn't be in this ui, and this should be removed (step order can be toggled as a layer like note repeat).
```

## 2026-06-11 - Audio Input: Channels Adapt, Arm/Monitor Rethink

Raw input:

```text
I changed to the 24 channel input and it still says input needs 2 channels. This is interface nonsense. The track should be mono or stereo. If stereo with mono interface, duplicate. If the opposite, merge the channels. The levels will show if it's coming in on only one side. It's unclear what "arm" does. In other daws, that allows the input in. Here it seems combined with recording? Likewise, monitoring the input or the loop is confusing. Can you reason about a better way of doing this
```

```text
I think monitor makes more sense if it's a toggle between buffer and live. Loop is the word that causes confusion. Obviously live is the only option if there is no buffer
```
