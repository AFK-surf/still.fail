---
name: stillfail-login
description: Which login command to give the login tool for common CLIs (gh, gcloud, aws, az, npm, docker, vercel, wrangler, firebase) so the person can finish it from the login card, and which flags lead to steps the card cannot take.
---

# Logging this station in to a CLI

The `login` tool runs the tool's own login command here; the person does only the browser step, from the login card in
their still.fail app. What the card can take, by what the command does:

- **Device code** (a page and a code): every client, the web and phones included. Prefer it where the tool has one.
- **Page with a code to paste back** (the command asks for "the verification code" after printing a page, or says
  "copy the code and paste it below"): every client; call `login {id, paste: true}` and the person pastes it on the
  card. Do not answer that prompt yourself.
- **Loopback** (the page comes back to `localhost:<port>` here): the desktop and Android apps only; a person on the
  web cannot finish it.
- **A page to open** (the command polls by itself): every client.
- **A password or token typed in the terminal**: nobody; it is refused. Use another way, or say it cannot be done here.

Which command, as tested (docs/remote-login.md):

| Tool | Use | Flow | Avoid |
|---|---|---|---|
| gh | `gh auth login --web -h github.com --insecure-storage` | device code (answer its Y/n yourself) | plain `gh auth login` (menus, a token option); keychain storage |
| gcloud (CLI) | `gcloud auth login` | loopback, port 8085 | `--no-browser` (needs gcloud on another machine) |
| gcloud, person on the web | `gcloud auth login --no-launch-browser` | page, then the code pasted on the card (`paste: true`) | – |
| gcloud (SDK/ADC) | `gcloud auth application-default login`, only when code needs ADC or a person asks | loopback | doing it in place of `gcloud auth login`: they are separate credentials |
| aws | `aws sso login --use-device-code` | device code | – |
| az | `az login --use-device-code` | device code; may then ask for a subscription (answer it) | – |
| npm | `npm login` | a page to open | `--auth-type=legacy` (username and password) |
| docker | `docker login` | device code (Docker Hub) | – |
| vercel | `vercel login` | device code | – |
| wrangler | `wrangler login --device` | device code (8 characters, 5 minutes) | plain `wrangler login` (loopback, fails if 8976 is taken) |
| firebase | `firebase login` | loopback; first asks two Y/n questions (answer them) | – |

Before starting:

- Check whether it is already logged in (`gh auth status`, `gcloud auth list`, `aws sts get-caller-identity`,
  `az account show`, `npm whoami`…). Say who it is logged in as; start a login only if another account is wanted or it
  has expired.
- A tool not listed: take its device-code option if it has one (`--device`, `--device-code`, `--use-device-code`),
  else its default browser login.
- The agents' own runtimes (Claude Code, Codex) are signed in from the station's accounts page, not with this tool.

After it ends, check it worked (the status command again) and say which account and project or org it is on.
