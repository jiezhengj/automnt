# Product Overview

automnt is a native, lightweight SMB auto-mounting tool for macOS that matches network policies based on target host TCP 445 reachability and mounts shares through macOS NetFS. If usable credentials exist in Keychain, mounting proceeds silently without interactive password prompts; mount failures return clear status codes and diagnostic logs.

# Project Origin and Core Problem

This project began with recurring SMB problems experienced by its maintainer on macOS. The following describes the maintainer's reported experience; the macOS version where Finder behavior changed has not been verified.

- Earlier macOS versions allowed the maintainer to add a server host itself to the Finder sidebar and browse its shares. In recent major versions, that workflow no longer works as before.
- Even a specific SMB share saved in the sidebar may lose its entry after a restart or similar event when the volume is not automatically mounted. **automnt does not currently solve disappearing Finder sidebar entries.**
- More seriously, a task that reads or writes files on an SMB volume can fail before the user realizes the share is not mounted. The user then has to interrupt the workflow, connect manually in Finder, and retry the task.

The maintainer's Windows experience is that a task can access a network path without a separate manual mounting step, provided the server is reachable and credentials and permissions are valid. This comparison describes the desired user experience; automnt does not implement Windows-style connection on arbitrary path access.

**automnt's core value is automatic mounting: when the server is reachable and configuration and credentials are valid, background mounting and recovery aim to make configured SMB volumes ready before tasks access them, reducing failures caused by an absent mount.** The current event-driven mechanism can delay recovery and does not guarantee successful access at every moment or when a server or credentials are unavailable.

The CLI and the GUI share one configuration and the same automatic-mounting policy. The CLI remains the free, scriptable entry point; the GUI owns status, graphical setup, and recovery guidance. Manual mounting/retry is still an exceptional fallback, not a substitute for automatic mounting; a product centered on clicking to mount would not fulfill this project's purpose, since Finder already offers manual connection.

# Key Features

- **Silent Background Mounting**: Operates entirely in the background using macOS native `NetFS.framework`, mounting volumes without opening Finder windows or interrupting desktop workflows.
- **Service Reachability Routing**: Network profiles match based on target host TCP 445 reachability checks (`HostReachabilityProbe`), eliminating dependencies on fragile link-layer MAC addresses or ARP caches.
- **User-Scoped Canonical Install & Shell Integration**: Installs canonically to `~/Library/Application Support/automnt/bin/automnt` and automatically injects its directory into user shell profiles (`.zshrc`, `.bash_profile`, etc.) for global terminal access.
- **Event-Driven Reactive Daemon**: The LaunchAgent daemon triggers strictly on macOS system network configuration changes (`WatchPaths`), completely eliminating periodic polling (`StartInterval`) to ensure zero idle battery and CPU consumption. An internal retry runner (`EvaluationRetryRunner`) accommodates network handshake delays.
- **Bounded Cleanup for Dead Mounts**: Employs Darwin kernel `MNT_NOWAIT` non-blocking mount table snapshots to eliminate `stat()` blocking and spinning beachballs. Only matching SMB mount points undergo bounded cleanup using `diskutil` and fallback `umount -f`.
- **Single Active Configuration Contract**: Uses a single source of truth at `~/Library/Application Support/automnt/automnt.plist`, written atomically with strict `0600` permissions.
- **Spotlight Indexing Protection**: Automatically executes `mdutil -i off` and attempts to write `.metadata_never_index` to protect network volumes from indexing degradation.
- **Compiler-Free Binary Self-Updates**: Directly downloads precompiled binaries from GitHub Releases, validates them in a sandbox, and transactionally updates in place without requiring local Xcode or Swift developer tools.
- **Self-Health Check and Healing**: The executable inspects its binary path, shell profile entry, and LaunchAgent status on launch, automatically healing broken components.
- **Zero External Dependencies**: Implemented purely in native Swift, compiled to a standalone executable optimized for Apple silicon.
- **Interactive Terminal Menus (3.2.0)**: Setup and configuration use arrow-key navigation and Enter to choose, with Space for multi-selection, scrolling for long lists, and Escape to cancel. Configuration edits are staged in memory and written only when you choose **Save and exit**.

- **Automatic Mount-Loss Recovery (3.3.0)**: Once the remote host is reachable again, shares that are enabled and were previously mounted are re-mounted automatically in the same evaluation round that follows the next wake-up event, with no user action and no credential or login dialog. Recovery only re-mounts volumes that were genuinely mounted before; newly added shares that were never mounted keep following the existing mount-evaluation logic.
- **Session-Level Suppression (respects manual ejection)**: A share you eject while healthy is not remounted for the rest of that reachable session. Suppression lifts on a network-context change or a re-login, whichever comes first. Ejecting an already-dead volume counts as a repair action rather than abandonment, so it can still recover once the host is reachable.
- **Fallback When Recovery Fails**: Healthy ejection and session suppression do not trigger failure notifications. If actual recovery fails, a plain-text notification lists the shares that were not restored and points at **Remount now**, at most once per round and twice per volume per session. A session boundary or successful mount resets that count.
- **Automatic Recovery Switch**: Toggle it from **Auto-recovery switch** in the `automnt --config` main menu (enabled by default). Turning it off falls back to the current behavior — evaluate on login and network changes only — while **Remount now** stays usable. It is written only on **Save and exit**; `Esc` leaves it unchanged.

**Boundary**: the CLI exposes `--mount`/`--eject`, and the GUI exposes ordinary eject in a share's details. Neither treats forced unmount as a routine action; a busy volume fails honestly. The program may still clean a detected dead mount before recovery. Healthy ejection includes actions initiated in the system (e.g. Finder) or in the product entry points.


# GUI and offline distribution (current scope)

- The GUI and CLI share `~/Library/Application Support/automnt/automnt.plist` and the same mounting/recovery policy. Whether background work continues after quitting the GUI follows the real background state.
- On first launch the program prepares the fixed settings directory itself; it never asks the user to pick an internal folder. Existing CLI targets appear automatically.
- Servers are grouped as managed or available to add; shares support single-row add, edit, remove, and ordinary eject. Removal changes management only and never ejects or deletes files or system credentials.
- Background automatic mounting needs system approval for the background item; without it the UI reports the real state and never pretends success.
- This build uses a free Apple Development signature for local/same-team offline verification. It is not a public distribution channel and is not submitted to the App Store. The prebuilt CLI and source builds coexist; building from source is optional.
- See `release/offline/` for the offline archive, checksum and install notes; see `release/offline/known-limitations.en.md` for current limits.

# Quick Start

## System Requirements

- Architecture: Apple silicon (arm64)
- Operating System: macOS 27.0 or later

## Installation & First Run

Download the prebuilt `automnt` binary from GitHub Releases:

```bash
chmod +x automnt
./automnt
```

Running `automnt` from a temporary or Downloads folder initiates automated relocation:
1. Installs canonically to `~/Library/Application Support/automnt/bin/automnt`;
2. Removes the temporary download artifact;
3. Injects the CLI PATH entry into the current user's shell configuration;
4. Informs you that `automnt` is now available directly in any new terminal window.

## Upgrading from Legacy Versions (2.7.4)

3.0.0 introduces a unified single-config model and event-driven architecture, and does not provide an in-place migration path for 2.7.4 installations. Legacy users should migrate via the following steps:

1. Perform a complete uninstall using the command from your 2.7.4 installation:
   ```bash
   ./<legacy-binary> --uninstall
   ```
2. Download the 3.0.0 prebuilt binary and run it once:
   ```bash
   chmod +x automnt
   ./automnt
   ```
3. Run the initial configuration wizard to create a canonical configuration:
   ```bash
   automnt --init
   ```

> [!NOTE]
> Under the clean single-model design, legacy configurations are not reused. Please select or enter your target shares in the setup wizard.

## Initial Setup Wizard (`automnt --init`)

Ensure you have connected to your target SMB share at least once via Finder ("Connect to Server", `Cmd + K`) and saved credentials in your Keychain.

Launch the setup wizard:

```bash
automnt --init
```

The wizard uses terminal menus to configure hosts and the update policy:

- Detected hosts and actions such as **Add manually**, **Skip**, and **Finish** appear in one radio list. Move with the arrow keys or `j`/`k`, then press `Enter`; already configured hosts are disabled.
- After choosing a host, enter an optional friendly name and select its currently mounted SMB shares. Press `Space` to toggle a share, `a` to select or clear all, and `Enter` to submit. An empty name uses the host address.
- Press `Escape` in a menu or text prompt to cancel the current step. The wizard does not save an incomplete setup.
- Choose an update policy and whether to install the LaunchAgent. In a non-interactive pipeline, selection menus fall back to numbered text input; enter a valid number to choose an option or press Enter to cancel.

> [!IMPORTANT]
> **Existing Configuration Protection**
> - `automnt --init` preserves existing usable configs without overwriting.
> - To rebuild configuration from scratch, run `automnt --init --reset`. A timestamped backup is created prior to writing.

## Daily Configuration (`automnt --config`)

Manage mount targets, probe hosts, and update preferences using the interactive menu:

```bash
automnt --config
```

The main menu combines configured hosts and management actions in one radio list. Move with the arrow keys and press `Enter` to manage a host's shares or choose an action. Select shares with `Space` and submit them with `Enter`. Reordering takes two steps: choose a host, then its destination priority. Before deleting a host or all hosts, move the focus to the confirmation item, press `Space` to select it, then press `Enter`; pressing `Enter` without that explicit selection cancels safely.

Changes are held in an in-memory working copy for the current session. Choose **Save and exit** to write them to the configuration file, or press `Escape` to discard all unsaved changes.

# CLI Interface Reference

```text
Usage:
  automnt                     Evaluate network profiles and mount matching targets
  automnt --init              Safe setup; preserves any existing usable config
  automnt --init --reset      Back up existing configuration and rebuild from scratch
  automnt --config            Daily configuration and daemon management menu
  automnt --install           Deploy or repair LaunchAgent daemon and CLI entry
  automnt --uninstall         Remove LaunchAgent daemon and CLI entry (preserves config)
  automnt --uninstall --purge Full purge (removes daemon, CLI entry, config, and logs)
  automnt --status            Show service status and active mount details
  automnt --update            Check and self-update to latest prebuilt release
  automnt --self-test         Run full automated test suite
  automnt --version, -v       Show software version
  automnt --help, -h          Show this help message

Environment Variables:
  AUTOMNT_LANG=zh|en          Explicitly set terminal UI language
```

# Technical Architecture

## Host Reachability Probing (HostReachabilityProbe)

Network environments are identified by verifying TCP port 445 connectivity against configured server endpoints:
- Sends bounded non-blocking socket requests (default 1000 ms timeout);
- A reachable port confirms network presence;
- Connection refused, host unreachable, or timeout transitions evaluation to the next profile.

## Reactive Event-Driven Daemon

- **Network Change Detection**: Registered LaunchAgent specifies `WatchPaths` for `/Library/Preferences/SystemConfiguration`, triggered by macOS whenever network state alters.
- **Bounded Retry Execution**: `EvaluationRetryRunner` performs limited retries within a configurable window, gracefully handling network handshake delays. If no profile matches, it exits silently with code `2`.
- **Integrity Self-Healing**: Validates `InstallState` on execution and repairs missing plist registrations or stripped shell paths.

## Non-Blocking Mount Snapshots

To prevent thread hangs on broken networks, `automnt` invokes Darwin kernel `getfsstat`:

```swift
let count = getfsstat(nil, 0, MNT_NOWAIT)
```

With `MNT_NOWAIT`, mount status returns instantly from kernel cache without waiting for remote I/O responses.

## Uninstallation Options

- Regular Uninstallation:
  ```bash
  automnt --uninstall
  ```
  Unloads LaunchAgent, cleans up shell profile PATH entries, and preserves configuration and logs.

- Full Purge:
  ```bash
  automnt --uninstall --purge
  ```
  Removes the service, cleans shell profiles, and deletes `~/Library/Application Support/automnt` and `~/Library/Logs/automnt`.
