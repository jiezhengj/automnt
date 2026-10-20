This is an offline-build position note, not an App Store submission packet.

# Review-relevant facts

- The build uses a free Apple Development signature, is not notarized and is not submitted to the App Store; no review outcome may be inferred.
- No telemetry, ads or third-party analytics; diagnostics export is user-initiated.
- The fixed settings directory is reached through an exact home-relative entitlement. A real signed GUI was verified to read/write it; App Store acceptance of the exception is not verified.
- Background automatic mounting needs system approval for the background item; the UI reports the real state without approval.
- Paid account, App Store Connect and formal submission are deferred (T100).

# Required before a future submission

Formal Developer ID/store signing and profiles, store privacy declarations, screenshots, nine-language metadata, pricing, review environment and real review feedback. Local free-signature results must not be substituted.
