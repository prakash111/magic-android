import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('github-release.py'))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


def result(code=0, stderr='', stdout=''):
    return subprocess.CompletedProcess([], code, stdout, stderr)


class ReleaseRetryTests(unittest.TestCase):
    @patch.object(release.time, 'sleep')
    def test_502_upload_is_retried_with_idempotent_clobber(self, sleep):
        with patch.object(release, 'invoke', side_effect=[result(1, 'HTTP 502: Server Error'), result()]) as invoke:
            release.transfer('upload', ['tag', '--repo', 'owner/repo', 'app.apk'])
        self.assertEqual(invoke.call_count, 2)
        self.assertIn('--clobber', invoke.call_args.args[0])
        sleep.assert_called_once_with(2)

    @patch.object(release.time, 'sleep')
    def test_permission_errors_are_not_retried(self, sleep):
        with patch.object(release, 'invoke', return_value=result(1, 'HTTP 403: Resource not accessible')) as invoke:
            with self.assertRaisesRegex(RuntimeError, 'HTTP 403'):
                release.transfer('upload', ['tag', 'app.apk'])
        self.assertEqual(invoke.call_count, 1)
        sleep.assert_not_called()

    @patch.object(release.time, 'sleep')
    def test_retry_budget_is_bounded(self, sleep):
        with patch.object(release, 'invoke', return_value=result(1, 'HTTP 503: unavailable')) as invoke:
            with self.assertRaises(RuntimeError):
                release.transfer('download', ['tag', '--dir', 'assets'])
        self.assertEqual(invoke.call_count, 5)
        self.assertEqual(sleep.call_count, 4)

    @patch.object(release.time, 'sleep')
    def test_partial_create_is_discovered_before_retrying_create(self, sleep):
        ready = json.dumps({'isDraft': True, 'targetCommitish': 'abc'})
        with patch.object(release, 'invoke', side_effect=[result(1, 'release not found'), result(1, 'HTTP 502'), result(stdout=ready)]) as invoke:
            release.ensure(['tag', '--repo', 'owner/repo', '--target', 'abc', '--title', 'Test', '--notes', 'Test'])
        self.assertEqual([c.args[0][0] for c in invoke.call_args_list], ['view', 'create', 'view'])
        self.assertIn('--draft', invoke.call_args_list[1].args[0])

    def test_existing_draft_is_reused(self):
        with patch.object(release, 'invoke', return_value=result(stdout=json.dumps({'isDraft': True, 'targetCommitish': 'abc'}))) as invoke:
            release.ensure(['tag', '--repo', 'owner/repo', '--target', 'abc', '--title', 'Test', '--notes', 'Test'])
        self.assertEqual(invoke.call_count, 1)

    def test_published_or_foreign_releases_are_never_modified(self):
        for draft, commit in [(False, 'abc'), (True, 'other')]:
            with self.subTest(draft=draft, commit=commit), patch.object(release, 'invoke', return_value=result(stdout=json.dumps({'isDraft': draft, 'targetCommitish': commit}))):
                with self.assertRaisesRegex(RuntimeError, 'Refusing'):
                    release.ensure(['tag', '--repo', 'owner/repo', '--target', 'abc', '--title', 'Test', '--notes', 'Test'])

    @patch.object(release.time, 'sleep')
    def test_partial_downloads_can_be_overwritten_on_retry(self, sleep):
        with patch.object(release, 'invoke', side_effect=[result(1, 'connection reset by peer'), result()]) as invoke:
            release.transfer('download', ['tag', '--dir', 'assets'])
        self.assertIn('--clobber', invoke.call_args.args[0])
        self.assertEqual(invoke.call_count, 2)


if __name__ == '__main__':
    unittest.main()
