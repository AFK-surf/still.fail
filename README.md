<p align="center"><img src="web/public/icon-192.png" width="96" height="96" alt="still.fail"></p>

<h1 align="center">still.fail</h1>

<p align="center">Coding agents for team conversations, running on machines you control.<br>
<a href="https://still.fail">Website</a> · <a href="https://app.still.fail">Web app</a> · <a href="docs/development.md">Development</a> · <a href="docs/design.md">Architecture</a></p>

still.fail connects Slack threads and its own web chats to persistent Claude Code or Codex sessions. Mention it in a thread and the conversation lands in an agent session that keeps its workspace, history and running jobs between messages. When the agent needs someone to decide something, the question goes to that person's list of pending decisions.

团队聊天里的 coding agent 服务：在 Slack 或 still.fail 自己的网页对话里找它，每个对话落到一个持久的 agent 会话，由 Claude Code 或 Codex 驱动。station 在你自己的机器上执行任务，workspace 管理团队和节点。部分设计文档目前只有中文。

## How it works

- A **station** (`station/`, TypeScript on Node, with a few prebuilt native parts in Rust) runs on a machine you choose. It starts and keeps the agent sessions, connects to Slack, and stores conversations locally in SQLite.
- A **workspace** groups people and stations. The cloud service (`cloud/`, Cloudflare Workers) handles accounts, workspaces and member credentials, and runs the relays.
- **Clients** (web, desktop and Android) share one client core in TypeScript (`client/core-ts`). They connect to stations peer-to-peer over [iroh](https://github.com/n0-computer/iroh), directly on the local network or through a relay; conversation content does not pass through the cloud's database.

See [docs/design.md](docs/design.md) and [docs/cloud.md](docs/cloud.md) for details.

## Try it

1. Open the [web app](https://app.still.fail), or download the desktop (macOS, Apple silicon) or Android app from [still.fail](https://still.fail).
2. Create a workspace. The free plan includes one workspace with one person and two stations.
3. Follow **Add station** on the machine that will run your agents. Stations are available for macOS (arm64) and Linux (x64, arm64).
4. Sign in to Claude Code or Codex on that station. Those runtimes and their accounts are separate from this project, and the agents run with that machine's user permissions; read the [trust boundary](SECURITY.md#trust-boundary) first.

Every station must join a workspace before it can run conversations.

## Build from source

[docs/development.md](docs/development.md) covers toolchains, builds and an isolated local setup: a local control plane with mock sign-in, a local relay and a disposable station. The cloud tests run without any accounts:

```sh
git clone https://github.com/AFK-surf/still.fail.git
cd still.fail
pnpm install --frozen-lockfile
cd cloud && pnpm install --frozen-lockfile && pnpm run types && pnpm test
```

**Self-hosting** is possible but not yet supported as a product. The deployment scripts and Wrangler configurations target the hosted still.fail service (its domains, relays and admin account); replace that configuration before deploying your own instance. See [Production self-hosting](docs/development.md#production-self-hosting).

## Privacy and telemetry

Desktop and Android builds connect to the hosted service at `app.still.fail` by default. Clients send operation traces (names, timings and errors, without message content) to the configured cloud. Product analytics (PostHog) are only included when a key is supplied at build time, so builds from this repository have none; station error reports are off unless the station's operator enables them. See [docs/telemetry.md](docs/telemetry.md).

## Repository

| Path | Contents |
| --- | --- |
| `station/` | Station (`stillfail-station`) and its agent runtime integrations; its native parts in `station/native/` |
| `client/` | Shared client core (`core-ts`), its native shells (the browser's iroh, Android's IO) and translations (`i18n`) |
| `web/` | Web app, official site and previews |
| `apps/desktop/`, `apps/android/` | Electron and native Android clients |
| `cloud/` | Accounts, workspaces, relays and releases on Cloudflare |
| `docs/` | Design and operation notes; release notes in `docs/releases/` |
| `test/`, `spike/` | Integration tests; experiments that verified runtime assumptions |
| `vendor/` | Patched third-party Rust crates |

## Documentation

- [Development setup](docs/development.md) and [contributing](CONTRIBUTING.md)
- [Architecture](docs/design.md), [client core](docs/client-core.md), [cloud](docs/cloud.md), [station storage](docs/station-storage.md)
- [Notifications](docs/notifications.md), [station peers](docs/station-peers.md), [telemetry](docs/telemetry.md)
- [Operations](docs/operations.md): how the maintainers build and deploy the hosted service, on their own infrastructure
- [Security](SECURITY.md): private reporting and the station's trust boundary

## Status

still.fail is under active development and pre-1.0. Versions are `0.1.<n>`; the beta channel follows `main`, and stable releases are published from reviewed release notes in [docs/releases](docs/releases). Stations, clients and the cloud update independently, so changes keep older and newer versions working together.

## License

[MIT](LICENSE). Vendored code, dependencies and third-party marks retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
