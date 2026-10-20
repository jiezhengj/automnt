#!/usr/bin/env python3
"""Verify the CLI target's Swift 6 concurrency invariants hold.

Why this exists: the migration to Swift 6 language mode replaced ~37 mutable globals
with `LockedBox` (a non-recursive `Mutex`), `Atomic` publication for the signal
handler, and thread-local carriers for non-`Sendable` test closures. Verification
showed the *compiler* only enforces one of those properties (no bare mutable global);
five mutation classes were invisible to both `swift build` and the 295-item
`--self-test`, because the terminal accessor paths are not exercised by it:

  * a `LockedBox` accessor that re-enters its own lock  -> segfault at runtime
    (`-swift-version 6` emits only a *warning* for the infinite recursion)
  * a `LockedBox` accessor that touches a second box    -> ABBA deadlock risk
  * dropping the `release`/`acquire` pairing on the signal-handler atomics
  * reintroducing `nonisolated(unsafe)` / `@unchecked Sendable`

This script turns those into build-time failures. It is deliberately conservative:
it fails closed on anything it cannot parse, and it only claims what it can check.

Known limits (stated so this is not mistaken for proof):
  * It is a lexical/structural check. A re-entry performed through a closure,
    a stored `@escaping` reference, or a protocol witness is not detectable here.
  * It does not prove deadlock freedom, only the absence of the two directly
    expressed accessor hazards.
  * It does not check `AutomntCore`/`AutomntPlatform` (different targets, not
    part of this migration).

Usage:
    python3 scripts/verify-swift6-concurrency.py          # exit 1 on violation
    python3 scripts/verify-swift6-concurrency.py --quiet  # failures only
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
CLI_DIR = REPO / "Sources" / "AutomntCLI"

# The Mutex-backed carrier introduced by the Swift 6 migration.
BOX_DECL = re.compile(r"\b(?:private\s+)?(?:static\s+)?let\s+(\w+)\s*=\s*LockedBox<")
# An accessor that wraps a box: `static var x: T { get { box.value } ... }`
# or the single-expression form `static var x: T { box.value }`.
ACCESSOR = re.compile(r"^\s*(?:private\s+)?static\s+var\s+(\w+)\s*:[^{]*\{", re.M)
# Any use of a box, used to find which boxes an accessor touches.
BOX_USE = re.compile(r"\b(\w+)\s*\.\s*value\b")

# Atomics whose release/acquire pairing carries the termios snapshot to the handler.
PUBLISH_STORE = re.compile(r"(\w+)\.store\(\s*1\s*,\s*ordering:\s*\.releasing\s*\)")
PUBLISH_LOAD = re.compile(r"(\w+)\.load\(ordering:\s*\.acquiring\s*\)")
UNSAFE_ANNOTATION = re.compile(r"nonisolated\(unsafe\)|@unchecked\s+Sendable")


def swift_files() -> list[pathlib.Path]:
    return sorted(CLI_DIR.glob("*.swift"))


def strip_comments(text: str) -> str:
    """Remove comments so documentation about a hazard is not read as the hazard."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def accessor_bodies(text: str) -> list[tuple[str, str, int]]:
    """Yield (accessor name, body, line number) by brace matching from the declaration."""
    results: list[tuple[str, str, int]] = []
    for match in ACCESSOR.finditer(text):
        name = match.group(1)
        start = match.end() - 1  # at the opening brace
        depth = 0
        index = start
        while index < len(text):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
            index += 1
        if depth != 0:
            results.append((name, "", text[: match.start()].count("\n") + 1))
            continue
        body = text[start + 1 : index]
        results.append((name, body, text[: match.start()].count("\n") + 1))
    return results


def check_accessors(files: list[pathlib.Path]) -> list[str]:
    failures: list[str] = []
    for path in files:
        raw = path.read_text()
        text = strip_comments(raw)
        boxes = set(BOX_DECL.findall(text))
        if not boxes:
            continue
        # Map each accessor to the boxes its body references.
        for name, body, line in accessor_bodies(text):
            if not body:
                failures.append(
                    f"{path.name}:{line}: could not parse accessor '{name}' "
                    f"(unbalanced braces); refusing to pass")
                continue
            touched = {box for box in BOX_USE.findall(body) if box in boxes}
            if not touched:
                continue
            if len(touched) > 1:
                failures.append(
                    f"{path.name}:{line}: accessor '{name}' touches {len(touched)} LockedBoxes "
                    f"({', '.join(sorted(touched))}); nested locks risk ABBA deadlock")
        # An accessor must not reference itself: with a non-recursive Mutex the
        # infinite recursion aborts at runtime, and `-swift-version 6` only warns.
        # Only a *bare* reference counts — `context.deadline` inside the `deadline`
        # accessor is member access on another value, not self-re-entry.
        for name, body, line in accessor_bodies(text):
            if not body:
                continue
            if re.search(rf"(?<![\w.]){re.escape(name)}\b", body):
                failures.append(
                    f"{path.name}:{line}: accessor '{name}' references its own name inside "
                    f"its body; with a non-recursive Mutex this self-re-entry aborts")
    return failures


def check_atomic_pairing(files: list[pathlib.Path]) -> list[str]:
    """The signal-handler publication gate must keep a releasing/acquiring pair.

    Only atomics stored with `.releasing` are required to also be read with
    `.acquiring`. An address published once with `.relaxed` is legitimate while a
    separate gate flag carries the release/acquire ordering, so requiring every
    atomic to pair would produce false positives. What must not happen is the pair
    disappearing: downgrading the releasing store or the acquiring load leaves the
    handler with no acquire-side ordering, which is exactly the mutation class that
    `swift build` and `--self-test` both miss.
    """
    store_flags: dict[str, set[str]] = {}
    load_flags: dict[str, set[str]] = {}
    for path in files:
        text = strip_comments(path.read_text())
        for name in PUBLISH_STORE.findall(text):
            store_flags.setdefault(name, set()).add(path.name)
        for name in PUBLISH_LOAD.findall(text):
            load_flags.setdefault(name, set()).add(path.name)

    failures: list[str] = []
    if not store_flags:
        failures.append(
            "no atomic is stored with .releasing; the signal-handler publication gate "
            "lost its release side (or was renamed — update this check)")
    if not load_flags:
        failures.append(
            "no atomic is read with .acquiring; the signal-handler read side lost its "
            "acquire ordering (or was renamed — update this check)")
    for name in sorted(store_flags):
        if name not in load_flags:
            failures.append(
                f"atomic '{name}' is published with .releasing but never read with "
                f".acquiring; the handler would read it without acquire ordering")
    return failures


def check_no_unsafe_annotations(files: list[pathlib.Path]) -> list[str]:
    failures: list[str] = []
    for path in files:
        text = strip_comments(path.read_text())
        for annotation in UNSAFE_ANNOTATION.findall(text):
            failures.append(
                f"{path.name}: uses '{annotation}'; the Swift 6 migration is required to "
                f"express isolation via LockedBox/Atomic/thread-local carriers instead")
    return failures


def check_language_mode() -> list[str]:
    """Package and build script must agree on Swift 6 for the CLI."""
    failures: list[str] = []
    package = (REPO / "Package.swift").read_text()
    cli_block = re.search(r"\.target\(name: \"AutomntCLI\".*?\)", package, re.S)
    if not cli_block:
        failures.append("Package.swift: cannot find the AutomntCLI target declaration")
    elif "swiftLanguageMode(.v6)" not in cli_block.group(0):
        failures.append(
            "Package.swift: AutomntCLI is not declared with swiftLanguageMode(.v6)")
    build = (REPO / "scripts" / "build.sh").read_text()
    if "-swift-version 6" not in build:
        failures.append(
            "scripts/build.sh: release build is not pinned to -swift-version 6")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--quiet", action="store_true", help="print failures only")
    args = parser.parse_args()

    files = swift_files()
    if not files:
        print(f"FAIL: no Swift files under {CLI_DIR.relative_to(REPO)}", file=sys.stderr)
        return 1

    failures = (check_accessors(files)
                + check_atomic_pairing(files)
                + check_no_unsafe_annotations(files)
                + check_language_mode())

    if failures:
        print(f"FAIL  {len(failures)} Swift 6 concurrency invariant violation(s):")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    if not args.quiet:
        text = "\n".join(strip_comments(p.read_text()) for p in files)
        print(f"files checked:        {len(files)} (Sources/AutomntCLI)")
        print(f"LockedBox carriers:   {len(set(BOX_DECL.findall(text)))}")
        print(f"accessors inspected:  {len(accessor_bodies(text))}")
        print(f"atomic publications:  {len(set(PUBLISH_STORE.findall(text)))}")
        print()
        print("PASS  no accessor touches a second LockedBox or re-enters its own lock")
        print("PASS  signal-handler atomics keep their .releasing/.acquiring pairing")
        print("PASS  no nonisolated(unsafe) or @unchecked Sendable in the CLI target")
        print("PASS  Package.swift and scripts/build.sh both compile the CLI as Swift 6")
        print()
        print("Reminder: this is a structural check, not a proof. It cannot see re-entry")
        print("through closures, stored @escaping references or protocol witnesses, and it")
        print("does not establish deadlock freedom. Concurrency stress testing and TSan")
        print("remain separate gates.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
