# Before making the repository public

This is the maintainer checklist for publishing `AFK-surf/still.fail`. Merging the preparation branch does not change repository visibility.

## Repository contents

- [x] MIT license selected by the maintainer; root license and third-party notices added.
- [x] Restore missing MIT/Apache license texts for vendored iroh crates from their release revisions.
- [x] Add a contributor guide, security policy and local development instructions; update the GitHub links and obsolete local-admin instructions.
- [x] Remove the tracked Python bytecode cache and extend ignores for local credentials and generated files.
- [x] Separate external PR cloud checks onto GitHub-hosted runners; scope the deployment tag's write permission to its job. Keep the persistent-runner workflow limited to trusted repository pushes/manual runs.
- [x] Run Gitleaks 8.30.1 with its default rules against available Git history and the working tree. The initial history scan examined 1,607 commits and reported eight findings: seven test/RFC examples and one Firebase client API key. The tree scan reported the four corresponding current locations. No server credential was identified in those findings.
- [x] 2026-10-03 recheck: Gitleaks 8.30.1 over all 1,979 local commits (all branches) found the same eight findings and nothing new. Personal names, emails and home paths were removed from tests, mockups and docs; the cloud's admin account moved from code to `cloud/wrangler.jsonc`; LAN and home IP addresses were removed from the operations log; logo licenses were added to the third-party notices. Remaining personal identifiers are operator configuration: the admin email in `cloud/wrangler.jsonc` and the Apple signing identity in `apps/desktop/package.json` and the pipeline.
- [ ] Confirm the Firebase client's API and application restrictions in the owning Google Cloud project. The client key is in `apps/android/firebase.properties` and existing APKs; do not treat it as a server secret or assume it is safely restricted. [Firebase documentation](https://firebase.google.com/docs/projects/api-keys).
- [ ] Review the intended public scope: commit author identities (the history is authored as `3720 <zuozijian1994@gmail.com>`), historical operations notes (`docs/ops-log.md`, `docs/rename-still-fail.md` name internal machines and paths and stay readable in history), relay addresses in `cloud/wrangler.jsonc`, product artwork (`design/icons`, drawn for still.fail) and the provenance of the provider marks noted as from "Zork's provider set" in `web/src/ui.tsx`. The scan does not establish publication rights or detect all private data. This preparation does not rewrite Git history.
- [ ] Review existing branches (27 on 2026-10-03, most unmerged work in progress), tags, Actions logs (862 runs) and artifacts (built web bundles), and issues/PRs that will become accessible. A local Git scan does not cover GitHub-hosted artifacts or private systems outside the repository.

## GitHub administrator settings

Settings below must be verified by an administrator. On 2026-10-03: `main` was not protected (agents and maintainers push to it directly), private vulnerability reporting was not available for the private repository, and Actions default to a read-only token.

- [ ] Protect `main` with review and appropriate required checks. Review who has write access: a trusted push can run on the persistent internal runners.
- [ ] Require approval for outside contributors' workflows. Never route fork PR code to `mini1`/`studio`, and do not add `pull_request_target` to execute a contributor's checkout. [GitHub runner guidance](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners).
- [ ] Check the `production` environment's allowed deployment branch and reviewers, runner availability after transfer, and Actions token defaults. The desktop release now uses the same production environment as the other release jobs.
- [ ] Enable private vulnerability reporting and verify that the [report link](https://github.com/AFK-surf/still.fail/security/advisories/new) is available before announcing it.
- [ ] Enable secret scanning and push protection where available; review alerts rather than broadly suppressing paths or secret rules.
- [ ] Run the new `contributions` workflow and the existing pipeline on the final commit; review results. A hosted cloud check is not the full multi-platform test suite.
- [ ] Confirm release assets preserve all bundled third-party notices. `THIRD_PARTY_NOTICES.md` covers vendored source; it is not a complete binary-distribution license audit.
- [ ] Once the checks and publication review are complete, explicitly approve switching repository visibility to Public in Settings → General → Danger Zone.

The official site's GitHub link is updated in source; publishing that link requires a site deployment. Local shared Git remotes were updated to the organization URL; other development machines can update their remotes independently (GitHub also redirects the previous URL).
