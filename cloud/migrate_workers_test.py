import importlib.util
import unittest
from pathlib import Path
spec = importlib.util.spec_from_file_location('migrate_workers', Path(__file__).with_name('migrate-workers.py'))
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class TransferPlan(unittest.TestCase):
    def test_transfer_never_creates_empty_replacements_or_routes_traffic(self):
        for part in migration.CLASSES:
            template = migration.deploy.read_template(migration.deploy.PARTS[part])
            plan = migration.transfer_config(template, part, 'test-account')
            self.assertEqual(plan['routes'], [])
            self.assertFalse(plan['workers_dev'])
            self.assertFalse(plan['preview_urls'])
            self.assertEqual(plan['name'], migration.NAMES[part][1])
            self.assertNotIn('new_sqlite_classes', plan['migrations'][0])
            self.assertNotIn('deleted_classes', plan['migrations'][0])
            self.assertEqual({c['from'] for c in plan['migrations'][0]['transferred_classes']}, set(migration.CLASSES[part]))
            for move in plan['migrations'][0]['transferred_classes']:
                self.assertEqual(move['from'], move['to'])
                self.assertEqual(move['from_script'], migration.NAMES[part][0])
            self.assertTrue(template['routes'], 'input template remains unchanged')

    def test_container_transfer_preserves_application_and_namespace(self):
        template = migration.deploy.read_template(migration.deploy.PARTS['relay'])
        plan = migration.transfer_config(template, 'relay', 'test-account')
        first = migration.without_containers(plan)
        self.assertNotIn('containers', first)
        self.assertIn('containers', plan)
        self.assertEqual(first['migrations'], plan['migrations'])
        apps = [{'id': 'existing-app', 'name': 'old-container', 'durable_objects': {'namespace_id': 'original-id'}}]
        self.assertEqual(migration.relay_container(apps, {'Relay': 'original-id'}), {'id': 'existing-app', 'name': 'old-container'})
        for invalid in ([], apps + apps):
            with self.assertRaises(RuntimeError):
                migration.relay_container(invalid, {'Relay': 'original-id'})


if __name__ == '__main__': unittest.main()
