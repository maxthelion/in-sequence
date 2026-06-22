we need an option in the top right of the track page to delete it with a confiration. Also, that could be an option on the tracks page when there are tracks selected.

---
RESOLVED 2026-06-22: added delete-track affordances — a trash button top-right of the single-track detail header (with confirmationDialog) and a "Delete" action in the tracks-selection bar (with confirmation); new Project.removeTrack(id:)/removeTracks(ids:) + session wrappers.
VERIFIED — independent agent: A1 PASS (track-detail delete button top-right, 19-track-detail-sound.png). A2 initially FAILED (selection-bar Delete rendered as an empty amber pill — invisible label, accent-on-accentFill); reworked to StudioTheme.background text (matching the other selection buttons) and re-captured — now PASS, evidence: 02a-tracks-selection-actions.png (visible trash+Delete). Confirmation dialogs require a tap so not in static captures.
