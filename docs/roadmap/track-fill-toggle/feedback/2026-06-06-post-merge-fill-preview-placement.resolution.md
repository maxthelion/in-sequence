# Resolution: Fill Preview Placement

Date: 2026-06-11 (foreman triage)
Status: fixed

Fill Preview is no longer a tab-row item. It renders as
`TrackFillPreviewControl` in the track header
(`TrackWorkspaceView.defaultTrackHeader`), beside the track name and above
the pattern context — reading as a playback-preview affordance rather than
a content section, per the desired direction. The source tab row is back to
Source / Modifiers / History only (QA captures 18-22).
