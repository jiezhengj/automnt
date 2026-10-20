#!/usr/bin/env python3
"""Verify GUI user-facing copy is localized in every supported language.

Why this exists: the extract-and-compare step is easy to do by hand once and then
silently rot. A new `Text("…")` added without a catalog entry looks perfect in
English-on-English review and only surfaces on a Mac set to another language.
This script turns "every visible string has nine translations" into a check that
fails loudly.

Scope and honesty:
- It checks *key coverage*, *per-language presence* and (by default) that a
  non-English value is not a verbatim copy of the English source. It cannot judge
  translation quality: a non-empty, differently-worded value may still be an
  unreviewed machine draft. Native review is a separate, human gate (see
  specs/005-swiftui-mas-gui/design/localization.md).
- The verbatim-copy check needs an allowlist, because a brand name and a handful of
  borrowed words are legitimately identical in another language. The allowlist is
  exact `(language, key)` pairs, so a *new* English backfill fails even if the
  wording happens to match an existing allowed term. `--require-translated` ignores
  the allowlist entirely and is the strictest mode.
- `NotificationCopy` (the GUI notification banner) is hand-written nine-language
  code rather than catalog entries, so it is inspected separately; otherwise a
  whole user-visible surface would sit outside this gate. For it, "untranslated" is
  judged on normalized *skeletons* rather than exact strings, and containment counts
  in both directions: exact comparison alone missed "the English sentence plus a
  prefix" and "the English title plus a suffix" (F10), and trimming as well as
  decorating produces the same defect.
- Known limit: a *freshly reworded* English sentence placed in a non-English branch
  is not detectable here. Telling it apart from a genuine translation would require
  language identification, and a heuristic such as "German must contain a non-ASCII
  letter" rejects valid German ("Server nicht erreichbar"). This gate is a floor,
  not a substitute for native review.

Usage:
    python3 scripts/verify-localization.py                 # report, exit 1 on gap
    python3 scripts/verify-localization.py --require-translated
    python3 scripts/verify-localization.py --quiet          # only failures
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import unicodedata

REPO = pathlib.Path(__file__).resolve().parents[1]
APP_DIR = REPO / "apps" / "Automnt"
CATALOG = APP_DIR / "Resources" / "Localizable.xcstrings"

# Hand-written nine-language copy that is not backed by the catalog.
NOTIFICATION_COPY = REPO / "Sources" / "AutomntPlatform" / "SystemUserNotifier.swift"
NOTIFICATION_COPY_SYMBOL = "enum NotificationCopy"

# The notification banner's copy lives in its own SwiftPM resource catalog. It was added
# later than the app catalog and sat entirely outside this gate — a known blind spot
# reported by verification, closed here. Its keys are the plural templates the system
# selects CLDR categories from, so each must ship every category its language uses.
PLATFORM_CATALOG = REPO / "Sources" / "AutomntPlatform" / "Resources" / "Localizable.xcstrings"

# CLDR cardinal categories each language actually uses for integer counts
# (Unicode CLDR 48, per specs/005-swiftui-mas-gui/design/localization.md).
# A resource must not ship a category the language never selects, and must not omit
# one it does; both are silent at build time and only surface as wrong wording.
PLURAL_CATEGORIES = {
    "en": {"one", "other"},
    "de": {"one", "other"},
    "fr": {"one", "many", "other"},
    "es": {"one", "many", "other"},
    "pt-BR": {"one", "many", "other"},
    "zh-Hans": {"other"},
    "zh-Hant": {"other"},
    "ja": {"other"},
    "ko": {"other"},
}

# The languages T030/T060 declare for the GUI. Order is only for stable output.
LANGUAGES = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"]

# SwiftUI/Foundation entry points whose *first string argument* is user-facing copy.
# `Text(verbatim:)` is deliberately absent: verbatim copy is not localized, and
# treating it as a catalog key would produce false requirements.
CALL_PATTERNS = [
    r"Text\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Button\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Label\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Toggle\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Section\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"ContentUnavailableView\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"navigationTitle\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"LabeledContent\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"String\(localized:\s*\"((?:[^\"\\]|\\.)*)\"",
    # Input labels and confirmation titles are as user-visible as a button, but
    # an earlier revision of this script missed them: the gap only surfaced when
    # a wider extraction was compared against it. Keep them in scope.
    r"TextField\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"SecureField\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"confirmationDialog\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"alert\(\s*\"((?:[^\"\\]|\\.)*)\"",
    # Scene/window titles are shown in the window bar and the Window menu.
    r"WindowGroup\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"MenuBarExtra\(\s*\"((?:[^\"\\]|\\.)*)\"",
    # Assistive and discoverability copy: invisible in a screenshot, still read to
    # the user, and the API shape also reaches VoiceOver. A specific verification
    # round added these after proving the older set let them pass unnoticed.
    r"navigationSubtitle\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"accessibilityLabel\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"accessibilityHint\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"accessibilityValue\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"help\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"\.help\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Picker\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Menu\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Link\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"Stepper\(\s*\"((?:[^\"\\]|\\.)*)\"",
    r"GroupBox\(\s*\"((?:[^\"\\]|\\.)*)\"",
    # Labels handed over as a named argument rather than positionally. A `Toggle`
    # written as `Toggle(isOn:value:)` with a `label:` string would otherwise slip
    # through: only the trailing-closure form was covered before.
    r"\blabel:\s*\"((?:[^\"\\]|\\.)*)\"",
    r"\btitle:\s*\"((?:[^\"\\]|\\.)*)\"",
    r"\bmessage:\s*\"((?:[^\"\\]|\\.)*)\"",
]
COMPILED = [re.compile(p) for p in CALL_PATTERNS]

# Copy built by interpolation must use a format resource, not string concatenation.
# Surface it so it is a conscious decision rather than an oversight.
INTERPOLATION = re.compile(r"\\\(")

# Non-English values that may legitimately equal the English source text. Keys are
# language codes, values are the exact source strings. Every pair here is a brand
# name (never translated) or a word that is genuinely spelled the same in that
# language. Verified against the compiled products, not asserted from memory.
TRANSLATION_ALLOWLIST: dict[str, set[str]] = {
    # Product brand: never translated, in any language.
    "zh-Hans": {"Automnt"},
    "zh-Hant": {"Automnt"},
    "ja": {"Automnt"},
    "ko": {"Automnt"},
    "de": {"Automnt", "Name", "Port", "Server"},
    "fr": {"Automnt", "Notifications", "Port", "Diagnostics"},
    "es": {"Automnt"},
    "pt-BR": {"Automnt"},
}

# Phrases that would advertise an action the GUI does not provide. The GUI has no
# "remount now" command (only the CLI does), so a banner must not name one.
FORBIDDEN_NOTIFICATION_ACTIONS = [
    "Remount",
    "remount",
    "重新挂载",
    "重新掛載",
    "再マウント",
    "다시 마운트",
    "erneut verbinden",
    "Reconnecter",
    "Reconectar",
    "Volver a conectar",
]

# Private-target shapes that must never reach a user-visible string.
PRIVATE_TARGET_PATTERNS = [
    re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),
    re.compile(r"smb://", re.IGNORECASE),
    re.compile(r"/Users/"),
    re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
]


def skeleton(value: str) -> str:
    """Collapse a user-visible string to a language-neutral shape for comparison.

    Interpolations, numbers and punctuation are erased so that "1 shared folder could
    not be mounted" and "\\\\(number) shared folders could not be mounted" compare equal,
    which is what makes containment meaningful across singular/plural variants.
    """
    folded = unicodedata.normalize("NFKC", value)
    # Swift interpolation and any run of digits become a single placeholder.
    folded = re.sub(r"\\\([^)]*\)", " ", folded)
    folded = re.sub(r"\d+", " ", folded)
    folded = folded.lower()
    # Drop punctuation and symbols; CJK/Korean/Japanese letters survive as-is.
    folded = "".join(ch if ch.isalnum() or ch.isspace() else " " for ch in folded)
    return " ".join(folded.split())


def swift_sources() -> list[pathlib.Path]:
    """Every Swift file in the GUI module, at any depth.

    A non-recursive glob silently skipped `Views/<NewFolder>/…`; a verification
    round proved that by adding a view one directory deeper and watching the gate
    pass. Recurse so a new subdirectory cannot create an unguarded surface.
    """
    return sorted(APP_DIR.rglob("*.swift"))


def extract_strings() -> dict[str, list[str]]:
    """Map each user-facing literal to the `path:line` sites that use it."""
    found: dict[str, list[str]] = {}
    for path in swift_sources():
        for number, line in enumerate(path.read_text().splitlines(), 1):
            for pattern in COMPILED:
                for match in pattern.finditer(line):
                    value = match.group(1)
                    relative = f"{path.relative_to(REPO)}:{number}"
                    sites = found.setdefault(value, [])
                    # Two patterns can legitimately match one site (`help(` and
                    # `.help(`); report each site once.
                    if relative not in sites:
                        sites.append(relative)
    return found


def check_notification_copy() -> list[str]:
    """Inspect the hand-written nine-language GUI banner copy.

    Returns a list of failure messages (empty means the check passed). This surface
    is not in the catalog and is not built with `String(localized:)`, so the
    catalog-driven checks above cannot see it at all.
    """
    failures: list[str] = []
    if not NOTIFICATION_COPY.exists():
        return [f"notification copy source not found: {NOTIFICATION_COPY.relative_to(REPO)}"]
    source = NOTIFICATION_COPY.read_text()
    if NOTIFICATION_COPY_SYMBOL not in source:
        return [f"{NOTIFICATION_COPY.relative_to(REPO)} no longer declares {NOTIFICATION_COPY_SYMBOL}"]

    body = source.split(NOTIFICATION_COPY_SYMBOL, 1)[1]

    # Each language is one `return (...)`. Splitting on the keyword avoids having to
    # balance parentheses in Swift, and the language-selection literals inside
    # `hasPrefix("…")` are excluded explicitly below so they are not mistaken for copy.
    literal = re.compile(r'"((?:[^"\\]|\\.)*)"')
    prefix_call = re.compile(r"language\.hasPrefix\(\s*\"((?:[^\"\\]|\\.)*)\"")
    returns = [m.start() for m in re.finditer(r"\breturn\s*\(", body)]
    if len(returns) < len(LANGUAGES):
        failures.append(
            f"NotificationCopy has {len(returns)} language branch(es); "
            f"{len(LANGUAGES)} are required")

    titles: list[str] = []
    # Messages carry the actual guidance, so they need the same backfill scrutiny as
    # titles. Checking only "distinct titles" left half of this surface unguarded:
    # replacing four languages' messages with the English sentence kept every rule
    # green in both this gate and the Swift test (found as F7 by verification).
    branch_messages: list[tuple[str, str, list[str]]] = []
    for index, start in enumerate(returns, 1):
        end = returns[index] if index < len(returns) else len(body)
        # The selector for this branch is the `hasPrefix(...)` immediately before its
        # `return`, so scan the gap since the previous branch. The final fallback
        # branch has no selector, which is how the English copy is identified.
        gap_start = 0 if index == 1 else returns[index - 2]
        selectors = {m.group(1) for m in prefix_call.finditer(body[gap_start:start])}
        # Drop the `hasPrefix("…")` language codes before collecting copy: they are
        # selectors, not user-visible text.
        chunk = prefix_call.sub("", body[start:end])
        strings = literal.findall(chunk)
        if len(strings) < 2:
            failures.append(f"NotificationCopy branch {index} has fewer than a title and a message")
            continue
        title, messages = strings[0], strings[1:]
        titles.append(title)
        branch_messages.append((next(iter(selectors), ""), title, messages))
        if not title.strip():
            failures.append(f"NotificationCopy branch {index} has an empty title")
        for message in messages:
            if not message.strip():
                failures.append(f"NotificationCopy branch {index} has an empty message")
        for value in (title, *messages):
            if "Automnt" not in value:
                failures.append(
                    f"NotificationCopy branch {index} omits the GUI brand 'Automnt': {value!r}")
            # NFKC folds full-width lookalikes (ａｕｔｏｍｎｔ) onto ASCII, which a plain
            # ASCII regex misses in both this gate and the Swift test (F6).
            # Deliberately NOT case-insensitive: `Automnt` is the correct GUI spelling,
            # so only the lowercase CLI spelling is a failure here.
            if re.search(r"(?<![A-Za-z])automnt(?![A-Za-z])",
                         unicodedata.normalize("NFKC", value)):
                failures.append(
                    f"NotificationCopy branch {index} uses the CLI brand spelling "
                    f"'automnt' in the GUI channel: {value!r}")
            folded_value = unicodedata.normalize("NFKC", value).lower()
            for phrase in FORBIDDEN_NOTIFICATION_ACTIONS:
                # Case-insensitive, and NFKC-normalized so a full-width or
                # differently-cased spelling cannot slip past (F7-b).
                if unicodedata.normalize("NFKC", phrase).lower() in folded_value:
                    failures.append(
                        f"NotificationCopy branch {index} advertises an action the GUI "
                        f"does not provide: {phrase!r} in {value!r}")
            for pattern in PRIVATE_TARGET_PATTERNS:
                if pattern.search(value):
                    failures.append(
                        f"NotificationCopy branch {index} contains a private target: {value!r}")

    # Backfill: any user-visible string in another language that is byte-identical to
    # *any* English string is not translated. The English copy is the selector-less
    # fallback branch. Comparing against its messages alone was too narrow: swapping a
    # translated message for the English *title* matched nothing and passed both this
    # gate and the Swift test (found as F9 by verification), so the whole English
    # branch — title and messages — forms the comparison set.
    english_forms: set[str] = set()
    for selector, title, messages in branch_messages:
        if not selector:
            english_forms.update([title, *messages])
    if not english_forms:
        failures.append("NotificationCopy has no fallback branch providing the English copy")
    for selector, title, messages in branch_messages:
        if not selector:
            continue
        shared = english_forms.intersection([title, *messages])
        if shared:
            failures.append(
                f"NotificationCopy branch for '{selector}' reuses English copy "
                f"verbatim: {sorted(shared)[0]!r}")

    # Exact-set membership alone let "the English sentence plus decoration" through:
    # prefixing the English message with "Notice: " (or appending "(details)" to the
    # English title) matched no member and left every other rule satisfied, so both
    # this gate and the Swift test passed (found as F10 by verification, alongside the
    # older-wording variant where a translation reverts to a previous English string).
    #
    # Compare skeletons instead of exact strings: after normalization, a non-English
    # string that is equal to, contains, or is contained by an English string is
    # treated as untranslated. Containment is symmetric on purpose - the same
    # regression can be produced by trimming as by decorating.
    english_skeletons = {skeleton(form) for form in english_forms if skeleton(form)}
    for selector, title, messages in branch_messages:
        if not selector:
            continue
        for value in (title, *messages):
            sk = skeleton(value)
            if not sk:
                continue
            match = next((en for en in english_skeletons if sk == en or en in sk or sk in en), None)
            if match is not None:
                failures.append(
                    f"NotificationCopy branch for '{selector}' is untranslated English "
                    f"(same skeleton as {match!r}): {value!r}")

    # Every declared GUI language must be selectable: each language needs one
    # `hasPrefix("<code>")` test, and Chinese additionally accepts the regional codes.
    tested = {m.group(1) for m in prefix_call.finditer(body)}
    required_prefixes = {"zh-hant", "zh", "ja", "ko", "de", "fr", "es", "pt"}
    absent = sorted(required_prefixes - tested)
    if absent:
        failures.append(f"NotificationCopy has no language branch for: {', '.join(absent)}")

    if titles and len(set(titles)) != len(titles):
        failures.append("NotificationCopy titles are not distinct across languages")

    # The es branch must use the catalog term `recuperación`, not `restauración`.
    if re.search(r"Restauración|restaurar", body):
        failures.append(
            "NotificationCopy uses 'Restauración/restaurar' for es; the catalog baseline "
            "term is 'Recuperación automática'")
    return failures


def check_platform_catalog() -> list[str]:
    """Verify the notification banner's own catalog ships the right CLDR categories.

    The banner's plural wording comes from `Sources/AutomntPlatform/Resources/`, which the
    app-catalog checks never looked at. Dropping a `many` form for fr/es/pt-BR is silent at
    build time and only shows up as wrong French/Spanish wording in a real notification.
    """
    failures: list[str] = []
    if not PLATFORM_CATALOG.exists():
        return [f"notification catalog missing at {PLATFORM_CATALOG.relative_to(REPO)}"]
    try:
        catalog = json.loads(PLATFORM_CATALOG.read_text())
    except json.JSONDecodeError as error:
        return [f"notification catalog is not valid JSON: {error}"]

    strings = catalog.get("strings")
    if not isinstance(strings, dict) or not strings:
        return ["notification catalog has no 'strings' object"]

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit")
            plural = localizations.get(language, {}).get("variations", {}).get("plural")
            if plural:
                shipped = set(plural)
                expected = PLURAL_CATEGORIES[language]
                if shipped != expected:
                    failures.append(
                        f"notification key {key!r} [{language}] ships plural categories "
                        f"{sorted(shipped)}; CLDR cardinal requires {sorted(expected)}")
                for category, form in plural.items():
                    value = form.get("stringUnit", {}).get("value")
                    if not isinstance(value, str) or not value.strip():
                        failures.append(
                            f"notification key {key!r} [{language}/{category}] is empty")
            elif unit is not None:
                value = unit.get("value")
                if not isinstance(value, str) or not value.strip():
                    failures.append(f"notification key {key!r} [{language}] is empty")
            else:
                failures.append(
                    f"notification key {key!r} has no entry for {language}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--require-translated", action="store_true",
                        help="fail on every English-copy value, ignoring the allowlist")
    parser.add_argument("--quiet", action="store_true", help="print failures only")
    args = parser.parse_args()

    if not CATALOG.exists():
        print(f"FAIL: catalog not found at {CATALOG}", file=sys.stderr)
        return 1
    try:
        catalog = json.loads(CATALOG.read_text())
    except json.JSONDecodeError as error:
        print(f"FAIL: catalog is not valid JSON: {error}", file=sys.stderr)
        return 1

    strings = catalog.get("strings")
    if not isinstance(strings, dict):
        print("FAIL: catalog has no 'strings' object", file=sys.stderr)
        return 1

    used = extract_strings()
    missing = {value: sites for value, sites in used.items() if value not in strings}
    interpolated = sorted(value for value in used if INTERPOLATION.search(value))

    incomplete: dict[str, list[str]] = {}
    identical: dict[str, list[str]] = {}
    for value in sorted(used):
        entry = strings.get(value)
        if entry is None:
            continue
        localizations = entry.get("localizations", {})
        gaps = []
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit", {})
            translated = unit.get("value")
            if not isinstance(translated, str) or not translated.strip():
                gaps.append(language)
        if gaps:
            incomplete[value] = gaps
            continue
        source = localizations.get("en", {}).get("stringUnit", {}).get("value", value)
        same = [language for language in LANGUAGES
                if language != "en"
                and localizations[language]["stringUnit"]["value"] == source]
        if not args.require_translated:
            # Default: allow only the documented brand/borrowed-word pairs.
            same = [language for language in same
                    if source not in TRANSLATION_ALLOWLIST.get(language, set())]
        if same:
            identical[value] = same

    notification_failures = check_notification_copy()
    platform_failures = check_platform_catalog()

    ok = not (missing or incomplete or identical or notification_failures or platform_failures)

    if not args.quiet or not ok:
        print(f"catalog: {CATALOG.relative_to(REPO)}")
        print(f"source strings found: {len(used)}   catalog keys: {len(strings)}")
        print(f"languages required:   {', '.join(LANGUAGES)}")
        print(f"swift files scanned:  {len(swift_sources())} (recursive)")
        print()
        if missing:
            print(f"FAIL  {len(missing)} source string(s) have no catalog entry:")
            for value, sites in sorted(missing.items()):
                print(f"  - {value!r}  ({', '.join(sites[:3])}{', …' if len(sites) > 3 else ''})")
        if incomplete:
            print(f"FAIL  {len(incomplete)} key(s) are missing language branches:")
            for value, gaps in sorted(incomplete.items()):
                print(f"  - {value!r}  missing: {', '.join(gaps)}")
        if identical:
            mode = "ignoring the allowlist" if args.require_translated else "outside the allowlist"
            print(f"FAIL  {len(identical)} key(s) reuse the English text for other languages ({mode}):")
            for value, same in sorted(identical.items()):
                print(f"  - {value!r}  identical in: {', '.join(same)}")
        if notification_failures:
            print(f"FAIL  {len(notification_failures)} problem(s) in the hand-written "
                  f"NotificationCopy banner copy:")
            for failure in notification_failures:
                print(f"  - {failure}")
        if platform_failures:
            print(f"FAIL  {len(platform_failures)} problem(s) in the notification banner "
                  f"catalog ({PLATFORM_CATALOG.relative_to(REPO)}):")
            for failure in platform_failures:
                print(f"  - {failure}")
        if interpolated:
            # Not a failure by itself: it flags copy that needs a format resource.
            print(f"NOTE  {len(interpolated)} source string(s) contain interpolation; confirm a format resource:")
            for value in interpolated:
                print(f"  - {value!r}  ({', '.join(used[value][:3])})")
        if ok:
            print(f"PASS  all {len(used)} source string(s) have non-empty entries "
                  f"in all {len(LANGUAGES)} languages")
            print("PASS  no non-English value copies the English source outside the "
                  "documented brand/borrowed-word allowlist")
            print("PASS  NotificationCopy has distinct, branded, redacted copy in every "
                  "language and names no action the GUI lacks")
            print(f"PASS  notification banner catalog ships the CLDR plural categories each "
                  f"of the {len(LANGUAGES)} languages uses")
            if args.require_translated:
                print("      (--require-translated: allowlist ignored; no non-English value "
                      "equals the English source)")
            print()
            print("Reminder: this checks presence, branding and backfill — not quality.")
            print("Unreviewed drafts are not approved translations; native review remains a")
            print("separate gate.")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
