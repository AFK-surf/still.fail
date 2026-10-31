#!/usr/bin/env python3
"""still.fail's macOS signing on the organization's Mac: the identity (AFK's Developer ID, `identity` below) and
Apple's notary service at hand, for the Mac app (.github/release-desktop.py, apps/mbui/scripts/beta.sh) and the
station's native parts (.github/sign-station.sh).

The keychain is AFK's (cue.surf's), the one AFK-surf/Cue signs and notarizes its apps with: its Developer ID
Application identity and its notarytool profile (Apple ID and app-specific password), in production's
MACOS_DEVELOPER_ID_KEYCHAIN_B64_1 and _2 (the file's base64 in two halves: one secret holds 48 KB at most), opened with
KEYCHAIN_PASSWORD_AFK (both copied from Cue's; a rotation there is copied again). A copy of it is put on the user's
search list for the command and taken off after (the list restored, the copy deleted), under the lock mini1's signing
jobs share: they run beside each other on its one search list.
Without the keychain's secrets (a maintainer's own Mac), nothing is set up: the login keychain has the identity.

    python3 .github/mac_signing.py run -- COMMAND…   COMMAND with MAC_SIGN_IDENTITY, STILLFAIL_SIGNING_KEYCHAIN and
                                                     STILLFAIL_NOTARY_PROFILE in its environment, the secrets not
    python3 .github/mac_signing.py notarize APP      APP (a signed .app) notarized and its ticket stapled to it
    python3 .github/mac_signing.py notarize APP --no-staple
                                                     notarized only: Gatekeeper asks Apple for its ticket as it
                                                     opens downloaded (the mbui app: below)
"""
import base64
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
# AFK's Developer ID, named without its kind ("Developer ID Application:"): found() finds its full name.
identity = 'AFK AI, Inc. (D9AAN3VJK8)'
SECRETS = ('MACOS_DEVELOPER_ID_KEYCHAIN_B64_1', 'MACOS_DEVELOPER_ID_KEYCHAIN_B64_2', 'KEYCHAIN_PASSWORD_AFK')


def run(args, **kwargs):
    result = subprocess.run(args, **kwargs)
    if result.returncode:
        # (what it said, when kept to be read: notarytool's submit failed main's beta with nothing but its name, the
        # reason in the output kept for its verdict, run 41169187343)
        for said in (result.stdout, result.stderr):
            if said:
                print(said if isinstance(said, str) else said.decode(errors='replace'), file=sys.stderr, flush=True)
        raise SystemExit(f'mac_signing: failed: {" ".join(args[:2])} (exit {result.returncode})')
    return result


def found(keychain=None):
    """The signing identity's full name as the keychain (default the search list) has it ("Developer ID Application:
    …"), None when it is not there."""
    listing = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning', *([keychain] if keychain else [])], text=True)
    for line in listing.splitlines():
        if '"' in line and identity in line:
            return line.split('"')[1]
    return None


def notary_profile(keychain):
    """The name notarytool's saved credentials go by in the keychain (notarytool store-credentials --keychain)."""
    dump = subprocess.run(['security', 'dump-keychain', keychain], capture_output=True, text=True, errors='replace').stdout
    prefix = 'com.apple.gke.notary.tool.saved-creds.'
    for line in dump.splitlines():
        if prefix in line:
            return line.split(prefix, 1)[1].split('"', 1)[0]
    return None


@contextlib.contextmanager
def keychain():
    """The signing keychain on the search list while inside: {'identity' (its full name), 'keychain', 'notary_profile'}
    (the last two None without its secrets). Leaves only with the identity found: nothing unsigned goes out."""
    halves = [os.environ.get(k, '') for k in SECRETS[:2]]
    password = os.environ.get('KEYCHAIN_PASSWORD_AFK', '')
    if not any(halves) and not password:
        name = found()
        if not name:
            raise SystemExit(f'mac_signing: {identity} is not in this Mac\'s keychains (CI: MACOS_DEVELOPER_ID_KEYCHAIN_B64_1 / _2 and KEYCHAIN_PASSWORD_AFK in production)')
        yield {'identity': name, 'keychain': None, 'notary_profile': None}
        return
    if not all(halves) or not password:
        raise SystemExit('mac_signing: MACOS_DEVELOPER_ID_KEYCHAIN_B64_1, _2 and KEYCHAIN_PASSWORD_AFK go together')
    lock = open(Path.home() / '.stillfail-mac-signing.lock', 'a')
    fcntl.flock(lock, fcntl.LOCK_EX)
    previous = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
    with tempfile.TemporaryDirectory(prefix='stillfail-signing-', dir=os.environ.get('RUNNER_TEMP')) as directory:
        path = str(Path(directory) / 'signing.keychain-db')
        Path(path).write_bytes(base64.b64decode(''.join(''.join(halves).split()), validate=True))
        Path(path).chmod(0o600)
        try:
            run(['security', 'unlock-keychain', '-p', password, path])
            run(['security', 'set-keychain-settings', '-lut', '21600', path])
            run(['security', 'list-keychains', '-d', 'user', '-s', path, *previous])
            name = found(path)
            if not name:
                raise SystemExit(f'mac_signing: {identity} is not in the signing keychain: nothing unsigned goes out')
            profile = notary_profile(path)
            if not profile:
                raise SystemExit('mac_signing: no notarytool profile in the signing keychain')
            yield {'identity': name, 'keychain': path, 'notary_profile': profile}
        finally:
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *previous], stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'delete-keychain', path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def signing_env(opened, env=None):
    """env (default this process's) for a command signing in `opened`: the secrets left out."""
    env = {k: v for k, v in (env or os.environ).items() if k not in SECRETS}
    env['MAC_SIGN_IDENTITY'] = opened['identity']
    if opened['keychain']:
        env['STILLFAIL_SIGNING_KEYCHAIN'] = opened['keychain']
        env['STILLFAIL_NOTARY_PROFILE'] = opened['notary_profile']
    return env


def notarize(app, staple=True):
    """Sends `app` to Apple's notary service, waits for its verdict (its log printed when not Accepted) and staples the
    ticket to it, so Gatekeeper lets it open downloaded, offline too. In `run`'s keychain (STILLFAIL_NOTARY_PROFILE)."""
    profile = os.environ.get('STILLFAIL_NOTARY_PROFILE')
    if not profile:
        raise SystemExit('mac_signing: notarize runs under `mac_signing.py run` (no STILLFAIL_NOTARY_PROFILE)')
    auth = ['--keychain-profile', profile, '--keychain', os.environ['STILLFAIL_SIGNING_KEYCHAIN']]
    with tempfile.TemporaryDirectory(prefix='stillfail-notarize-', dir=os.environ.get('RUNNER_TEMP')) as directory:
        archive = str(Path(directory) / (Path(app).stem + '.zip'))
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive])
        out = run(['xcrun', 'notarytool', 'submit', archive, *auth, '--wait', '--output-format', 'json'], capture_output=True, text=True).stdout
    verdict = json.loads(out)
    print(f"notarytool: {verdict.get('id')} {verdict.get('status')}", flush=True)
    if verdict.get('status') != 'Accepted':
        subprocess.run(['xcrun', 'notarytool', 'log', verdict.get('id', ''), *auth])
        raise SystemExit(f'mac_signing: Apple did not notarize {app}: {verdict.get("status")}')
    # (staple validates what it stapled: "The staple and validate action worked!". Validating again asked Apple's
    # CloudKit once more, and a connection it dropped failed main's beta with the app notarized and stapled, run
    # 39682975188)
    # (Gatekeeper's verdict only on what is stapled: unstapled, spctl asks Apple for a ticket it may not yet hand out
    # seconds after Accepted, "Unnotarized Developer ID", which failed main's mbui beta, run 40053983329)
    if staple:
        run(['xcrun', 'stapler', 'staple', app])
        run(['spctl', '--assess', '--type', 'execute', '-vv', app])


if __name__ == '__main__':
    if sys.argv[1:2] == ['notarize'] and len(sys.argv) == 3:
        notarize(sys.argv[2])
    elif sys.argv[1:2] == ['notarize'] and sys.argv[3:] == ['--no-staple']:
        notarize(sys.argv[2], staple=False)
    elif sys.argv[1:3] == ['run', '--'] and len(sys.argv) > 3:
        with keychain() as opened:
            code = subprocess.run(sys.argv[3:], env=signing_env(opened)).returncode
        sys.exit(code)
    else:
        raise SystemExit(__doc__)
