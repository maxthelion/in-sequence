The copy paste buttons at the top don't seem to work. If I select a step in a sequencer, press copy, select another step and press paste,  the layers of the first step should be applied to the second in the clip. This doesn't happen, it just loses the selection. Likewise, clear doesn't do anything.

Status: RESOLVED 50f1876b

Copy preserves the clipboard while destination selection changes; Paste maps
all copied layers to the selected steps and Clear erases the selected steps.
