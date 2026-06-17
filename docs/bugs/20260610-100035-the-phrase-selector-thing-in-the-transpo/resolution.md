# Resolution — branch fix/ui-consistency-bugs

Transport phrase control now has a matrix-style grid icon and opens an 8×8
phrase launch grid (`Sources/UI/PhraseLaunchGrid.swift`). The playing phrase
is highlighted with a progress bar that fills as the phrase advances. Click
cues the phrase for when the current one finishes; shift-click switches
immediately (when stopped, click switches directly).
