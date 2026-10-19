# The still.fail core in mbui's Apple hosts

The still.fail client core (`client/core-ts` of github.com/zzj3720/ember) runs in JavaScriptCore, on the same Rust
shell (`client/shell`) the Android app uses, behind a three-function C API the MoonBit host can call:

```
src/host/core_api.h    mb_core_start / mb_core_send / mb_core_stop, the on_message callback
src/host/apple_core.m  the engine (ObjC, ARC; macOS and iOS): JSContext, __native, timers, the shell
src/host/apple_auth.m  a sign-in's browser page: ASWebAuthenticationSession (macOS and iOS)
core/jsc-start.ts      hermes-globals' polyfills, JSC's case conversion, then ember's hosts/engine.ts startEngine
core/jsc.ts            still.fail's entry: startJsc([]) (an app's own entry passes its modules)
core/jsc-pre.ts        keeps JSC's own toLowerCase/toUpperCase (hermes-globals replaces them for Hermes)
core/smoke.m           headless smoke test: accounts, auth.begin, stop
core/delta-vectors.ts  test vectors from core-ts's diff and apply -> src/core/vectors_test.mbt
src/core               mbui/core: the MoonBit client (subscriptions, deltas, calls, sign-in) and its C queue
src/coredemo           the macOS app with the core linked in (MBUI_CORE=1 scripts/mac.sh)
scripts/core.sh        deps | shell [TARGET] | bundle | smoke [build|run] | vectors | sizes | clean | all
```

The default `moon` build does not link the engine: only `src/coredemo` (its `core_engine.m` includes `apple_core.m`
and `apple_auth.m`, its `moon.pkg` links the shell's `.a`), built by `MBUI_CORE=1 scripts/mac.sh build`.

## Building and the smoke test (on Studio)

`scripts/core.sh` expects an ember checkout at `$EMBER` (default: `ember-src` beside the session's `tools/`, i.e.
`<session>/work/ember-src`, origin/main), pnpm, and rustup's cargo. Everything it makes goes to `out/core/`
(ignored); the shell's intermediate build goes to `$CARGO_TARGET_DIR` (default `<session>/work/core-target`), which
can be deleted once the `.a` is copied out.

```sh
scripts/core.sh deps                 # pnpm install --frozen-lockfile in client/core-ts
scripts/core.sh shell                # out/core/aarch64-apple-darwin/libstillfail_shell.a (+ shell-<target>.libs)
scripts/core.sh shell aarch64-apple-ios       # (or aarch64-apple-ios-sim) for iOS
scripts/core.sh bundle               # out/core/core.js
scripts/core.sh smoke                # bundle, build out/core/smoke, run it twice against https://app.still.fail
scripts/core.sh clean                # drop the shell's intermediate build (out/core stays)
```

The shell crate is `crate-type = ["cdylib", "lib"]`; `cargo rustc --crate-type staticlib` makes the archive without
touching ember. The link line it needs (`-framework Security -framework CoreFoundation … -liconv -lc …`) is what
rustc prints as `native-static-libs`, kept in `out/core/shell-<target>.libs`.

The bundle is esbuild only (IIFE, ES2020, minified), no Babel: JavaScriptCore has classes, private fields and block
scoping; `@core/` is aliased to ember's `client/core-ts/src`.

The smoke test starts the core with a temporary data directory and cloud `https://app.still.fail`, sends
`{"id":1,"subscribe":{"topic":"accounts"}}`, then `{"id":2,"call":"auth.begin","params":{"redirect_uri":
"stillfail://auth/callback","return_to":"/"}}`, prints everything that comes back and the login URL (never opened),
stops the core and prints timings and the process's memory footprint.

## The engine (apple_core.m)

- One thread, `still.fail core`, with an 8 MB stack and a CFRunLoop: tasks (`mb_core_send`, the shell's answers) are
  `CFRunLoopPerformBlock`s, in order; timers are `CFRunLoopTimer`s. A dispatch queue would serialize just as well, but
  its workers have 512 KB stacks and the core parses (markdown, JSON) recursively; React Native's JSC thread and the
  Android engine (Hermes, 8 MB) make the same choice. JavaScriptCore drains promise jobs itself when each call into it
  returns, so there is no explicit microtask step.
- `__native` is ember's `HermesNative` (hosts/hermes-globals.ts) as it is, plus `os` (`macos`, `ios`), so the script
  starts the core the way Android's does: `startEngine(modules, os)` (ember hosts/engine.ts, since ember 524baa05).
  Bytes are ArrayBuffers both ways: `call(id, op, json, ArrayBuffer?)`, `emitBytes(client, json, ArrayBuffer)`,
  `__stillfail.receiveBytes(client, json, ArrayBuffer)`, `complete(id, json, error, ArrayBuffer?)`, `random(n)`.
  Bytes from the JS are read in place (the ArrayBuffer's pointer); bytes into the JS are one malloc'd copy handed over
  with `JSObjectMakeArrayBufferWithBytesNoCopy` (freed by the GC). engine.ts copies what goes out of a view first.
- The shell's answers come on tokio's threads; they go through a `Gate` (as engine.cpp's) closed by `mb_core_stop`, so
  an answer arriving after a stop is dropped instead of touching a dead core.
- `secure.*` and `listen.*` are the app's, not the shell's (on Android too): answered here (the Keychain, below;
  apple_listen.m, under Login).
- An exception that escapes to the engine, or the core's own `fatal`, sends `{"fatal": reason}` once; the host then
  stops this core and starts another (as Android does).
- `on_message` runs on the core thread. The MoonBit host must copy and hop to its UI thread (on macOS
  `dispatch_async(dispatch_get_main_queue(), …)` and then request a frame), and must not wait on the UI thread for the
  core while the core waits for it.
- Timers run on the run loop's clock (mach absolute time), which stops while the machine sleeps; Android uses
  CLOCK_BOOTTIME so a 10 s wait begun before a sleep is over after it. On macOS a wake should probably nudge the core
  (the shell's `reset` op, `resetConnections`) — not done yet.

## Measurements

`scripts/core.sh smoke` on Studio (Apple silicon, macOS, release shell, ember dda655bbf), 2026-10-19; three
first runs on an empty data directory, and runs again over what one left:

| | |
|---|---|
| `core.js` | 2,140,827 bytes (595,185 gzip -9); esbuild 0.1 s |
| `libstillfail_shell.a` (aarch64-apple-darwin) | 66.2 MB archive (57.0 MB `strip -S -x`); release build ≈ 45 s from clean |
| `libstillfail_shell.a` for iOS | aarch64-apple-ios 65.4 MB, aarch64-apple-ios-sim 65.2 MB (≈ 56 MB stripped); both build, ≈ 41 s each; `apple_core.m` compiles for iphoneos and iphonesimulator |
| what the shell adds to a binary | smoke linked with `-dead_strip`: 19.8 MB, 15.3 MB stripped (apple_core + smoke are a few KB of it) |
| cold start to first message | 105–124 ms (first run), 68–76 ms (again, warm file cache): shell start 9–31 ms, `evaluateScript` 47–80 ms, `start` + `connect` 4–6 ms, then the core's own first storage reads |
| `auth.begin` → URL | 6–10 ms (made locally, with PKCE; the cloud is asked when the browser opens it) |
| memory | phys_footprint 1.8 MB before start → 26–30 MB running; peak footprint 34 MB; max RSS 55–59 MB (shared JavaScriptCore pages included) |
| stop | 2–18 ms |

Both directions of bytes are exercised: `storage.set` with 171 and 31,233 bytes out of the JS, `fetch` (the changelog,
31,224 bytes) and `storage.get` (31,233 bytes, the second run) into it. `MB_CORE_TRACE=1` prints every shell
operation.

## mbui/core (src/core)

The MoonBit side, independent of `mbui/ui`:

- `core_native.c`: `on_message` (core thread) copies each message into a queue and wakes the main queue once per run
  of them (`dispatch_async_f`); there `@core.pump` drains it into the client and calls the app's `on_change` hook once.
  A host without a main queue (Android's GL thread) calls `@core.pump()` each frame. The engine is handed over by the
  app that links it (`core_client.h`: `mbc_use`, from a constructor), so `mbui/core` builds and tests without it.
- `client.mbt`: subscriptions by topic and params (the same `Sub` each time, so a view can ask every frame), each with
  its current value, error and a `version` bumped per message; calls with an `on_done`; `{fatal}` fails the calls in
  flight, and the core is started again (at most 3 times a minute) with every subscription asked again.
- `delta.mbt`: deltas applied as core-ts's `applyKeyed` (collections.ts): `set`/`append`/`remove`, and the keyed
  `put`/`patch`/`drop`/`move` a `keyed: true` subscription gets; only what is along a path is copied.
  `vectors_test.mbt` holds it to core-ts's own results (`scripts/core.sh vectors`).
- `sign_in(on_done)`: `auth.begin`, the browser session (apple_auth.m), `auth.complete {query}`.

```moonbit
@core.on_change(fn() { @host.request_frame() })   // the redraw hook
@core.start() |> ignore                            // data: $MBUI_CORE_DATA, else Application Support/<bundle id|mbui>/core
fn view(c : @ui.Ctx) {
  let accounts = @core.subscribe("accounts")       // .value : Json?, .error : Json?, .version : Int
  match accounts.value { Some(Array(list)) => ..., _ => ... }
  if c.button("登录") { @core.sign_in(fn(r) { ... }) }
}
```

Still to do: ship `core.js` in an app bundle (`Contents/Resources/core.js`; today `MB_CORE_BUNDLE`, which
`scripts/mac.sh` sets), the iOS build (`scripts/ios.sh`: `core_engine.m`'s two includes, the shell for the device and
simulator, `-framework JavaScriptCore -framework AuthenticationServices`), bytes beside messages (dropped by the queue
for now), a call's progress values.

## iOS

The same `apple_core.m` (it names the OS `ios` under `TARGET_OS_IPHONE`; it compiles for iphoneos and
iphonesimulator as is), `core.js` as a resource of the app, and the shell for the device and the simulator:

```sh
scripts/core.sh shell aarch64-apple-ios       # out/core/aarch64-apple-ios/libstillfail_shell.a
scripts/core.sh shell aarch64-apple-ios-sim   # out/core/aarch64-apple-ios-sim/libstillfail_shell.a
```

`scripts/ios.sh` links the MoonBit objects by hand; add `apple_core.o`, the shell's `.a`, the libraries in
`out/core/shell-<target>.libs` (for iOS: Network, SystemConfiguration, Security, CoreFoundation, Foundation, iconv) and
`-framework JavaScriptCore`, and copy `out/core/core.js` into `MBUI.app/`. An xcframework of the two `.a`s is the
tidy form once there is an Xcode project.

What differs from macOS:
- JIT: a third-party iOS app's JSContext runs without JIT (LLInt/baseline interpreter only), so evaluating the
  2 MB script and the core's own work are slower than the macOS numbers here; measure on a device. If the script's
  start matters, look at JSC's `JSScript` (a bytecode cache file; check it is usable from public API first) or at
  loading less script before the first answer.
- Lifecycle: a suspended app's timers and sockets stop. On becoming active again, the core's cloud socket notices on
  its own ping; a `mb_core_reset` sending the shell's `reset` (BridgeHost.resetConnections) would make it immediate.
- `secure.*` → the Keychain (below).

## Android

Built (`APP=coredemo scripts/android.sh build`): the core runs in ember's own engine, as still.fail's Android app runs
it, not in one of ours.

- **Engine**: ember's `apps/android/core/src/main/cpp/engine.cpp`, prebuilt (`node scripts/native.ts path engine
  android-arm64` in the ember checkout: `libstillfail_hermes.so`, `libjsi.so`, `libc++_shared.so`), on the shell
  `libstillfail_shell.so` (`... path shell android-arm64`). Hermes itself (`libhermes.so`) and `libfbjni.so` come
  from React Native 0.81.4's `hermes-android` and fbjni 0.7.0's AARs (Gradle's cache, else Maven Central). All go
  into `out/android/apk/jniLibs`, which Gradle packs; nothing is committed.
- **Script**: `scripts/core.sh hermes` makes `out/core/core.hbc` as ember's `hermes-bundle.ts` does (esbuild, Babel's
  class transform, hermesc 0.81.4 to bytecode) from `core/hermes.ts` (still.fail alone) or, for coredemo by default,
  `core/media-hermes.ts` (with the media module). It goes into the APK's assets.
- **Host** (`src/host/android_core.c`, included by `src/coredemo/android_engine.c`): calls the engine's
  `Java_fail_still_core_HermesNative_*` entry points as C functions (none looks at its `this`), with a
  `dev.mbui.CoreHost` (android/) as the listener the engine calls back on its thread: `onBytes`/`onFrame` (a message,
  or one with bytes) go straight into core_native.c's queue and ask for a frame; android_host.c drains the queue as
  each frame begins (`mbc_frame`). Timers are the engine's (CLOCK_BOOTTIME).
- **`secure.*`**: CoreHost seals each value with AES-GCM under one Android Keystore key (alias
  `dev.mbui.core.secure`), a file per value in `<files>/core/secure`, the value's name as associated data.
  `secure.ask` and `user: true` (biometrics) answer `"unsupported"`. `MBUI_SECURE_TEST=1` makes coredemo round-trip
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
- **Sign-in**: no browser session on Android (`@core.has_browser_session()` false), so coredemo's 登录 signs in on
  `@host.browser_login` (`dev.mbui.BrowserLogin`): `auth.begin` with `http://127.0.0.1:<port>/oauth/callback`, the
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
  core says goes into core_native.c's queue and asks for a frame, which win_app.c drains as it begins (`mbc_frame`).
- **`secure.*`**: sealed with DPAPI for the Windows user (CryptProtectData, never a prompt), a file per value in
  `<data>\secure`. `secure.ask` and `user: true` (Windows Hello) answer `"unsupported"`. `MBUI_SECURE_TEST=1` round-trips
  it once as the core starts (`SECURE_TEST …` on stderr).
- **`listen.*`** and **sign-in**: on mbui's win_listen.c (Winsock); the app signs in on `@host.browser_login`
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
  the host: open the URL and catch the callback. On iOS and macOS `ASWebAuthenticationSession(url:,
  callbackURLScheme: "stillfail")` does both (no `CFBundleURLTypes` registration needed, the callback URL comes back
  to its completion handler); otherwise register the scheme (`CFBundleURLTypes`; on macOS handle `kAEGetURL`, on iOS
  `application:openURL:`). Then `mb_core_send({"id":…,"call":"auth.complete","params":{"query":"<query>"}})`.
  Built: `src/host/apple_auth.m` and `@core.sign_in`; `MBUI_AUTH_DRY=1` makes the session but does not start it (no one
  has signed in through it yet: a real sign-in is the person's to do). Caveat: another installed still.fail app
  (Studio has one) also owns `stillfail://`; ASWebAuthenticationSession avoids that clash, a registered scheme does not.
- **Loopback** (`http://127.0.0.1:<port>/oauth/callback`, what command-line tools do). Nothing of it is
  still.fail's: mbui/host's `browser_login` (browser_login.mbt, `src/host/apple_browser_login.m`) listens on
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
login cards). apple_core.m answers it on the same listener, as Android's Loopback.kt does there; `scripts/core.sh
listen` tests it with core/listen-test.js in the core's place (`scripts/android.sh listen-test` on Android's).

`secure.*` is the other gap: at start the core asks `secure.get` twice (the lock's signing key `lock-signer`, and the
vault's) and goes on without them (the smoke run shows it); after login, making a lock signer or opening a vault
would fail with "unsupported". The Keychain (`kSecClassGenericPassword`, `kSecAttrAccessControl` with user presence
when `user` is set; `secure.ask` → `LAContext evaluatePolicy`) answered through `complete` closes it.
