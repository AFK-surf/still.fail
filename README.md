# still.fail

Coding agents for team conversations, running on machines you control.

still.fail connects Slack and its own web chat to persistent Claude Code or Codex sessions. A **station** runs the agents on your machine; a **workspace** brings the team and its stations together. Web, desktop and Android clients share a Rust client core.

团队聊天里的 coding agent 服务：在 Slack 或 still.fail 自己的网页对话里找它，每个对话落到一个持久的 agent 会话，由 Claude Code 或 Codex 驱动。station 在你自己的机器上执行任务，workspace 管理团队和节点。

## Try it

Visit [still.fail](https://still.fail) for the apps, or open the [web app](https://app.still.fail). Create a workspace and follow its **Add station** instructions on the machine that will run your agents. Configure the Claude Code or Codex account on that station. Those runtimes and their accounts are separate from this project.

Every station must join a workspace before it can run conversations. For an isolated development setup with a local control plane and mock sign-in, see [Development](docs/development.md).

## Repository

- `mesh/`：station（Rust，`ember-station`），跑在执行 agent 的机器上
- `client/`：各客户端共用的 Rust client core；`web/`（网页版和管理页）、`apps/desktop`（Electron）、`apps/android`
- `cloud/`：still.fail cloud（账号、workspace、成员凭证、relay，部署在 Cloudflare）

## Development and contributions

- [Development setup](docs/development.md): toolchains, builds and local services.
- [Contributing](CONTRIBUTING.md): changes, checks and pull requests.
- [Architecture](docs/design.md) and [client core](docs/client-core.md).
- [Operations](docs/operations.md): maintainer deployment details; these use the project's own infrastructure.
- [Security](SECURITY.md): private reporting and the station's trust boundary.

The project is under active development. Some deployment scripts and Wrangler configurations target the hosted still.fail service; they are not a one-command self-hosting installer. Read and replace the service-specific configuration before deploying your own instance.

## License

[MIT](LICENSE). Vendored code and dependencies retain their own licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
