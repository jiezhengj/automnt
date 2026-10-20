This is the free offline build of Automnt 3.4.0, distributed through GitHub Releases. It uses a free Apple Development signature, is not notarized, and is not distributed through the App Store; Gatekeeper may block it on other Macs.

# Contents

- `Automnt.app` — SwiftUI app with its independent helper/worker.
- `automnt` — signed prebuilt command-line program; no compilation on the user's Mac.
- Install, known-limitations and release-notes documents.
- A `.zip.sha256` file next to the archive.

# Verify

```sh
shasum -a 256 -c Automnt-3.4.0-offline.zip.sha256
```

# Install the app

1. Move `Automnt.app` to `/Applications` (or run it from a local folder).
2. If Gatekeeper blocks the first launch, the Mac does not accept this free development signature. Do not disable system security to bypass it; use a local or same-team environment instead.
3. On first launch the app prepares its fixed settings directory itself; no internal folder picker is shown.
4. To use background automatic mounting, turn it on in Settings and allow the background item when macOS asks. Until then the UI reports the real state rather than pretending it is on.

# Install the command line (optional)

`payload/automnt` keeps its executable bit when unzipped. If you download the standalone `automnt` release asset, browsers usually drop it; run:

```sh
chmod +x automnt
./automnt --install
```

This copies the signed program to its canonical directory and configures the shell entry. Registering the background LaunchAgent still requires system permission; if registration fails, do not hand-write a service—read the command output first.

# Upgrade

Replace the old `Automnt.app` with the new one. Settings live in the user configuration directory and should not require reauthorization; if macOS asks, allow or deny through the shown explanation and no second configuration is created.

# Remove

Delete the app, and run `automnt --uninstall` for the CLI. Settings are kept unless `--purge` is passed explicitly.
