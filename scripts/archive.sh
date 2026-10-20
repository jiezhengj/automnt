#!/bin/bash
# Reproducible offline archive for the GUI app and prebuilt CLI.
# Requires a signing team via DEVELOPMENT_TEAM (no personal team is hardcoded).
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^let automntVersion = "\(.*\)"/\1/p' "$TASK_ROOT/automnt.swift")"
TEAM="${DEVELOPMENT_TEAM:-}"
IDENTITY="${CODE_SIGN_IDENTITY:-Apple Development}"
OUT="${1:-$TASK_ROOT/.build/offline/$VERSION}"

if [[ -z "$TEAM" ]]; then
  echo "DEVELOPMENT_TEAM is required (the repository never hardcodes a personal team)." >&2
  exit 2
fi
if [[ -z "$VERSION" ]]; then
  echo "Could not read the sole version declaration from automnt.swift." >&2
  exit 2
fi

rm -rf "$OUT"
mkdir -p "$OUT/build" "$OUT/payload"
DERIVED="$OUT/build/DerivedData"
echo "== Archiving Automnt $VERSION (team $TEAM) =="

echo "-- Package tests"
(cd "$TASK_ROOT" && swift test)

echo "-- Optimized CLI + self-test"
(cd "$TASK_ROOT" && bash scripts/build.sh "$OUT/build/automnt")
"$OUT/build/automnt" --version
"$OUT/build/automnt" --self-test

echo "-- Signed Release app"
xcodebuild -project "$TASK_ROOT/apps/Automnt/Automnt.xcodeproj" -scheme Automnt \
  -configuration Release -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual \
  build

APP="$DERIVED/Build/Products/Release/Automnt.app"
echo "-- Signature, localization and Swift 6 gates"
bash "$TASK_ROOT/scripts/verify-signature.sh" "$APP"
python3 "$TASK_ROOT/scripts/verify-localization.py" --quiet
python3 "$TASK_ROOT/scripts/verify-swift6-concurrency.py" >/dev/null

echo "-- Payload"
ditto "$APP" "$OUT/payload/Automnt.app"
install -m 0755 "$OUT/build/automnt" "$OUT/payload/automnt"
install -m 0644 "$TASK_ROOT/release/offline/install.zh.md" "$OUT/payload/Install-zh.md"
install -m 0644 "$TASK_ROOT/release/offline/install.en.md" "$OUT/payload/Install-en.md"
install -m 0644 "$TASK_ROOT/release/offline/known-limitations.zh.md" "$OUT/payload/Known-Limitations-zh.md"
install -m 0644 "$TASK_ROOT/release/offline/known-limitations.en.md" "$OUT/payload/Known-Limitations-en.md"
install -m 0644 "$TASK_ROOT/release/offline/release-notes.zh.md" "$OUT/payload/Release-Notes-zh.md"
install -m 0644 "$TASK_ROOT/release/offline/release-notes.en.md" "$OUT/payload/Release-Notes-en.md"

ARCHIVE="$OUT/Automnt-$VERSION-offline.zip"
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$OUT/payload" "$ARCHIVE"
(cd "$OUT" && shasum -a 256 "Automnt-$VERSION-offline.zip" > "Automnt-$VERSION-offline.zip.sha256")

{
  echo "version=$VERSION"
  echo "team=$TEAM"
  echo "identity=$IDENTITY"
  echo "xcodebuild=$(xcodebuild -version | tr '\n' ' ')"
  echo "swift=$(swift --version | head -1)"
  echo "archive=$(basename "$ARCHIVE")"
  echo "sha256=$(cut -d' ' -f1 "$ARCHIVE.sha256")"
} > "$OUT/manifest.txt"

echo "== Done =="
cat "$OUT/manifest.txt"
echo "Archive: $ARCHIVE"
