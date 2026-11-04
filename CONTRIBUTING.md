# Contributing to still.fail

Bug reports and focused pull requests are welcome. Describe the expected behavior, what happened, your platform and app version, and steps to reproduce. Remove credentials, conversation content and personal data from logs and screenshots. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

For a larger change, open an issue first to agree on the scope. Start from `main`, keep a change focused, and explain the problem and resulting behavior in the pull request. Include the checks you ran and their results; include screenshots or a recording for visible changes.

## Set up and check a change

Follow [docs/development.md](docs/development.md). After installing the required toolchains:

```sh
git fetch origin
sh scripts/check.sh full origin/main..HEAD
```

This checks the parts changed by your commits. `sh scripts/check.sh all` checks the entire project and needs the Rust, WebAssembly and Android toolchains. Git hooks run the faster checks when committing and pushing. Do not treat a skipped toolchain check as a passing full check.

Run integration tests with a local control plane and a disposable station, not against the hosted service or a station with real conversations. Never commit station data, runtime credentials, deployment secrets or signing keys.

## Design constraints

- Older stations and newer clients coexist, for a while: a path kept for older versions is removed 7 days after its replacement ships, and the same change raises the floor for the other side (`OLDEST_CORE` in `station/src/api/oldest.ts`, `OLDEST_STATION` in `client/core-ts/src/station/oldest.ts`) to the build that first did without it, so older versions are told to update instead of being served the old way. Preserve existing commands and shared links. Databases are migrated forward; a station is not expected to open a database a newer one migrated.
- Keep client state and operations in the core (`client/core-ts`). Views name operations and render state; they do not call station HTTP endpoints directly.
- Keep workspace data isolated. Show progress and errors for user operations.
- Keep upstream notices in `vendor/`; document local patches in its README.

## CI and review

External pull requests run the `contributions` workflow on GitHub-hosted runners with a read-only token and no deployment secrets. Its cloud checks are only part of validation; maintainers run the relevant full checks before merging. The separate `pipeline` workflow is for trusted pushes to this repository and uses maintainer infrastructure. Do not add fork pull-request triggers to it or run unreviewed contributions on those machines.

Contributions must be yours to submit and are provided under this repository's MIT license, except material explicitly retaining a compatible third-party license. Preserve third-party attribution when copying code or assets.
