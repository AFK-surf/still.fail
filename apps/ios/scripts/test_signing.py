from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import unittest
from signing import profile_uuid


class AppStoreProfiles(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 7, tzinfo=timezone.utc)
        self.certificate = b"synthetic distribution certificate"
        self.identity = hashlib.sha1(self.certificate).hexdigest().upper()
        self.profile = {
            "UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "TeamIdentifier": ["TEAM"], "ApplicationIdentifierPrefix": ["TEAM"],
            "ExpirationDate": self.now + timedelta(days=30),
            "DeveloperCertificates": [self.certificate],
            "Entitlements": {"application-identifier": "TEAM.fail.still.iphone", "get-task-allow": False,
                             "com.apple.security.application-groups": ["group.fail.still.iphone"],
                             "com.apple.developer.applesignin": ["Default"]},
        }

    def validate(self, profile=None, bundle="fail.still.iphone"):
        return profile_uuid(profile or self.profile, "TEAM", bundle, self.identity, self.now)

    def test_valid_app_and_widget_profiles(self):
        self.assertEqual(self.validate(), "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        widget = deepcopy(self.profile)
        widget["Entitlements"]["application-identifier"] = "TEAM.fail.still.iphone.widgets"
        del widget["Entitlements"]["com.apple.developer.applesignin"]
        self.validate(widget, "fail.still.iphone.widgets")

    def test_cue_and_wrong_team_profiles_are_rejected(self):
        for changes in ({"TeamIdentifier": ["OTHER"]},
                        {"Entitlements": {**self.profile["Entitlements"], "application-identifier": "TEAM.surf.comma.ios"}}):
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    self.validate({**self.profile, **changes})

    def test_missing_apple_signin_and_app_group_are_rejected(self):
        for capability in ("com.apple.developer.applesignin", "com.apple.security.application-groups"):
            with self.subTest(capability=capability):
                profile = deepcopy(self.profile)
                del profile["Entitlements"][capability]
                with self.assertRaises(ValueError):
                    self.validate(profile)

    def test_expired_development_adhoc_and_wrong_certificate_are_rejected(self):
        for changes in ({"ExpirationDate": self.now}, {"DeveloperCertificates": [b"other certificate"]},
                        {"ProvisionedDevices": ["some-device"]}, {"ProvisionsAllDevices": True},
                        {"Entitlements": {**self.profile["Entitlements"], "get-task-allow": True}}):
            with self.subTest(changes=changes):
                with self.assertRaises(ValueError):
                    self.validate({**self.profile, **changes})

    def test_invalid_uuid_is_rejected_before_installing_files(self):
        for uuid in ("../profile", None, "", "{aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"):
            with self.subTest(uuid=uuid):
                with self.assertRaises(ValueError):
                    self.validate({**self.profile, "UUID": uuid})


if __name__ == "__main__":
    unittest.main()
