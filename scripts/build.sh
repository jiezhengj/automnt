#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_OUTPUT="${1:-$TASK_ROOT/.build/automnt}"
python3 "$TASK_ROOT/scripts/generate-version.py"
python3 "$TASK_ROOT/scripts/generate-version.py" --check
# User-visible GUI copy must stay localized in all nine declared languages.
# Cheap, and it runs on every build so a new unlocalized string cannot ship unnoticed.
if [[ -f "$TASK_ROOT/apps/Automnt/Resources/Localizable.xcstrings" ]]; then
  python3 "$TASK_ROOT/scripts/verify-localization.py" --quiet
fi
# Swift 6 concurrency invariants for the CLI target. These are structural properties
# the compiler and `--self-test` both miss: accessor re-entry aborts at runtime with
# only a compiler warning, nested locks risk deadlock, and the signal-handler atomic
# pairing can be downgraded silently.
if [[ -f "$TASK_ROOT/scripts/verify-swift6-concurrency.py" ]]; then
  python3 "$TASK_ROOT/scripts/verify-swift6-concurrency.py" --quiet
fi
TASK_SDK="$(xcrun --sdk macosx --show-sdk-path)"
TASK_TMP="$(mktemp -d "${TMPDIR:-/tmp}/automnt-build.XXXXXX")"
trap 'if [[ "$TASK_TMP" == "${TMPDIR:-/tmp}"/automnt-build.* && -d "$TASK_TMP" ]]; then rm -r -- "$TASK_TMP"; fi' EXIT
mkdir -p "$(dirname "$TASK_OUTPUT")"
# Package.swift is authoritative for source membership. No directory wildcard compilation.
/usr/bin/swift package --package-path "$TASK_ROOT" describe --type json > "$TASK_TMP/package.json"
python3 - "$TASK_ROOT" "$TASK_TMP" <<'PY'
import json
import pathlib
import sys
root, temp = map(pathlib.Path, sys.argv[1:])
package = json.loads((temp / 'package.json').read_text())
sources = []
for name in ('AutomntCore', 'AutomntCLI'):
    target = next(t for t in package['targets'] if t['name'] == name)
    sources += [root / target['path'] / source for source in target['sources']]
# Root declaration is already present in the temporary main entry.
contents = '\n'.join(p.read_text() for p in sources)
contents = contents.replace('var automntVersion: String { AutomntBuildVersion.value }', '')
(temp / 'Shared.swift').write_text(contents)
(temp / 'main.swift').write_text((root / 'automnt.swift').read_text())
PY
/usr/bin/swiftc -O -swift-version 6 -sdk "$TASK_SDK" -target arm64-apple-macosx27.0 "$TASK_TMP/Shared.swift" "$TASK_TMP/main.swift" -o "$TASK_OUTPUT"
# 正式运行产物必须可被 macOS 验证，且 CLI 的 --install/替换校验要求候选带
# `anchor apple generic and identifier "automnt"`。未签名的输出会在安装时被拒
# （"代码签名无效或与已安装版本身份不兼容"），故此处显式签名并严格验证。
# 身份来源：显式 AUTOMNT_SIGN_IDENTITY，否则自动取本机第一个 Apple Development/Developer ID Application。
# 没有可用身份时给出明确警告，不静默产出无法自我安装的二进制。
TASK_SIGN_IDENTITY="${AUTOMNT_SIGN_IDENTITY:-}"
if [[ -z "$TASK_SIGN_IDENTITY" ]]; then
  # 身份连续性：Designated Requirement 内嵌叶子证书 CN，换证书会改变系统识别到的
  # 程序身份（违反宪法 V）。因此优先复用现有根二进制已用的身份，再退回任意可用身份。
  if [[ -f "$TASK_ROOT/automnt" ]]; then
    TASK_EXISTING_CN="$(/usr/bin/codesign -d --verbose=4 "$TASK_ROOT/automnt" 2>&1 \
      | grep -E '^Authority=(Apple Development|Developer ID Application): ' \
      | head -1 | sed 's/^Authority=//')"
    if [[ -n "$TASK_EXISTING_CN" ]] \
      && security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$TASK_EXISTING_CN\""; then
      TASK_SIGN_IDENTITY="$TASK_EXISTING_CN"
    fi
  fi
fi
if [[ -z "$TASK_SIGN_IDENTITY" ]]; then
  TASK_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -oE '"(Apple Development|Developer ID Application): [^"]*"' \
    | head -1 | tr -d '"')"
fi
if [[ -n "$TASK_SIGN_IDENTITY" ]]; then
  /usr/bin/codesign --force --sign "$TASK_SIGN_IDENTITY" --identifier automnt \
    --options runtime --timestamp=none "$TASK_OUTPUT"
  /usr/bin/codesign --verify --strict "$TASK_OUTPUT"
  echo "signed: $TASK_SIGN_IDENTITY (identifier automnt)"
else
  echo "⚠ 未找到签名身份：产物未签名，无法通过 --install 的签名校验。" >&2
  echo "  设置 AUTOMNT_SIGN_IDENTITY 或安装 Apple Development 证书后重试。" >&2
fi
"$TASK_OUTPUT" --version
