#!/bin/bash
# Generate the macOS AppIcon asset catalog from the reviewed design source.
# The source is never modified. Lower resolutions use the macOS `sips` utility;
# the 1024-pixel output is copied byte-for-byte. Check mode regenerates every
# expected output in a private temporary directory and compares contents.
#
# Usage:
#   bash scripts/generate-app-icon.sh            # write the appiconset
#   bash scripts/generate-app-icon.sh --check    # verify, do not write assets
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$TASK_ROOT/specs/005-swiftui-mas-gui/design/app-icon-1024.png"
ICONSET="$TASK_ROOT/apps/Automnt/Resources/Assets.xcassets/AppIcon.appiconset"
CHECK=0
case "${1:-}" in
  "") [[ $# -eq 0 ]] || { echo "Usage: $0 [--check]" >&2; exit 2; } ;;
  --check) [[ $# -eq 1 ]] || { echo "Usage: $0 [--check]" >&2; exit 2; }; CHECK=1 ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

if [[ ! -f "$SOURCE" ]]; then
  echo "FAIL: design source not found: $SOURCE" >&2
  exit 1
fi
if ! command -v sips >/dev/null 2>&1; then
  echo "FAIL: sips not found; it is required to generate the icon" >&2
  exit 1
fi
source_size="$(sips -g pixelWidth -g pixelHeight "$SOURCE" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
if [[ "$source_size" != "1024x1024" ]]; then
  echo "FAIL: design source must be 1024x1024, actual $source_size" >&2
  exit 1
fi

# macOS uses five nominal sizes, each at 1x and 2x.
SIZES=(16 32 128 256 512)
render_icon() {
  local pixels="$1" out="$2"
  if [[ $pixels -eq 1024 ]]; then
    cp "$SOURCE" "$out"
  else
    sips -z "$pixels" "$pixels" "$SOURCE" --out "$out" >/dev/null
  fi
}

if [[ $CHECK -eq 1 ]]; then
  # Check mode never creates or modifies the real asset tree.
  TEMP_PARENT="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  CHECK_DIR="$(mktemp -d "$TEMP_PARENT/automnt-icon-check.XXXXXX")"
  cleanup() {
    # Resolve and verify the precise directory before deleting it.
    if [[ -d "$CHECK_DIR" && ! -L "$CHECK_DIR" ]]; then
      local resolved
      resolved="$(cd "$CHECK_DIR" && pwd -P)" || return 1
      case "$resolved" in
        "$TEMP_PARENT"/automnt-icon-check.*)
          [[ "${resolved%/*}" == "$TEMP_PARENT" && "$resolved" == "$CHECK_DIR" ]] || return 1
          rm -rf -- "${CHECK_DIR:?}"
          ;;
        *) echo "FAIL: refusing unexpected cleanup path: $resolved" >&2; return 1 ;;
      esac
    fi
  }
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  failed=0
  for size in "${SIZES[@]}"; do
    for scale in 1 2; do
      pixels=$((size * scale))
      suffix=""; [[ $scale -eq 2 ]] && suffix="@2x"
      name="icon_${size}x${size}${suffix}.png"
      file="$ICONSET/$name"
      if [[ ! -f "$file" ]]; then
        echo "FAIL missing: $name" >&2; failed=1; continue
      fi
      actual="$(sips -g pixelWidth -g pixelHeight "$file" 2>/dev/null | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')" || actual="unreadable"
      if [[ "$actual" != "${pixels}x${pixels}" ]]; then
        echo "FAIL $name: declared ${pixels}x${pixels}, actual $actual" >&2; failed=1
      fi
      render_icon "$pixels" "$CHECK_DIR/$name"
      if ! cmp -s "$file" "$CHECK_DIR/$name"; then
        echo "FAIL stale content: $name does not match the current design source" >&2; failed=1
      fi
    done
  done
  [[ $failed -ne 0 ]] || echo "PASS all 10 appiconset PNGs match declared sizes and current source contents"
  exit "$failed"
fi

mkdir -p "$ICONSET"
for size in "${SIZES[@]}"; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""; [[ $scale -eq 2 ]] && suffix="@2x"
    render_icon "$pixels" "$ICONSET/icon_${size}x${size}${suffix}.png"
  done
done

cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png",      "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png",      "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png",    "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png",    "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png",    "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "generated appiconset: $ICONSET"
bash "$0" --check
