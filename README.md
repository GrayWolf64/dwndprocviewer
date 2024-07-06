# Derma Window Process Viewer

As the name might suggests, this tool offers an insight into all the panels created using GLua API, which are children or non-direct children of `GModBase` or `HudGMOD`, see[Base HUD Element List](https://wiki.facepunch.com/gmod/HUD_Element_List).

The 'insight' includes but is not limited to:
1. Real-time updated Hierarchy structure shown in tree
2. Colorful highlights
3. Convenient right-click menu with some actions to perform
4. Hover on the node to see tip(some info on the panel)

## Colors
| **State**           | **Color**        |
|---------------------|------------------|
| Disabled            | Gray             |
| Invisible           | Light Gray       |
| Marked For Deletion | Red              |
| Keyboard Focused    | Light Blue(cyan) |
| Focused             | Orange           |
| New                 | Bright Green     |
| Modal               | Dark Pink        |

**Note**: 'Marked For Deletion' Red will stay for 1s, and 'New' Green will stay for 1.25s.
