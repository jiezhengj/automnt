"""Exercise signature verification decisions without signing or running product code."""
import importlib.util
import pathlib
import plistlib
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout, redirect_stderr
from io import StringIO
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / 'verify-signature.py'
spec = importlib.util.spec_from_file_location('verify_signature', SCRIPT)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class SignatureDecisionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = pathlib.Path(self.directory.name).resolve() / 'Automnt.app'
        (self.app / 'Contents/Helpers').mkdir(parents=True)
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({}))
        for name in ('AutomntHelper', 'AutomntWorker'):
            (self.app / 'Contents/Helpers' / name).touch()
        self.team = 'TESTTEAM01'
        self.adhoc = False
        self.foreign_team = False
        self.unexpected_entitlement = False
        self.changed_entitlement = False
        self.foreign_identifier = False
        self.requirement_failed = False
        self.calls = []

    def run_codesign(self, args, **kwargs):
        self.calls.append(args)
        code = pathlib.Path(args[-1])
        target = next(target for target in checker.TARGETS if code == self.app / target[1])
        role, _, identifier, declaration = target
        team = 'OTHERTEAM1' if self.foreign_team and role == 'worker' else self.team
        if '--entitlements' in args:
            data = plistlib.loads((checker.ROOT / declaration).read_bytes())
            data['com.apple.developer.team-identifier'] = team
            data['com.apple.application-identifier'] = f'{team}.{identifier}'
            if self.unexpected_entitlement and role == 'helper':
                data['com.apple.security.network.server'] = True
            if self.changed_entitlement and role == 'worker':
                data['com.apple.security.inherit'] = False
            return subprocess.CompletedProcess(args, 0, plistlib.dumps(data), b'')
        if '--verbose=4' in args:
            if self.foreign_identifier and role == 'helper':
                identifier = 'org.example.unrelated'
            metadata = f'Identifier={identifier}\nTeamIdentifier={team}\n'
            if self.adhoc:
                metadata += 'Signature=adhoc\n'
            return subprocess.CompletedProcess(args, 0, b'', metadata.encode())
        if '-R' in args and self.requirement_failed:
            return subprocess.CompletedProcess(args, 1, b'', b'code failed to satisfy specified code requirement')
        return subprocess.CompletedProcess(args, 0, b'', b'')

    def execute(self):
        with patch.object(checker.sys, 'argv', ['verify-signature.py', str(self.app)]), \
             patch.object(checker.subprocess, 'run', side_effect=self.run_codesign), \
             redirect_stdout(StringIO()) as stdout, redirect_stderr(StringIO()) as stderr:
            result = checker.main()
        return result, stdout.getvalue() + stderr.getvalue()

    def test_matching_declarations_use_distinct_identifiers_and_common_team(self):
        result, _ = self.execute()
        self.assertEqual(result, 0)
        requirements = [call[call.index('-R') + 1] for call in self.calls if '-R' in call]
        self.assertEqual(len(requirements), 3)
        for requirement, target in zip(requirements, checker.TARGETS):
            self.assertTrue(requirement.startswith('='), 'codesign requires = for inline requirement text')
            self.assertIn(f'identifier "{target[2]}"', requirement)
            self.assertIn('anchor apple generic', requirement)
            self.assertIn(self.team, requirement)
        self.assertTrue(any('--deep' in call for call in self.calls))

    def test_adhoc_is_rejected_even_with_team_field(self):
        self.adhoc = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('ad-hoc', output)

    def test_embedded_target_cannot_use_another_team(self):
        self.foreign_team = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('team differs', output)

    def test_extra_network_permission_is_rejected(self):
        self.unexpected_entitlement = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('network.server', output)

    def test_changed_inheritance_permission_is_rejected(self):
        self.changed_entitlement = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('com.apple.security.inherit', output)

    def test_foreign_identifier_is_rejected(self):
        self.foreign_identifier = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('unexpected signing identifier', output)

    def test_metadata_does_not_substitute_for_requirement_validation(self):
        self.requirement_failed = True
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('code failed to satisfy', output)

    def test_missing_nested_code_is_rejected(self):
        (self.app / 'Contents/Helpers/AutomntWorker').unlink()
        result, output = self.execute()
        self.assertEqual(result, 1)
        self.assertIn('executable is absent', output)


if __name__ == '__main__':
    unittest.main()
