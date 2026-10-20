#!/usr/bin/env python3
"""Verify actual signatures and declared sandbox entitlements, without launching code."""
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGETS = [
    ('app', pathlib.Path('.'), 'org.automnt.automnt', 'apps/Automnt/Resources/Automnt.entitlements'),
    ('helper', pathlib.Path('Contents/Helpers/AutomntHelper'), 'org.automnt.automnthelper', 'apps/Automnt/Service/Helper.entitlements'),
    ('worker', pathlib.Path('Contents/Helpers/AutomntWorker'), 'org.automnt.automntworker', 'apps/Automnt/Worker/Worker.entitlements'),
]
# Xcode may add development metadata. These do not grant a different sandbox capability.
GENERATED_KEYS = {'com.apple.developer.team-identifier', 'com.apple.application-identifier',
                  'application-identifier', 'com.apple.security.get-task-allow'}


def command(args):
    result = subprocess.run(args, capture_output=True, timeout=30)
    if result.returncode:
        detail = result.stderr.decode(errors='replace').strip()
        raise ValueError(f'{args[0]} failed (exit {result.returncode}): {detail}')
    return result


def fail(message):
    print('FAIL: ' + message, file=sys.stderr)
    return 1


def main():
    if len(sys.argv) != 2:
        return fail('expected one application-bundle path')
    app = pathlib.Path(sys.argv[1]).resolve()
    if not (app / 'Contents/Info.plist').is_file():
        return fail('application Info.plist is absent')
    verified_team = None
    try:
        for role, relative, identifier, declaration in TARGETS:
            code = app / relative
            if not code.exists():
                raise ValueError(f'{role}: embedded executable is absent')
            command(['codesign', '--verify', '--strict', '--all-architectures', str(code)])
            metadata = command(['codesign', '-d', '--verbose=4', str(code)]).stderr.decode(errors='replace')
            fields = dict(re.findall(r'^([^=\n]+)=(.*)$', metadata, re.M))
            team = fields.get('TeamIdentifier')
            if fields.get('Signature') == 'adhoc' or not team or team == 'not set':
                raise ValueError(f'{role}: unsigned/ad-hoc code is not a development or distribution identity')
            if not re.fullmatch(r'[A-Z0-9]+', team):
                raise ValueError(f'{role}: invalid team identifier')
            if fields.get('Identifier') != identifier:
                raise ValueError(f'{role}: unexpected signing identifier')
            if verified_team is None:
                verified_team = team
            elif team != verified_team:
                raise ValueError(f'{role}: signing team differs from containing application')
            # Identifiers intentionally differ. Validate each against its own identifier
            # and the containing application's team, rather than requiring identical DRs.
            requirement = f'anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{team}"'
            command(['codesign', '--verify', '--strict', '--all-architectures', '-R', '=' + requirement, str(code)])
            actual = plistlib.loads(command(['codesign', '-d', '--entitlements', ':-', str(code)]).stdout)
            declaration_bytes = (ROOT / declaration).read_bytes().replace(b'$(DEVELOPMENT_TEAM)', team.encode('ascii'))
            expected = plistlib.loads(declaration_bytes)
            if not isinstance(actual, dict):
                raise ValueError(f'{role}: embedded entitlements are not a dictionary')
            for key, value in expected.items():
                if actual.get(key) != value:
                    raise ValueError(f'{role}: declared entitlement missing or changed: {key}')
            sandbox = {k: v for k, v in actual.items() if k not in GENERATED_KEYS}
            expected_sandbox = {k: v for k, v in expected.items() if k not in GENERATED_KEYS}
            if sandbox != expected_sandbox:
                missing = sorted(k for k in expected if actual.get(k) != expected[k])
                extra = sorted(set(sandbox) - set(expected))
                raise ValueError(f'{role}: declared/embedded entitlements mismatch; missing-or-changed={missing}, unexpected={extra}')
            for key in ('com.apple.application-identifier', 'application-identifier'):
                if key in actual and actual[key] != f'{team}.{identifier}':
                    raise ValueError(f'{role}: generated application identifier differs from code identity')
            if 'com.apple.developer.team-identifier' in actual and actual['com.apple.developer.team-identifier'] != team:
                raise ValueError(f'{role}: entitlement team differs from signature team')
            if role == 'helper':
                # A valid codesign identifier alone cannot initialize an independent
                # sandbox container. Tool products also need signed Mach-O metadata.
                section = command(['otool', '-s', '__TEXT', '__info_plist', str(code)]).stdout.decode()
                payload = bytearray()
                for line in section.splitlines():
                    columns = line.split()
                    if not columns or not re.fullmatch(r'[0-9a-fA-F]{16}', columns[0]):
                        continue
                    for word in columns[1:]:
                        if not re.fullmatch(r'(?:[0-9a-fA-F]{2}){1,4}', word):
                            raise ValueError('helper: invalid embedded Info.plist section output')
                        raw = bytes.fromhex(word)
                        payload.extend(raw[::-1] if len(raw) == 4 else raw)
                info = plistlib.loads(bytes(payload).rstrip(b'\x00'))
                if info.get('CFBundleIdentifier') != identifier or info.get('CFBundleExecutable') != code.name:
                    raise ValueError('helper: embedded bundle identity does not match executable/signature')
                print('PASS helper metadata: embedded bundle identifier and executable match')
            print(f'PASS {role}: Apple-anchored identity, common team, exact declared sandbox entitlements')
        command(['codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app)])
        print('PASS bundle: nested-code seal verifies; no executable was launched')
        return 0
    except (ValueError, OSError, subprocess.TimeoutExpired, plistlib.InvalidFileException) as error:
        return fail(str(error))


if __name__ == '__main__':
    raise SystemExit(main())
