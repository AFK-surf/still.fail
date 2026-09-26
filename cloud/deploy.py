#!/usr/bin/env python3
"""Deploys ember cloud: the Worker, its relay container, the web app and the admin's console
(one Worker on two custom domains, PUBLIC_ORIGIN and ADMIN_ORIGIN).

    python3 deploy.py            # build the web app, deploy, set secrets, check /healthz
    python3 deploy.py --check    # only report what is missing

Inputs (none of them in the repository):
  --google  Google "Web application" OAuth client JSON (default ~/ember-deploy/google-oauth.json;
            its redirect URIs must include <origin>/v1/auth/google/callback)
  keys      ~/ember-deploy/keys.json, created on first run: session signing key, admin token and
            the Ed25519 key that signs station grants. Keep it; losing it logs everyone out and makes
            stations distrust new grants until they re-enroll.
  posthog   ~/ember-deploy/posthog.json, {host, key}: PostHog's project key, built into the web app
            (docs/telemetry.md). Without it the web app is built without analytics.
  axiom     ~/ember-deploy/axiom.json, {"dataset", "token"}: where traces go (docs/telemetry.md).
            Without it the cloud takes no traces.
Cloudflare: an interactive `wrangler login` (or CLOUDFLARE_API_TOKEN). Docker (OrbStack) builds the relay image.
"""
import argparse
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import urllib.request
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent
DEPLOY = Path.home() / "ember-deploy"
KEYS = DEPLOY / "keys.json"
POSTHOG = DEPLOY / "posthog.json"
AXIOM = DEPLOY / "axiom.json"


def write_private(path: Path, value) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(value, f, indent=2)
    os.replace(tmp, path)


def read_template() -> dict:
    text = (ROOT / "wrangler.jsonc").read_text()
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def wrangler(*args, env=None, capture=False):
    command = ["pnpm", "exec", "wrangler", *args]
    if capture:
        return subprocess.run(command, cwd=ROOT, env=env, check=True, text=True, capture_output=True).stdout
    subprocess.run(command, cwd=ROOT, env=env, check=True)


def account_id() -> str:
    out = wrangler("whoami", "--json", capture=True)
    accounts = json.loads(out).get("accounts") or []
    if len(accounts) != 1:
        sys.exit(f"expected one Cloudflare account, got {len(accounts)}")
    return accounts[0]["id"]


def grant_jwk() -> dict:
    # Node's crypto makes the Ed25519 JWK; Python's stdlib cannot.
    out = subprocess.check_output(["node", "-e", """
      const { generateKeyPairSync } = require("node:crypto");
      const { privateKey } = generateKeyPairSync("ed25519");
      console.log(JSON.stringify({ ...privateKey.export({ format: "jwk" }), kid: "grant-" + Date.now().toString(36) }));
    """], text=True)
    return json.loads(out)


def keys() -> dict:
    if KEYS.exists():
        return json.loads(KEYS.read_text())
    value = {"AUTH_SIGNING_KEY": secrets.token_urlsafe(32), "ADMIN_TOKEN": secrets.token_urlsafe(32), "GRANT_SIGNING_JWK": json.dumps(grant_jwk())}
    write_private(KEYS, value)
    print(f"created {KEYS}")
    return value


def axiom() -> dict:
    if not AXIOM.exists():
        print(f"note: {AXIOM} is missing; the cloud will take no traces")
        return {}
    value = json.loads(AXIOM.read_text())
    return {"AXIOM_TOKEN": value["token"], "AXIOM_DATASET": value["dataset"]}


@contextmanager
def docker_env():
    """A throwaway Docker config: an SSH session cannot unlock the macOS keychain Docker's default helper uses."""
    env = dict(os.environ)
    env["PATH"] = "/opt/homebrew/bin:" + env.get("PATH", "")
    host = subprocess.check_output(["docker", "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"], env=env, text=True).strip()
    with tempfile.TemporaryDirectory(prefix="ember-docker-") as directory:
        # Keep the plugins (buildx) the normal config would find.
        plugins = [str(p) for p in [Path.home() / ".docker" / "cli-plugins", Path("/opt/homebrew/lib/docker/cli-plugins"), Path("/Applications/OrbStack.app/Contents/MacOS/xbin")] if p.exists()]
        Path(directory, "config.json").write_text(json.dumps({"auths": {"https://index.docker.io/v1/": {}}, "credsStore": "", "cliPluginsExtraDirs": plugins}))
        env["DOCKER_CONFIG"] = directory
        env["DOCKER_HOST"] = host
        yield env


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--google", type=Path, default=DEPLOY / "google-oauth.json")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help="deploy the web apps already in dist/cloud-app")
    args = parser.parse_args()

    template = read_template()
    origin = template["vars"]["PUBLIC_ORIGIN"]
    web = json.loads(args.google.read_text())["web"]
    callback = f"{origin}/v1/auth/google/callback"
    if callback not in web.get("redirect_uris", []):
        print(f"note: {args.google} does not list {callback}; make sure it is registered in Google Cloud Console")
    if args.check:
        print("account", account_id())
        print("keys", "present" if KEYS.exists() else "will be created")
        print("posthog", "present" if POSTHOG.exists() else "missing: the web app will have no analytics")
        print("axiom", "present" if AXIOM.exists() else f"missing: no traces without {AXIOM}")
        return

    config = {**template, "account_id": account_id(), "vars": {**template["vars"], "GOOGLE_CLIENT_ID": web["client_id"]}}
    local = ROOT / "wrangler.local.json"
    local.write_text(json.dumps(config, indent=2) + "\n")

    if not args.skip_build:
        # web/vite.config.ts reads the key from the file EMBER_POSTHOG names.
        if not POSTHOG.exists():
            print(f"note: no {POSTHOG}; building the web app without analytics")
        env = {**os.environ, "EMBER_POSTHOG": str(POSTHOG)} if POSTHOG.exists() else None
        subprocess.run(["pnpm", "run", "build:cloud"], cwd=REPO, env=env, check=True)
    values = {**keys(), "GOOGLE_CLIENT_SECRET": web["client_secret"], **axiom()}
    with docker_env() as env:
        wrangler("deploy", "--config", str(local), "--containers-rollout", "immediate", env=env)
        with tempfile.TemporaryDirectory(prefix="ember-secrets-") as directory:
            path = Path(directory) / "secrets.json"
            write_private(path, values)
            wrangler("secret", "bulk", str(path), "--config", str(local), env=env)

    # Cloudflare turns away urllib's default User-Agent. A new custom domain's
    # certificate may take a few minutes; a failure here is not a failed deploy.
    for each in (origin, template["vars"]["ADMIN_ORIGIN"], template["vars"]["PREVIEW_ORIGIN"]):
        request = urllib.request.Request(f"{each}/healthz", headers={"user-agent": "ember-deploy"})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                print("healthz", each, response.status, response.read().decode())
        except OSError as error:
            print("healthz", each, "failed:", error)


if __name__ == "__main__":
    main()
