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

## Model and runtime marks

The AI model and runtime logos (`web/public/models/`, `design/mobile/assets/`, the Android `maker_*` drawables and the marks drawn in `web/src/ui.tsx`) are adapted from [Simple Icons](https://github.com/simple-icons/simple-icons) (CC0-1.0) and [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT). The names and logos are trademarks of their respective owners; their use here identifies the services and does not imply endorsement.

LobeHub Icons is distributed under this notice:

```
MIT License

Copyright (c) 2023 LobeHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Installed dependencies

JavaScript, Rust and Android dependencies are recorded in their package manifests and lockfiles and retain their respective licenses. Inter is supplied by `@fontsource-variable/inter` under the SIL Open Font License. Electron and application bundles include additional third-party components; preserve the notices distributed with them.

This inventory of vendored code is not a complete license inventory for compiled distributions. Review the exact dependency versions and bundled notices for each release target before redistribution.
