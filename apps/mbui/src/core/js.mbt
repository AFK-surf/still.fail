// The engine's side in a browser: the page's (still.fail's web/src/mbui/core.ts) `globalThis.__mbcore`, the web's own
// core worker (web/src/core/worker.ts) behind it, whose messages it posts to mbui's queue (web/host.js H.post) on the
// channel "core" as core_native.c does on the native hosts. A page without one (the headless runs, mbui's own web
// demo): `start` answers false.

///|
extern "js" fn ffi_start(data_dir : String, cloud : String, beta : Int) -> Int =
  #|(d, c, b) => { const C = globalThis.__mbcore; return C ? (C.start(d, c, b !== 0) ? 1 : 0) : 0 }

///|
extern "js" fn ffi_send(json : String) -> Unit =
  #|(j) => { const C = globalThis.__mbcore; if (C) C.send(j, null) }

///|
extern "js" fn ffi_send_bytes(json : String, bytes : Bytes) -> Unit =
  #|(j, b) => { const C = globalThis.__mbcore; if (C) C.send(j, b) }

///|
extern "js" fn ffi_stop() -> Unit =
  #|() => { const C = globalThis.__mbcore; if (C) C.stop() }

///|
/// A browser signs in on its own page (`sign_in` goes there: the cloud brings it back to `return_to`).
extern "js" fn ffi_has_web_auth() -> Int =
  #|() => (globalThis.__mbcore ? 1 : 0)

///|
extern "js" fn ffi_web_auth(token : Int, url : String, scheme : String) -> Int =
  #|(_t, u, _s) => { const C = globalThis.__mbcore; return C ? (C.signIn(u) ? 1 : 0) : 0 }

///|
extern "js" fn ffi_now() -> Double =
  #|() => (typeof performance !== "undefined" ? performance.now() : Date.now())

///|
extern "js" fn ffi_wall_ms() -> Double =
  #|() => Date.now()

///|
fn ffi_screen_ack(_call : Double, _ts : Double) -> Int {
  0
}

///|
/// Where the cloud sends a sign-in back to: the web's own page for it (web/src/cloud/accounts.ts), which takes it in
/// and goes on to `return_to`.
extern "js" fn auth_redirect() -> String =
  #|() => (typeof location !== "undefined" ? location.origin + "/auth/callback" : "stillfail://auth/callback")

///|
/// Where a sign-in comes back to once it is in: this page.
extern "js" fn auth_return_to() -> String =
  #|() => (typeof location !== "undefined" ? location.pathname + location.search : "/")
