# still.fail mbui

still.fail's Android app (and its macOS build) written in [mbui](https://github.com/zzj3720/mbui), the MoonBit UI
framework: an app of its own, **still.fail mbui** (`fail.still.mbui`, the debug build `fail.still.mbui.debug`),
installable beside still.fail's apps. The plan and what is done: `docs/stillfail-port.md`.

mbui is the framework (layout, text, the UI tree, motion, Markdown, the platform hosts, the build's C step) and stays
in its own repository; what knows still.fail is here: its design system (`src/sf`), its pages (`src/sfapp`), the core
client and its engine hosts (`src/core`, `src/sfcore`, `src/host/*_core.*`), the apps (`src/stillfail`, `src/sffix`
over made-up data, `src/sfkit`, `src/coredemo`), the media screens (`src/gallery`, `src/shelf`, `src/videos`, with
`src/photos` and `src/books` over made-up data, and the player, `src/player`), the core's bundling (`core/`, from this repository's
`client/core-ts`), the end-to-end flows against a local still.fail (`e2e/`), the goldens, and the Android project
(`android/`: mbui's host Java with `CoreHost.java`).

`src/player` (the full-screen player and the audio viewer) knows nothing of still.fail's core, but draws with its design
system (`@sf` icons, theme, spinner): it could go back to mbui as framework once it takes those from its caller.

## mbui, pinned

`mbui.rev` is the mbui commit this builds with. `scripts/mbui.sh` makes `apps/mbui/mbui` a link to a copy of it (kept
in `~/Library/Caches/stillfail-mbui`, shared by every worktree); `moon.work` names it a member beside this module, whose
`moon.mod` imports `mbui`. `MBUI=<a checkout of mbui>` links that one instead (a change to both at once); `scripts/mbui.sh
bump [REF]` moves the pin to mbui's `main` (or REF). Every script here runs `mbui.sh` first.

## Building

```sh
apps/mbui/scripts/check.sh                          # moon check, js and native
apps/mbui/scripts/test.sh                           # the design system's, the pages' and the core client's tests
APP=sffix apps/mbui/scripts/mac.sh build            # macOS: sffix (Home over made-up chats), sfkit, stillfail, coredemo…
APP=sffix apps/mbui/scripts/web.sh build            # the browser build (tests and previews only)
apps/mbui/scripts/shots.sh home web-home            # screenshots against goldens/ (UPDATE=1 accepts them)
apps/mbui/scripts/android.sh build                  # the Android app, debug (APP=stillfail); VARIANT=release the beta
apps/mbui/scripts/e2e-local.sh all                  # the end-to-end flows against a local still.fail (e2e/)
```

These are mbui's own scripts (`mbui/scripts/`) building this module (`MBUI_APP_MOD`), with what still.fail adds:
the core's engine and bytecode for Android (`scripts/android-core.sh`), its shell and script on macOS
(`scripts/core.sh`).

## The beta

Every push to main that changes what the app is built from (this directory, `client/`, `media/`, the native parts) is
built, signed with every still.fail Android release's key and put out by `.github/workflows/mbui.yml` on mini1
(`scripts/beta.sh`), its feed `android/mbui/latest.json` (still.fail's `AppRelease`):

https://app.still.fail/releases/latest/android-mbui
