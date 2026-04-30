# Phrase Features User Stories

## Stories

### 1. Set phrase length from the phrase button

- **As a:** composer arranging a song structure
- **I want:** to set how many bars a phrase spans directly from the phrase button (e.g. "Phrase A")
- **So that:** I can define the looping boundary of a phrase without leaving the main view
- **Done when:** the phrase button exposes a bar-count control; changing it immediately resizes the phrase loop boundary; the value is persisted with the phrase

### 2. Set phrase repeat count

- **As a:** composer building song sections
- **I want:** to set how many times a phrase repeats before the song moves on
- **So that:** I can build repetitive sections (verse, chorus) without manually duplicating phrases in a song arrangement
- **Done when:** the phrase button exposes a repeat-count control; the sequencer advances to the next phrase (or stops) after the specified number of repeats; zero or unlimited repeats is a valid option

### 3. Toggle a phrase into permanent loop mode

- **As a:** performer or composer testing a phrase live
- **I want:** a dedicated loop toggle on the phrase button that keeps the phrase looping indefinitely
- **So that:** I can jam and iterate on a phrase without it advancing to the next section — this replaces the current "free mode vs. song mode" distinction with a per-phrase control
- **Done when:** the loop toggle exists on the phrase button; when enabled the phrase repeats forever regardless of the repeat count; when disabled normal song-mode advancement resumes; the toggle state is visually distinct and persisted with the phrase

### 4. Use a phrase as a performance baseline and save edits back

- **As a:** live performer
- **I want:** performance-mode variations to use the active phrase as their starting point, and to be able to commit those changes back into the phrase
- **So that:** I can improvise on top of a phrase during a set and lock in the result without losing the original unless I choose to
- **Done when:** entering a performance mode seeds it from the current phrase; a "save back" action writes the performance edits into the phrase; the original phrase is recoverable if the user cancels before saving

### 5. Page-switching arrows at the matrix corners with occupancy hints

- **As a:** composer working with more tracks than fit on one page
- **I want:** left and right page-navigation arrows positioned at the top-left and top-right corners of the track matrix — occupying the cells beside the track names — and some visual indication of whether tracks exist on the adjacent page
- **So that:** I can quickly see whether there is anything to navigate to and switch pages without hunting for a control
- **Done when:** arrows sit in the corner cells of the matrix header row; arrows for a direction with no tracks on the adjacent page are hidden or visibly inactive; arrows with tracks available are clearly active; tapping navigates to that page

### 6. Fixed-width, grid-aligned layer selector

- **As a:** composer switching between layers (e.g. notes, automation)
- **I want:** the layer selector to be horizontally centred above the grid and to maintain a fixed width regardless of which layer is selected
- **So that:** the layout does not jump or shift when I switch layers, giving me a stable visual anchor
- **Done when:** the layer selector is visually aligned with the grid columns; its horizontal width does not change when the active layer changes; switching layers produces no layout shift in surrounding elements

## Acceptance Signals

- Changing phrase bar count and repeat count in the phrase button is possible without opening a separate modal or settings screen
- The loop toggle makes it unambiguous whether the sequencer is in "play forever" or "song advance" mode for that phrase
- Performance-mode edits can be discarded or committed independently — accidental saves do not silently overwrite a phrase
- Page navigation arrows are always visible at the matrix corners and communicate whether adjacent pages have content
- Switching layers does not cause the layer selector or surrounding layout to shift horizontally

## Assumptions

- "Phrase button" refers to the existing UI control labelled e.g. "Phrase A" that represents the active phrase
- "Performance modes" are an existing or separately planned concept — this feature assumes they exist and adds the save-back behaviour
- "Free mode vs. song mode" is the existing global distinction; this feature replaces or augments it with per-phrase loop control
- Bar count and repeat count live on the phrase data model, not only in the UI
- The track matrix currently has a header row where corner cells can be repurposed for navigation arrows
- The layer selector currently changes width when switching layers — this is the bug being corrected
