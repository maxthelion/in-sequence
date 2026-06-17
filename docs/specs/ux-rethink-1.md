Create a new view that takes a selection of tracks (or all tracks) and maps a layer toggling interface on top. So all layer options are shown at once, and when they are changed, the value is applied to all the tracks in the selection.

Create a new view that is similar to the current tracks perform mode. Maybe called layer perform. This shows a bunch of tracks and allows switching between layers to put a toggle/changer for each track on a matrix (so we can see what pattern, or mute state each track is set to).

Create a new track perform page that allows toggling different values for a track, and possibly its macros. Do a similar thing for drum groups.

For drum groups, different parts could be muted differently, for example. In the main, the pattern and associated clip settings should be shared between parts. This could include mute settings, but that might overcomplicate.

Maybe we change the navigation to make perform less confusing. These are the things you are likely to want to do in perform mode:

Move between different phrases
Make layer changes across tracks
Change the sounds of a running track
Change the scene values and crossfade between

I’m thinking that phrases have a number of roles to play. WHen the sequencer is playing, it should always be in a phrase. When layer values etc are being modified, they should be done in a copy of a phrase. A phrase should contain scene crossfade values, as well as scene parameter changes. It should possibly contain event data (like midi format) for continuous changes etc.

There should be  a richer view for cueing up changes in phrase etc. like the little modal from the transport. There should be a visible current phrase in transport.

There should also be a track-in-phrase view that combines the following for each layer: how the value is mapped to the phrase (continuous, single value, per bar), what the values are. How we get here is a bit of an open question.

The other thing is that the track page needs to somehow work differently depending on the phrase that is playing. For example, if the track is muted in the phrase, that should be visible (and it shouldn’t be playing). The pattern that is active in the current phrase should be indicated too. The sequencer should only be progressing if it is aligned, otherwise it’s confusing. Likewise, we added a button to preview fill, but it should really be a button to turn it on or off within the playing phrase.

There is an argument for being able to preview changes through a cue output when in perform mode, but I think we leave that for the time being.

This also highlights another point. The capture/history mechanism needs to be able to work in a number of places. At the moment, it is geared towards the melodic generators. However, there are other areas that would also benefit from having capture, such as: drum groups/parts - especially where chance is applied in the clip, sometimes it comes up with pleasing versions that might need to be captured. Also the scene x cross fader and value changes, and the layer changes.

I’m thinking that capture becomes a higher- level menu item perhaps at the transport level. There might need to be 2 versions: capture clip which works like the current track history feature, but first requires choosing the track it applies to. The output of this is generally a new pattern in that track. The other capture is capture phrase. This might also be in the top level, and would print changes to a copy of the current phrase.

I’d like you to build a set of html wireframes that try to get to grips with the interfaces described here. Look at the captures of the current app to understand the current layout, and think about which bits need to change. Write out your reasoning in a separate doc.
