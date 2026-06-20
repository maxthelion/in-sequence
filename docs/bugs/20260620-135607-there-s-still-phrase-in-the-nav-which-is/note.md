There's still "Phrase..." in the nav which is useless. The bottom part of the page is broken, the matrix is too wide.

Screenshots:
- 08-phrase-layers-pattern.png

RESOLVED 2026-06-20: Removed the truncated "Phrase…" title from the perform shell and pinned the layer matrix ScrollView to its intrinsic grid width so the bottom section no longer overflows.

REOPENED + RESOLVED 2026-06-20: The earlier "pin to intrinsic width" fix pinned the matrix to its fixed 8-column span (~1166pt), which is wider than the ~1100pt panel, so the last column (Mono 8) still clipped off the right edge. Replaced matrixContentWidth with a GeometryReader that measures the actual available width and shrinks the track columns (fittedTrackColumnWidth, floor 92pt) so a full page of columns fits inside the page. Verified in 08-phrase-layers-pattern.png: all eight columns (through Mono 8) plus the next-page arrow sit inside the panel, no clipped partial column.
