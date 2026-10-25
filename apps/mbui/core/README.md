# The still.fail core in mbui's native hosts

The still.fail client core (`client/core-ts` of this repository) runs in Hermes on every native host, the same
engine, version and bytecode still.fail's Android app runs it in (React Native 0.81.4's Hermes; `core.hbc`), on the
same Rust shell (`client/shell`), behind a three-function C API the MoonBit host can call. The user decided it
(2026-10-19): one engine for the four native apps (the measurements behind it: Hermes starts the core 4–5× sooner than
Node in a quarter of the memory). Apple's systems ran it in JavaScriptCore until then.

```
src/host/core_api.h     mb_core_start / mb_core_send / mb_core_stop, the on_message callback
src/host/apple_core.mm  the engine on macOS and iOS (Objective-C++, ARC): Hermes and its JSI, the core's thread and
                        loop, __native, the shell, secure.* (the Keychain) and listen.*
src/host/apple_auth.m   a sign-in's browser page: ASWebAuthenticationSession (macOS and iOS)
src/host/android_core.c the engine on Android: still.fail's own, prebuilt (below)
core/hermes.ts          still.fail's entry: ember's hosts/hermes-start.ts, no app's modules
core/media-hermes.ts    the media app's entry (still.fail's core with the media module): what the apps ship
core/smoke.m            headless smoke test on macOS: accounts, auth.begin, stop
core/delta-vectors.ts   test vectors from core-ts's diff and apply -> src/core/vectors_test.mbt
src/core                mbui/core: the MoonBit client (subscriptions, deltas, calls, sign-in) and its C queue
src/coredemo            the core demo app (MBUI_CORE=1 scripts/mac.sh), src/stillfail still.fail itself
scripts/core.sh         deps | shell [TARGET] | hermes | hermes-apple | engine [TARGET] | apple [TARGET] | smoke | listen | …
```

The default `moon` build does not link the engine: only the apps with the core (src/coredemo, src/stillfail: their
`core_engine.m` includes src/sfcore/apple_engine.m, their `moon.pkg` links `out/core/<target>/libmbui_core.a`, the
shell's `.a` and Hermes's framework), built by `scripts/mac.sh`, which makes what they link first (`scripts/core.sh
apple`).

## Building and the smoke test (on Studio)

`scripts/core.sh` builds from the still.fail checkout it is in (`$EMBER`), with pnpm and rustup's cargo. Everything it
makes goes to `out/core/` (ignored); the shell's intermediate build goes to `$CARGO_TARGET_DIR` (`out/core-target`).

```sh
scripts/core.sh deps                 # pnpm install --frozen-lockfile in client/core-ts
scripts/core.sh hermes-apple         # Hermes for macOS and iOS, fetched once (out/core/hermes, a link into the cache)
scripts/core.sh engine [TARGET]      # out/core/<target>/libmbui_core.a: src/host/apple_core.mm (when it changed)
scripts/core.sh shell [TARGET]       # out/core/<target>/libstillfail_shell.a (+ shell-<target>.libs), built here by cargo
scripts/core.sh hermes               # out/core/core.hbc (ENTRY: core/hermes.ts, or core/media-hermes.ts)
scripts/core.sh apple [TARGET]       # all four for an app, each when missing or stale (the shell by its key; the media entry)
scripts/core.sh smoke                # out/core/smoke built and run twice against https://app.still.fail
scripts/core.sh listen               # listen.* with core/listen-test.js in the core's place
scripts/core.sh exit                 # exit() with the core in a task (core/exit_test.m, core/exit-test.js)
```

TARGET is aarch64-apple-darwin (the default), aarch64-apple-ios-sim or aarch64-apple-ios.

- **Hermes** (`hermes-apple`): React Native 0.81.4's Maven tarball `react-native-artifacts:0.81.4:hermes-ios-release`
  (21.3 MB, its sha256 pinned in core.sh), the release the Android app's `hermes-android:0.81.4` comes from: macOS's
  `Library/Frameworks/macosx/hermes.framework` (universal, arm64 4.7 MB; macOS 11 and later), iOS's
  `Library/Frameworks/universal/hermes.xcframework` (`ios-arm64`, `ios-arm64_x86_64-simulator`; iOS 15.1 and later)
  and the headers of Hermes and its JSI (`include`; the JSI is compiled into the framework). Fetched once into
  `~/Library/Caches/stillfail-build/hermes-apple-0.81.4`, which every worktree shares (as ember's
  `apps/android/build.py` keeps hermesc), never committed; `out/core/hermes` links to it.
- **The shell** is the crate's `cdylib` built as a static library (`cargo rustc --crate-type staticlib`), so ember's
  Cargo.toml is untouched. What it needs from the system (`-framework Security -framework CoreFoundation … -liconv`) is
  what rustc prints as `native-static-libs`, kept in `out/core/shell-<target>.libs`. `apple` takes it from
  still.fail's natives (scripts/native.ts `shell-apple`, by the shell's sources: built once by CI's natives job, else
  by native.ts here); `shell` builds it here (≈ 1 min with sccache, 4 without).
- **The bytecode** is Android's exactly (`hermes`: esbuild to ES2020, Babel's class transform, hermesc 0.81.4 `-O
  -block-scoping`), kept with a stamp of its inputs.
- **The engine** (`engine`): `src/host/apple_core.mm` compiled for the target (`-std=c++20 -fobjc-arc -fexceptions
  -frtti`) against the tarball's headers into `libmbui_core.a` (1-2 s). moon does not see it: `scripts/mac.sh` touches the
  app's `core_engine.m` when it is made again, so the app is linked again.
- The macOS apps find the framework where it is (`-rpath` to `out/core/hermes/…/macosx` from the executable, and
  `@executable_path/../Frameworks` for an app bundle); the iOS app carries it in `MBUI.app/Frameworks`.

The smoke test starts the core with a temporary data directory and cloud `https://app.still.fail`, sends
`{"id":1,"subscribe":{"topic":"accounts"}}`, then `{"id":2,"call":"auth.begin","params":{"redirect_uri":
"stillfail://auth/callback","return_to":"/"}}`, prints everything that comes back and the login URL (never opened),
stops the core and prints timings and the process's memory footprint.

## The engine (apple_core.mm)

- The app's engine (`apps/mbui/engine/engine.cpp`) as Apple's host has it, as `bench/hermes-host` is: one thread,
  `still.fail core`, with an 8 MB stack (the core's parsers recurse); a queue of tasks (`mb_core_send`, the shell's
  answers, the host's own) and the timers, under one lock and condition variable; after each task or timer the
  microtasks drained (`withMicrotaskQueue`). The runtime is `makeHermesRuntime` with the Android app's configuration
  (microtask queue, block scoping, Intl).
- Timers run on `CLOCK_MONOTONIC`, which on Apple's systems goes on while the machine sleeps (as Android's
  CLOCK_BOOTTIME): a 10 s wait begun before a sleep is over after it.
- In a run on a clock of its own (`@ui.own_clock()`: a settled screenshot run, Android's shot_at, the web's) the core's
  timers are on the app's clock instead (`core/clock.ts`, the entries' first import, the same on every engine): the
  app's `{"clock": ms}` runs what is due by then and is answered `{"clocked": ms, "next": due, "later": due}`, said
  again whenever either changes. `next` is what what is shown waits for (a retry, a request's time running out),
  `later` what it does not (setInterval's, core-ts's `laterSleep`: a keepalive, a shown clock's next second).
  The app tells it its clock before anything it sends too (what that sets off is timed from then). `src/core/
  clock.mbt` makes each a wait of the runtime's (`src/sfcore/clock.mbt` gives it the runtime: a fiber's sleep), so
  `at_rest` and `next_wake` see them, and awaits the core while it runs what is due; the core's `monotonic` and `now`
  are the app's clock then too. On a device none of
  this: the engine's timers, real time.
- `__native` is ember's `HermesNative` (hosts/hermes-globals.ts) as it is, plus `os`; the engine starts the core with
  `__stillfail.start(cloudOrigin, beta, os)` (`macos`, `ios`; hosts/engine.ts takes the third over hermes-start.ts's
  `android`). Bytes are ArrayBuffers both ways: `call(id, op, json, ArrayBuffer?)`, `emitBytes(client, json,
  ArrayBuffer)`, `__stillfail.receiveBytes(client, json, ArrayBuffer)`, `complete(id, json, error, ArrayBuffer?)`,
  `random(n)`.
- The shell's answers come on tokio's threads; they go through a `Gate` (as engine.cpp's) closed by `mb_core_stop`, so
  an answer arriving after a stop is dropped instead of touching a dead core.
- `exit()` (a host's `mb_host_exit`, AppKit's as the app quits) stops the core before anything is destroyed: its
  statics' destructors (the core's mutex and queues, Hermes's) run after what atexit was given, and the first
  `mb_core_start` gives it `mb_core_stop`. A core thread left in a task had locked a destroyed mutex or read freed
  memory, and macOS reported the app as crashed (`scripts/core.sh exit` holds it).
- `secure.*` and `listen.*` are the app's, not the shell's (on Android too): answered here (the Keychain, below;
  apple_listen.m, under Login). A `user` value (a vault's box key) and `secure.ask` take the person: LocalAuthentication's
  device owner prompt (Touch ID, Face ID or the device's password, the core's `reason` in it), on a queue of its own so
  the core goes on while they answer; the Keychain item is a `user` one's own account, given once they said yes. The
  prompt is a gate, not the Keychain's access control (the data protection keychain's, which on macOS takes an
  entitlement a Developer ID app has only with a provisioning profile). A device with no password: `no_device_lock`.
- An exception that escapes to the engine, or the core's own `fatal`, sends `{"fatal": reason}` once; the host then
  stops this core and starts another (as Android does).
- `on_message` runs on the core thread. The MoonBit host copies and hops to its UI thread (core_native.c), and must
  not wait on the UI thread for the core while the core waits for it.
- `MBUI_SECURE_TEST=1` (src/coredemo) round-trips `secure.set`, `get` (and `get` as the person's: none, nobody asked),
  `delete` and `get` again through the engine's own Keychain code and logs `SECURE_TEST …`, as Android's CoreHost does.
- `MB_CORE_TRACE=1` prints every operation and its answer, `MB_CORE_DEBUG=1` the core's debug log; the start says
  what it took (`[core] Hermes: shell … ms, script … ms (… bytes), start … ms`).
- Not yet: Hermes's sampling profiler (Android's `HermesNative.profile`), a debugger (the release framework has none;
  the `hermes-ios-debug` tarball has CDP), a `reset` on wake (the shell's `resetConnections`).

## Measurements

`scripts/core.sh smoke` on Studio (M2 Max, macOS 26.4), 2026-10-19, two runs on one data directory, against
JavaScriptCore's before it (same machine, ember dda655bbf):

| | Hermes 0.81.4 (`core.hbc`) | JavaScriptCore (`core.js`, before) |
|---|---|---|
| the script | 3,605,259 bytes of bytecode (the media entry) | 2,140,827 bytes of JS |
| cold start to first message | **23–24 ms**: shell 2–3 ms, script 10 ms, `start` + `connect` 0.3 ms | 105–124 ms (first run), 68–76 ms (again) |
| `auth.begin` → URL | 6–12 ms (made locally, with PKCE) | 6–10 ms |
| memory | phys_footprint 1.9 MB before start → **21 MB** running; peak 22 MB; max RSS 33 MB | 26–30 MB running; peak 34 MB; max RSS 55–59 MB |
| stop | 0.8–0.9 ms | 2–18 ms |
| what the engine adds | `libmbui_core.a` 155 KB; `hermes.framework` 4.7 MB (arm64) | the system's |

`libstillfail_shell.a` (aarch64-apple-darwin) is a 66.4 MB archive (57.2 MB `strip -S -x`); linked with `-dead_strip`
into the smoke test it adds about 15 MB stripped.

## mbui/core (src/core)

The MoonBit side, independent of `mbui/ui`:

- `core_native.c`: `on_message` (core thread) posts each message to mbui's queue on the channel `core` (`mb_post`,
  mbui's src/host/post.h), whose first post since a frame took the last asks the host for a frame; as that frame
  begins mbui takes all that came and hands each, in order, to the app's handler (`@ui.on_message("core",
  @core.receive)`, given by `@sfcore.start`), and keeps it on the run's tape (MBUI_DRAW_LOG=1: `MSG` lines, given
  again by `Tester::replay_frames`). A Tester posts the core's answers itself (`Tester::post`). The engine is handed over by the
  app that links it (`core_client.h`: `mbc_use`, from a constructor), so `mbui/core` builds and tests without it.
- `client.mbt`: subscriptions by topic and params (the same `Sub` each time, so a view can ask every frame), each with
  its current value, error and a `version` bumped per message; calls with an `on_done`; `{fatal}` fails the calls in
  flight, and the core is started again (at most 3 times a minute) with every subscription asked again.
- `delta.mbt`: deltas applied as core-ts's `applyKeyed` (collections.ts): `set`/`append`/`remove`, and the keyed
  `put`/`patch`/`drop`/`move` a `keyed: true` subscription gets; only what is along a path is copied.
  `vectors_test.mbt` holds it to core-ts's own results (`scripts/core.sh vectors`).
- `sign_in(on_done)`: `auth.begin`, the browser session (apple_auth.m), `auth.complete {query}`.

```moonbit
@ui.on_message("core", @core.receive)             // what the core says, handed on as each frame begins
@core.start() |> ignore                            // data: $MBUI_CORE_DATA, else Application Support/<bundle id|mbui>/core
fn view(c : @ui.Ctx) {
  let accounts = @core.subscribe("accounts")       // .value : Json?, .error : Json?, .version : Int
  match accounts.value { Some(Array(list)) => ..., _ => ... }
  if c.button("登录") { @core.sign_in(fn(r) { ... }) }
}
```

Still to do: a macOS app bundle (`Contents/Resources/core.hbc`, `Contents/Frameworks/hermes.framework`; today
`MB_CORE_BUNDLE`, which `scripts/mac.sh` sets), a call's progress values.

## iOS

`APP=stillfail scripts/ios.sh build | run` (or `APP=coredemo`): mbui's scripts/ios.sh on this module's app, with
`scripts/ios-core.sh` as its hook, on a simulator of its own (`MBUI_IOS_DEVICE`, default `ios-mbui-sf`):

- The same `apple_core.mm` (it names the OS `ios` under `TARGET_OS_IPHONE`), built for the simulator (`scripts/core.sh
  apple aarch64-apple-ios-sim`: the engine, the shell built for aarch64-apple-ios-sim, `core.hbc`; the device's target
  is aarch64-apple-ios), linked with Hermes's xcframework slice, the app's `core_engine.m` (src/sfcore/apple_engine.m)
  and `src/core/core_native.c`. The app carries `core.hbc` and `Frameworks/hermes.framework` (React Native 0.81.4's,
  the simulator's slice; `@executable_path/Frameworks`), signed ad hoc.
- `secure.*`: the Keychain (`kSecClassGenericPassword`, `AfterFirstUnlockThisDeviceOnly`) and Face ID or the passcode
  for a `user` one, as on macOS (`NSFaceIDUsageDescription` in ios/Info.plist); no file stand-in (MBUI_KEYS_IN_FILES is a
  macOS development build's).
- Sign-in: ASWebAuthenticationSession (`apple_auth.m`) with the `stillfail` scheme, as on macOS: the cloud's callback
  comes back to the session's handler, nothing registered.
- The core's files: `Library/Application Support/<bundle id>/core` in the app's container (`MBUI_CORE_DATA` elsewhere:
  the e2e gives it a path of the Mac's, which a simulator's app reads and writes as it is).
- `ENV="K=V;…" scripts/ios.sh run` gives the app its environment (simctl's `SIMCTL_CHILD_*`); its log (stderr: the
  host's lines, the core's) is `out/ios/app.log`.

What differs from macOS:
- Hermes runs bytecode, so there is no JIT to miss on iOS (JavaScriptCore would have run without one there).
- Lifecycle: a suspended app's timers and sockets stop. On becoming active again, the core's cloud socket notices on
  its own ping; a `mb_core_reset` sending the shell's `reset` (BridgeHost.resetConnections) would make it immediate.
- Not yet: pushes (APNs), a share extension (sharing in), a signed build for a device or TestFlight (docs/stillfail-port.md,
  "iOS").

## Android

Built (`APP=coredemo scripts/android.sh build`): the core runs in the app's engine, the one Windows' app runs too.

- **Engine**: `apps/mbui/engine/engine.cpp` (its C API `engine.h`), prebuilt for Android with the NDK's CMake
  (`apps/mbui/engine/android`; `node scripts/native.ts path engine android-arm64` in the ember checkout:
  `libstillfail_hermes.so`, `libjsi.so`, `libc++_shared.so`), on the shell `libstillfail_shell.so` (`... path shell
  android-arm64`). Hermes itself (`libhermes.so`, and its headers for the engine's build) and `libfbjni.so` come from
  React Native 0.81.4's `hermes-android` and fbjni 0.7.0's AARs (Gradle's cache, else Maven Central). All go into
  `out/android/apk/jniLibs`, which Gradle packs; nothing is committed. (Until 2026-10-23 the engine was still.fail's
  Kotlin app's, JNI and all, built in its tree: that app is frozen, and nothing here reads it.)
- **Script**: `scripts/core.sh hermes` makes `out/core/core.hbc` as ember's `hermes-bundle.ts` does (esbuild, Babel's
  class transform, hermesc 0.81.4 to bytecode) from `core/hermes.ts` (still.fail alone) or, for coredemo by default,
  `core/media-hermes.ts` (with the media module). It goes into the APK's assets.
- **Host** (`src/host/android_core.c`, included by `src/coredemo/android_engine.c`): starts the engine through its C
  API (`sf_engine_start`, os `android`); what the core says (a message, or one with bytes) comes back on the core's
  thread straight through core_native.c into mbui's queue (`mb_post`), which asks for the frame that takes it, and
  the calls only the app does go to a `dev.mbui.CoreHost` (android/), which answers through `sf_engine_complete`.
  Timers are the engine's (CLOCK_BOOTTIME on Android).
- **`secure.*`**: CoreHost seals each value with AES-GCM under one Android Keystore key (alias
  `dev.mbui.core.secure`), a file per value in `<files>/core/secure`, the value's name as associated data.
  `user: true` and `secure.ask`: the person asked (BiometricPrompt, biometrics or the screen lock; CoreHost's
  `secureUser`). `MBUI_SECURE_TEST=1` makes coredemo round-trip
  `secure.set`, `secure.get` (the same bytes back, sealed on disk), `secure.delete` and `secure.get` again (`{none}`)
  through CoreHost's own answers and log `SECURE_TEST …`.
- **`listen.*`**: `dev.mbui.Loopback` (android/), the twin of apple_listen.m and of ember's Loopback.kt: a
  `ServerSocket` on 127.0.0.1 or ::1 (port 0: the system's pick), each request read whole (64 KB head, 1 MB body,
  15 s), answered once, its connection closed. CoreHost answers `listen.open {port, host}` → `{id, port}` (an error
  such as `BindException: … (Address already in use)`), `listen.next` → `{request, method, path, headers}` + body or
  `{end: true}` (a waiting one is answered as a request comes, never blocking a thread), `listen.respond`,
  `listen.close`; a core's listeners close with it. While any listener is open, `dev.mbui.LoginService` (a
  `specialUse` foreground service, as ember's LoginRelay.kt) holds the process up so the cached apps freezer does not
  stop it answering the browser. `scripts/android.sh listen-test` runs it with core/listen-test.js in the core's place
  (a POST from the emulator's shell; then build again without it).
- **Sign-in**: no browser session on Android, macOS and Windows (`@core.has_browser_session()` false), so 登录 signs in on
  `@hostapi.browser_login` (`dev.mbui.BrowserLogin`): `auth.begin` with `http://127.0.0.1:<port>/oauth/callback`, the
  page in a Custom Tab (the Custom Tabs protocol's own intent extras, no androidx) on the app's task, the one GET to
  that path under that host taken and answered, then the app brought back in front (MainActivity is `singleTask`, as
  still.fail's; starting it again closes the tab above it; the page also links `dev.mbui.demo://back`), and
  `auth.complete {query}`. `MB_CORE_TRACE=1` logs what the core says and the app's calls.
- **Data**: `<the app's files>/core` (`/data/user/0/dev.mbui.demo/files/core`).
- **Environment**: `ENV="MBUI_AUTH_BEGIN=1;K=V" APP=coredemo scripts/android.sh run` passes the intent's `env` extra,
  which MainActivity sets with `Os.setenv` before the app's MoonBit starts.
- The moon build of the Android copy still links a macOS program, which nothing runs: android.sh links the copy's
  coredemo with `-undefined dynamic_lookup` instead of the Apple shell, so it needs no `scripts/core.sh shell`.

## Windows

Built (`apps/mbui/scripts/win.sh build`, Git Bash with MSVC's environment and MoonBit; CI: mbui.yml's `windows` job on
GitHub's Windows): the core in Hermes 0.81.4, in-process, on the Rust shell, as on Android (the decision and its
measurements: core-engine-pc.md of the session that made it; Hermes starts 4–5× sooner than Node in a quarter of the
memory).

- **Engine**: `apps/mbui/engine` (engine.cpp, Android's engine.cpp without JNI, behind a C API, engine.h), built with
  clang-cl in Hermes's own CMake tree from facebook/hermes at the tag React Native 0.81.4's Hermes is (MSVC fails on
  Hermes at that tag), Hermes static in `stillfail_engine.dll`; the shell `stillfail_shell.dll` (client/shell for
  `x86_64-pc-windows-msvc`). Both are this repository's native parts (`node scripts/native.ts fetch engine|shell
  win32-x64`), prebuilt on a Mac (Studio: `node scripts/native.ts prebuild`, cross-built with cargo-xwin and clang-cl
  on xwin's SDK) into the releases bucket by their keys; CI only fetches them, nothing is committed. win.sh puts them
  and `core.hbc` beside the app's .exe.
- **Script**: `scripts/core.sh hermes` with the engine's own hermesc (`hermesc.exe` in the engine part).
- **Host** (`src/host/win_core.c`, included by `src/sfcore/win_engine.c`, which mbui's win.sh puts in place of the
  app's Apple stub): `mb_core_start` hands the engine the bytecode, the data directory and the host's calls; what the
  core says goes through core_native.c into mbui's queue (`mb_post`), which asks for the frame that takes it.
- **`secure.*`**: sealed with DPAPI for the Windows user (CryptProtectData, never a prompt), a file per value in
  `<data>\secure` (a `user` one's with `.user` after it). Nothing asks the person yet (Windows Hello): `secure.ask` says
  yes at once and a `user` value is as safe as the Windows login, as with the Electron app. `MBUI_SECURE_TEST=1` round-trips
  it once as the core starts (`SECURE_TEST …` on stderr).
- **`listen.*`** and **sign-in**: on mbui's win_listen.c (Winsock); the app signs in on `@hostapi.browser_login`
  (win_browser_login.c: `$BROWSER`, else the system's browser), the CLI's loopback redirect, as on Android.
- **Data**: `%LOCALAPPDATA%\fail.still.mbui\core` (`MBUI_CORE_DATA` instead).
- **End to end**: `apps/mbui/e2e/win.sh` signs the app in against a local cloud (cloud/test/dev.ts) through
  `e2e/win/browser.cmd`, a browser standing in for the person (Google's page answered by the dev cloud's
  `/__dev/google`), then starts it again on its files. No station there yet: Home has no chat.
- Not yet: packaging (an installer), code signing, updates, Windows Hello for `secure.ask`, arm64.

## Login

`auth.begin {redirect_uri, return_to, device_name?}` answers `{url}`: still.fail cloud's login page (Google), with
PKCE (the smoke test prints one). The person signs in in a browser; the cloud sends the browser to `redirect_uri`
with a query, and the app finishes with `auth.complete {query}` (the callback URL's query string), as the web and the
desktop app do (ember docs/client-core.md, "Sign-in"). The cloud accepts exactly `stillfail://auth/callback`,
`stillfail-beta://auth/callback`, `ember://auth/callback` and loopback `http://127.0.0.1:<port>/oauth/callback`
(cloud/src/auth.ts `APP_REDIRECTS`, `validRedirect`). Two ways back:

- **Custom scheme** (`stillfail://auth/callback`, what the smoke test asks for). Needs nothing from the core, only
  the host: open the URL and catch the callback. On iOS `ASWebAuthenticationSession(url:,
  callbackURLScheme: "stillfail")` does both (no `CFBundleURLTypes` registration needed, the callback URL comes back
  to its completion handler; on macOS it is Safari's whatever the default browser, so the Mac signs in on the loopback
  below, in the default browser, as the desktop app does); otherwise register the scheme (`CFBundleURLTypes`; on macOS handle `kAEGetURL`, on iOS
  `application:openURL:`). Then `mb_core_send({"id":…,"call":"auth.complete","params":{"query":"<query>"}})`.
  Built: `src/host/apple_auth.m` and `@core.sign_in`; `MBUI_AUTH_DRY=1` makes the session but does not start it (no one
  has signed in through it yet: a real sign-in is the person's to do). Caveat: another installed still.fail app
  (Studio has one) also owns `stillfail://`; ASWebAuthenticationSession avoids that clash, a registered scheme does not.
- **Loopback** (`http://127.0.0.1:<port>/oauth/callback`, what command-line tools do). Nothing of it is
  still.fail's: mbui/hostapi's `browser_login` (browser_login.mbt, `src/host/apple_browser_login.m`) listens on
  127.0.0.1 at a port the system picks, gives the app the address to come back to, opens the app's login page with
  `$BROWSER`, else `open` (the system on iOS), and gives back the address the browser came back to, any app, any
  service (on Android: `dev.mbui.BrowserLogin`, above). The listener is `src/host/apple_listen.m` (`listen_api.h`: BSD sockets on a dispatch source, a request
  read whole, answered once, its connection closed). The core demo's login command is still.fail's sign-in on it:
  `scripts/mac.sh login` (MBUI_AUTH_LOGIN=1) asks `auth.begin` with that address, `auth.complete`s what comes back,
  and exits 0 once signed in (1 when not). An app like that is what a station's remote login (ember
  docs/remote-login.md) can run as its command: it takes the page from `BROWSER`, sees the loopback `redirect_uri`
  and its `state`, and the person's phone (the still.fail Android or desktop app) listens on that port there and
  relays the browser's way back to this process, after checking with `lsof` that the port is this command's.
  `scripts/core.sh login-test` runs it up to the person's step, with curl as the browser coming back.

The core's own `listen.*` (`listen.open/next/respond/close`, ember client/core-ts hosts/bridge.ts) is the other way
round: this device taking a station's login callback for it (`canRelay`; machine logins on the station page and in
login cards). apple_core.mm answers it on the same listener, as Android's Loopback.kt does there; `scripts/core.sh
listen` tests it with core/listen-test.js in the core's place (`scripts/android.sh listen-test` on Android's).

`secure.*` is answered here too (the Keychain, and LocalAuthentication's prompt for a `user` value and `secure.ask`:
above).
