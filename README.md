## In-Sequence

In sequence is designed to be a generative DAW/groovebox taking inspiration from a number of different sources, both hardware boxes and DAWs.

At the core of it are a couple of key ideas:

1. That it should be easy to turn a loop that you like into something approaching an arrangement
2. That being able to perform is fun, but it's also nice to be able to capture that output.
3. That generated melodies are fun, but it's nice to have coordination between parts so that it hangs together
4. That getting stuff running quickly is valuable
5. That it's fun to curate generated output according to our taste
6. That it's fun to change the rules of a system to get new outputs that surprise and delight us
7. That randomness and happy accidents are great, but they need to be bounded by our preferences
8. That it's nice hear variations on stuff we already like

## Tracks

Tracks are designed to be sources of note data paired with sound sources. These can be melodies, drums, loops/slicers.

Different types of track work in different ways:

* Slicers can sample inputs or use drum loops from disk that are sliced and sequenced in clips
* Drum kits are groups of part tracks can be populated with holistic clip patterns that are spread across them. Individual parts have their own destinations and audio routing
* Melodic tracks can store/generate note data to be played, or to form the basis of further modulation

They generally have a sink in the mixer.

## Clips

There are multiple ways of generating note data with varying degrees of randomness:

* Static clips of steps with probability
* Auto generated live step outputter
* Replays of recent live output (history)
* Modified outputs of the above

There's generally a separation between step generation (whether a trigger happens at a point in time) vs the specific pitches that are played.

A workflow can be: create a live generator. Listen to it play and tweak rules. Capture a clip that has been generated and put that into a pattern slot in the track.

Clips for slicers will seek to play each part of the slice in the correct part of the grid.

## Scenes

Scenes are swappable audio busses (A and B) that are mixed with a crossfader just before the master output. By default, all tracks go to both these, and they can have different insert effects on each. It is also possible to route input audio from your audio interface to these destinations to transition between song parts etc.

There are 16 scene slots that can be placed at A or B.

## Phrases

The song mode of In-sequence is composed of phrases. These group a number of settings for the running tracks in the form of different layers. For example, whether a track is muted or playing when a phrase is active, or whether its fill is active.

A phrase has a length (in bars), and can be repeated a number of times within a song arrangement.

The data for a given layer can be modified relative to the start of the phrase at different levels of granularity:

* It can be set for the entirety of the phrase
* For certain bars in the phrase (eg fill on the last bar)
* As a continuous ramp in value (eg ramping up to a crescendo)

The starting value for a phrase can be set to follow its preceding phrase and inherit values from that layer for consistency across the song.

## Song mode and phrase mode

When the sequencer is running, it can be in either song mode - where phrases progress to the next when they finish, or phrase mode where the current phrase loops continuously.

When in the latter mode, you can choose a new phrase to move to at any time, and choos whether that phrase is immediate, or whether it happens when the phrase finishes.

## Performance modifications

There are a number of modifications that can be applied to music that is playing. These are in a number of categories:

* Track based preferences (muting, fill on, macro parameter values, step order, note repeat, scale)
* Audio based modification via scenes

Single tracks can have values changed, and multiple tracks can be changed simultaneously.

## Setup vs performing

There are tasks that can be done for setting up the sequencer, and tasks that can be done to change it while it's running.

The former tasks might include setting up instruments in slots, creating patterns, setting up effects chains etc. Performance modifications might include changing the balance between scenes, changing values for track layers.

In each case, the general principle is that changing values modifies a new version of the scene/phrase with timing information. This means that the modifications can be quickly discarded to return to the previous settings, or turned into a new phrase or scene.

## Parameter routing

The input and output of different tracks can be sent to each other as midi sidechains - so a chord progression can run on one track and effect the generated melody on another.

Layers in the phrase view can change this too. Factors like intensity can be fed through to influence the probability of things happening.
