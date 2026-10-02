# Security

## Reporting a vulnerability

Please do not report vulnerabilities, credentials or private conversation data in public issues. Use GitHub's **Security → Report a vulnerability** on [AFK-surf/still.fail](https://github.com/AFK-surf/still.fail/security/advisories/new) when private vulnerability reporting is enabled. If that option is unavailable, contact a repository maintainer privately to arrange a secure channel before sending sensitive details.

Include the affected version or commit, reproduction steps, impact and a minimal proof of concept with synthetic data. Test only systems and accounts you are authorized to use. We do not currently promise a response SLA or maintain an LTS release line; fixes target current development and releases.

## Trust boundary

A station runs coding agents with access to its operating-system account, files, commands and configured runtime credentials. Workspace membership is an application access boundary, not an operating-system sandbox for agent execution. Use a dedicated account or machine appropriate to the people and code you trust. Do not expose local MCP endpoints to the public internet.

The local development cloud uses mock sign-in and development-only login routes. Keep it on loopback and do not deploy it as a production authentication service.

## Credentials and automation

- Keep deployment credentials, OAuth client secrets, service-account keys and signing keys outside Git. Revocation or rotation comes before history cleanup if a real secret is committed.
- Firebase client configuration is embedded in the Android app. Its API key is not a server credential, but the owning project must restrict the key to the intended APIs and applications. See [Firebase's guidance](https://firebase.google.com/docs/projects/api-keys).
- External contributions must not run on persistent self-hosted runners or receive deployment credentials. Review code before running it on maintainer machines.
- Automated secret scanning can miss secrets and private data. Review logs, fixtures, assets and Git history before publishing them.
