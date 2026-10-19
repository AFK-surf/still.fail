#!/usr/bin/env python3
"""Runs a command with still.fail's macOS signing identity at hand (MAC_SIGN_IDENTITY in its environment), as
.github/release-desktop.py has it for the desktop app: the identity (apps/desktop/package.json build.mac.identity)
imported from MACOS_SIGNING_CERTIFICATE_B64 / _PASSWORD into a keychain of its own, put on the user's search list for
the command and taken off after (the list restored, the keychain deleted), under the lock mini1's signing jobs share;
without the certificate, the login keychain unlocked with KEYCHAIN_PASSWORD_AFK. No identity, no command: nothing
unsigned goes out.
    python3 apps/mbui/scripts/mac-sign.py -- COMMAND…"""
import base64
import fcntl
import json
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[3]
identity = json.loads((root / 'apps/desktop/package.json').read_text())['build']['mac']['identity']
command = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
if not command:
    raise SystemExit(__doc__)


def run(args, **kwargs):
    if subprocess.run(args, **kwargs).returncode:
        raise SystemExit('mac-sign: failed: ' + args[0] + ' ' + (args[1] if len(args) > 1 else ''))


lock = open(Path.home() / '.stillfail-mac-signing.lock', 'a')
fcntl.flock(lock, fcntl.LOCK_EX)
previous = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
with tempfile.TemporaryDirectory(prefix='stillfail-mbui-signing-', dir=os.environ.get('RUNNER_TEMP')) as directory:
    keychain = str(Path(directory) / 'signing.keychain-db')
    imported = False
    try:
        certificate = os.environ.get('MACOS_SIGNING_CERTIFICATE_B64')
        if certificate:
            password = os.environ.get('MACOS_SIGNING_CERTIFICATE_PASSWORD') or ''
            if not password:
                raise SystemExit('MACOS_SIGNING_CERTIFICATE_PASSWORD is required')
            path = Path(directory) / 'certificate.p12'
            path.write_bytes(base64.b64decode(''.join(certificate.split()), validate=True))
            path.chmod(0o600)
            keypass = secrets.token_urlsafe(48)
            run(['security', 'create-keychain', '-p', keypass, keychain])
            imported = True
            run(['security', 'set-keychain-settings', '-lut', '21600', keychain])
            run(['security', 'unlock-keychain', '-p', keypass, keychain])
            run(['security', 'import', str(path), '-k', keychain, '-P', password, '-T', '/usr/bin/codesign'], stdout=subprocess.DEVNULL)
            run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', keypass, keychain], stdout=subprocess.DEVNULL)
            run(['security', 'list-keychains', '-d', 'user', '-s', keychain, *previous])
            path.unlink()
        elif os.environ.get('KEYCHAIN_PASSWORD_AFK'):
            run(['security', 'unlock-keychain', '-p', os.environ['KEYCHAIN_PASSWORD_AFK'], str(Path.home() / 'Library/Keychains/login.keychain-db')])
        if identity not in subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True):
            raise SystemExit('still.fail\'s signing identity is missing (MACOS_SIGNING_CERTIFICATE_B64 and _PASSWORD in production): nothing unsigned goes out')
        env = dict(os.environ, MAC_SIGN_IDENTITY=identity)
        for k in ('MACOS_SIGNING_CERTIFICATE_B64', 'MACOS_SIGNING_CERTIFICATE_PASSWORD', 'KEYCHAIN_PASSWORD_AFK'):
            env.pop(k, None)
        code = subprocess.run(command, env=env).returncode
    finally:
        if imported:
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *previous], stdout=subprocess.DEVNULL)
            subprocess.run(['security', 'delete-keychain', keychain], stdout=subprocess.DEVNULL)
sys.exit(code)
