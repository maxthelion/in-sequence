# Resolution — branch fix/ui-consistency-bugs

New shared `StudioModal` chrome (Sources/UI/Theme/StudioModal.swift): one
dark stage background, one title row, one ✕ close button. Applied to the
macro assign sheets and all other modal sheets. The mismatched corner radii
came from `.ultraThinMaterial` presentation backgrounds behind differently
rounded content; all sheets now use `.clear` presentation backgrounds with
opaque modal chrome.
