# still.fail's apps

still.fail's apps for Android, iOS, macOS, Windows and Linux, one app on every device,
written in mbui (`libs/mbui`), the MoonBit UI framework. The released apps are built from here: the Android app since
2026-10-24, the Mac and Windows apps since 2026-10-26, each in the place of the one before it (its ids, its data and
sign-in kept).

mbui is the framework (layout, text, the UI tree, motion, Markdown, the platform hosts, the build's C step), at
`libs/mbui` (zzj3720/mbui merged in with its history, 2026-10-21): a change to the framework and the app is one
pull request, checked by one run. `moon.work` names it a member beside this module, whose `moon.mod` imports `mbui`;
`scripts/mbui.sh` says where it is.

What knows still.fail is the rest of this directory: its component library (`src/sf`, sf/styles.mbt), its pages and
frames (`src/sfpages`, `src/sfdesk`, `src/sfapp`, over the model in `src/sfbase`), the core client and its engine
hosts (`src/core`, `src/sfcore`, `src/host/*_core.*`), the apps (`src/stillfail`; `src/sffix` over made-up data,
`src/sfkit`, `src/coredemo`), a photo's ThumbHash picture (`src/gallery`), the core's bundling (`core/`, from
this repository's `client/core-ts`), the end-to-end flows against a local still.fail (`e2e/`, scripts/e2e-local.sh), and
the platforms' projects (`android/`, `ios/`, `windows/`, `linux/`).

## Which app is built

The same code is built as each of still.fail's apps, by its variant (`MBUI_VARIANT`; Android's `android/apk.json`):

| variant | Android | macOS, Windows | feed | built |
|---|---|---|---|---|
| `stable` | still.fail, `fail.still.android` | still.fail, `fail.still.desktop` | `android`, `mac`, `win` | `scripts/release.sh` (stable.yml) |
| `beta` | youdid.wtf, `fail.still.android.beta` | youdid.wtf, `fail.still.desktop.beta` | `android/beta`, `mac/beta`, `win/beta` | `scripts/release.sh --beta` (pipeline.yml, main once checked) |
| `preview` (Android's `release`) | still.fail preview, `fail.still.mbui` (not built in CI since 2026-11-03) | still.fail preview, `fail.still.mbui` (Windows, Linux; the Mac's not built in CI since 2026-11-03) | `win/mbui`, `linux/mbui` | `.github/workflows/preview.yml`, every push to main that changes it |
| `debug` | still.fail dev, `fail.still.android.dev` | | none | `scripts/android.sh build` |

`preview` is the build of every push to main, out in minutes, an app beside the released ones to try a change on
before it is checked (https://app.still.fail/releases/latest/win-mbui, `linux-mbui`, `linux-arm64-mbui`); on Android
and the Mac the beta is the channel for that. Its feeds and id keep the name mbui: installed preview apps update by
them. iOS: `scripts/ios.sh`, TestFlight by hand (.github/workflows/mbui-testflight.yml in the
repository's docs).

## Building

```sh
apps/mbui/scripts/check.sh                          # moon check, js and native
apps/mbui/scripts/test.sh                           # the library's, the pages' and the core client's tests
APP=sffix apps/mbui/scripts/mac.sh build            # macOS: sffix (Home over made-up chats), sfkit, stillfail, coredemo…
apps/mbui/scripts/web-app.sh                        # the web's build of the app (web/mbui.html)
apps/mbui/scripts/shots.sh home web-home            # screenshots to look at, in out/shots (no references)
apps/mbui/scripts/android.sh build                  # the Android app, debug (APP=stillfail); VARIANT=release the mbui one
apps/mbui/scripts/e2e-local.sh all                  # the end-to-end flows against a local still.fail (e2e/)
apps/mbui/scripts/win.sh build                      # Windows (Git Bash, MSVC): APP=stillfail, the core in Hermes (engine/)
apps/mbui/e2e/win.sh                                # Windows: signed in against a local cloud, then Home (CI: preview.yml)
```

These are mbui's own scripts (`libs/mbui/scripts/`) building this module (`MBUI_APP_MOD`), with what still.fail adds:
the core in Hermes, the same `core.hbc` on every platform: on Android and Windows still.fail's prebuilt engine
(`scripts/android-core.sh`, `engine/`), on Apple's `src/host/apple_core.mm` with React Native 0.81.4's Hermes
framework and the Rust shell (`scripts/core.sh apple`).

## The macOS app

`scripts/mac-app.sh` makes `out/mac/<name>.app` (arm64) as its variant says: the release build of `APP=stillfail`,
the core's script in its Resources (the core host finds it there), its icon (`scripts/mac-icon.swift`: the Android
icon on macOS's rounded square), an Info.plist of its own; then signs, checks and zips it. In CI it is signed with
still.fail's macOS identity (`.github/mac_signing.py`): AFK's Developer ID, the hardened runtime, notarized before it
is zipped (the ticket not stapled: Gatekeeper checks it online), so it opens downloaded from the web. As a bundle it has the system's
notifications (mbui's mac host: UNUserNotificationCenter), its own Keychain items and data
(`~/Library/Application Support/<its id>`).
