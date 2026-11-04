// The engine's side on Wasm: none yet (a test's program, `moon test --target wasm-gc`, runs on the Tester's fake and
// the recorded cores, as on native; a Wasm app's host will give it): `start` answers false, as a page without one does
// (js.mbt).

///|
fn ffi_start(_data_dir : String, _cloud : String, _beta : Int) -> Int {
  0
}

///|
fn ffi_send(_json : String) -> Unit {

}

///|
fn ffi_send_bytes(_json : String, _bytes : Bytes) -> Unit {

}

///|
fn ffi_stop() -> Unit {

}

///|
fn ffi_has_web_auth() -> Int {
  0
}

///|
fn ffi_web_auth(_token : Int, _url : String, _scheme : String) -> Int {
  0
}

///|
fn ffi_now() -> Double {
  @env.now().to_double()
}

///|
fn ffi_wall_ms() -> Double {
  @env.now().to_double()
}

///|
fn ffi_screen_ack(_call : Double, _ts : Double) -> Int {
  0
}

///|
fn auth_redirect() -> String {
  "stillfail://auth/callback"
}

///|
fn auth_return_to() -> String {
  "/"
}
