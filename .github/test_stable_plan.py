"""Release selection must stay pinned as beta advances, and fail before publishing unsafe candidates."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('stable_plan', Path(__file__).with_name('stable-plan.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StablePlanTest(unittest.TestCase):
    def git(self, *args):
        return subprocess.check_output(['git', *args], stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self, name):
        self.git('add', '.')
        self.git('commit', '-qm', name, '--allow-empty')
        return self.git('rev-parse', 'HEAD')

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.getcwd()
        os.chdir(self.tmp.name)
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 'test@example.invalid')
        self.git('config', 'user.name', 'Release test')
        self.commit('initial')
        Path('docs/releases').mkdir(parents=True)
        Path('docs/releases/0.1.2.md').write_text('---\nversion: 2\ndate: 2026-10-02\nparts: [web, station, android, desktop]\n---\n- Compatible clients\n')
        self.release = self.commit('reviewed notes')
        self.newer = self.commit('beta advances')
        self.git('update-ref', 'refs/remotes/origin/main', self.newer)
        self.conclusion = 'success'
        self.expired = False
        self.original_output = module.output
        self.mock = patch.object(module, 'output', self.output)
        self.mock.start()

    def tearDown(self):
        self.mock.stop()
        os.chdir(self.before)
        self.tmp.cleanup()

    def output(self, *args):
        if args[0] == 'node':
            return json.dumps([{'version': 2}])
        if args[:3] == ('gh', 'run', 'list'):
            self.assertEqual(args[args.index('--commit') + 1], self.release)
            return json.dumps([{'databaseId': 1, 'conclusion': self.conclusion}])
        if args[:2] == ('gh', 'api'):
            return json.dumps({'artifacts': [{'name': f'cloud-web-{self.release}', 'expired': self.expired}]})
        return self.original_output(*args)

    def test_default_remains_pinned_when_beta_advances(self):
        self.assertEqual(module.plan(), {'sha': self.release, 'version': '2'})
        self.assertEqual(module.plan(self.release)['sha'], self.release)

    def test_failed_pipeline_is_not_publishable(self):
        self.conclusion = 'failure'
        with self.assertRaisesRegex(SystemExit, 'No successful'):
            module.plan()

    def test_expired_artifact_is_not_rebuilt_or_guessed(self):
        self.expired = True
        with self.assertRaisesRegex(SystemExit, 'No successful'):
            module.plan()

    def test_missing_notes_for_revision_rejects(self):
        with self.assertRaises(subprocess.CalledProcessError):
            module.plan(self.newer)

    def test_branch_revision_cannot_access_production(self):
        branch = self.commit('not on main')
        with self.assertRaises(subprocess.CalledProcessError):
            module.plan(branch)

    def test_downgrade_rejects_but_retry_is_allowed(self):
        self.git('tag', 'deployed/stable', self.release)
        self.assertEqual(module.plan()['sha'], self.release)
        self.git('tag', '-f', 'deployed/stable', self.newer)
        with self.assertRaises(subprocess.CalledProcessError):
            module.plan()

    def test_untrusted_revision_is_not_a_git_option(self):
        with self.assertRaisesRegex(SystemExit, 'full commit SHA'):
            module.plan('--help')


if __name__ == '__main__':
    unittest.main()
