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
            return json.dumps([{'version': int(f.name.split('.')[2])} for f in Path('docs/releases').glob('0.1.*.md')])
        if args[:3] == ('gh', 'run', 'list'):
            self.asked = (args[args.index('--branch') + 1], args[args.index('--commit') + 1])
            return json.dumps([{'databaseId': 1, 'conclusion': self.conclusion}])
        if args[:2] == ('gh', 'api'):
            return json.dumps({'artifacts': [{'name': f'cloud-web-{self.release}', 'expired': self.expired}]})
        return self.original_output(*args)

    def test_default_remains_pinned_when_beta_advances(self):
        self.assertEqual(module.plan(), {'sha': self.release, 'version': '2', 'web': 'artifact'})
        self.assertEqual(self.asked, ('main', self.release))
        self.assertEqual(module.plan(self.release)['sha'], self.release)

    def test_failed_pipeline_is_not_publishable(self):
        self.conclusion = 'failure'
        with self.assertRaisesRegex(SystemExit, 'No successful'):
            module.plan()

    def test_expired_artifact_is_built_again_from_the_release(self):
        self.expired = True
        self.assertEqual(module.plan(), {'sha': self.release, 'version': '2', 'web': 'build'})

    def test_a_base_on_main_is_found_by_its_count_with_its_notes_merged_after_it(self):
        self.git('rm', '-q', 'docs/releases/0.1.2.md')
        self.commit('beta advances again')
        Path('docs/releases').mkdir(parents=True)
        Path('docs/releases/0.1.3.md').write_text('---\nversion: 3\ndate: 2026-11-10\nparts: [web]\n---\n- The day before\n')
        self.git('update-ref', 'refs/remotes/origin/main', self.commit('notes for the day before'))
        self.release = self.newer
        self.assertEqual(module.plan(), {'sha': self.newer, 'version': '3', 'web': 'artifact'})
        self.git('tag', 'deployed/stable', self.git('rev-list', '--max-parents=0', 'HEAD'))
        self.assertEqual(module.plan(self.newer)['sha'], self.newer)

    def release_branch(self, same_notes=True):
        self.git('checkout', '-q', '-b', 'release/2026-11-10', self.release)
        self.commit('a serious fix, cherry-picked')
        notes = '---\nversion: 4\ndate: 2026-11-10\nparts: [web]\nbase: 2\nbranch: release/2026-11-10\n---\n- A fix\n'
        Path('docs/releases/0.1.4.md').write_text(notes)
        tip = self.commit('notes on the branch')
        self.git('update-ref', 'refs/remotes/origin/release/2026-11-10', tip)
        self.git('checkout', '-q', 'main')
        Path('docs/releases/0.1.4.md').write_text(notes if same_notes else notes.replace('A fix', 'Another'))
        self.git('update-ref', 'refs/remotes/origin/main', self.commit('the branch\'s notes on main'))
        return tip

    def test_a_release_branch_is_its_newest_commit_built_here_its_number_a_main_commit_s_too(self):
        tip = self.release_branch()
        self.assertEqual(module.plan(), {'sha': tip, 'version': '4', 'web': 'build'})
        self.assertEqual(self.asked, ('release/2026-11-10', tip))
        self.assertEqual(module.plan(tip)['sha'], tip)
        self.git('tag', 'deployed/stable', tip)
        self.assertEqual(module.plan()['sha'], tip)

    def test_a_release_branch_carries_the_notes_main_has(self):
        self.release_branch(same_notes=False)
        with self.assertRaisesRegex(SystemExit, 'does not carry'):
            module.plan()

    def test_after_a_release_branch_the_next_base_on_main_is_not_backwards(self):
        tip = self.release_branch()
        self.git('tag', 'deployed/stable', tip)
        Path('docs/releases/0.1.5.md').write_text('---\nversion: 5\ndate: 2026-11-11\nparts: [web]\n---\n- Next day\n')
        self.git('update-ref', 'refs/remotes/origin/main', self.commit('the next notes'))
        self.release = self.git('rev-parse', 'HEAD')
        self.assertEqual(module.plan(), {'sha': self.release, 'version': '5', 'web': 'artifact'})

    def test_not_above_the_last_release_rejects(self):
        tip = self.release_branch()
        self.git('tag', 'deployed/stable', tip)
        Path('docs/releases/0.1.3.md').write_text('---\nversion: 3\ndate: 2026-11-11\nparts: [web]\n---\n- Older\n')
        self.git('update-ref', 'refs/remotes/origin/main', self.commit('notes naming an older commit'))
        with self.assertRaisesRegex(SystemExit, 'not above'):
            module.plan(self.newer)

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
