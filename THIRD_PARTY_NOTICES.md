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

## Vendored Java sources

The Android app builds in [JZlib](https://github.com/ymnk/jzlib) 1.1.3 (Copyright (c) 2000-2011 ymnk, JCraft, Inc.; based on zlib by Jean-loup Gailly and Mark Adler), unmodified, under its [BSD-style license](libs/mbui/android/jzlib/LICENSE); where it came from is in [libs/mbui/android/jzlib/README.md](libs/mbui/android/jzlib/README.md).

## scrcpy's server in the station's release

The station puts [scrcpy](https://github.com/Genymobile/scrcpy)'s server, the unmodified `scrcpy-server-v5.0.1` of its release (Genymobile and contributors, Apache-2.0), on an Android device for as long as a person views it (`station/src/screens/scrcpy-server`).

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

still.fail's apps (`apps/mbui`) are written in mbui (MIT, Copyright (c) 2026 still.fail contributors), which is in this repository at `libs/mbui`; its notices are its `THIRD_PARTY_NOTICES.md`. Its ThumbHash decoder (`apps/mbui/src/gallery/thumbhash.mbt`) is ported from [ThumbHash](https://github.com/evanw/thumbhash)'s reference implementation (MIT, Copyright (c) 2023 Evan Wallace). Its Android build fetches Hermes, JSI and fbjni (MIT, Meta Platforms) and AndroidX Media3 (Apache-2.0) from Maven Central. The pictures its photos and books apps show are drawn by mbui's `scripts/test_images.swift` (CC0 1.0); its `goldens/` are its own output over made-up data, drawn with the system's fonts.

## Installed dependencies

JavaScript, Rust and Android dependencies are recorded in their package manifests and lockfiles and retain their respective licenses. Inter is supplied by `@fontsource-variable/inter` under the SIL Open Font License. The apps carry JetBrains Mono (`apps/mbui/assets/fonts/jetbrains_mono.ttf`, Copyright 2020 The JetBrains Mono Project Authors) under the SIL Open Font License 1.1, whose text is below. Electron and application bundles include additional third-party components; preserve the notices distributed with them.

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

## JetBrains Mono's license

```text
Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono)

This Font Software is licensed under the SIL Open Font License, Version 1.1.
This license is copied below, and is also available with a FAQ at:
https://openfontlicense.org


-----------------------------------------------------------
SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007
-----------------------------------------------------------

PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded, 
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```
