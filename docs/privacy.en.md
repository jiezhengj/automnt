Automnt manages SMB share settings on this Mac. This describes the current offline build's actual behavior and is not legal advice.

# Data

- Settings live in a fixed local configuration directory created by the program, never hand-written.
- Sign-in is handled by macOS and the system Keychain; Automnt keeps no separate password and writes none into settings or diagnostics.
- No telemetry, ads or third-party analytics. Diagnostics leave the Mac only after you preview and export them; nothing is uploaded automatically.
- Logs are kept for 7 days with a 5 MB per-file cap and can be cleared from Diagnostics.
- When connecting to a share, the server you connect to processes the connection request; its privacy practices are its own.

# Your choices

You can turn off automatic mounting, eject shares in Finder, remove managed shares, or clear logs. If you deny a background/access permission, the app reports the real state and never creates a second configuration.
