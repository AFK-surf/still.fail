"""Validate the two App Store profiles before installing them on a runner."""
from datetime import datetime, timezone
import hashlib
from uuid import UUID


def profile_uuid(profile, team, bundle, identity, now=None):
    raw_uuid = profile.get("UUID")
    try:
        uuid = str(UUID(raw_uuid))
    except (AttributeError, TypeError, ValueError) as error:
        raise ValueError(f"Profile for {bundle} has an invalid UUID") from error
    if raw_uuid.lower() != uuid:
        raise ValueError(f"Profile for {bundle} must use a canonical UUID")
    if team not in profile.get("TeamIdentifier", []):
        raise ValueError(f"Profile for {bundle} belongs to another Apple team")
    entitlements = profile.get("Entitlements", {})
    identifiers = [f"{prefix}.{bundle}" for prefix in profile.get("ApplicationIdentifierPrefix", [])]
    if entitlements.get("application-identifier") not in identifiers:
        raise ValueError(f"Profile does not match {bundle}")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime) or expires.replace(tzinfo=timezone.utc) <= (now or datetime.now(timezone.utc)):
        raise ValueError(f"Profile for {bundle} has expired or has no expiration date")
    if entitlements.get("get-task-allow") is not False or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        raise ValueError(f"Profile for {bundle} must be an App Store distribution profile")
    certificates = [hashlib.sha1(value).hexdigest().upper() for value in profile.get("DeveloperCertificates", [])]
    if identity.upper() not in certificates:
        raise ValueError(f"Profile for {bundle} does not include the supplied distribution certificate")
    if "group.fail.still.iphone" not in entitlements.get("com.apple.security.application-groups", []):
        raise ValueError(f"Profile for {bundle} must enable App Group group.fail.still.iphone")
    if bundle == "fail.still.iphone" and "Default" not in entitlements.get("com.apple.developer.applesignin", []):
        raise ValueError("The app profile must enable Sign in with Apple")
    return uuid
