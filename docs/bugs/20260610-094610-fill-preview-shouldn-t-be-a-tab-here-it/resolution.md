# Resolution — branch fix/ui-consistency-bugs

Fill Preview moved out of the tab bar row up into the track page header
(next to the track name) as a compact toggle (`TrackFillPreviewControl`).
The orange explainer text is gone; status detail lives in the hover tooltip.

Partially deferred: "available for everything" — fill lanes only exist on
clip content in the engine, so generator-backed slots still show the control
disabled. Making fill work for generator sources is an engine feature, not a
UI fix; flagged for a follow-up.
