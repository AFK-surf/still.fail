# Third-party notices

The root MIT license covers this project's original work. It does not replace licenses or copyright notices for third-party code and assets.

## Vendored Rust crates

These patched crates come from the corresponding crates.io releases. The iroh and iroh-mdns-address-lookup MIT/Apache license texts were restored from the upstream revisions recorded in those releases’ `.cargo_vcs_info.json` (`f2eb930dda3779c6d852b72f3712aacd6e573ab1` and `87fdd7ea1a902845695f8f685c1905f096b3d02d`). Preserve their license files when redistributing them; local changes are described in [vendor/README.md](vendor/README.md).

| Crate | Version | Upstream license | Included notices |
| --- | --- | --- | --- |
| iroh | 1.0.3 | MIT OR Apache-2.0; BSD-3-Clause for the separately attributed code | [MIT](https://github.com/zzj3720/iroh/blob/stillfail/LICENSE-MIT), [Apache](https://github.com/zzj3720/iroh/blob/stillfail/LICENSE-APACHE), [BSD](https://github.com/zzj3720/iroh/blob/stillfail/iroh/LICENSE-BSD3) |
| iroh-relay | 1.3.0 | MIT OR Apache-2.0; BSD-3-Clause for the separately attributed code | [MIT](https://github.com/zzj3720/iroh/blob/stillfail/LICENSE-MIT), [Apache](https://github.com/zzj3720/iroh/blob/stillfail/LICENSE-APACHE), [BSD](https://github.com/zzj3720/iroh/blob/stillfail/iroh-relay/LICENSE-BSD3) |
| iroh-mdns-address-lookup | 0.4.0 | MIT OR Apache-2.0 | [MIT](vendor/iroh-mdns-address-lookup/LICENSE-MIT), [Apache](vendor/iroh-mdns-address-lookup/LICENSE-APACHE) |
| noq-udp | 1.3.0 | MIT OR Apache-2.0 | [MIT](vendor/noq-udp/LICENSE-MIT), [Apache](vendor/noq-udp/LICENSE-APACHE) |
| swarm-discovery | 0.6.3 | Apache-2.0 | [Apache](vendor/swarm-discovery/LICENSE.Apache_2.0) |

## Vendored Swift sources

still.fail Helper (the station's macOS app) builds in the simulator capture and input of [serve-sim](https://github.com/EvanBacon/serve-sim) (Evan Bacon, `packages/serve-sim/Sources` at `0193e65c481fc9b64a62427f32fcf143dbc3d2c0`), under its [Apache-2.0 license](vendor/serve-sim/LICENSE); the files taken and the local changes are listed in [vendor/README.md](vendor/README.md). The station's `station/src/screens/sim-chrome.ts` is ported from serve-sim's `packages/serve-sim/src/devicekit-chrome.ts` and `device-displays.ts`, under the same license; the Apple artwork it reads stays on the Mac it is read on, in no repository or app.

## scrcpy's server in the station's release

The station puts [scrcpy](https://github.com/Genymobile/scrcpy)'s server, the unmodified `scrcpy-server-v5.0.1` of its release (Genymobile and contributors, Apache-2.0), on an Android device for as long as a person views it (`station/src/screens/scrcpy-server`, docs/remote-screens.md "Android").

## agent-desktop in the station's release

still.fail Helper (macOS) carries `agent-desktop` and `agent-desktop-macos-helper` beside its executable, and the Windows station `agent-desktop.exe` beside `stillfail-screen.exe`: the unmodified binaries of [agent-desktop](https://github.com/vercel-labs/agent-desktop) 1.0.2 (Vercel, Inc.) from its GitHub release, each archive checked against the SHA-256 in that release's `checksums.txt` (`AGENT_DESKTOP` in `scripts/native.ts`), under its [Apache-2.0 license](https://github.com/vercel-labs/agent-desktop/blob/v1.0.2/LICENSE). The station runs them to read and act on the desktop's apps by their accessibility trees.

## Model and runtime marks

The AI model and runtime logos (`web/public/models/`, `design/mobile/assets/`, the Android `maker_*` drawables, their copies in `apps/mbui/src/sf/drawable_data.mbt` and the marks drawn in `web/src/ui.tsx`) are adapted from [Simple Icons](https://github.com/simple-icons/simple-icons) (CC0-1.0) and [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT). The names and logos are trademarks of their respective owners; their use here identifies the services and does not imply endorsement.

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

## The apps (`apps/mbui`)

still.fail's apps (`apps/mbui`) are written in mbui (MIT, Copyright (c) 2026 still.fail contributors), which is in this repository at `apps/mbui/mbui`; its notices are its `THIRD_PARTY_NOTICES.md`. Its ThumbHash decoder (`apps/mbui/src/gallery/thumbhash.mbt`) is ported from [ThumbHash](https://github.com/evanw/thumbhash)'s reference implementation (MIT, Copyright (c) 2023 Evan Wallace), as `web/src/thumbhash.ts` has it. Its Android build fetches Hermes, JSI and fbjni (MIT, Meta Platforms) and AndroidX Media3 (Apache-2.0) from Maven Central. The pictures its photos and books apps show are drawn by mbui's `scripts/test_images.swift` (CC0 1.0); its `goldens/` are its own output over made-up data, drawn with the system's fonts.

## Installed dependencies

JavaScript, Rust and Android dependencies are recorded in their package manifests and lockfiles and retain their respective licenses. Inter is supplied by `@fontsource-variable/inter` under the SIL Open Font License. The Android app carries JetBrains Mono (Copyright 2020 The JetBrains Mono Project Authors) under the SIL Open Font License 1.1; the license text ships with it in `apps/android/app/src/main/assets/licenses/JetBrainsMono-OFL.txt`. Electron and application bundles include additional third-party components; preserve the notices distributed with them.

The core bundles [alien-signals](https://github.com/stackblitz/alien-signals) 3.2.1 under this license:

```
MIT License

Copyright (c) 2024-present Johnson Chu

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

This inventory of vendored code is not a complete license inventory for compiled distributions. Review the exact dependency versions and bundled notices for each release target before redistribution.
