#!/usr/bin/env python3
"""Resolve the one signing identity this checkout must keep using, and its team.

Why this exists: a code signature's designated requirement embeds the leaf
certificate's CN, e.g.

    designated => identifier "org.automnt.automnt" and anchor apple generic and
                  certificate leaf[subject.CN] = "Apple Development: a@b.c (XXXXXXXXXX)" ...

macOS keys TCC grants and Background Task Management records to that identity.
When several Apple Development certificates exist on one machine (this Mac has
three), passing the bare type `CODE_SIGN_IDENTITY="Apple Development"` lets
codesign/xcodebuild pick whichever is first in the keychain, so the next build
silently becomes a *different* application and every system authorisation has to
be granted again.

Resolution order (first hit wins):
  1. AUTOMNT_SIGN_IDENTITY            explicit override: CN or SHA-1 hash
  2. .build/sign-identity             the identity this checkout already pinned
  3. /Applications/Automnt.app        identity of the installed application
  4. ./automnt                        identity of the committed CLI binary
  5. nothing                          hard failure, never a silent first-in-keychain pick

Prints `identity=<CN>` and `team=<TEAM>` on stdout; diagnostics on stderr.
Exit 2 when no pinned identity can be established.
"""
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PIN_FILE = ROOT / '.build' / 'sign-identity'
INSTALLED_APP = pathlib.Path('/Applications/Automnt.app')
ROOT_BINARY = ROOT / 'automnt'
IDENTITY_PREFIXES = ('Apple Development: ', 'Developer ID Application: ')


def run(args):
    return subprocess.run(args, capture_output=True, timeout=30)


def available_identities():
    """Map SHA-1 hash -> CN for every valid codesigning identity."""
    result = run(['security', 'find-identity', '-v', '-p', 'codesigning'])
    text = result.stdout.decode(errors='replace')
    identities = {}
    for match in re.finditer(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"([^"]+)"\s*$', text, re.M):
        identities[match.group(1)] = match.group(2)
    return identities


def resolve(token, identities):
    """Accept an exact CN, a SHA-1 hash, or an unambiguous CN fragment."""
    token = token.strip()
    if not token:
        return None
    if token in identities:
        return identities[token]
    if token in identities.values():
        return token
    matches = sorted(cn for cn in identities.values() if token in cn)
    if len(matches) == 1:
        return matches[0]
    if len(matches) > 1:
        raise SystemExit(
            'sign-identity: ambiguous identity token %r matches %d certificates: %s'
            % (token, len(matches), '; '.join(matches))
        )
    return None


def authority_of(bundle, identities):
    result = run(['codesign', '-d', '--verbose=4', str(bundle)])
    metadata = result.stderr.decode(errors='replace')
    if result.returncode != 0 and 'Authority=' not in metadata:
        return None
    for line in metadata.splitlines():
        if line.startswith('Authority=') and line[len('Authority='):].startswith(IDENTITY_PREFIXES):
            cn = line[len('Authority='):].strip()
            return cn if cn in identities.values() else None
    return None


def team_of(identity):
    """Team identifier lives in the certificate's OU field; the CN suffix is not it."""
    certificate = run(['security', 'find-certificate', '-c', identity, '-p'])
    if certificate.returncode != 0:
        return None
    parse = subprocess.run(
        ['openssl', 'x509', '-noout', '-subject', '-nameopt', 'sep_multiline'],
        input=certificate.stdout, capture_output=True, timeout=30,
    )
    if parse.returncode != 0:
        return None
    for line in parse.stdout.decode(errors='replace').splitlines():
        key, _, value = line.partition('=')
        if key.strip() == 'OU':
            value = value.strip()
            if re.fullmatch(r'[A-Z0-9]{10}', value):
                return value
            return None
    return None


def pinned_from_file(identities):
    if not PIN_FILE.is_file():
        return None
    for line in PIN_FILE.read_text().splitlines():
        if line.startswith('identity='):
            cn = line[len('identity='):].strip()
            return cn if cn in identities.values() else None
    return None


def main():
    identities = available_identities()
    if not identities:
        print('sign-identity: no valid codesigning identity is present', file=sys.stderr)
        return 2

    override = resolve(sys.argv[1] if len(sys.argv) > 1 else '', identities)
    source = 'AUTOMNT_SIGN_IDENTITY'
    if override is None:
        source = 'pinned .build/sign-identity'
        override = pinned_from_file(identities)
    if override is None:
        source = 'installed /Applications/Automnt.app'
        override = authority_of(INSTALLED_APP, identities) if INSTALLED_APP.exists() else None
    if override is None:
        source = 'existing ./automnt'
        override = authority_of(ROOT_BINARY, identities) if ROOT_BINARY.exists() else None

    if override is None:
        print('sign-identity: refusing to guess. This Mac has %d codesigning identities:' % len(identities),
              file=sys.stderr)
        for hash_, cn in sorted(identities.items()):
            print('  %s  %s' % (hash_, cn), file=sys.stderr)
        print('Pass AUTOMNT_SIGN_IDENTITY=<CN or SHA-1> or install the application once.', file=sys.stderr)
        return 2

    team = team_of(override)
    if team is None:
        print('sign-identity: could not read the team (certificate OU) of %s' % override, file=sys.stderr)
        return 2

    print('sign-identity: %s (team %s, from %s)' % (override, team, source), file=sys.stderr)
    PIN_FILE.parent.mkdir(parents=True, exist_ok=True)
    PIN_FILE.write_text('identity=%s\nteam=%s\n' % (override, team))
    print('identity=%s' % override)
    print('team=%s' % team)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
