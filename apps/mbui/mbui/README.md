# mbui — a MoonBit UI framework

mbui is a cross-platform UI framework written in MoonBit: one core that
builds, lays out and paints a tree every frame and draws everything itself on
the GPU, and thin hosts that put it on the screen and feed it input — macOS
and iOS (Metal), Windows (Direct3D 11), Android and Linux (OpenGL ES), and a
WebGL2 host for tests and previews. Its flexbox passes Yoga's tests and its text
segmentation Unicode's own. [still.fail](https://still.fail)'s apps are
written in it: that app, its design system and pages, live in still.fail's
repository (`apps/mbui`, built by these scripts with `MBUI_APP_MOD`). It is
experimental: APIs change without notice.

## Running (on a Mac with MoonBit and Xcode)

```sh
scripts/mac.sh build && scripts/mac.sh run      # macOS window
scripts/mac.sh script ime                       # scripted IME run, snapshots in out/ime
MBUI_BENCH=1 _build/native/release/build/demo/demo.exe   # scroll bench
scripts/bench.sh                                # offscreen benchmark scenes
scripts/web.sh build && scripts/web.sh test     # browser build + Playwright run
scripts/ios.sh build && scripts/ios.sh run      # iOS simulator
scripts/textdiff.sh mac web android             # mbui's text against the platform's own drawing:
                                                # out/textdiff/<host>/report.html (scripts/test.sh runs mac web)
```

Every native build compiles the one C file moonc generates for an app split into
units, in parallel (`scripts/mbc`, a MoonBit program in `tools/mbc` that the
script builds when it is not; its splitter `tools/mbc/csplit.mbt`): the
Android and iOS builds take only moonc's C from moon (`mbc gen`, its compile
for macOS left out) and compile it with their own compiler (`mbc compile`);
the macOS and Windows builds give moon a `cc`/`cl.exe` of ours that passes every
command through but that one (`mbc shim`/`wrap`). `moonbit_init` (every
global's initial value, run once) is a unit of its own at `-O0` (`/Od`).
The split is stable: moonc's made-up names (locals,
anonymous functions, layouts' offsets) are named by what they are, a package's
functions are a unit (a big package's in pieces by source file), and each unit
has only the declarations it uses, so an object made of the same text is kept
and a change compiles only the units whose functions it changed.
`MBC_SPLIT=0` compiles the file whole; `mbc check` compares the global
symbols of the whole and the split build; `moon test` in `tools` tests the
splitter, `scripts/mbc_test.sh` programs built with it.

On Windows (Git Bash, MoonBit, MSVC from a Developer Command Prompt):

```sh
scripts/win.sh build && scripts/win.sh run      # Win32 window
scripts/win.sh script ime                       # scripted IME run, snapshots in out/ime
scripts/shots.sh windows                        # a screenshot to look at (goldens/windows.png, by hand)
```

CI (the repository's `.github/workflows/mbui-windows.yml`) builds it on `windows-latest` and runs the `ime` script;
no picture of the window is compared: what Direct3D draws is held to its references by `mbui-render-windows`.

On Linux (MoonBit, a C compiler, GTK 4.12 or later with its development files: Ubuntu 24.04's `libgtk-4-dev
libsoup-3.0-dev`):

```sh
scripts/linux.sh build && scripts/linux.sh run    # GTK 4 window (Wayland or X11; Xvfb's under xvfb-run)
scripts/linux.sh script ime                       # scripted IME run, snapshots in out/ime
```

CI (the repository's `.github/workflows/mbui-host-linux.yml`) builds kitdemo on `ubuntu-24.04` and runs the host's
contracts in Xvfb, drawn by Mesa's llvmpipe.

## Licence

MIT, Copyright (c) 2026 still.fail contributors: see `LICENSE`. Third-party
data, tests and code it carries keep their own licences
(`THIRD_PARTY_NOTICES.md`).
