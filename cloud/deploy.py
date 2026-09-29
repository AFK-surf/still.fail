#!/usr/bin/env python3
"""Deploys still.fail cloud, five Workers (wrangler.jsonc says what each is; they keep their names from before the
rename to still.fail, as do their Durable Objects, bucket and secrets: renaming would make new, empty ones):
  api      ember-cloud    the API (wrangler.jsonc)
  relay    ember-relay    the relay and its container (wrangler.relay.jsonc)
  web      ember-web      the web app, static (wrangler.web.jsonc)
  admin    ember-admin    the admin's console, static (wrangler.admin.jsonc)
  preview  ember-preview  the preview host, static (wrangler.preview.jsonc)
Each is deployed on its own: deploying the API drops no relay connection and serves no page. (And the official
site, `site`, still-fail-site: only when asked for by name or with all of them.)

    python3 deploy.py                 # all of them, in this order: relay, api, web, admin, preview
    python3 deploy.py api web         # only these (the static ones are built first)
    python3 deploy.py --check         # only report what is missing

Inputs (none of them in the repository), in the deploy directory: $STILLFAIL_DEPLOY_DIR (or $EMBER_DEPLOY_DIR),
else ~/stillfail-deploy, else ~/ember-deploy while only that one exists (from before the rename; move it when you
like, nothing else changes):
  --google  Google "Web application" OAuth client JSON (default <deploy>/google-oauth.json;
            its redirect URIs must include <origin>/v1/auth/google/callback for every origin still in use:
            https://app.still.fail and https://ember.3720.org)
  keys      <deploy>/keys.json, created on first run: session signing key, admin token and
            the Ed25519 key that signs station grants. Keep it; losing it logs everyone out and makes
            stations distrust new grants until they re-enroll.
  posthog   <deploy>/posthog.json, {host, key}: PostHog's project key, built into the web app
            (docs/telemetry.md). Without it the web app is built without analytics.
  axiom     <deploy>/axiom.json, {"dataset", "token"}: where traces go (docs/telemetry.md).
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
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent


def env_var(name: str):
    """STILLFAIL_<name>, or EMBER_<name> from before the rename."""
    return os.environ.get(f"STILLFAIL_{name}") or os.environ.get(f"EMBER_{name}")


def deploy_dir() -> Path:
    if env_var("DEPLOY_DIR"):
        return Path(env_var("DEPLOY_DIR")).expanduser()
    new, old = Path.home() / "stillfail-deploy", Path.home() / "ember-deploy"
    # The keys in it are what every session and station trusts: never start a fresh one next to the old.
    return old if old.exists() and not new.exists() else new


DEPLOY = deploy_dir()
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


PARTS = {"relay": "wrangler.relay.jsonc", "api": "wrangler.jsonc", "web": "wrangler.web.jsonc", "admin": "wrangler.admin.jsonc", "preview": "wrangler.preview.jsonc", "site": "wrangler.site.jsonc"}


def read_template(name: str = "wrangler.jsonc") -> dict:
    text = (ROOT / name).read_text()
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def wrangler(*args, env=None, capture=False):
    command = ["pnpm", "exec", "wrangler", *args]
    if capture:
        # Kept apart (deploys run side by side), and shown when it fails.
        done = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True)
        if done.returncode != 0:
            print(f"wrangler {' '.join(args)} failed:\n{done.stdout}{done.stderr}", file=sys.stderr, flush=True)
            raise subprocess.CalledProcessError(done.returncode, command, done.stdout, done.stderr)
        return done.stdout
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
    with tempfile.TemporaryDirectory(prefix="stillfail-docker-") as directory:
        # Keep the plugins (buildx) the normal config would find.
        plugins = [str(p) for p in [Path.home() / ".docker" / "cli-plugins", Path("/opt/homebrew/lib/docker/cli-plugins"), Path("/Applications/OrbStack.app/Contents/MacOS/xbin")] if p.exists()]
        Path(directory, "config.json").write_text(json.dumps({"auths": {"https://index.docker.io/v1/": {}}, "credsStore": "", "cliPluginsExtraDirs": plugins}))
        env["DOCKER_CONFIG"] = directory
        env["DOCKER_HOST"] = host
        yield env


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("parts", nargs="*", help=f"what to deploy, of {', '.join(PARTS)} (default: all)")
    parser.add_argument("--google", type=Path, default=DEPLOY / "google-oauth.json")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help="deploy the static sites already in dist/")
    args = parser.parse_args()
    unknown = set(args.parts) - set(PARTS)
    if unknown:
        sys.exit(f"no such part: {', '.join(sorted(unknown))}")
    parts = [p for p in PARTS if p in args.parts] or list(PARTS)

    template = read_template()
    origin = template["vars"]["PUBLIC_ORIGIN"]
    aliases = [o.strip() for o in template["vars"].get("PUBLIC_ORIGIN_ALIASES", "").split(",") if o.strip()]
    web = json.loads(args.google.read_text())["web"]
    # Google calls back the new origin; a login started on an old one before a deploy, the old one.
    for callback in [f"{o}/v1/auth/google/callback" for o in [origin, *aliases]]:
        if callback not in web.get("redirect_uris", []):
            print(f"note: {args.google} does not list {callback}; make sure it is registered in Google Cloud Console")
    if args.check:
        print("account", account_id())
        print("keys", "present" if KEYS.exists() else "will be created")
        print("posthog", "present" if POSTHOG.exists() else "missing: the web app will have no analytics")
        print("axiom", "present" if AXIOM.exists() else f"missing: no traces without {AXIOM}")
        return

    account = account_id()
    if not args.skip_build and {"web", "admin", "preview"} & set(parts):
        # web/vite.config.ts reads the key from the file STILLFAIL_POSTHOG (EMBER_POSTHOG before the rename) names.
        if not POSTHOG.exists():
            print(f"note: no {POSTHOG}; building the web app without analytics")
        env = {**os.environ, "STILLFAIL_POSTHOG": str(POSTHOG), "EMBER_POSTHOG": str(POSTHOG)} if POSTHOG.exists() else None
        subprocess.run(["pnpm", "run", "build:cloud"], cwd=REPO, env=env, check=True)
    if not args.skip_build and "site" in parts:
        subprocess.run(["pnpm", "run", "build:site"], cwd=REPO, check=True)
    secrets_of = {
        "api": {**keys(), "GOOGLE_CLIENT_SECRET": web["client_secret"], **axiom()},
        "relay": {"ADMIN_TOKEN": keys()["ADMIN_TOKEN"]},
    }
    def deploy(part: str, env) -> None:
        config = {**read_template(PARTS[part]), "account_id": account}
        if part == "api":
            config["vars"] = {**config["vars"], "GOOGLE_CLIENT_ID": web["client_id"]}
        local = ROOT / PARTS[part].replace(".jsonc", ".local.json")
        local.write_text(json.dumps(config, indent=2) + "\n")
        print(f"deploying {part} ({config['name']})", flush=True)
        extra = ["--containers-rollout", "immediate"] if part == "relay" else []
        wrangler("deploy", "--config", str(local), *extra, env=env, capture=True)
        if part in secrets_of:
            with tempfile.TemporaryDirectory(prefix="stillfail-secrets-") as directory:
                path = Path(directory) / "secrets.json"
                write_private(path, secrets_of[part])
                wrangler("secret", "bulk", str(path), "--config", str(local), env=env, capture=True)
        print(f"deployed {part}", flush=True)

    with docker_env() as env:
        # The relay, then the API, in that order (the first split moved paths from one to the other); the static sites,
        # which depend on nothing, side by side after them (each is mostly wrangler's own round trips).
        for part in [p for p in parts if p in ("relay", "api")]:
            deploy(part, env)
        with ThreadPoolExecutor() as pool:
            for done in [pool.submit(deploy, p, env) for p in parts if p not in ("relay", "api")]:
                done.result()

    # Cloudflare turns away urllib's default User-Agent. A new custom domain's
    # certificate may take a few minutes; a failure here is not a failed deploy.
    # Each on its new host and its old one.
    admin = template["vars"]["ADMIN_ORIGIN"]
    old, old_admin = (aliases or [origin])[0], (template["vars"].get("ADMIN_ORIGIN_ALIASES") or admin).split(",")[0].strip()
    checks = {
        "api": [f"{origin}/healthz", f"{old}/healthz"],
        "relay": [f"{origin}/ping", f"{old}/ping"],
        "web": [f"{origin}/", f"{old}/"],
        "admin": [f"{admin}/", f"{old_admin}/"],
        "preview": ["https://preview.still.fail/_stillfail/frame", "https://preview.ember.3720.org/_ember/frame"],
        "site": ["https://still.fail/"],
    }
    for part in parts:
        for url in dict.fromkeys(checks[part]):
            request = urllib.request.Request(url, headers={"user-agent": "stillfail-deploy"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    print("check", part, url, response.status)
            except OSError as error:
                print("check", part, url, "failed:", error)


if __name__ == "__main__":
    main()
