#!/bin/bash
# Build the signed GUI app with a *pinned* signing identity.
#
# Why: a code signature's designated requirement embeds the leaf certificate CN
# (`certificate leaf[subject.CN] = "Apple Development: name@host (XXXXXXXXXX)"`).
# macOS keys TCC grants and background-task records to that requirement, so
# building with a different Apple Development certificate makes the next build a
# different application and every system authorisation has to be granted again.
# `CODE_SIGN_IDENTITY = Apple Development` is a certificate *type*, not a
# certificate, so xcodebuild would pick whichever identity comes first.
#
# This script resolves one identity (see scripts/sign-identity.py), passes its
# SHA-1 hash so the choice cannot drift, and then refuses to hand back a product
# whose designated requirement differs from the reference identity.
#
# Usage: bash scripts/build-app.sh [derivedDataPath]
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${1:-$TASK_ROOT/.build/xcode}"

RESOLVED="$(python3 "$TASK_ROOT/scripts/sign-identity.py" "${AUTOMNT_SIGN_IDENTITY:-}")"
IDENTITY_CN="$(printf '%s\n' "$RESOLVED" | sed -n 's/^identity=//p')"
TEAM="$(printf '%s\n' "$RESOLVED" | sed -n 's/^team=//p')"
if [[ -z "$IDENTITY_CN" || -z "$TEAM" ]]; then
  echo "build-app: could not resolve a signing identity; see scripts/sign-identity.py" >&2
  exit 2
fi
HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$IDENTITY_CN\"" | head -1 | awk '{print $2}')"
if [[ -z "$HASH" ]]; then
  echo "build-app: identity not found in the keychain: $IDENTITY_CN" >&2
  exit 2
fi

echo "== Automnt app build (identity $IDENTITY_CN, team $TEAM, hash $HASH) =="

# Replacing a differently-signed app is how system authorisations get lost: TCC and
# background-task records follow the designated requirement, which embeds the CN.
# Refuse it unless the caller says the identity change is intended.
INSTALLED_CN="$(codesign -d --verbose=4 /Applications/Automnt.app 2>&1 \
  | sed -n 's/^Authority=\(Apple Development: .*\)$/\1/p' | head -1)"
if [[ -n "$INSTALLED_CN" && "$INSTALLED_CN" != "$IDENTITY_CN" ]] \
   && [[ "${AUTOMNT_ALLOW_IDENTITY_CHANGE:-}" != "1" ]]; then
  echo "build-app: FAIL refusing to build with a different identity than the installed app." >&2
  echo "  installed: $INSTALLED_CN" >&2
  echo "  this build: $IDENTITY_CN" >&2
  echo "  Replacing the app with another certificate makes macOS treat it as a new app and" >&2
  echo "  discard its system authorisations. Set AUTOMNT_ALLOW_IDENTITY_CHANGE=1 only when you" >&2
  echo "  intend to switch identity once, then keep the new one pinned." >&2
  exit 1
fi

xcodebuild -project "$TASK_ROOT/apps/Automnt/Automnt.xcodeproj" -scheme Automnt \
  -configuration Release -derivedDataPath "$DERIVED" \
  DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_IDENTITY="$HASH" CODE_SIGN_STYLE=Manual \
  build

APP="$DERIVED/Build/Products/Release/Automnt.app"
bash "$TASK_ROOT/scripts/verify-signature.sh" "$APP"

# The designated requirement is what macOS matches TCC grants and background-task
# records against, so it must stay identical between builds signed with this
# identity. Remember it per identity and fail on any drift.
BUILT_DR="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p' | head -1)"
DR_FILE="$TASK_ROOT/.build/sign-app-dr"
if [[ -f "$DR_FILE" ]]; then
  STORED_CN="$(sed -n 's/^identity=//p' "$DR_FILE")"
  STORED_DR="$(sed -n 's/^dr=//p' "$DR_FILE")"
  if [[ "$STORED_CN" == "$IDENTITY_CN" && "$STORED_DR" != "$BUILT_DR" ]]; then
    echo "build-app: FAIL designated requirement drifted; system authorisations would be lost." >&2
    echo "  previous: $STORED_DR" >&2
    echo "  built:    $BUILT_DR" >&2
    exit 1
  fi
  if [[ "$STORED_CN" != "$IDENTITY_CN" ]]; then
    echo "build-app: noted identity change $STORED_CN -> $IDENTITY_CN (authorisations must be granted once again)" >&2
  fi
fi
printf 'identity=%s\ndr=%s\n' "$IDENTITY_CN" "$BUILT_DR" > "$DR_FILE"
if [[ "$BUILT_DR" != *'certificate leaf[subject.CN] = "'"$IDENTITY_CN"'"'* ]]; then
  echo "build-app: FAIL designated requirement does not name the pinned identity: $BUILT_DR" >&2
  exit 1
fi
echo "PASS designated requirement stays pinned to $IDENTITY_CN"
echo "app=$APP"
