# Third-party notices

The root MIT license covers this project's original work. It does not replace licenses or copyright notices for third-party code and assets.

## Vendored Rust crates

These patched crates come from the corresponding crates.io releases. The iroh and iroh-mdns-address-lookup MIT/Apache license texts were restored from the upstream revisions recorded in those releases’ `.cargo_vcs_info.json` (`f2eb930dda3779c6d852b72f3712aacd6e573ab1` and `87fdd7ea1a902845695f8f685c1905f096b3d02d`). Preserve their license files when redistributing them; local changes are described in [vendor/README.md](vendor/README.md).

| Crate | Version | Upstream license | Included notices |
| --- | --- | --- | --- |
| iroh | 1.0.3 | MIT OR Apache-2.0; BSD-3-Clause for the separately attributed code | [MIT](vendor/iroh/LICENSE-MIT), [Apache](vendor/iroh/LICENSE-APACHE), [BSD](vendor/iroh/LICENSE-BSD3) |
| iroh-mdns-address-lookup | 0.4.0 | MIT OR Apache-2.0 | [MIT](vendor/iroh-mdns-address-lookup/LICENSE-MIT), [Apache](vendor/iroh-mdns-address-lookup/LICENSE-APACHE) |
| noq-udp | 1.3.0 | MIT OR Apache-2.0 | [MIT](vendor/noq-udp/LICENSE-MIT), [Apache](vendor/noq-udp/LICENSE-APACHE) |
| swarm-discovery | 0.6.3 | Apache-2.0 | [Apache](vendor/swarm-discovery/LICENSE.Apache_2.0) |

## Installed dependencies

JavaScript, Rust and Android dependencies are recorded in their package manifests and lockfiles and retain their respective licenses. Inter is supplied by `@fontsource-variable/inter` under the SIL Open Font License. Electron and application bundles include additional third-party components; preserve the notices distributed with them.

This inventory of vendored code is not a complete license inventory for compiled distributions. Review the exact dependency versions and bundled notices for each release target before redistribution.
