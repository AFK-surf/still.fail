#!/usr/bin/env python3
"""Deploys still.fail cloud, six Workers (wrangler.jsonc says what each is; they keep their names from before the
rename to still.fail, as do their Durable Objects, bucket and secrets: renaming would make new, empty ones):
  api       stillfail-cloud     the API (wrangler.jsonc)
  relay     stillfail-relay     the relay and its container (wrangler.relay.jsonc)
  web       stillfail-web       the web app, static (wrangler.web.jsonc): app.still.fail, the stable one
  web-beta  stillfail-web-beta  the same build on app.youdid.wtf, the test channel (wrangler.web-beta.jsonc)
  admin     stillfail-admin     the admin's console, static (wrangler.admin.jsonc)
  preview   stillfail-preview   the preview host, static (wrangler.preview.jsonc)
Each is deployed on its own: deploying the API drops no relay connection and serves no page. (And the official
site, `site`, still-fail-site; and the test channel's, `site-beta`, youdid-wtf-site on youdid.wtf, only when named.)
The test channel lives on its own domain, youdid.wtf: until that zone is active on Cloudflare (or with STILLFAIL_BETA=off)
web-beta and site-beta are skipped, the API is deployed without the app.youdid.wtf routes and BETA_ORIGIN, and a deploy
without parts deploys web instead of web-beta. STILLFAIL_BETA=on skips the check.

The web app goes to the test channel first: a deploy without parts deploys web-beta, not web, and keeps the build it
deployed in <deploy>/builds/<commit>/cloud-web (the newest ten). Once tried there, that very build (not a new one) goes
to app.still.fail with promote-web. `web` named deploys a new build to app.still.fail straight away.

    python3 deploy.py                   # all but web and site-beta: relay, api, then web-beta, admin, preview, site
    python3 deploy.py api web-beta      # only these (the static ones are built first)
    python3 deploy.py web               # a new build to app.still.fail, without the test channel
    python3 deploy.py promote-web <dir> # a build already made (a directory, or a commit kept in <deploy>/builds) to app.still.fail
    python3 deploy.py --check           # only report what is missing

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
  apple     <deploy>/apple.json, {"services_id", "team_id", "key_id", "private_key", "bundle_ids"}: Sign in with
            Apple (cloud/src/apple.ts). The Services ID's return URL is <origin>/v1/auth/apple/callback; private_key
            is the PEM of the team's Sign in with Apple key (.p8); bundle_ids, the iOS apps'. Without it, no Apple.
Cloudflare: an interactive `wrangler login` (or CLOUDFLARE_API_TOKEN). Docker (OrbStack) builds the relay image.
"""
import argparse
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager, nullcontext
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
# Push notifications (docs/notifications.md): the VAPID key ({public, private, subject}) and Firebase's service account.
VAPID = DEPLOY / "vapid.json"
FCM = DEPLOY / "fcm-service-account.json"
APPLE = DEPLOY / "apple.json"


def write_private(path: Path, value) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(value, f, indent=2)
    os.replace(tmp, path)


PARTS = {"relay": "wrangler.relay.jsonc", "api": "wrangler.jsonc", "web": "wrangler.web.jsonc", "web-beta": "wrangler.web-beta.jsonc", "admin": "wrangler.admin.jsonc", "preview": "wrangler.preview.jsonc", "site": "wrangler.site.jsonc", "site-beta": "wrangler.site-beta.jsonc"}
# What a deploy without parts deploys: the web app only to the test channel (promote-web takes it on); not youdid.wtf's site.
DEFAULT_PARTS = [p for p in PARTS if p not in ("web", "site-beta")]
# The test channel's parts, on its own domain (youdid.wtf): deployed only once that zone is on Cloudflare (beta_zone()).
BETA_PARTS = ("web-beta", "site-beta")
# The web app's builds deployed to the test channel, by commit, for promote-web.
BUILDS = DEPLOY / "builds"
KEEP_BUILDS = 10


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


def push() -> dict:
    value = {}
    if VAPID.exists():
        vapid = json.loads(VAPID.read_text())
        value |= {"VAPID_PUBLIC_KEY": vapid["public"], "VAPID_PRIVATE_KEY": vapid["private"], "VAPID_SUBJECT": vapid["subject"]}
    else:
        print(f"note: {VAPID} is missing; no Web Push")
    if FCM.exists():
        value["FCM_SERVICE_ACCOUNT"] = FCM.read_text()
    else:
        print(f"note: {FCM} is missing; no pushes to Android")
    return value


def apple() -> dict:
    if not APPLE.exists():
        print(f"note: {APPLE} is missing; no Sign in with Apple")
        return {}
    value = json.loads(APPLE.read_text())
    return {"APPLE_CLIENT_ID": value["services_id"], "APPLE_TEAM_ID": value["team_id"], "APPLE_KEY_ID": value["key_id"],
            "APPLE_PRIVATE_KEY": value["private_key"], "APPLE_BUNDLE_IDS": ",".join(value.get("bundle_ids", []))}


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


def beta_zone() -> str:
    """The test channel's zone: the registrable domain of BETA_ORIGIN (youdid.wtf)."""
    host = urllib.parse.urlparse(read_template()["vars"].get("BETA_ORIGIN", "")).hostname or ""
    return ".".join(host.split(".")[-2:])


def beta_ready(account: str) -> bool:
    """Whether the test channel's zone is an active zone of the account. STILLFAIL_BETA=on|off says so instead."""
    said = (env_var("BETA") or "").lower()
    if said in ("on", "off"):
        return said == "on"
    zone = beta_zone()
    if not zone:
        return False
    try:
        auth = json.loads(wrangler("auth", "token", "--json", capture=True))
        headers = {"user-agent": "stillfail-deploy"}
        if auth.get("type") == "api_key":
            headers |= {"x-auth-key": auth["key"], "x-auth-email": auth["email"]}
        else:
            headers["authorization"] = f"Bearer {auth['token']}"
        url = f"https://api.cloudflare.com/client/v4/zones?name={zone}&account.id={account}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as response:
            zones = json.loads(response.read()).get("result") or []
        return any(z.get("status") == "active" for z in zones)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"note: could not ask Cloudflare about the zone {zone} ({error}); taking it for missing")
        return False


def without_beta(config: dict) -> dict:
    """The API's config without the test channel's host: its routes (their zone is not there yet) and BETA_ORIGIN."""
    zone = beta_zone()
    routes = [r for r in config.get("routes", []) if not (zone and isinstance(r, dict) and r.get("zone_name") == zone)]
    return {**config, "routes": routes, "vars": {k: v for k, v in config["vars"].items() if k != "BETA_ORIGIN"}}


def commit() -> str:
    sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=REPO, text=True).strip()
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=REPO, text=True).strip()
    return f"{sha}-dirty" if dirty else sha


def keep_build() -> Path:
    """dist/cloud-web, as just deployed to the test channel, under <deploy>/builds/<commit>/cloud-web; the newest ten stay."""
    target = BUILDS / commit() / "cloud-web"
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(REPO / "dist" / "cloud-web", target)
    for old in sorted((d for d in BUILDS.iterdir() if d.is_dir()), key=lambda d: d.stat().st_mtime, reverse=True)[KEEP_BUILDS:]:
        shutil.rmtree(old)
    return target


def promoted_build(name: str) -> Path:
    """The build promote-web was given: a directory of the web app's files, or a commit (or its start) kept in BUILDS."""
    given = Path(name).expanduser()
    if given.is_dir():
        return (given / "cloud-web" if (given / "cloud-web" / "index.html").exists() else given).resolve()
    kept = [d for d in BUILDS.iterdir() if d.name.startswith(name)] if BUILDS.exists() and name else []
    if len(kept) != 1:
        sys.exit(f"no build {name}: give the directory of a build of the web app, or one commit of {BUILDS} ({len(kept)} match)")
    return kept[0] / "cloud-web"


def promote_web(name: str) -> None:
    """A build already deployed to the test channel to app.still.fail (stillfail-web), byte for byte: nothing is built."""
    build = promoted_build(name)
    if not (build / "index.html").exists():
        sys.exit(f"{build} has no index.html: not a build of the web app")
    config = {**read_template(PARTS["web"]), "account_id": account_id()}
    config["assets"] = {**config["assets"], "directory": str(build)}
    local = ROOT / "wrangler.web.local.json"
    local.write_text(json.dumps(config, indent=2) + "\n")
    print(f"promoting {build} to web ({config['name']})", flush=True)
    wrangler("deploy", "--config", str(local), capture=True)
    say_web_build(build, beta=False)
    origin = read_template()["vars"]["PUBLIC_ORIGIN"]
    request = urllib.request.Request(f"{origin}/", headers={"user-agent": "stillfail-deploy"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            print("check web", origin, response.status)
    except OSError as error:
        print("check web", origin, "failed:", error)


def say_web_build(build: Path, beta: bool) -> None:
    """What the web app has out on a channel, from its build.json, in the releases bucket's web.json (web-beta.json) for
    the changelog to say which fixes it carries (src/changelog.ts). A build from before build.json says nothing."""
    said = build / "build.json"
    if not said.exists():
        print(f"note: {said} is missing: web{'-beta' if beta else ''}.json not written", flush=True)
        return
    name = "web-beta.json" if beta else "web.json"
    wrangler("r2", "object", "put", f"stillfail-releases/{name}", "--file", str(said), "--content-type", "application/json", "--remote", capture=True)
    print(f"put {name} ({json.loads(said.read_text()).get('version')})", flush=True)


def main() -> None:
    if sys.argv[1:2] == ["promote-web"]:
        if len(sys.argv) != 3:
            sys.exit("usage: deploy.py promote-web <directory of a build, or a commit kept in <deploy>/builds>")
        return promote_web(sys.argv[2])
    parser = argparse.ArgumentParser()
    parser.add_argument("parts", nargs="*", help=f"what to deploy, of {', '.join(PARTS)} (default: all but web)")
    parser.add_argument("--google", type=Path, default=DEPLOY / "google-oauth.json")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--skip-build", action="store_true", help="deploy the static sites already in dist/")
    parser.add_argument("--dry-run", action="store_true", help="build and bundle each part (wrangler deploy --dry-run), "
                        "deploy nothing: CI on a branch, without Cloudflare's login or the deploy directory's secrets")
    args = parser.parse_args()
    unknown = set(args.parts) - set(PARTS)
    if unknown:
        sys.exit(f"no such part: {', '.join(sorted(unknown))}")
    parts = [p for p in PARTS if p in args.parts] or list(DEFAULT_PARTS)

    template = read_template()
    origin = template["vars"]["PUBLIC_ORIGIN"]
    aliases = [o.strip() for o in template["vars"].get("PUBLIC_ORIGIN_ALIASES", "").split(",") if o.strip()]
    # Only the API needs the Google client: a deploy of the static sites (CI's web-beta) goes without it.
    web = json.loads(args.google.read_text())["web"] if (args.check or "api" in parts) and not args.dry_run else {}
    # Google calls back the new origin; a login started on an old one before a deploy, the old one.
    for callback in [f"{o}/v1/auth/google/callback" for o in [origin, *aliases]] if web else []:
        if callback not in web.get("redirect_uris", []):
            print(f"note: {args.google} does not list {callback}; make sure it is registered in Google Cloud Console")
    if args.check:
        print("account", account_id())
        print("keys", "present" if KEYS.exists() else "will be created")
        print("posthog", "present" if POSTHOG.exists() else "missing: the web app will have no analytics")
        print("axiom", "present" if AXIOM.exists() else f"missing: no traces without {AXIOM}")
        print("vapid", "present" if VAPID.exists() else f"missing: no Web Push without {VAPID}")
        print("fcm", "present" if FCM.exists() else f"missing: no pushes to Android without {FCM}")
        print("apple", "present" if APPLE.exists() else f"missing: no Sign in with Apple without {APPLE}")
        print("beta zone", beta_zone(), "active" if beta_ready(account_id()) else "not active: web-beta and site-beta will be skipped")
        return

    # A dry run asks Cloudflare nothing: any account, and the test channel taken as there (STILLFAIL_BETA=off says not).
    account = "0" * 32 if args.dry_run else account_id()
    beta = (env_var("BETA") or "").lower() != "off" if args.dry_run else beta_ready(account)
    if not beta:
        skipped = [p for p in parts if p in BETA_PARTS]
        print(f"note: the test channel's zone ({beta_zone() or 'BETA_ORIGIN unset'}) is not an active zone on Cloudflare yet: "
              f"skipping {', '.join(skipped) or 'nothing'}, and the API goes without its routes and BETA_ORIGIN "
              "(STILLFAIL_BETA=on to deploy them anyway)", flush=True)
        parts = [p for p in parts if p not in BETA_PARTS]
        # Without the test channel, the web app a deploy without parts would have sent there goes to app.still.fail.
        if not args.parts and "web-beta" in skipped:
            parts.insert(parts.index("admin"), "web")
            print("note: deploying web (app.still.fail) instead of web-beta", flush=True)
    if not args.skip_build and {"web", "web-beta", "admin", "preview"} & set(parts):
        # web/vite.config.ts reads the key from the file STILLFAIL_POSTHOG (EMBER_POSTHOG before the rename) names.
        if not POSTHOG.exists():
            print(f"note: no {POSTHOG}; building the web app without analytics")
        env = {**os.environ, "STILLFAIL_POSTHOG": str(POSTHOG), "EMBER_POSTHOG": str(POSTHOG)} if POSTHOG.exists() else None
        subprocess.run(["pnpm", "run", "build:cloud"], cwd=REPO, env=env, check=True)
    if not args.skip_build and "site" in parts:
        subprocess.run(["pnpm", "run", "build:site"], cwd=REPO, check=True)
    if not args.skip_build and "site-beta" in parts:
        subprocess.run(["pnpm", "run", "build:site-beta"], cwd=REPO, check=True)
    # Read only for the parts that take them: keys() makes keys.json where there is none, which a deploy of the static
    # sites alone (CI's web-beta, on a machine without the deploy directory's keys) must not do.
    secrets_of = {
        "api": lambda: {**keys(), "GOOGLE_CLIENT_SECRET": web["client_secret"], **axiom(), **push(), **apple()},
        "relay": lambda: {"ADMIN_TOKEN": keys()["ADMIN_TOKEN"]},
    }
    def deploy(part: str, env) -> None:
        config = {**read_template(PARTS[part]), "account_id": account}
        if part == "api":
            config["vars"] = {**config["vars"], "GOOGLE_CLIENT_ID": web.get("client_id", "dry-run")}
            if not beta:
                config = without_beta(config)
        local = ROOT / PARTS[part].replace(".jsonc", ".local.json")
        local.write_text(json.dumps(config, indent=2) + "\n")
        print(f"{'bundling' if args.dry_run else 'deploying'} {part} ({config['name']})", flush=True)
        if args.dry_run:
            with tempfile.TemporaryDirectory(prefix="stillfail-dry-run-") as out:
                wrangler("deploy", "--config", str(local), "--dry-run", "--outdir", out, env=env, capture=True)
            print(f"bundled {part}", flush=True)
            return
        extra = ["--containers-rollout", "immediate"] if part == "relay" else []
        wrangler("deploy", "--config", str(local), *extra, env=env, capture=True)
        if part == "web-beta":
            print(f"kept the build for promote-web in {keep_build()}", flush=True)
        if part in ("web", "web-beta"):
            say_web_build(REPO / "dist" / "cloud-web", beta=part == "web-beta")
        if part in secrets_of:
            with tempfile.TemporaryDirectory(prefix="stillfail-secrets-") as directory:
                path = Path(directory) / "secrets.json"
                write_private(path, secrets_of[part]())
                wrangler("secret", "bulk", str(path), "--config", str(local), env=env, capture=True)
        print(f"deployed {part}", flush=True)

    # Docker only builds the relay's image: the other parts deploy without it (a CI runner may have none).
    with docker_env() if "relay" in parts else nullcontext(dict(os.environ)) as env:
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
        "web-beta": [f"{template['vars'].get('BETA_ORIGIN', 'https://app.youdid.wtf')}/"],
        "admin": [f"{admin}/", f"{old_admin}/"],
        "preview": ["https://preview.still.fail/_stillfail/frame", "https://preview.ember.3720.org/_ember/frame"],
        "site": ["https://still.fail/"],
        "site-beta": [f"https://{beta_zone()}/"],
    }
    for part in [] if args.dry_run else parts:
        for url in dict.fromkeys(checks[part]):
            request = urllib.request.Request(url, headers={"user-agent": "stillfail-deploy"})
            try:
                with urllib.request.urlopen(request, timeout=30) as response:
                    print("check", part, url, response.status)
            except OSError as error:
                print("check", part, url, "failed:", error)


if __name__ == "__main__":
    main()
