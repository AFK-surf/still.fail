# still.fail mbui

still.fail's Android app (and its macOS and Windows builds: a phone's pages in a narrow window, the web app's wide frame
in a desktop's, docs/stillfail-port.md "The PC (wide) frame") written in mbui (`mbui/`), the MoonBit UI
framework: an app of its own, **still.fail mbui** (`fail.still.mbui`, the debug build `fail.still.mbui.debug`),
installable beside still.fail's apps. The plan and what is done: `docs/stillfail-port.md`.

mbui is the framework (layout, text, the UI tree, motion, Markdown, the platform hosts, the build's C step) and stays
in its own repository; what knows still.fail is here: its design system (`src/sf`), its pages (`src/sfapp`), the core
client and its engine hosts (`src/core`, `src/sfcore`, `src/host/*_core.*`), the apps (`src/stillfail`, `src/sffix`
over made-up data, `src/sfkit`, `src/coredemo`), the media screens (`src/gallery`, `src/shelf`, `src/videos`, with
`src/photos` and `src/books` over made-up data, and the player, `src/player`), the core's bundling (`core/`, from this repository's
`client/core-ts`), the end-to-end flows against a local still.fail (`e2e/`), and the Android project
(`android/`: mbui's host Java with `CoreHost.java`).

`src/player` (the full-screen player and the audio viewer) knows nothing of still.fail's core, but draws with its design
system (`@sf` icons, theme, spinner): it could go back to mbui as framework once it takes those from its caller.

## mbui, here

mbui is in this repository, at `apps/mbui/mbui` (zzj3720/mbui merged in with its history, 2026-10-21): a change to
the framework and the app is one pull request, checked by one run. `moon.work` names it a member beside this module,
whose `moon.mod` imports `mbui`; `scripts/mbui.sh` says where it is.

## Building

```sh
apps/mbui/scripts/check.sh                          # moon check, js and native
apps/mbui/scripts/test.sh                           # the design system's, the pages' and the core client's tests
APP=sffix apps/mbui/scripts/mac.sh build            # macOS: sffix (Home over made-up chats), sfkit, stillfail, coredemo…
APP=sffix apps/mbui/scripts/web.sh build            # the browser build (tests and previews only)
apps/mbui/scripts/shots.sh home web-home            # screenshots to look at, in out/shots (no references)
apps/mbui/scripts/android.sh build                  # the Android app, debug (APP=stillfail); VARIANT=release the beta
apps/mbui/scripts/e2e-local.sh all                  # the end-to-end flows against a local still.fail (e2e/)
apps/mbui/scripts/win.sh build                      # Windows (Git Bash, MSVC): APP=stillfail, the core in Hermes (engine/)
apps/mbui/e2e/win.sh                                # Windows: signed in against a local cloud, then Home (CI: mbui.yml)
```

These are mbui's own scripts (`mbui/scripts/`) building this module (`MBUI_APP_MOD`), with what still.fail adds:
the core in Hermes, the same `core.hbc` on both: on Android still.fail's prebuilt engine (`scripts/android-core.sh`),
on macOS `src/host/apple_core.mm` with React Native 0.81.4's Hermes framework and the Rust shell (`scripts/core.sh apple`).

## The macOS app

`scripts/mac-app.sh` makes `out/mac/still.fail mbui.app` (`fail.still.mbui`, arm64 as still.fail's desktop app): the
release build of `APP=stillfail`, the core's script in its Resources (the core host finds it there), its icon
(`scripts/mac-icon.swift`: the Android icon on macOS's rounded square), an Info.plist of its own; then signs, checks
and zips it (`out/mac/stillfail-mbui-<n>-arm64-mac.zip`). In CI it is signed with still.fail's macOS identity as its
desktop app is (`.github/mac_signing.py`): with AFK's Developer ID it is also notarized and stapled before it is
zipped, so Gatekeeper opens it downloaded from the web. While the identity is still the Apple Development certificate
(apps/desktop/package.json `build.mac.identity`), it is not notarized and Gatekeeper refuses it on first open
(System Settings → Privacy & Security → Open Anyway once, or `xattr -dr com.apple.quarantine "still.fail mbui.app"`).
As a bundle it has the system's notifications (mbui's mac host: UNUserNotificationCenter), its own Keychain items
and data (`~/Library/Application Support/fail.still.mbui`).

## The beta

Every push to main that changes what the app is built from (this directory, `client/`, `media/`, the native parts) is
built, signed with every still.fail Android release's key and put out by `.github/workflows/mbui.yml` on mini1
(`scripts/beta.sh`), its feed `android/mbui/latest.json` (still.fail's `AppRelease`):

https://app.still.fail/releases/latest/android-mbui

and after it, on the same runner, the macOS app (`scripts/beta.sh mac`; feed `mac/mbui/latest.json`):

https://app.still.fail/releases/latest/mac-mbui

Measured (2026-10-19, mini1-6, push to main → the feed out): ~70 s with a fresh build directory and no Gradle daemon
(build 28.5 s, of it Gradle 17.5 s; the put and its check 9 s), ~38 s warm with nothing of the app changed (build
3.6 s, put and check 11 s); the rest is GitHub's: the run made (~7 s) and the job picked up (~6 s), the checkout.
