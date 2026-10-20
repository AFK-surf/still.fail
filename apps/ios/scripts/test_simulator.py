import json
import unittest
from unittest.mock import patch
import simulator


class SimulatorSelection(unittest.TestCase):
    def inventory(self):
        return {
            "runtimes": [
                {"identifier": "old", "name": "iOS 18.0", "version": "18.0", "isAvailable": True},
                {"identifier": "missing", "name": "iOS 27.0", "version": "27.0", "isAvailable": False},
                {"identifier": "current", "name": "iOS 26.4", "version": "26.4", "isAvailable": True,
                 "supportedDeviceTypes": [{"identifier": "iphone"}]},
                {"identifier": "watch", "name": "watchOS 27.0", "version": "27.0", "isAvailable": True},
            ],
            "devicetypes": [{"identifier": "iphone", "name": "iPhone 17"},
                            {"identifier": "unsupported", "name": "iPhone Future"}],
        }

    def test_creates_an_isolated_phone_using_an_installed_supported_runtime(self):
        with patch.object(simulator.subprocess, "check_output", side_effect=[json.dumps(self.inventory()), "new-simulator\n"]) as run:
            self.assertEqual(simulator.create(), "new-simulator")
            command = run.call_args.args[0]
            self.assertEqual(command[:3], ["xcrun", "simctl", "create"])
            self.assertTrue(command[3].startswith("stillfail-ci-"))
            self.assertEqual(command[-2:], ["iphone", "current"])

    def test_missing_current_runtime_fails_before_creating_a_device(self):
        inventory = self.inventory()
        for runtime in inventory["runtimes"]:
            if runtime["identifier"] == "current":
                runtime["isAvailable"] = False
        with patch.object(simulator.subprocess, "check_output", return_value=json.dumps(inventory)) as run:
            with self.assertRaisesRegex(SystemExit, "Install an iOS 26"):
                simulator.create()
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
