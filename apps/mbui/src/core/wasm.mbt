// The engine's side on Wasm GC: what the main a native shell runs gives it as the program starts (wasm_engine: its
// imports, src/stillfail/core_gc.mbt); none in a test's program (`moon test --target wasm-gc`, on the Tester's fake and
// the recorded cores, as on native), where `start` answers false, as a page without one does (js.mbt).

///|
/// The engine's calls a native shell answers (core_api.h's, as native.mbt's are on native).
pub(all) struct WasmEngine {
  start : (String, String, Int) -> Int
  send : (String) -> Unit
  send_bytes : (String, Bytes) -> Unit
  stop : () -> Unit
  has_web_auth : () -> Int
  web_auth : (Int, String, String) -> Int
  now : () -> Double
  wall_ms : () -> Double
  screen_ack : (Double, Double) -> Int
}

///|
/// The shell's engine, given by the main as it starts (none: a test's program).
// kept across runs: set once by the main, before anything starts the engine
pub let wasm_engine : Ref[WasmEngine?] = Ref(None)

///|
fn ffi_start(data_dir : String, cloud : String, beta : Int) -> Int {
  match wasm_engine.val {
    Some(e) => (e.start)(data_dir, cloud, beta)
    None => 0
  }
}

///|
fn ffi_send(json : String) -> Unit {
  match wasm_engine.val {
    Some(e) => (e.send)(json)
    None => ()
  }
}

///|
fn ffi_send_bytes(json : String, bytes : Bytes) -> Unit {
  match wasm_engine.val {
    Some(e) => (e.send_bytes)(json, bytes)
    None => ()
  }
}

///|
fn ffi_stop() -> Unit {
  match wasm_engine.val {
    Some(e) => (e.stop)()
    None => ()
  }
}

///|
fn ffi_has_web_auth() -> Int {
  match wasm_engine.val {
    Some(e) => (e.has_web_auth)()
    None => 0
  }
}

///|
fn ffi_web_auth(token : Int, url : String, scheme : String) -> Int {
  match wasm_engine.val {
    Some(e) => (e.web_auth)(token, url, scheme)
    None => 0
  }
}

///|
fn ffi_now() -> Double {
  match wasm_engine.val {
    Some(e) => (e.now)()
    None => @env.now().to_double()
  }
}

///|
fn ffi_wall_ms() -> Double {
  match wasm_engine.val {
    Some(e) => (e.wall_ms)()
    None => @env.now().to_double()
  }
}

///|
fn ffi_screen_ack(call : Double, ts : Double) -> Int {
  match wasm_engine.val {
    Some(e) => (e.screen_ack)(call, ts)
    None => 0
  }
}

///|
fn auth_redirect() -> String {
  "stillfail://auth/callback"
}

///|
fn auth_return_to() -> String {
  "/"
}
