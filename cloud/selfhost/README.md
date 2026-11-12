# still.fail cloud, self-hosted

still.fail cloud runs outside Cloudflare on [workerd](https://github.com/cloudflare/workerd), the runtime under
Workers: the same scripts, Durable Objects with SQLite on a local disk, the static sites from disk. Nothing of
still.fail's hosted service is used or named: the cloud's names, its relay, its admin and its sign-in are the
operator's, read from the environment as it starts, so one build serves any name.

| On Cloudflare | Self-hosted |
| --- | --- |
| The Workers (`wrangler*.jsonc`) and their routes | One workerd process (`config.capnp`, made by `config.ts` from the wrangler files); `router.ts` sends each request to the Worker its host and path are routed to |
| Durable Objects | workerd's, SQLite in `$STILLFAIL_DATA/objects` |
| R2 `RELEASES` | `releases.ts`: files in `$STILLFAIL_DATA/releases`, at the bucket's keys |
| `send_email` | `mail.ts`: SMTP to the operator's relay (`SMTP_URL`), or, without one, the mail written to workerd's log |
| Google sign-in | Google with the operator's client, or any OpenID provider (`OIDC_ISSUER`); and codes sent to an email |
| The relay's Container (`relay-worker.ts`, `Dockerfile`) | `iroh-relay` itself, on a name of its own (`RELAY_URL`) |
| TLS, the hosts | A reverse proxy in front (Caddy, say) |
| The cron (`triggers`) | `POST /v1/scheduled` on the setup socket, from the operator's timer (hourly at :07 for the models' catalog) |

## Build

```sh
pnpm install --frozen-lockfile && (cd cloud && pnpm install --frozen-lockfile)
bash apps/mbui/scripts/web-app.sh       # the app for the browser (MoonBit), as for any web build
cd cloud && node selfhost/build.ts      # --out DIR (default dist/selfhost); --sites-built to keep dist/cloud-* as they are
```

The directory has workerd (the `workerd` package's binary, the version `package.json` pins), the bundled Workers,
`config.capnp`, the sites, `run` and `cloud.env.example`. It is made anew each time. The web app is built without a
preview host of its own: its pages are told this cloud's (`PREVIEW_ORIGIN`) as they are served.

## Run

```sh
cp dist/selfhost/cloud.env.example cloud.env    # and fill it in
set -a; . ./cloud.env; set +a
STILLFAIL_DATA=/var/lib/stillfail-cloud dist/selfhost/run
iroh-relay --config-path relay.toml             # HTTP on 127.0.0.1:3340; cloud/relay-entrypoint.sh's settings
```

`run` listens on `LISTEN` (default `127.0.0.1:8080`) for the proxy in front, and on `SETUP_LISTEN` (default
`127.0.0.1:8081`) for the operator's own calls; neither may be reachable from anywhere else. The proxy ends TLS for
the cloud's names and sends `X-Forwarded-Proto` and `X-Forwarded-For` (Caddy does by default):

```
cloud.example.com, admin.cloud.example.com, preview.cloud.example.com {
	reverse_proxy 127.0.0.1:8080
}
relay.cloud.example.com {
	reverse_proxy 127.0.0.1:3340
}
```

### Settings

| Variable | |
| --- | --- |
| `PUBLIC_ORIGIN` | The cloud: the web app and the API (`https://cloud.example.com`). Stations enroll with it; the web app needs nothing else, as it talks to the origin it is served from. |
| `ADMIN_ORIGIN`, `PREVIEW_ORIGIN` | The console's host and the preview host (stations' web services): each a name of its own. |
| `RELAY_URL` | iroh-relay; more in `RELAY_URLS` (comma-separated). |
| `PUBLIC_ORIGIN_ALIASES` | Other names of the cloud, answered the same (comma-separated). |
| `AUTH_SIGNING_KEY`, `ADMIN_TOKEN` | 43 random characters or more each (`head -c 32 /dev/urandom \| basenc --base64url \| tr -d =`). |
| `GRANT_SIGNING_JWK` | An Ed25519 private JWK with a `kid`: `node -e 'const k=require("crypto").generateKeyPairSync("ed25519").privateKey.export({format:"jwk"});console.log(JSON.stringify({...k,kid:"selfhost-1"}))'`. Keep it and the two above: losing them signs everyone out and makes stations distrust new grants. |
| `ADMIN_EMAIL` | The console's admin. |
| `EMAIL_FROM`, `SMTP_URL`, `SMTP_HELO` | Signing in with a code sent to an email: from `EMAIL_FROM`, through `smtp://user:password@host:587` (STARTTLS, required) or `smtps://…:465`. Without `SMTP_URL` the codes are written to the log (`MAIL to …`): enough for a cloud only its operator signs in to, who reads its log. |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | The OAuth client people sign in through, its redirect URI `$PUBLIC_ORIGIN/v1/auth/google/callback`: Google's, or with `OIDC_ISSUER` that provider's (its discovery document at `$OIDC_ISSUER/.well-known/openid-configuration`; a public client with PKCE needs no secret). `OIDC_NAME` is what the sign-in page calls it. Its accounts are named apart from Google's (`oi-…`) and join one with the same email. |

The API's other settings (`env.ts`: push, traces) are read from the environment under their own names too; settings
that are JSON on Cloudflare (`RELAY_NAMES`, `STATUS_PAGES`) are not available.

### The setup socket

Each call with `Authorization: Bearer $ADMIN_TOKEN`:

- `POST /v1/setup {"admin": "<email>", "workspace": "<name>", "station": "<name>"}`: the admin's account (the one a
  code to that email signs in to), its workspace of that name, made once, and while it has no station an enrollment
  for one: `{cloud, relays, workspace, workspace_name, stations, enrollment?: {name, token, expires_at, command}}`. What a machine
  that is its own cloud runs at its first boot.
- `POST /v1/scheduled`: what Cloudflare's cron runs.

### Releases

Stations update, and the installer gets them, from `$PUBLIC_ORIGIN/releases/…`: the files `scripts/release.sh` puts in
the bucket, put in `$STILLFAIL_DATA/releases` at the same paths.

## Apps

The web app is served by the cloud and talks to the origin it is served from, so it needs nothing more. The native
apps are built for one cloud (`MBUI_CLOUD`, `https://app.still.fail` by default) and have no setting to choose another
yet.
