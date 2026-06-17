# Resolution — branch fix/ui-consistency-bugs

The white background came from SwiftUI's `.inset` List style. Replaced with
a theme-styled ScrollView and section headers, wrapped in the shared
`StudioModal` chrome with the standard ✕ close.
