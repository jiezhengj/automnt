This build is for local and same-team verification. The following are current facts, not marketing copy.

# Signing and distribution

- Free Apple Development signature, not Developer ID, not notarized; Gatekeeper may block it on other Macs. It is not a public distribution channel.
- App Store submission, pricing and review are not done; those tasks are deferred until a paid-account request is opened.
- Permission and upgrade continuity on other devices is unverified.

# Background and permissions

- Automatic mounting depends on the app's background item and system approval. Without approval the UI reports the real "off/unknown" state and does not pretend success.
- The fixed settings directory is reached through an exact home-relative entitlement. Real signed GUI reads/writes were verified; App Store review acceptance is not.
- Background mounting by the independent helper (formerly T095/T096): the defect chain is fixed — mounting runs in-process (`Sources/AutomntPlatform/MountExecutionService.swift`), and helper readiness uses the fixed LaunchAgent definition + `XPC_SERVICE_NAME` + committed backend-state. The 2026-10-24 19:00 real restart mounted both volumes unattended with healthy observations. A real log-out/log-in round remains impossible (it ends the session), and the same-boot session boundary does not refresh by design; full history in `specs/005-swiftui-mas-gui/CHANGELOG.md`.
- Failure notifications: helper records, resident app delivers. Explicit limits: if the app is quit, not set to open at login, or notification permission is denied/revoked, background failures are not delivered; records older than 10 minutes are dropped — background failure notifications require the login item plus the menu bar icon. The end-to-end path was verified on 2026-10-24 (delivery within 17–22 s); denial/paused/expiry states are covered by unit tests but not verified in the live path.
- The menu bar icon is the only visible entry of the resident process: a login-item launch shows the menu bar and never opens the main window. Real restart launch, menu-bar clicks, light/dark, nine-language launch rendering, GUI eject/mount, VoiceOver speech and accessible names (zero unnamed product controls after labelling eight) were verified. A real log-out/log-in round is not executable; dynamic type is not supported (next item); evidence in `specs/005-swiftui-mas-gui/evidence/2026-10-24/`.
- The sandbox cannot read the contents of a network volume it mounted: the GUI/helper can verify mount identity only, not read files inside the volume (App Sandbox restriction). The user's own non-sandboxed apps can still read and write (observed with `ls`). This app therefore does not claim "content verified readable"; real file usability must be checked with the user's own apps.
- A manual `diskutil unmount` is recorded as a user eject for the current session, so the share is not auto-mounted again until the session boundary changes (by design); an equivalent simulation cleared it on a boundary change, but clearing a pre-restart suppression on a real restart was not observed directly (T138).
- Session boundary and session suppression: the sandboxed process cannot read utmpx, so the session boundary falls back to `<boot>-console-unreadable`; a real log-out/log-in within the same boot does not clear session suppression (documented design limit). Recovery paths: "Try automatic mounting now" or per-share mount/retry.
- Without app background control, Eject explains that it needs background mounting and points to Finder; it never forces an unmount.

# CLI

- `--mount`/`--eject` need working background ownership and launchd registration. If `--install` cannot register on this Mac, the command refuses and may currently misreport `requiresRepair` (T101).
- CLI 3.5.0 is not affected by defects A/B/C (not sandboxed, flat single binary, spawns no worker, never queries SMAppService). However, the CLI was not installed this round and backend owner=app, so the CLI's own background automatic mounting remains unverified and must not be reported as passing.
- The CLI only acts on configured shares; it never guesses another server.

# Language and accessibility

- Nine-language resource coverage and per-language launch rendering checks are done; round eight had agy review all nine languages and applied 24 high-confidence fixes after checking each current value (French/Spanish clauses, German Einbindung/freigegeben, Brazilian Portuguese Ajustes, Japanese 復旧, Traditional Chinese 檔案夾/圖示/復原, Simplified Chinese phrasing, Korean honorifics); remaining pronoun/terminology unification is left to the maintainer. Accepted by Lead + agy on the maintainer's behalf (T144), not external native-speaker certification.
- Actual VoiceOver speech was executed and captured through its caption panel; the system Larger Text slider does not affect this app (dynamic type is not adopted; decided to be a platform limitation); accessibility names were fixed and re-audited (T143). The only remaining environment limit is the real log-out/log-in round.
- The icon appears in the quit confirmation panel; final Finder/Dock/dark-light/small-size visual checks are not recorded.

# Configuration and logs

- Log retention/cleanup policy is not decided yet (T003); nothing is deleted automatically.
- Settings are generated by the program, not hand-written. A real test configuration may remain with a managed share; remove it in the app.

# Copy and text size (late 2026-10-24 decision)

- Nine-language terminology unification was decided jointly by the Lead and agy and 63 mechanical, meaning-safe fixes were applied: German freigegeben for shared folders, einbinden for mounting, Befehlszeile for the command line; pt-BR Definições→Ajustes and entrar na sessão→iniciar a sessão; Japanese standalone アプリ→App (the 「アプリケーション」 folder is kept) and network 復元→復旧; Korean 하십시오→하세요 and 세부사항; Traditional Chinese 資料夾→檔案夾 and 恢復→回復 for restoring access; French/Spanish login-item names follow Apple's own pane terms « Ouverture » and «Ítems de inicio»; case-duplicate translation drift was aligned. Simplified Chinese App/应用 was left unchanged because most occurrences are the verb "apply" or existing product terms.
- German du/Sie was unified to du sentence by sentence by the Lead and agy (65 rewrites; the remaining three "Sie" are third-person references — the address, the order, the settings — not formal address). Basis: Apple's German system text “Personalisiere den Mac so, wie es für dich am besten funktioniert …” and “Erlaube die Verwendung von Befehlszeilen-Werkzeugen …”.
- System Larger Text is no longer a requirement: the pane lists supported apps only, Automnt is not among them, and increasing the slider then relaunching the app does not change text (measured); no public way was found for third-party native apps to register in that pane. The maintainer confirmed the requirement is dropped, so it is not tracked as an improvement and has no substitute (display resolution changes are not used to pretend support). Automatic mounting and nine-language layout are unaffected, and this must not be reported as supported.
