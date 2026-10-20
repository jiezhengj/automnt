# Automnt 3.4.0 local offline build

- The GUI and CLI share one configuration and mounting policy. The GUI includes server grouping, share add/remove, automatic-mounting switches, details, settings and draft protection on quit.
- The fixed settings directory is prepared by the program. A signed GUI was verified to read/write it without a folder picker; first launch never asks for an internal folder.
- Single-row add persists immediately; duplicate address/location is rejected without any write; removal changes management only and keeps mounted volumes.
- Narrow windows use native server → shares → detail navigation; wide windows keep two columns.
- Nine-language resources and eight-language real-window checks; mount-location terminology was aligned in German, Spanish, French, Japanese, Korean and Chinese.
- See `Known-Limitations.md`. Background automatic mounting still needs system approval; the real logout/restart matrix is not verified.
